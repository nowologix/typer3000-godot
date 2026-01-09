## zen_select_state.gd
## Work selection screen for ZEN mode
## Carousel UI for choosing literary works, filtered by language
extends Control

# Carousel configuration
const CARD_WIDTH_SELECTED := 480.0
const CARD_HEIGHT_SELECTED := 285.0
const CARD_WIDTH_SIDE := 320.0
const CARD_HEIGHT_SIDE := 190.0
const CARD_SPACING := 50.0
const TRANSITION_TIME := 0.25

# Colors
const COLOR_SELECTED := Color(0.4, 0.9, 0.5)  # Zen green
const COLOR_UNSELECTED := Color(0.6, 0.6, 0.65)
const COLOR_BORDER_SELECTED := Color(0.5, 1.0, 0.6)
const COLOR_BORDER_UNSELECTED := Color(0.3, 0.3, 0.35)
const COLOR_BG := Color(0.08, 0.1, 0.12)
const COLOR_COMMAND := Color(0.3, 0.7, 1.0)  # Blue for commands

# Commands (type to execute)
const CMD_ALL := "ALL"
const CMD_DE := "DE"
const CMD_EN := "EN"
const CMD_SUBMIT := "SUBMIT"  # Future: submit own works

# Filter options
const FILTER_OPTIONS := ["ALL", "DE", "EN"]
const FILTER_LABELS := {"ALL": "Alle Werke", "DE": "Deutsch", "EN": "English"}

# Bilingual strings
const STRINGS := {
	"continue": {"DE": "Fortsetzen", "EN": "Continue"},
	"restart": {"DE": "Neustart", "EN": "Restart"},
	"progress": {"DE": "Fortschritt", "EN": "Progress"},
	"by": {"DE": "von", "EN": "by"},
}

# UI References
@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var filter_container: HBoxContainer = $VBoxContainer/FilterContainer
@onready var carousel_container: Control = $VBoxContainer/CarouselContainer
@onready var hint_label: Label = $VBoxContainer/HintLabel
@onready var typed_display: Label = $VBoxContainer/TypedDisplay

# Filter chip button
var filter_chip: Button = null
var current_filter: String = "ALL"
var selected_index: int = 0
var typed_buffer: String = ""
var works: Array = []  # Current filtered works
var cards: Array = []  # Card nodes

# Confirmation dialog
var confirm_dialog: Control = null
var pending_work = null

# Blur shader for side cards
var blur_shader: Shader

func _ready() -> void:
	_setup_shader()
	_create_filter_chip()
	_refresh_works()
	_create_carousel_cards()
	# Defer carousel update until layout is ready
	await get_tree().process_frame
	_update_carousel(false)
	_update_ui()

func on_enter(_params: Dictionary) -> void:
	DebugHelper.log_info("ZenSelectState entered")
	MenuBackground.show_background()
	typed_buffer = ""
	selected_index = 0
	_create_filter_chip()
	_refresh_works()
	_create_carousel_cards()
	# Defer carousel update until layout is ready
	await get_tree().process_frame
	_update_carousel(false)
	_update_ui()

func on_exit() -> void:
	DebugHelper.log_info("ZenSelectState exiting")
	_clear_cards()

func _create_filter_chip() -> void:
	# Remove existing chip if any
	if filter_chip and is_instance_valid(filter_chip):
		filter_chip.queue_free()
	
	# Create filter chip button
	filter_chip = Button.new()
	filter_chip.name = "FilterChip"
	filter_chip.custom_minimum_size = Vector2(140, 36)
	filter_chip.text = FILTER_LABELS[current_filter]
	filter_chip.flat = false
	
	# Style the chip
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.17, 0.2)
	style.border_color = COLOR_SELECTED
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.content_margin_left = 16
	style.content_margin_right = 16
	filter_chip.add_theme_stylebox_override("normal", style)
	
	var hover_style := style.duplicate()
	hover_style.bg_color = Color(0.2, 0.22, 0.25)
	filter_chip.add_theme_stylebox_override("hover", hover_style)
	
	var pressed_style := style.duplicate()
	pressed_style.bg_color = COLOR_SELECTED.darkened(0.5)
	filter_chip.add_theme_stylebox_override("pressed", pressed_style)
	
	filter_chip.add_theme_font_size_override("font_size", 16)
	filter_chip.add_theme_color_override("font_color", COLOR_SELECTED)
	filter_chip.add_theme_color_override("font_hover_color", Color.WHITE)
	
	# Connect signals
	filter_chip.pressed.connect(_on_filter_chip_pressed)
	filter_chip.mouse_entered.connect(func(): SoundManager.play_menu_select())
	
	filter_container.add_child(filter_chip)

