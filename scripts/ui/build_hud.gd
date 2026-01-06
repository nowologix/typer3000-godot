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
const COLOR_UPGRADE := Color("#FFD700")  # Gold for upgrades
const COLOR_MAX_LEVEL := Color("#FF44FF")  # Magenta for max level towers

# GUN turret animated sprite config
const GUN_SPRITE_PATH := "res://assets/sprites/towers/gun/"
const GUN_FRAME_COUNT := 66
const GUN_FPS := 20.0
const GUN_SPRITE_SCALE := 0.36  # Scale 256px to ~92px diameter

# TESLA turret animated sprite config
const TESLA_SPRITE_PATH := "res://assets/sprites/towers/tesla/"
const TESLA_FRAME_COUNT := 77
const TESLA_FPS := 20.0
const TESLA_SPRITE_SCALE := 0.36  # Same size as GUN

# FREEZE turret animated sprite config
const FREEZE_SPRITE_PATH := "res://assets/sprites/towers/freeze/"
const FREEZE_FRAME_COUNT := 111
const FREEZE_FPS := 20.0
const FREEZE_SPRITE_SCALE := 0.36  # Same size as others

var visible_in_build_mode: bool = false
var is_in_upgrade_mode: bool = false
var tower_visuals: Dictionary = {}  # tower_id -> AnimatedSprite2D
var gun_sprite_frames: SpriteFrames = null
var tesla_sprite_frames: SpriteFrames = null
var freeze_sprite_frames: SpriteFrames = null

func _ready() -> void:
	# Connect to BuildManager signals
	BuildManager.build_mode_entered.connect(_on_build_mode_entered)
	BuildManager.build_mode_exited.connect(_on_build_mode_exited)
	BuildManager.tower_placed.connect(_on_tower_placed)
	BuildManager.towers_reset.connect(clear_tower_visuals)
	BuildManager.upgrade_mode_entered.connect(_on_upgrade_mode_entered)
	BuildManager.upgrade_mode_exited.connect(_on_upgrade_mode_exited)

	# Preload turret sprite frames
	_load_gun_sprite_frames()
	_load_tesla_sprite_frames()
	_load_freeze_sprite_frames()

func _load_gun_sprite_frames() -> void:
	gun_sprite_frames = SpriteFrames.new()
	gun_sprite_frames.add_animation("idle")
	gun_sprite_frames.set_animation_speed("idle", GUN_FPS)
	gun_sprite_frames.set_animation_loop("idle", true)

	for i in range(GUN_FRAME_COUNT):
		var frame_path := GUN_SPRITE_PATH + "typer3000-gun-turret-01_%02d.png" % i
		var texture := _load_png_directly(frame_path)
		if texture:
			gun_sprite_frames.add_frame("idle", texture)

	DebugHelper.log_info("BuildHUD: Loaded %d GUN turret frames" % gun_sprite_frames.get_frame_count("idle"))

func _load_tesla_sprite_frames() -> void:
	tesla_sprite_frames = SpriteFrames.new()
	tesla_sprite_frames.add_animation("idle")
	tesla_sprite_frames.set_animation_speed("idle", TESLA_FPS)
	tesla_sprite_frames.set_animation_loop("idle", true)

	for i in range(TESLA_FRAME_COUNT):
		var frame_path := TESLA_SPRITE_PATH + "typer3000-tesla-turret-01_%02d.png" % i
		var texture := _load_png_directly(frame_path)
		if texture:
			tesla_sprite_frames.add_frame("idle", texture)

	DebugHelper.log_info("BuildHUD: Loaded %d TESLA turret frames" % tesla_sprite_frames.get_frame_count("idle"))

func _load_freeze_sprite_frames() -> void:
	freeze_sprite_frames = SpriteFrames.new()
	freeze_sprite_frames.add_animation("idle")
	freeze_sprite_frames.set_animation_speed("idle", FREEZE_FPS)
	freeze_sprite_frames.set_animation_loop("idle", true)

	for i in range(FREEZE_FRAME_COUNT):
		var frame_path := FREEZE_SPRITE_PATH + "typer3000-freeze-turret-01_%03d.png" % i
		var texture := _load_png_directly(frame_path)
		if texture:
			freeze_sprite_frames.add_frame("idle", texture)

	DebugHelper.log_info("BuildHUD: Loaded %d FREEZE turret frames" % freeze_sprite_frames.get_frame_count("idle"))

