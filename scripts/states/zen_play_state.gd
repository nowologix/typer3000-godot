## zen_play_state.gd
## Main ZEN gameplay state
## Features: smooth scroll physics, focus band fade, piano key audio
extends Control

# Font for literary text
const ZEN_FONT_PATH := "res://assets/fonts/zen/Crimson-Roman.otf"
var zen_font: Font = null

# Configuration
const LINE_HEIGHT := 36.0
const CHAR_WIDTH := 18.0  # Approximate for monospace
const VISIBLE_LINES_FULL_ALPHA := 2
const MIN_ALPHA := 0.12
const FADE_LENGTH_RATIO := 0.6  # Fade extends over 60% of viewport height

# Scroll physics (critically damped spring)
const SCROLL_SMOOTHING := 8.0  # Higher = faster follow
const MAX_SCROLL_SPEED := 800.0  # px/sec safety cap
const ANCHOR_Y_RATIO := 0.5  # Cursor aims for center of screen

# Colors
const COLOR_UNTYPED := Color(0.45, 0.45, 0.5)
const COLOR_TYPED := Color(1.0, 1.0, 1.0)  # White for typed text
const COLOR_CURSOR := Color(0.4, 0.9, 0.5)
const COLOR_CURSOR_BG := Color(0.4, 0.9, 0.5, 0.15)

# Pause menu commands
const PAUSE_COMMANDS := {
	"RESUME": "resume_game",
	"QUIT": "quit_to_menu"
}

# References
@onready var title_label: Label = $HUD/TitleLabel
@onready var text_container: Control = $TextContainer
@onready var pause_overlay: Control = $PauseOverlay
@onready var pause_typed_display: Label = $PauseOverlay/CenterContainer/VBoxContainer/TypedDisplay

# Background
var background_video: VideoStreamPlayer = null
var background_image: TextureRect = null
var background_dimmer: ColorRect = null
var foreground_overlay: TextureRect = null  # Optional overlay on top of text

# State
var work_id: String = ""
var work_title: String = ""
var raw_text: String = ""
var glyphs: Array = []
var cursor_index: int = 0
var is_paused: bool = false
var pause_typed_buffer: String = ""

# Scroll state
var scroll_y: float = 0.0
var scroll_y_target: float = 0.0
var scroll_velocity: float = 0.0

# Text layout
var text_lines: Array = []  # Array of {text: String, y: float, start_idx: int, end_idx: int}
var glyph_positions: Array = []  # Array of Vector2 for each glyph
var total_text_height: float = 0.0

# Timing
var session_start_time: float = 0.0
var chars_typed: int = 0
var errors: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	focus_mode = Control.FOCUS_ALL
	if pause_overlay:
		pause_overlay.visible = false

	# Load ZEN font
	if ResourceLoader.exists(ZEN_FONT_PATH):
		zen_font = load(ZEN_FONT_PATH)
		DebugHelper.log_info("ZenPlayState: Loaded Crimson font")
	else:
		zen_font = ThemeDB.fallback_font
		DebugHelper.log_warning("ZenPlayState: Crimson font not found, using fallback")

# Resume state
var resume_index: int = 0

func on_enter(params: Dictionary) -> void:
	DebugHelper.log_info("ZenPlayState entered")
	MenuBackground.hide_background()
	SoundManager.stop_music()  # Stop menu music
	grab_focus()

	# Ensure font is loaded before layout
	if zen_font == null:
		if ResourceLoader.exists(ZEN_FONT_PATH):
			zen_font = load(ZEN_FONT_PATH)
		else:
			zen_font = ThemeDB.fallback_font

	work_id = params.get("work_id", "")
	resume_index = params.get("resume_index", 0)

	if work_id.is_empty():
		DebugHelper.log_error("ZenPlayState: No work_id provided")
		StateManager.change_state("zen_select")
		return

	_load_work()
	_start_session()

func on_exit() -> void:
	DebugHelper.log_info("ZenPlayState exiting")
	# Save progress before exiting
	if cursor_index > 0 and glyphs.size() > 0:
		ZenProgressManager.save_progress(work_id, cursor_index, glyphs.size())
	ZenAudio.stop_ambient()
	_cleanup_background()