func _on_filter_chip_pressed() -> void:
	_cycle_filter()

func _cycle_filter() -> void:
	var idx := FILTER_OPTIONS.find(current_filter)
	idx = (idx + 1) % FILTER_OPTIONS.size()
	current_filter = FILTER_OPTIONS[idx]
	typed_buffer = ""
	selected_index = 0
	_refresh_works()
	_create_carousel_cards()
	# Defer carousel update until layout is ready
	await get_tree().process_frame
	_update_carousel(false)
	_update_ui()
	SoundManager.play_menu_select()

func _load_image_texture(res_path: String) -> ImageTexture:
	if res_path.is_empty():
		return null
	# Load image directly from file (works without Godot import)
	var abs_path := ProjectSettings.globalize_path(res_path)
	var image := Image.new()
	var err := image.load(abs_path)
	if err != OK:
		DebugHelper.log_warning("ZenSelectState: Failed to load image: %s" % res_path)
		return null
	return ImageTexture.create_from_image(image)

func _setup_shader() -> void:
	# Simple blur/desaturate shader for non-selected cards
	blur_shader = Shader.new()
	blur_shader.code = """
shader_type canvas_item;
uniform float blur_amount : hint_range(0.0, 5.0) = 0.0;
uniform float desaturate : hint_range(0.0, 1.0) = 0.0;
uniform float darken : hint_range(0.0, 1.0) = 0.0;
uniform float corner_radius : hint_range(0.0, 20.0) = 0.0;
uniform vec2 rect_size = vec2(480.0, 320.0);

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	// Desaturate
	float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
	color.rgb = mix(color.rgb, vec3(gray), desaturate);
	// Darken
	color.rgb *= (1.0 - darken);
	// Corner clipping
	if (corner_radius > 0.0) {
		vec2 pixel_pos = UV * rect_size;
		vec2 from_corner = min(pixel_pos, rect_size - pixel_pos);
		if (from_corner.x < corner_radius && from_corner.y < corner_radius) {
			float dist = corner_radius - length(vec2(corner_radius) - from_corner);
			color.a *= smoothstep(0.0, 1.5, dist);
		}
	}
	COLOR = color;
}
"""

func _refresh_works() -> void:
	if current_filter == "ALL":
		works = ZenWorksLoader.get_all_works()
	else:
		works = ZenWorksLoader.get_works_for_language(current_filter)
	if works.is_empty():
		DebugHelper.log_warning("ZenSelectState: No works found for filter %s" % current_filter)
	selected_index = clampi(selected_index, 0, maxi(0, works.size() - 1))

func _clear_cards() -> void:
	for card in cards:
		if is_instance_valid(card):
			card.queue_free()
	cards.clear()

func _create_carousel_cards() -> void:
	_clear_cards()

	for i in range(works.size()):
		var work = works[i]
		var card: Control = _create_card(work, i)
		carousel_container.add_child(card)
		cards.append(card)