func _load_png_directly(res_path: String) -> ImageTexture:
	var abs_path := ProjectSettings.globalize_path(res_path)
	var image := Image.new()
	var err := image.load(abs_path)
	if err != OK:
		return null
	return ImageTexture.create_from_image(image)

func _on_tower_placed(tower: Dictionary) -> void:
	# Create visual node for new tower
	_create_tower_visual(tower)

func _on_build_mode_entered() -> void:
	visible_in_build_mode = true

func _on_build_mode_exited() -> void:
	visible_in_build_mode = false
	is_in_upgrade_mode = false

func _on_upgrade_mode_entered() -> void:
	is_in_upgrade_mode = true

func _on_upgrade_mode_exited() -> void:
	is_in_upgrade_mode = false

func clear_tower_visuals() -> void:
	# Remove all animated tower sprites (called on game reset)
	for tower_id in tower_visuals:
		var sprite = tower_visuals[tower_id]
		if is_instance_valid(sprite):
			sprite.queue_free()
	tower_visuals.clear()
	DebugHelper.log_debug("BuildHUD: Cleared tower visuals")

func _create_tower_visual(tower: Dictionary) -> void:
	if not tower.has("type"):
		return

	var sprite: AnimatedSprite2D = null
	var tower_name: String = ""

	match tower.type:
		BuildManager.TowerType.GUN:
			if gun_sprite_frames == null or gun_sprite_frames.get_frame_count("idle") == 0:
				DebugHelper.log_warning("BuildHUD: GUN sprite frames not loaded")
				return
			sprite = AnimatedSprite2D.new()
			sprite.sprite_frames = gun_sprite_frames
			sprite.scale = Vector2(GUN_SPRITE_SCALE, GUN_SPRITE_SCALE)
			tower_name = "GUN"

		BuildManager.TowerType.TESLA:
			if tesla_sprite_frames == null or tesla_sprite_frames.get_frame_count("idle") == 0:
				DebugHelper.log_warning("BuildHUD: TESLA sprite frames not loaded")
				return
			sprite = AnimatedSprite2D.new()
			sprite.sprite_frames = tesla_sprite_frames
			sprite.scale = Vector2(TESLA_SPRITE_SCALE, TESLA_SPRITE_SCALE)
			tower_name = "TESLA"

		BuildManager.TowerType.FREEZE:
			if freeze_sprite_frames == null or freeze_sprite_frames.get_frame_count("idle") == 0:
				DebugHelper.log_warning("BuildHUD: FREEZE sprite frames not loaded")
				return
			sprite = AnimatedSprite2D.new()
			sprite.sprite_frames = freeze_sprite_frames
			sprite.scale = Vector2(FREEZE_SPRITE_SCALE, FREEZE_SPRITE_SCALE)
			tower_name = "FREEZE"

		_:
			return  # No animated sprite for this tower type

	sprite.animation = "idle"
	sprite.position = Vector2(tower.x, tower.y)
	sprite.z_index = 5  # Above background, below enemies

	add_child(sprite)
	sprite.play("idle")

	# Generate unique ID for this tower
	var tower_id := "%d_%d" % [int(tower.x), int(tower.y)]
	tower_visuals[tower_id] = sprite

	DebugHelper.log_info("BuildHUD: Created %s turret visual at (%d, %d)" % [tower_name, int(tower.x), int(tower.y)])