func _save_progress() -> void:
	# Save progress if we have made any
	if cursor_index > 0 and glyphs.size() > 0:
		ZenProgressManager.save_progress(work_id, cursor_index, glyphs.size())


func _load_work() -> void:
	print(">>> ZEN PLAY: _load_work called for: ", work_id)
	var work = ZenWorksLoader.get_work(work_id)
	if work == null:
		DebugHelper.log_error("ZenPlayState: Work not found: %s" % work_id)
		return

	work_title = work.title
	if title_label:
		title_label.text = work_title + " — " + work.author

	# Setup background (video or image)
	_setup_background(work)

	# Load and parse content
	raw_text = ZenWorksLoader.load_work_content(work_id)
	if raw_text.is_empty():
		DebugHelper.log_error("ZenPlayState: Failed to load work content")
		return

	# Convert to glyphs
	glyphs = ZenWorksLoader.text_to_glyphs(raw_text)
	DebugHelper.log_info("ZenPlayState: Loaded %d glyphs" % glyphs.size())

	# Layout text
	_layout_text()

func _layout_text() -> void:
	text_lines.clear()
	glyph_positions.clear()

	var viewport_width: float = get_viewport().size.x
	var max_line_width: float = viewport_width * 0.7  # 70% of screen width for text
	var current_y := LINE_HEIGHT * 2  # Start with some padding

	# Temporary storage for current line
	var line_glyphs: Array = []  # Array of {index, char, width}
	var line_width: float = 0.0
	var current_line := ""
	var current_line_start := 0

	for i in range(glyphs.size()):
		var glyph = glyphs[i]
		var c: String = glyph.char

		if c == "\n":
			# End current line - center it
			_finish_line_centered(line_glyphs, line_width, current_y, viewport_width)
			text_lines.append({
				"text": current_line,
				"y": current_y,
				"start_idx": current_line_start,
				"end_idx": i
			})

			# Position for newline glyph (at end of line)
			var line_end_x: float = (viewport_width - line_width) / 2.0 + line_width
			glyph_positions.append(Vector2(line_end_x, current_y))

			# Start new line
			current_y += LINE_HEIGHT
			line_glyphs.clear()
			line_width = 0.0
			current_line = ""
			current_line_start = i + 1
		else:
			var char_width := _get_char_width(c)

			# Check if we need to wrap
			if line_width + char_width > max_line_width and c != " " and line_glyphs.size() > 0:
				# Finish current line centered
				_finish_line_centered(line_glyphs, line_width, current_y, viewport_width)
				text_lines.append({
					"text": current_line,
					"y": current_y,
					"start_idx": current_line_start,
					"end_idx": i
				})

				# Start new line
				current_y += LINE_HEIGHT
				line_glyphs.clear()
				line_width = 0.0
				current_line = ""
				current_line_start = i

			# Add glyph to current line (position calculated later)
			line_glyphs.append({"index": i, "char": c, "width": char_width, "x_offset": line_width})
			line_width += char_width
			current_line += c

	# Add final line
	if line_glyphs.size() > 0:
		_finish_line_centered(line_glyphs, line_width, current_y, viewport_width)
		text_lines.append({
			"text": current_line,
			"y": current_y,
			"start_idx": current_line_start,
			"end_idx": glyphs.size()
		})

	total_text_height = current_y + LINE_HEIGHT * 3
	DebugHelper.log_info("ZenPlayState: Layout complete, %d lines, height %.0f" % [text_lines.size(), total_text_height])

func _finish_line_centered(line_glyphs: Array, line_width: float, y: float, viewport_width: float) -> void:
	# Calculate starting X to center the line
	var start_x: float = (viewport_width - line_width) / 2.0

	# Assign final positions to each glyph
	for glyph_data in line_glyphs:
		var final_x: float = start_x + glyph_data.x_offset
		glyph_positions.append(Vector2(final_x, y))