func _create_card(work, index: int) -> Control:
	var card := Control.new()
	card.name = "Card_%d" % index
	

	# Panel for styled background
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Card style with rounded corners
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = COLOR_BG
	card_style.border_color = COLOR_BORDER_UNSELECTED
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(12)
	card_style.content_margin_left = 0
	card_style.content_margin_right = 0
	card_style.content_margin_top = 0
	card_style.content_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", card_style)
	card.add_child(panel)

	# Enable mouse input (click only, no hover scrolling)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_card_gui_input.bind(card))

	# Container with clip_contents to properly clip image to panel bounds
	var preview_container := Control.new()
	preview_container.name = "PreviewContainer"
	preview_container.mouse_filter = Control.MOUSE_FILTER_PASS
	preview_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_container.clip_contents = true
	panel.add_child(preview_container)

	# Background - preview image or fallback color
	var preview_texture: Texture2D = _load_image_texture(work.preview_path)
	var bg_node: Control = null
	if preview_texture:
		var preview := TextureRect.new()
		preview.name = "Background"
		preview.mouse_filter = Control.MOUSE_FILTER_PASS
		preview.texture = preview_texture
		preview.set_anchors_preset(Control.PRESET_FULL_RECT)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		# Apply shader to preview for corner rounding and effects
		var mat := ShaderMaterial.new()
		mat.shader = blur_shader
		mat.set_shader_parameter("blur_amount", 0.0)
		mat.set_shader_parameter("desaturate", 0.0)
		mat.set_shader_parameter("darken", 0.0)
		mat.set_shader_parameter("corner_radius", 10.0)
		mat.set_shader_parameter("rect_size", Vector2(CARD_WIDTH_SELECTED, CARD_HEIGHT_SELECTED))
		preview.material = mat
		preview_container.add_child(preview)
		bg_node = preview

		# Darken overlay for text readability
		var overlay := ColorRect.new()
		overlay.name = "Overlay"
		overlay.mouse_filter = Control.MOUSE_FILTER_PASS
		overlay.color = Color(0.0, 0.0, 0.0, 0.5)
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		card.add_child(overlay)
	else:
		var bg := ColorRect.new()
		bg.name = "Background"
		bg.mouse_filter = Control.MOUSE_FILTER_PASS
		bg.color = COLOR_BG
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		card.add_child(bg)
		bg_node = bg

	# Language pill (top left)
	var lang_pill := PanelContainer.new()
	lang_pill.name = "LangPill"
	lang_pill.mouse_filter = Control.MOUSE_FILTER_PASS
	var pill_style := StyleBoxFlat.new()
	pill_style.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	pill_style.set_corner_radius_all(12)
	pill_style.content_margin_left = 10
	pill_style.content_margin_right = 10
	pill_style.content_margin_top = 4
	pill_style.content_margin_bottom = 4
	lang_pill.add_theme_stylebox_override("panel", pill_style)
	lang_pill.set_anchors_preset(Control.PRESET_TOP_LEFT)
	lang_pill.offset_left = 12
	lang_pill.offset_top = 12
	var lang_label := Label.new()
	lang_label.text = work.language
	lang_label.add_theme_font_size_override("font_size", 12)
	lang_label.add_theme_color_override("font_color", Color.WHITE)
	lang_pill.add_child(lang_label)
	card.add_child(lang_pill)

	# Title (center of card)
	var title := Label.new()
	title.name = "Title"
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	title.text = work.title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.offset_left = 16
	title.offset_right = -16
	title.offset_top = 0
	title.offset_bottom = -30
	title.add_theme_font_size_override("font_size", 28)
	var bold_font = load("res://assets/fonts/zen/Crimson-Bold.otf")
	if bold_font:
		title.add_theme_font_override("font", bold_font)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	card.add_child(title)

	# Author (bottom centered)
	var author := Label.new()
	author.name = "Author"
	author.mouse_filter = Control.MOUSE_FILTER_PASS
	author.text = work.author
	author.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	author.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	author.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	author.offset_top = -30
	author.offset_bottom = -10
	author.add_theme_font_size_override("font_size", 18)
	author.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	author.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	author.add_theme_constant_override("shadow_offset_x", 1)
	author.add_theme_constant_override("shadow_offset_y", 1)
	card.add_child(author)

	return card

# Mouse event handlers
func _on_card_gui_input(event: InputEvent, card: Control) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var idx = cards.find(card)
		if idx != -1:
			selected_index = idx
			typed_buffer = ""
			SoundManager.play_word_complete()
			_update_carousel(true)
			_update_ui()
			_confirm_selection()