func _update_tower_visuals() -> void:
	var towers := BuildManager.get_towers()

	for tower in towers:
		if tower.type != BuildManager.TowerType.GUN:
			continue

		var tower_id := "%d_%d" % [int(tower.x), int(tower.y)]
		if not tower_visuals.has(tower_id):
			continue

		var sprite: AnimatedSprite2D = tower_visuals[tower_id]
		if not is_instance_valid(sprite):
			tower_visuals.erase(tower_id)
			continue

		# Rotate sprite to point at target
		if tower.has("target") and tower.target != null and is_instance_valid(tower.target):
			var tower_pos := Vector2(tower.x, tower.y)
			var target_pos: Vector2 = tower.target.global_position
			var direction := target_pos - tower_pos
			# Sprite arrow points UP, so we subtract PI/2 to adjust
			sprite.rotation = direction.angle() + PI / 2
		else:
			# No target - slowly rotate back to default (pointing up)
			sprite.rotation = lerp_angle(sprite.rotation, 0.0, 0.1)

func _process(_delta: float) -> void:
	# Update tower visual rotations
	_update_tower_visuals()
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
	elif phase == BuildManager.BuildPhase.SELECTING_UPGRADE:
		draw_upgrade_selection()
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

	# Draw UPGRADE option
	y += 20
	var upgrade_word := "UPGRADE"
	var upgradeable := BuildManager.get_upgradeable_towers()
	var can_upgrade := not upgradeable.is_empty()
	var char_x := center_x - 120

	for i in range(upgrade_word.length()):
		var char_str := upgrade_word[i]
		var color: Color
		if i < buffer.length() and buffer[i] == char_str:
			color = COLOR_TYPED
		elif not can_upgrade:
			color = COLOR_DIM
		elif upgrade_word.begins_with(buffer) and buffer.length() > 0:
			color = COLOR_UNTYPED
		else:
			color = COLOR_UPGRADE
		draw_string(font, Vector2(char_x, y), char_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, color)
		char_x += 20

	# Show upgrade info
	if can_upgrade:
		draw_string(font, Vector2(center_x + 80, y), "%d towers" % upgradeable.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_UPGRADE)
	else:
		draw_string(font, Vector2(center_x + 80, y), "no towers", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_DIM)

	# Draw EXIT option
	y += 50
	var cancel_word := "EXIT"
	char_x = center_x - 120
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

	# Draw existing towers (skip those with animated visuals)
	var towers := BuildManager.get_towers()
	for tower in towers:
		var tower_id := "%d_%d" % [int(tower.x), int(tower.y)]
		if tower_visuals.has(tower_id) and is_instance_valid(tower_visuals[tower_id]):
			continue  # Skip - has animated sprite
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

