## build_hud.gd
## Renders the BUILD mode overlay UI with live typing feedback
extends Control

const COLOR_BG := Color(0.02, 0.02, 0.05, 0.85)
const COLOR_TITLE := Color("#FF2A8A")
const COLOR_TEXT := Color.WHITE
const COLOR_DIM := Color("#666688")
const COLOR_TYPED := Color("#7CFF00")  # Acid green for typed chars
const COLOR_UNTYPED := Color.WHITE
const COLOR_HIGHLIGHT := Color("#00E5FF")
const COLOR_AFFORDABLE := Color("#7CFF00")
const COLOR_UNAFFORDABLE := Color("#FF4444")
const COLOR_POSITION := Color("#00E5FF")
const COLOR_POSITION_OCCUPIED := Color("#444466")

var visible_in_build_mode: bool = false

func _ready() -> void:
	# Connect to BuildManager signals
	BuildManager.build_mode_entered.connect(_on_build_mode_entered)
	BuildManager.build_mode_exited.connect(_on_build_mode_exited)

func _on_build_mode_entered() -> void:
	visible_in_build_mode = true

func _on_build_mode_exited() -> void:
	visible_in_build_mode = false

func _process(_delta: float) -> void:
	# Always redraw for live typing feedback
	queue_redraw()

func _draw() -> void:
	# Always draw placed towers (even outside build mode)
	draw_placed_towers()

	if not visible_in_build_mode:
		# Show BUILD command with typing progress
		draw_build_command_hint()
		return

	# Draw semi-transparent overlay
	draw_rect(Rect2(0, 0, 1280, 720), COLOR_BG)

	var phase := BuildManager.get_build_phase()

	if phase == BuildManager.BuildPhase.SELECTING_TOWER:
		draw_tower_selection()
	else:
		draw_position_selection()

	# Always draw build points
	draw_build_points()

func draw_build_command_hint() -> void:
	# Show BUILD command in bottom right with typing progress
	var font := ThemeDB.fallback_font
	var build_word := "BUILD"
	var typed_buffer := TypingManager.build_buffer
	var x := 1100
	var y := 700

	# Draw background for better visibility
	draw_rect(Rect2(x - 10, y - 25, 120, 35), Color(0, 0, 0, 0.5))

	# Draw each character
	for i in range(build_word.length()):
		var char_str := build_word[i]
		var is_typed := i < typed_buffer.length() and typed_buffer[i] == char_str
		var color := COLOR_TYPED if is_typed else COLOR_DIM

		draw_string(font, Vector2(x, y), char_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, color)
		x += 20

	# Also show build points outside build mode
	var points := BuildManager.get_build_points()
	draw_string(font, Vector2(1100, y - 35), "%d pts" % points, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_HIGHLIGHT)

func draw_tower_selection() -> void:
	var font := ThemeDB.fallback_font
	var center_x := 640
	var buffer := BuildManager.get_build_buffer()

	# Title
	draw_string(font, Vector2(center_x - 80, 100), "BUILD MODE", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, COLOR_TITLE)

	# Instructions
	draw_string(font, Vector2(center_x - 100, 140), "Type tower name to build", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_DIM)

	# Available towers with typing progress
	var towers := BuildManager.get_available_towers()
	var y := 200

	for tower_info in towers:
		var stats: Dictionary = tower_info.stats
		var command: String = tower_info.command
		var can_build: bool = tower_info.can_build
		var remaining: int = tower_info.remaining

		# Check if currently typing this command
		var is_typing_this := command.begins_with(buffer) and buffer.length() > 0

		# Draw command with character-by-character coloring
		var char_x := center_x - 120
		for i in range(command.length()):
			var char_str := command[i]
			var color: Color

			if i < buffer.length() and buffer[i] == char_str:
				# Typed correctly
				color = COLOR_TYPED
			elif not can_build:
				# Can't afford
				color = COLOR_UNAFFORDABLE
			elif is_typing_this:
				# Currently typing this command
				color = COLOR_UNTYPED
			else:
				# Not typing this
				color = COLOR_DIM

			draw_string(font, Vector2(char_x, y), char_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, color)
			char_x += 22

		# Cost and remaining
		var cost_color := COLOR_AFFORDABLE if can_build else COLOR_UNAFFORDABLE
		draw_string(font, Vector2(center_x + 80, y), "%d pts" % stats.cost, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, cost_color)
		draw_string(font, Vector2(center_x + 160, y), "(%d/wave)" % remaining, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_DIM)

		# Description
		draw_string(font, Vector2(center_x - 120, y + 28), stats.description, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_DIM)

		y += 80

	# Draw EXIT option
	y += 20
	var cancel_word := "EXIT"
	var char_x := center_x - 120
	for i in range(cancel_word.length()):
		var char_str := cancel_word[i]
		var color: Color
		if i < buffer.length() and buffer[i] == char_str:
			color = COLOR_TYPED
		elif cancel_word.begins_with(buffer) and buffer.length() > 0:
			color = COLOR_UNTYPED
		else:
			color = COLOR_DIM
		draw_string(font, Vector2(char_x, y), char_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, color)
		char_x += 20

	draw_string(font, Vector2(center_x + 40, y), "or CANCEL or ESC", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_DIM)

	# Current typed buffer display
	if buffer.length() > 0:
		draw_string(font, Vector2(center_x - 50, 600), "> " + buffer, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, COLOR_HIGHLIGHT)