func _on_card_mouse_entered(card: Control) -> void:
	if InputMode.is_keyboard_mode():
		return
	var idx = cards.find(card)
	if idx != -1 and idx != selected_index:
		selected_index = idx
		typed_buffer = ""
		SoundManager.play_menu_select()
		_update_carousel(true)
		_update_ui()

func _on_card_mouse_exited(_card: Control) -> void:
	pass  # Keep selection on mouse exit

func _get_best_match() -> int:
	# Returns the index of the best matching work based on typed buffer
	if typed_buffer.length() == 0:
		return selected_index
	for i in range(works.size()):
		var work = works[i]
		var title_upper: String = work.title.to_upper()
		if title_upper.begins_with(typed_buffer):
			return i
	return -1  # No match

func _update_carousel(animate: bool = true) -> void:
	if cards.is_empty():
		return

	var container_width: float = carousel_container.size.x
	var center_x: float = container_width / 2.0

	for i in range(cards.size()):
		var card: Control = cards[i]
		var is_selected: bool = (i == selected_index)

		# Target dimensions
		var target_width: float = CARD_WIDTH_SELECTED if is_selected else CARD_WIDTH_SIDE
		var target_height: float = CARD_HEIGHT_SELECTED if is_selected else CARD_HEIGHT_SIDE

		# Calculate x position relative to selected
		var offset_from_selected: int = i - selected_index
		var target_x: float = center_x - (target_width / 2.0)
		target_x += offset_from_selected * (CARD_WIDTH_SIDE + CARD_SPACING)

		# Y position (centered vertically, selected slightly higher)
		var container_height: float = carousel_container.size.y
		var target_y: float = (container_height - target_height) / 2.0
		if not is_selected:
			target_y += 20  # Push non-selected cards down slightly

		# Z-index (selected on top)
		var z_idx: int = 10 if is_selected else (5 - absi(offset_from_selected))

		# Shader parameters
		var desaturate: float = 0.0 if is_selected else 0.6
		var darken: float = 0.0 if is_selected else 0.3

		# Border and title styling
		var border_color: Color = COLOR_BORDER_SELECTED if is_selected else COLOR_BORDER_UNSELECTED
		var border_width: int = 4 if is_selected else 2
		var title_size: int = 36 if is_selected else 28
		
		# Get title label for font size animation
		var title_label: Label = card.get_node_or_null("Content/Title")

		if animate:
			var tween := create_tween()
			tween.set_parallel(true)
			tween.tween_property(card, "position", Vector2(target_x, target_y), TRANSITION_TIME)
			tween.tween_property(card, "size", Vector2(target_width, target_height), TRANSITION_TIME)
			tween.tween_property(card, "z_index", z_idx, TRANSITION_TIME)

			var panel_node = card.get_node_or_null("Panel")
			var preview_container = panel_node.get_node_or_null("PreviewContainer") if panel_node else null
			var bg_node = preview_container.get_node_or_null("Background") if preview_container else null
			if bg_node and bg_node.material:
				bg_node.material.set_shader_parameter("rect_size", Vector2(target_width, target_height))
				tween.tween_property(bg_node.material, "shader_parameter/desaturate", desaturate, TRANSITION_TIME)
				tween.tween_property(bg_node.material, "shader_parameter/darken", darken, TRANSITION_TIME)

			# Update StyleBox (can't tween, so just set)
			var style: StyleBoxFlat = panel_node.get_theme_stylebox("panel").duplicate() if panel_node else StyleBoxFlat.new()
			style.border_color = border_color
			style.set_border_width_all(border_width)
			if panel_node: panel_node.add_theme_stylebox_override("panel", style)
			
			# Update title font size
			if title_label:
				title_label.add_theme_font_size_override("font_size", title_size)
		else:
			card.position = Vector2(target_x, target_y)
			card.size = Vector2(target_width, target_height)
			card.z_index = z_idx

			var panel_node = card.get_node_or_null("Panel")
			var preview_container = panel_node.get_node_or_null("PreviewContainer") if panel_node else null
			var bg_node = preview_container.get_node_or_null("Background") if preview_container else null
			if bg_node and bg_node.material:
				bg_node.material.set_shader_parameter("rect_size", Vector2(target_width, target_height))
				bg_node.material.set_shader_parameter("desaturate", desaturate)
				bg_node.material.set_shader_parameter("darken", darken)

			# Update StyleBox
			var style: StyleBoxFlat = panel_node.get_theme_stylebox("panel").duplicate() if panel_node else StyleBoxFlat.new()
			style.border_color = border_color
			style.set_border_width_all(border_width)
			if panel_node: panel_node.add_theme_stylebox_override("panel", style)
			
			# Update title font size
			if title_label:
				title_label.add_theme_font_size_override("font_size", title_size)