func _setup_background(work) -> void:
	_cleanup_background()
	
	print("=== BACKGROUND DEBUG === path: ", work.background_path)
	DebugHelper.log_info("ZenPlayState: Setting up background, path: '%s'" % work.background_path)

	if work.background_path.is_empty():
		DebugHelper.log_warning("ZenPlayState: No background path set for work")
		return

	var is_video: bool = work.background_path.ends_with(".ogv") or work.background_path.ends_with(".webm")

	if is_video:
		# Create video player
		background_video = VideoStreamPlayer.new()
		background_video.set_anchors_preset(Control.PRESET_FULL_RECT)
		background_video.expand = true
		background_video.loop = true
		background_video.show_behind_parent = true
		background_video.z_index = -2  # Behind dimmer
		background_video.finished.connect(_on_background_video_finished)

		if ResourceLoader.exists(work.background_path):
			background_video.stream = load(work.background_path)
			add_child(background_video)
			background_video.play()
			DebugHelper.log_info("ZenPlayState: Playing background video")
	else:
		# Create image background using direct loading (bypasses import)
		var bg_texture := _load_image_texture(work.background_path)
		if bg_texture:
			background_image = TextureRect.new()
			background_image.set_anchors_preset(Control.PRESET_FULL_RECT)
			background_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			background_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			background_image.texture = bg_texture
			background_image.show_behind_parent = true
			background_image.z_index = -2  # Behind dimmer
			add_child(background_image)
			DebugHelper.log_info("ZenPlayState: Showing background image")

	# Add dimmer overlay for readability (between background and text)
	background_dimmer = ColorRect.new()
	background_dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	background_dimmer.color = Color(0.0, 0.0, 0.0, 0.6)  # 60% black overlay
	background_dimmer.show_behind_parent = true
	background_dimmer.z_index = -1  # In front of background, behind text
	add_child(background_dimmer)

	# Add foreground overlay if available (on top of text, also dimmed)
	if not work.overlay_path.is_empty():
		var overlay_texture := _load_image_texture(work.overlay_path)
		if overlay_texture:
			foreground_overlay = TextureRect.new()
			foreground_overlay.texture = overlay_texture
			foreground_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
			foreground_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			foreground_overlay.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			foreground_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			foreground_overlay.modulate = Color(0.4, 0.4, 0.4, 1.0)  # Darken overlay
			add_child(foreground_overlay)
			DebugHelper.log_info("ZenPlayState: Showing foreground overlay (dimmed)")

func _cleanup_background() -> void:
	if background_video:
		background_video.stop()
		background_video.queue_free()
		background_video = null
	if background_image:
		background_image.queue_free()
		background_image = null
	if background_dimmer:
		background_dimmer.queue_free()
		background_dimmer = null
	if foreground_overlay:
		foreground_overlay.queue_free()
		foreground_overlay = null

func _on_background_video_finished() -> void:
	if background_video:
		background_video.play()

func _get_char_width(c: String) -> float:
	# Use actual font metrics for proper proportional spacing
	if zen_font:
		return zen_font.get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	# Fallback to approximate widths
	if c == " " or c == "\t":
		return CHAR_WIDTH * 0.5
	elif c in [".", ",", ":", ";", "'", "\"", "!", "?"]:
		return CHAR_WIDTH * 0.6
	elif c in ["m", "w", "M", "W"]:
		return CHAR_WIDTH * 1.3
	elif c in ["i", "l", "I", "1", "|"]:
		return CHAR_WIDTH * 0.5
	else:
		return CHAR_WIDTH

func _start_session() -> void:
	errors = 0
	is_paused = false
	session_start_time = Time.get_unix_time_from_system()

	# Handle resume
	if resume_index > 0 and resume_index < glyphs.size():
		cursor_index = resume_index
		chars_typed = resume_index
		# Mark all previous glyphs as typed
		for i in range(resume_index):
			if i < glyphs.size():
				glyphs[i].is_typed = true
		DebugHelper.log_info("ZenPlayState: Resuming at position %d" % resume_index)
	else:
		cursor_index = 0
		chars_typed = 0
		# Skip any leading newlines
		_skip_newlines_and_leading_whitespace()

	# Start progress tracking
	ZenProgressManager.start_tracking(work_id)

	# Set initial scroll to center current character immediately
	if cursor_index < glyph_positions.size():
		var cursor_y: float = glyph_positions[cursor_index].y
		var viewport_height: float = get_viewport().size.y
		var anchor_y: float = viewport_height * ANCHOR_Y_RATIO
		scroll_y = cursor_y - anchor_y
		scroll_y_target = scroll_y
	else:
		scroll_y = 0.0
		scroll_y_target = 0.0
	scroll_velocity = 0.0

	# Start ambient music
	ZenAudio.start_ambient()

	# Force initial draw
	queue_redraw()