func draw_position_selection() -> void:
	var font := ThemeDB.fallback_font
	var center_x := 640
	var buffer := BuildManager.get_build_buffer()

	# Title with selected tower
	var tower_type := BuildManager.get_selected_tower_type()
	var command: String = BuildManager.TOWER_COMMANDS.get(tower_type, "")
	var stats: Dictionary = BuildManager.TOWER_STATS.get(tower_type, {})
	draw_string(font, Vector2(center_x - 100, 80), "PLACE " + command, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, COLOR_TITLE)

	# Cost info
	draw_string(font, Vector2(center_x - 60, 110), "Cost: %d pts" % stats.get("cost", 0), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_HIGHLIGHT)

	# Instructions
	draw_string(font, Vector2(center_x - 80, 150), "Type 0-9 to select position", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COLOR_TEXT)

	# Draw position indicators around portal
	var positions := BuildManager.get_build_positions()
	for pos in positions:
		var is_occupied: bool = pos.occupied
		var bg_color := COLOR_POSITION_OCCUPIED if is_occupied else Color(0.1, 0.1, 0.15, 0.8)
		var border_color := COLOR_POSITION_OCCUPIED if is_occupied else COLOR_POSITION

		# Draw circle background
		draw_circle(Vector2(pos.x, pos.y), 25, bg_color)

		# Draw border
		for i in range(24):
			var angle := float(i) / 24 * TAU
			var next_angle := float(i + 1) / 24 * TAU
			var p1 := Vector2(pos.x + cos(angle) * 25, pos.y + sin(angle) * 25)
			var p2 := Vector2(pos.x + cos(next_angle) * 25, pos.y + sin(next_angle) * 25)
			draw_line(p1, p2, border_color, 2)

		# Draw position number
		var num_str := str(pos.index)
		var text_color := COLOR_DIM if is_occupied else COLOR_TEXT
		var text_pos := Vector2(pos.x - 7, pos.y + 8)
		draw_string(font, text_pos, num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, text_color)

	# Draw existing towers
	var towers := BuildManager.get_towers()
	for tower in towers:
		var tower_stats: Dictionary = tower.stats
		draw_circle(Vector2(tower.x, tower.y), 18, tower_stats.color)
		draw_circle(Vector2(tower.x, tower.y), 10, tower_stats.inner_color)

	# EXIT option at bottom
	var y := 580
	var cancel_word := "EXIT"
	var char_x := center_x - 60
	for i in range(cancel_word.length()):
		var char_str := cancel_word[i]
		var color: Color
		if i < buffer.length() and buffer[i] == char_str:
			color = COLOR_TYPED
		elif cancel_word.begins_with(buffer) and buffer.length() > 0:
			color = COLOR_UNTYPED
		else:
			color = COLOR_DIM
		draw_string(font, Vector2(char_x, y), char_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, color)
		char_x += 18

	draw_string(font, Vector2(center_x + 40, y), "or CANCEL or ESC", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_DIM)

func draw_build_points() -> void:
	var font := ThemeDB.fallback_font
	var points := BuildManager.get_build_points()
	var text := "BUILD POINTS: %d" % points
	draw_string(font, Vector2(50, 40), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, COLOR_HIGHLIGHT)

func draw_placed_towers() -> void:
	# Draw all placed towers with their effect radius
	var towers := BuildManager.get_towers()
	if towers.is_empty():
		return

	for tower in towers:
		if not tower.has("stats") or not tower.has("x") or not tower.has("y"):
			continue

		var tower_stats: Dictionary = tower.stats
		var pos := Vector2(tower.x, tower.y)

		# Draw effect radius (subtle)
		if tower_stats.has("effect_radius") and tower_stats.has("color"):
			var radius_color: Color = tower_stats.color
			radius_color.a = 0.15
			draw_circle(pos, tower_stats.effect_radius, radius_color)

			# Draw tower body
			draw_circle(pos, 20, tower_stats.color)
			if tower_stats.has("inner_color"):
				draw_circle(pos, 12, tower_stats.inner_color)

		# Draw targeting line for gun towers
		if tower.has("type") and tower.type == BuildManager.TowerType.GUN:
			if tower.has("target") and tower.target != null and is_instance_valid(tower.target):
				var target_pos: Vector2 = tower.target.global_position
				draw_line(pos, target_pos, Color(1, 0.3, 0.3, 0.6), 2)