func _update_ui() -> void:
	# Update filter chip text
	if filter_chip:
		filter_chip.text = FILTER_LABELS[current_filter]

	# Update hint label
	if hint_label:
		if works.is_empty():
			hint_label.text = "Keine Werke gefunden / No works found"
		else:
			hint_label.text = "< > Auswahl   ENTER Start   TAB Filter   ESC Zurueck"

	# Update typed display
	if typed_display:
		typed_display.text = typed_buffer

		if typed_buffer.length() > 0:
			var matches: bool = _check_typed_match()
			typed_display.add_theme_color_override("font_color", COLOR_SELECTED if matches else Color(1, 0.3, 0.3))
		else:
			typed_display.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

func _check_typed_match() -> bool:
	# Returns true if typed buffer matches a command or work title (no side effects)
	if typed_buffer.is_empty():
		return false

	# Check for filter commands (ALL, DE, EN)
	for filter_opt in FILTER_OPTIONS:
		if filter_opt.begins_with(typed_buffer):
			return true

	# Check for submit command
	if CMD_SUBMIT.begins_with(typed_buffer):
		return true

	# Check for work title matches
	for i in range(works.size()):
		var work = works[i]
		var title_upper: String = work.title.to_upper()
		if title_upper.begins_with(typed_buffer):
			return true

	return false

func _execute_typed_command() -> void:
	# Execute completed commands - call this after typing
	if typed_buffer.is_empty():
		return

	# Check for filter commands (ALL, DE, EN)
	for filter_opt in FILTER_OPTIONS:
		if typed_buffer == filter_opt:
			if current_filter != filter_opt:
				_set_filter(filter_opt)
			else:
				typed_buffer = ""
				_update_ui()
			return

	# Check for submit command (placeholder)
	if typed_buffer == CMD_SUBMIT:
		SoundManager.play_menu_select()
		DebugHelper.log_info("SUBMIT: Feature coming soon!")
		typed_buffer = ""
		_update_ui()
		return

	# Check for work title matches - auto-select matching work
	for i in range(works.size()):
		var work = works[i]
		var title_upper: String = work.title.to_upper()
		if title_upper.begins_with(typed_buffer):
			if selected_index != i:
				selected_index = i
				_update_carousel(true)
			return

func _set_filter(new_filter: String) -> void:
	current_filter = new_filter
	typed_buffer = ""
	selected_index = 0
	_refresh_works()
	_create_carousel_cards()
	# Defer carousel update until layout is ready
	await get_tree().process_frame
	_update_carousel(false)
	_update_ui()
	SoundManager.play_menu_select()

func is_back_button_area(pos: Vector2) -> bool:
	# Back button area in bottom-left corner
	return pos.x < 120 and pos.y > GameConfig.SCREEN_HEIGHT - 60