func _process(delta: float) -> void:
	if is_paused:
		return

	_update_scroll(delta)
	queue_redraw()

func _update_scroll(delta: float) -> void:
	# Calculate target scroll based on cursor position
	if cursor_index < glyph_positions.size():
		var cursor_y: float = glyph_positions[cursor_index].y
		var viewport_height: float = get_viewport().size.y
		var anchor_y: float = viewport_height * ANCHOR_Y_RATIO

		scroll_y_target = cursor_y - anchor_y

		# Only clamp at the end (allow negative scroll so first char can be centered)
		var max_scroll := total_text_height - viewport_height + LINE_HEIGHT * 2
		scroll_y_target = minf(scroll_y_target, max_scroll)

	# Smooth damp towards target (critically damped spring approximation)
	var diff := scroll_y_target - scroll_y
	var spring_force := diff * SCROLL_SMOOTHING
	scroll_velocity += spring_force * delta
	scroll_velocity *= exp(-SCROLL_SMOOTHING * delta * 2)  # Damping

	# Clamp velocity
	scroll_velocity = clampf(scroll_velocity, -MAX_SCROLL_SPEED, MAX_SCROLL_SPEED)

	# Apply velocity
	scroll_y += scroll_velocity * delta

	# Snap if very close
	if abs(diff) < 0.5 and abs(scroll_velocity) < 1.0:
		scroll_y = scroll_y_target
		scroll_velocity = 0.0