func draw_upgrade_selection() -> void:
	var font := ThemeDB.fallback_font
	var center_x := 640
	var buffer := BuildManager.get_build_buffer()

	# Title
	draw_string(font, Vector2(center_x - 100, 80), "UPGRADE MODE", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, COLOR_UPGRADE)

	# Instructions
	draw_string(font, Vector2(center_x - 120, 120), "Type 0-9 to select tower to upgrade", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COLOR_TEXT)

	# Get upgradeable towers info
	var upgradeable := BuildManager.get_upgradeable_towers()
	var upgradeable_positions: Dictionary = {}
	for info in upgradeable:
		upgradeable_positions[info.position] = info

	# Draw position indicators with tower info
	var positions := BuildManager.get_build_positions()
	for pos in positions:
		var tower = BuildManager.get_tower_at_position(pos.index)
		var has_tower := not tower.is_empty()

		if has_tower:
			# Position has a tower
			var level: int = tower.level
			var tower_type: int = tower.type
			var is_max := level >= BuildManager.MAX_TOWER_LEVEL

			# Determine colors
			var bg_color: Color
			var border_color: Color
			var text_color: Color

			if is_max:
				bg_color = Color(0.2, 0.1, 0.2, 0.9)
				border_color = COLOR_MAX_LEVEL
				text_color = COLOR_MAX_LEVEL
			elif upgradeable_positions.has(pos.index):
				var info = upgradeable_positions[pos.index]
				if info.can_afford:
					bg_color = Color(0.15, 0.15, 0.1, 0.9)
					border_color = COLOR_UPGRADE
					text_color = COLOR_UPGRADE
				else:
					bg_color = Color(0.15, 0.1, 0.1, 0.9)
					border_color = COLOR_UNAFFORDABLE
					text_color = COLOR_UNAFFORDABLE
			else:
				bg_color = Color(0.1, 0.1, 0.15, 0.9)
				border_color = COLOR_DIM
				text_color = COLOR_DIM

			# Draw circle background
			draw_circle(Vector2(pos.x, pos.y), 30, bg_color)

			# Draw border
			for i in range(24):
				var angle := float(i) / 24 * TAU
				var next_angle := float(i + 1) / 24 * TAU
				var p1 := Vector2(pos.x + cos(angle) * 30, pos.y + sin(angle) * 30)
				var p2 := Vector2(pos.x + cos(next_angle) * 30, pos.y + sin(next_angle) * 30)
				draw_line(p1, p2, border_color, 2)

			# Draw position number
			var num_str := str(pos.index)
			draw_string(font, Vector2(pos.x - 7, pos.y - 8), num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, text_color)

			# Draw tower type abbreviation and level
			var type_abbr := ""
			match tower_type:
				BuildManager.TowerType.GUN:
					type_abbr = "G"
				BuildManager.TowerType.FREEZE:
					type_abbr = "F"
				BuildManager.TowerType.TESLA:
					type_abbr = "T"

			var level_text := "%s%d" % [type_abbr, level]
			if is_max:
				level_text = "%sMAX" % type_abbr
			draw_string(font, Vector2(pos.x - 12, pos.y + 18), level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, text_color)

			# Draw upgrade cost below circle for upgradeable towers
			if not is_max and upgradeable_positions.has(pos.index):
				var info = upgradeable_positions[pos.index]
				var cost_color := COLOR_AFFORDABLE if info.can_afford else COLOR_UNAFFORDABLE
				draw_string(font, Vector2(pos.x - 18, pos.y + 48), "%d" % info.upgrade_cost, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, cost_color)
		else:
			# Empty position - draw dimmed
			draw_circle(Vector2(pos.x, pos.y), 25, Color(0.05, 0.05, 0.08, 0.6))
			for i in range(24):
				var angle := float(i) / 24 * TAU
				var next_angle := float(i + 1) / 24 * TAU
				var p1 := Vector2(pos.x + cos(angle) * 25, pos.y + sin(angle) * 25)
				var p2 := Vector2(pos.x + cos(next_angle) * 25, pos.y + sin(next_angle) * 25)
				draw_line(p1, p2, Color(0.2, 0.2, 0.25, 0.5), 1)

			var num_str := str(pos.index)
			draw_string(font, Vector2(pos.x - 7, pos.y + 8), num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.3, 0.3, 0.35, 0.5))

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

		# Check if this tower has an animated sprite visual
		var tower_id := "%d_%d" % [int(tower.x), int(tower.y)]
		var has_animated_visual := tower_visuals.has(tower_id) and is_instance_valid(tower_visuals[tower_id])

		# Draw effect radius (subtle, 50% transparency)
		if tower_stats.has("effect_radius") and tower_stats.has("color"):
			var radius_color: Color = tower_stats.color
			radius_color.a = 0.075  # 50% of original 0.15
			draw_circle(pos, tower_stats.effect_radius, radius_color)

			# Only draw circle body if no animated sprite
			if not has_animated_visual:
				draw_circle(pos, 20, tower_stats.color)
				if tower_stats.has("inner_color"):
					draw_circle(pos, 12, tower_stats.inner_color)

		# Draw targeting line for gun towers
		if tower.has("type") and tower.type == BuildManager.TowerType.GUN:
			if tower.has("target") and tower.target != null and is_instance_valid(tower.target):
				var target_pos: Vector2 = tower.target.global_position
				draw_line(pos, target_pos, Color(1, 0.3, 0.3, 0.6), 2)

		# Draw level indicator for upgraded towers (level 2+)
		if tower.has("level") and tower.level > 1:
			var level: int = tower.level
			var level_color := COLOR_MAX_LEVEL if level >= BuildManager.MAX_TOWER_LEVEL else COLOR_UPGRADE
			var level_text := "Lv%d" % level if level < BuildManager.MAX_TOWER_LEVEL else "MAX"
			var font := ThemeDB.fallback_font
			draw_string(font, Vector2(pos.x - 12, pos.y + 35), level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, level_color)