func _input(event: InputEvent) -> void:
	# Handle dialog-specific input first
	if confirm_dialog != null:
		if event is InputEventKey and event.pressed and not event.is_echo():
			if event.keycode == KEY_ESCAPE:
				_close_confirm_dialog()
				get_viewport().set_input_as_handled()
		return  # Block other input while dialog is open

	# Mouse wheel scrolling
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_navigate(-1)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_navigate(1)
			get_viewport().set_input_as_handled()
			return

		if event.button_index == MOUSE_BUTTON_XBUTTON1:
			SoundManager.play_menu_back()
			StateManager.change_state("solo_mode_select")
			return

	if event is InputEventKey and event.pressed and not event.is_echo():
		var handled: bool = true

		match event.keycode:
			KEY_ESCAPE:
				SoundManager.play_menu_back()
				StateManager.change_state("solo_mode_select")

			KEY_ENTER:
				# Autofill best match and confirm
				var best_idx = _get_best_match()
				if best_idx >= 0:
					selected_index = best_idx
					_update_carousel(true)
					_update_ui()
				_confirm_selection()

			KEY_TAB:
				# Cycle filter with TAB key
				_cycle_filter()

			KEY_LEFT:
				_navigate(-1)

			KEY_RIGHT:
				_navigate(1)

			KEY_BACKSPACE:
				if typed_buffer.length() > 0:
					typed_buffer = typed_buffer.substr(0, typed_buffer.length() - 1)
					SoundManager.play_menu_select()
					_update_ui()

			_:
				# Check for letter input
				var char_code: int = event.unicode
				var is_letter: bool = (char_code >= 65 and char_code <= 90) or (char_code >= 97 and char_code <= 122)
				var is_umlaut: bool = char_code in [196, 214, 220, 228, 246, 252]

				if is_letter or is_umlaut:
					typed_buffer += char(char_code).to_upper()
					SoundManager.play_menu_select()
					_execute_typed_command()
					_update_ui()
				else:
					handled = false

		if handled:
			get_viewport().set_input_as_handled()

func _navigate(direction: int) -> void:
	if works.is_empty():
		return

	selected_index = (selected_index + direction + works.size()) % works.size()
	typed_buffer = ""
	SoundManager.play_menu_select()
	_update_carousel(true)
	_update_ui()

func _confirm_selection() -> void:
	if works.is_empty():
		return

	var work = works[selected_index]
	pending_work = work
	SoundManager.play_word_complete()
	_show_confirm_dialog(work)