func _draw() -> void:
	var viewport_size: Vector2i = get_viewport().size
	var viewport_height: float = viewport_size.y

	# Only draw background color if no image/video background is set
	if background_image == null and background_video == null:
		draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.05, 0.06, 0.08))

	# Calculate fade parameters
	var cursor_screen_y := 0.0
	if cursor_index < glyph_positions.size():
		cursor_screen_y = glyph_positions[cursor_index].y - scroll_y

	var fade_start_y := cursor_screen_y + LINE_HEIGHT * VISIBLE_LINES_FULL_ALPHA
	var fade_end_y := viewport_height * FADE_LENGTH_RATIO + fade_start_y

	# Get font
	var font: Font = zen_font if zen_font else ThemeDB.fallback_font
	var font_size: int = 28

	# OPTIMIZATION: Find visible line range instead of iterating all glyphs
	var visible_top := scroll_y - LINE_HEIGHT
	var visible_bottom := scroll_y + viewport_height + LINE_HEIGHT
	
	var first_visible_line := -1
	var last_visible_line := -1
	
	# Binary search for first visible line
	var low := 0
	var high := text_lines.size() - 1
	while low <= high:
		var mid := (low + high) / 2
		var line_y: float = text_lines[mid].y
		if line_y < visible_top:
			low = mid + 1
		else:
			first_visible_line = mid
			high = mid - 1
	
	# Find last visible line (linear from first, usually only ~30 lines visible)
	if first_visible_line >= 0:
		last_visible_line = first_visible_line
		while last_visible_line < text_lines.size() and text_lines[last_visible_line].y < visible_bottom:
			last_visible_line += 1
	
	# Early exit if nothing visible
	if first_visible_line < 0 or first_visible_line >= text_lines.size():
		return
	
	# Get glyph range for visible lines
	var start_glyph: int = text_lines[first_visible_line].start_idx
	var end_glyph: int = text_lines[mini(last_visible_line, text_lines.size() - 1)].end_idx

	# Draw only visible glyphs
	for i in range(start_glyph, mini(end_glyph + 1, glyphs.size())):
		if i >= glyph_positions.size():
			break

		var glyph = glyphs[i]
		var pos: Vector2 = glyph_positions[i]
		var screen_pos := Vector2(pos.x, pos.y - scroll_y)

		# Skip newline characters (they're just markers)
		if glyph.is_newline:
			continue

		# Calculate alpha based on vertical position (focus band effect)
		var alpha := 1.0
		if screen_pos.y > fade_start_y:
			if screen_pos.y >= fade_end_y:
				alpha = MIN_ALPHA
			else:
				var t := (screen_pos.y - fade_start_y) / (fade_end_y - fade_start_y)
				t = _smoothstep(0.0, 1.0, t)
				alpha = lerpf(1.0, MIN_ALPHA, t)

		# Determine color
		var color: Color
		if i < cursor_index:
			# Typed
			color = COLOR_TYPED
		elif i == cursor_index:
			# Current cursor position
			color = COLOR_CURSOR
			# Draw cursor background highlight
			var char_width := _get_char_width(glyph.char)
			draw_rect(Rect2(screen_pos.x - 2, screen_pos.y - font_size + 4, char_width + 4, font_size + 8), COLOR_CURSOR_BG)
		else:
			# Untyped
			color = COLOR_UNTYPED

		# Apply alpha
		color.a *= alpha

		# Draw character
		draw_string(font, Vector2(screen_pos.x, screen_pos.y), glyph.char, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

	# Draw cursor underline
	if cursor_index < glyph_positions.size():
		var glyph = glyphs[cursor_index]
		var pos: Vector2 = glyph_positions[cursor_index]
		var screen_pos := Vector2(pos.x, pos.y - scroll_y)
		var char_width := _get_char_width(glyph.char)
		draw_line(
			Vector2(screen_pos.x, screen_pos.y + 4),
			Vector2(screen_pos.x + char_width, screen_pos.y + 4),
			COLOR_CURSOR,
			2.0
		)

func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.is_echo():
		# Handle pause
		if event.keycode == KEY_ESCAPE:
			_toggle_pause()
			get_viewport().set_input_as_handled()
			return

		if is_paused:
			_handle_pause_input(event)
			return

		# Handle typing
		_handle_typing(event)

func _handle_typing(event: InputEventKey) -> void:
	if cursor_index >= glyphs.size():
		# End of text reached
		return

	var expected_glyph = glyphs[cursor_index]
	var expected_char: String = expected_glyph.char
	var typed_char := ""

	# Get typed character
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		typed_char = "\n"
	elif event.keycode == KEY_SPACE:
		typed_char = " "
	elif event.unicode > 0:
		typed_char = char(event.unicode)

	if typed_char.is_empty():
		return

	# Check if correct (case-insensitive for letters, with character equivalences)
	var is_correct := false

	if expected_char == "\n":
		# Newline: accept Enter key
		is_correct = (typed_char == "\n")
	elif expected_char == " ":
		# Space: accept space
		is_correct = (typed_char == " ")
	elif expected_char in ["—", "–", "−"]:
		# Em-dash, en-dash, minus sign: accept regular hyphen
		is_correct = (typed_char == "-")
	elif expected_char in ["„", """, """, "»", "«"]:
		# German/typographic quotes: accept regular quote
		is_correct = (typed_char == "\"")
	elif expected_char in ["'", "'", "‚"]:
		# Typographic apostrophes: accept regular apostrophe
		is_correct = (typed_char == "'")
	elif expected_char == "…":
		# Ellipsis: accept period (will need 3 periods for full ellipsis)
		is_correct = (typed_char == ".")
	else:
		# Regular character: case-insensitive match
		is_correct = (typed_char.to_lower() == expected_char.to_lower())

	if is_correct:
		# Mark as typed
		expected_glyph.is_typed = true
		cursor_index += 1
		chars_typed += 1

		# Play key sound
		ZenAudio.play_key_sound(expected_char)

		# Auto-skip newlines and whitespace at line starts for smoother flow
		_skip_newlines_and_leading_whitespace()

		# Auto-save progress (at period, newline, or every 200 chars)
		if ZenProgressManager.should_save(cursor_index, expected_char):
			ZenProgressManager.save_progress(work_id, cursor_index, glyphs.size())

		# Check for end of text
		if cursor_index >= glyphs.size():
			_on_text_complete()
	else:
		# Wrong key - soft feedback, no cursor advance
		errors += 1
		# Could add subtle visual feedback here

	get_viewport().set_input_as_handled()
	queue_redraw()

func _skip_newlines_and_leading_whitespace() -> void:
	# Auto-skip newlines for smoother typing flow
	while cursor_index < glyphs.size():
		var glyph = glyphs[cursor_index]
		if glyph.char == "\n":
			glyph.is_typed = true
			cursor_index += 1
		else:
			break

func _toggle_pause() -> void:
	is_paused = not is_paused
	pause_typed_buffer = ""
	_update_pause_display()

	if pause_overlay:
		pause_overlay.visible = is_paused

	if is_paused:
		SoundManager.play_pause()
		ZenAudio.set_ambient_volume(0.3)
		# Save progress when pausing
		_save_progress()
	else:
		SoundManager.play_unpause()
		ZenAudio.set_ambient_volume(0.7)

	queue_redraw()

func _update_pause_display() -> void:
	if pause_typed_display:
		pause_typed_display.text = pause_typed_buffer

func _check_pause_commands() -> void:
	for command in PAUSE_COMMANDS:
		if pause_typed_buffer == command:
			SoundManager.play_word_complete()
			call(PAUSE_COMMANDS[command])
			return

	var could_match := false
	for command in PAUSE_COMMANDS:
		if command.begins_with(pause_typed_buffer):
			could_match = true
			break

	if not could_match and pause_typed_buffer.length() > 0:
		SoundManager.play_type_error()
		pause_typed_buffer = ""
		_update_pause_display()

func resume_game() -> void:
	_toggle_pause()

func quit_to_menu() -> void:
	_save_progress()
	is_paused = false
	StateManager.change_state("zen_select")

func _handle_pause_input(event: InputEventKey) -> void:
	if event.keycode == KEY_ESCAPE:
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_BACKSPACE:
		if pause_typed_buffer.length() > 0:
			pause_typed_buffer = pause_typed_buffer.substr(0, pause_typed_buffer.length() - 1)
			SoundManager.play_menu_select()
			_update_pause_display()
		get_viewport().set_input_as_handled()
		return

	var char_code = event.unicode
	var is_letter = (char_code >= 65 and char_code <= 90) or (char_code >= 97 and char_code <= 122)
	if is_letter:
		pause_typed_buffer += char(char_code).to_upper()
		SoundManager.play_menu_select()
		_update_pause_display()
		_check_pause_commands()

	get_viewport().set_input_as_handled()

func _on_text_complete() -> void:
	var session_time := Time.get_unix_time_from_system() - session_start_time
	var wpm := 0.0
	if session_time > 0:
		wpm = (chars_typed / 5.0) / (session_time / 60.0)

	DebugHelper.log_info("ZenPlayState: Text complete! WPM: %.1f, Errors: %d" % [wpm, errors])

	# Could show completion screen here
	# For now, just pause
	_toggle_pause()

func _get_stats() -> Dictionary:
	var session_time := Time.get_unix_time_from_system() - session_start_time
	var wpm := 0.0
	if session_time > 0:
		wpm = (chars_typed / 5.0) / (session_time / 60.0)

	var accuracy := 100.0
	if chars_typed + errors > 0:
		accuracy = (float(chars_typed) / float(chars_typed + errors)) * 100.0

	return {
		"chars_typed": chars_typed,
		"errors": errors,
		"wpm": wpm,
		"accuracy": accuracy,
		"session_time": session_time,
		"progress": float(cursor_index) / float(glyphs.size()) * 100.0 if glyphs.size() > 0 else 0.0
	}

# Load image directly (bypasses Godot's resource import system)
func _load_image_texture(res_path: String) -> ImageTexture:
	if res_path.is_empty():
		return null

	var abs_path := ProjectSettings.globalize_path(res_path)
	var image := Image.new()
	var err := image.load(abs_path)
	if err != OK:
		DebugHelper.log_warning("ZenPlayState: Failed to load image: %s (error %d)" % [res_path, err])
		return null

	return ImageTexture.create_from_image(image)