func _show_confirm_dialog(work) -> void:
	if confirm_dialog:
		confirm_dialog.queue_free()

	var has_progress := ZenProgressManager.has_progress(work.id)
	var progress_pct := ZenProgressManager.get_progress_percentage(work.id) if has_progress else 0.0
	var lang: String = work.language  # Use work language for dialog

	# Create dialog overlay
	confirm_dialog = Control.new()
	confirm_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	confirm_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	confirm_dialog.z_index = 100  # On top of carousel cards
	add_child(confirm_dialog)

	# Dim background
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.7)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dialog_background_click)
	confirm_dialog.add_child(dim)

	# Dialog box
	var dialog_box := PanelContainer.new()
	dialog_box.custom_minimum_size = Vector2(400, 280)
	dialog_box.set_anchors_preset(Control.PRESET_CENTER)
	dialog_box.set("offset_left", -200)
	dialog_box.set("offset_right", 200)
	dialog_box.set("offset_top", -140)
	dialog_box.set("offset_bottom", 140)

	# Style the panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.12, 0.95)
	style.border_color = COLOR_BORDER_SELECTED
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	dialog_box.add_theme_stylebox_override("panel", style)
	confirm_dialog.add_child(dialog_box)

	# Content
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.set("offset_left", 30)
	vbox.set("offset_right", -30)
	vbox.set("offset_top", 30)
	vbox.set("offset_bottom", -30)
	vbox.add_theme_constant_override("separation", 15)
	dialog_box.add_child(vbox)

	# Title
	var title_lbl := Label.new()
	title_lbl.text = work.title
	title_lbl.add_theme_font_size_override("font_size", 28)
	title_lbl.add_theme_color_override("font_color", Color.WHITE)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)

	# Author
	var author_lbl := Label.new()
	author_lbl.text = STRINGS["by"][lang] + " " + work.author
	author_lbl.add_theme_font_size_override("font_size", 16)
	author_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	author_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(author_lbl)

	# Progress (if exists)
	if has_progress:
		var progress_lbl := Label.new()
		progress_lbl.text = "%s: %.0f%%" % [STRINGS["progress"][lang], progress_pct]
		progress_lbl.add_theme_font_size_override("font_size", 18)
		progress_lbl.add_theme_color_override("font_color", COLOR_SELECTED)
		progress_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(progress_lbl)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Buttons container
	var btn_container := VBoxContainer.new()
	btn_container.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_container)

	# Continue button (only if progress exists)
	if has_progress:
		var continue_btn := Button.new()
		continue_btn.text = STRINGS["continue"][lang]
		continue_btn.add_theme_font_size_override("font_size", 20)
		continue_btn.custom_minimum_size = Vector2(0, 50)
		continue_btn.pressed.connect(_on_continue_pressed)
		continue_btn.mouse_entered.connect(func(): SoundManager.play_menu_select())
		btn_container.add_child(continue_btn)

		# Style continue button (primary)
		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = COLOR_SELECTED.darkened(0.3)
		btn_style.set_corner_radius_all(4)
		continue_btn.add_theme_stylebox_override("normal", btn_style)
		var btn_hover := btn_style.duplicate()
		btn_hover.bg_color = COLOR_SELECTED.darkened(0.1)
		continue_btn.add_theme_stylebox_override("hover", btn_hover)
		var btn_press := btn_style.duplicate()
		btn_press.bg_color = COLOR_SELECTED
		continue_btn.add_theme_stylebox_override("pressed", btn_press)
		continue_btn.add_theme_color_override("font_color", Color.WHITE)
		continue_btn.add_theme_color_override("font_hover_color", Color.WHITE)

	# Restart button
	var restart_btn := Button.new()
	restart_btn.text = STRINGS["restart"][lang]
	restart_btn.add_theme_font_size_override("font_size", 20)
	restart_btn.custom_minimum_size = Vector2(0, 50)
	restart_btn.pressed.connect(_on_restart_pressed)
	restart_btn.mouse_entered.connect(func(): SoundManager.play_menu_select())
	btn_container.add_child(restart_btn)

	# Style restart button (secondary if there is progress, primary otherwise)
	var restart_style := StyleBoxFlat.new()
	if has_progress:
		restart_style.bg_color = Color(0.2, 0.2, 0.25)
	else:
		restart_style.bg_color = COLOR_SELECTED.darkened(0.3)
	restart_style.set_corner_radius_all(4)
	restart_btn.add_theme_stylebox_override("normal", restart_style)
	var restart_hover := restart_style.duplicate()
	restart_hover.bg_color = restart_style.bg_color.lightened(0.2)
	restart_btn.add_theme_stylebox_override("hover", restart_hover)
	restart_btn.add_theme_color_override("font_color", Color.WHITE)
	restart_btn.add_theme_color_override("font_hover_color", Color.WHITE)

	# Focus the appropriate button
	if has_progress:
		# Focus continue button (first child of btn_container)
		await get_tree().process_frame
		btn_container.get_child(0).grab_focus()
	else:
		await get_tree().process_frame
		restart_btn.grab_focus()

func _on_dialog_background_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_confirm_dialog()

func _close_confirm_dialog() -> void:
	if confirm_dialog:
		confirm_dialog.queue_free()
		confirm_dialog = null
		pending_work = null
		SoundManager.play_menu_back()

func _on_continue_pressed() -> void:
	if pending_work == null:
		return
	SoundManager.play_word_complete()
	var progress := ZenProgressManager.get_progress(pending_work.id)
	StateManager.change_state("zen_play", {
		"work_id": pending_work.id,
		"resume_index": progress.get("cursor_index", 0)
	})

func _on_restart_pressed() -> void:
	if pending_work == null:
		return
	SoundManager.play_word_complete()
	ZenProgressManager.clear_progress(pending_work.id)
	StateManager.change_state("zen_play", {"work_id": pending_work.id})
