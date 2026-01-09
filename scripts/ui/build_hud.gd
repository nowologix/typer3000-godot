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
const COLOR_SELL := Color("#00BFFF")  # Light blue for sell
const COLOR_MAX_LEVEL := Color("#FF44FF")  # Magenta for max level towers

# Tower sprite scale (adjust based on actual image size)
const TOWER_SPRITE_SCALE := 0.25

# Tower upgrade textures (Level 1-5 for each type)
const GUN_TEXTURES := [
	preload("res://assets/sprites/towers/turret_gun_01.png"),
	preload("res://assets/sprites/towers/turret_gun_02.png"),
	preload("res://assets/sprites/towers/turret_gun_03.png"),
	preload("res://assets/sprites/towers/turret_gun_04.png"),
	preload("res://assets/sprites/towers/turret_gun_05.png"),
]

const TESLA_TEXTURES := [
	preload("res://assets/sprites/towers/turret_tesla_01.png"),
	preload("res://assets/sprites/towers/turret_tesla_02.png"),
	preload("res://assets/sprites/towers/turret_tesla_03.png"),
	preload("res://assets/sprites/towers/turret_tesla_04.png"),
	preload("res://assets/sprites/towers/turret_tesla_05.png"),
]

const FREEZE_TEXTURES := [
	preload("res://assets/sprites/towers/turret_freeze_01.png"),
	preload("res://assets/sprites/towers/turret_freeze_02.png"),
	preload("res://assets/sprites/towers/turret_freeze_03.png"),
	preload("res://assets/sprites/towers/turret_freeze_04.png"),
	preload("res://assets/sprites/towers/turret_freeze_05.png"),
]

var visible_in_build_mode: bool = false
var is_in_upgrade_mode: bool = false
var is_in_sell_mode: bool = false
var tower_visuals: Dictionary = {}  # tower_id -> Sprite2D
var shadow_visuals: Dictionary = {}  # tower_id -> Sprite2D (shadows)

# Shadow settings
const SHADOW_OFFSET := Vector2(4, 4)
const SHADOW_SCALE_MULT := 1.1
const SHADOW_COLOR := Color(0, 0, 0, 0.6)

func _ready() -> void:
	# Connect to BuildManager signals
	BuildManager.build_mode_entered.connect(_on_build_mode_entered)
	BuildManager.build_mode_exited.connect(_on_build_mode_exited)
	BuildManager.tower_placed.connect(_on_tower_placed)
	BuildManager.tower_sold.connect(_on_tower_sold)
	BuildManager.tower_upgraded.connect(_on_tower_upgraded)
	BuildManager.towers_reset.connect(clear_tower_visuals)
	BuildManager.upgrade_mode_entered.connect(_on_upgrade_mode_entered)
	BuildManager.upgrade_mode_exited.connect(_on_upgrade_mode_exited)
	BuildManager.sell_mode_entered.connect(_on_sell_mode_entered)
	BuildManager.sell_mode_exited.connect(_on_sell_mode_exited)

	DebugHelper.log_info("BuildHUD: Tower upgrade sprites loaded (5 levels per type)")

func _on_tower_placed(tower: Dictionary) -> void:
	# Create visual node for new tower
	_create_tower_visual(tower)

func _on_build_mode_entered() -> void:
	visible_in_build_mode = true

func _on_build_mode_exited() -> void:
	visible_in_build_mode = false
	is_in_upgrade_mode = false
	is_in_sell_mode = false

func _on_upgrade_mode_entered() -> void:
	is_in_upgrade_mode = true

func _on_upgrade_mode_exited() -> void:
	is_in_upgrade_mode = false

func _on_sell_mode_entered() -> void:
	is_in_sell_mode = true

func _on_sell_mode_exited() -> void:
	is_in_sell_mode = false

func _on_tower_sold(tower: Dictionary, _refund: int) -> void:
	# Remove visual for sold tower
	var tower_id := "%d_%d" % [int(tower.x), int(tower.y)]
	if tower_visuals.has(tower_id):
		var sprite = tower_visuals[tower_id]
		if is_instance_valid(sprite):
			sprite.queue_free()
		tower_visuals.erase(tower_id)
	if shadow_visuals.has(tower_id):
		var shadow = shadow_visuals[tower_id]
		if is_instance_valid(shadow):
			shadow.queue_free()
		shadow_visuals.erase(tower_id)
	DebugHelper.log_info("BuildHUD: Removed sold tower visual at (%d, %d)" % [int(tower.x), int(tower.y)])

func _on_tower_upgraded(tower: Dictionary) -> void:
	# Update sprite and shadow texture for upgraded tower
	var tower_id := "%d_%d" % [int(tower.x), int(tower.y)]
	var level: int = tower.level
	var level_index := clampi(level - 1, 0, 4)  # 0-4 for levels 1-5
	var new_texture: Texture2D = null

	match tower.type:
		BuildManager.TowerType.GUN:
			new_texture = GUN_TEXTURES[level_index]
		BuildManager.TowerType.TESLA:
			new_texture = TESLA_TEXTURES[level_index]
		BuildManager.TowerType.FREEZE:
			new_texture = FREEZE_TEXTURES[level_index]

	if new_texture and tower_visuals.has(tower_id):
		var sprite: Sprite2D = tower_visuals[tower_id]
		if is_instance_valid(sprite):
			sprite.texture = new_texture

	if new_texture and shadow_visuals.has(tower_id):
		var shadow: Sprite2D = shadow_visuals[tower_id]
		if is_instance_valid(shadow):
			shadow.texture = new_texture

	DebugHelper.log_info("BuildHUD: Updated tower sprite to level %d" % level)

func clear_tower_visuals() -> void:
	# Remove all animated tower sprites (called on game reset)
	for tower_id in tower_visuals:
		var sprite = tower_visuals[tower_id]
		if is_instance_valid(sprite):
			sprite.queue_free()
	tower_visuals.clear()
	for tower_id in shadow_visuals:
		var shadow = shadow_visuals[tower_id]
		if is_instance_valid(shadow):
			shadow.queue_free()
	shadow_visuals.clear()
	DebugHelper.log_debug("BuildHUD: Cleared tower visuals")

func _create_tower_visual(tower: Dictionary) -> void:
	if not tower.has("type"):
		return

	var sprite := Sprite2D.new()
	var shadow := Sprite2D.new()
	var tower_name: String = ""
	var level: int = tower.get("level", 1)
	var level_index := clampi(level - 1, 0, 4)  # 0-4 for levels 1-5

	match tower.type:
		BuildManager.TowerType.GUN:
			sprite.texture = GUN_TEXTURES[level_index]
			shadow.texture = GUN_TEXTURES[level_index]
			tower_name = "GUN"

		BuildManager.TowerType.TESLA:
			sprite.texture = TESLA_TEXTURES[level_index]
			shadow.texture = TESLA_TEXTURES[level_index]
			tower_name = "TESLA"

		BuildManager.TowerType.FREEZE:
			sprite.texture = FREEZE_TEXTURES[level_index]
			shadow.texture = FREEZE_TEXTURES[level_index]
			tower_name = "FREEZE"

		_:
			sprite.queue_free()
			shadow.queue_free()
			return  # Unknown tower type

	# Shadow setup
	shadow.position = Vector2(tower.x, tower.y) + SHADOW_OFFSET
	shadow.scale = Vector2(TOWER_SPRITE_SCALE * SHADOW_SCALE_MULT, TOWER_SPRITE_SCALE * SHADOW_SCALE_MULT)
	shadow.modulate = SHADOW_COLOR
	shadow.z_index = -11  # Below tower sprite
	add_child(shadow)

	# Sprite setup
	sprite.position = Vector2(tower.x, tower.y)
	sprite.scale = Vector2(TOWER_SPRITE_SCALE, TOWER_SPRITE_SCALE)
	sprite.z_index = -10  # Below enemies and UI
	add_child(sprite)

	# Generate unique ID for this tower
	var tower_id := "%d_%d" % [int(tower.x), int(tower.y)]
	tower_visuals[tower_id] = sprite
	shadow_visuals[tower_id] = shadow

	DebugHelper.log_info("BuildHUD: Created %s turret visual at (%d, %d) level %d" % [tower_name, int(tower.x), int(tower.y), level])

func _update_tower_visuals() -> void:
	var towers := BuildManager.get_towers()

	for tower in towers:
		# Only rotate GUN towers (they aim at enemies)
		if tower.type != BuildManager.TowerType.GUN:
			continue

		var tower_id := "%d_%d" % [int(tower.x), int(tower.y)]
		if not tower_visuals.has(tower_id):
			continue

		var sprite: Sprite2D = tower_visuals[tower_id]
		if not is_instance_valid(sprite):
			tower_visuals.erase(tower_id)
			continue

		# Rotate sprite to point at target (calculated locally for visuals)
		var tower_pos := Vector2(tower.x, tower.y)
		var target_pos: Vector2 = Vector2.ZERO
		var has_target := false

		# Check for local target first (HOST has real target)
		if tower.has("target") and tower.target != null and is_instance_valid(tower.target):
			target_pos = tower.target.global_position
			has_target = true
		else:
			# Calculate nearest enemy locally (CLIENT visual targeting)
			var nearest = find_nearest_enemy_in_range(tower_pos, tower.stats.effect_radius if tower.has("stats") else 150.0)
			if nearest != null:
				target_pos = nearest.global_position
				has_target = true

		var target_rotation: float
		if has_target:
			var direction := target_pos - tower_pos
			# Sprite points UP (0°), so add PI/2 to adjust
			target_rotation = direction.angle() + PI / 2
		else:
			# No target - slowly rotate back to default (pointing up)
			target_rotation = lerp_angle(sprite.rotation, 0.0, 0.1)

		sprite.rotation = target_rotation

		# Also rotate shadow
		if shadow_visuals.has(tower_id):
			var shadow: Sprite2D = shadow_visuals[tower_id]
			if is_instance_valid(shadow):
				shadow.rotation = target_rotation

func find_nearest_enemy_in_range(pos: Vector2, radius: float) -> Node:
	# Find nearest enemy within range (for local visual targeting)
	var enemies = get_tree().get_nodes_in_group("enemies")
	var nearest: Node = null
	var nearest_dist: float = radius

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.has_method("is_alive") and not enemy.is_alive():
			continue

		var dist = pos.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy

	return nearest

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

	var phase := BuildManager.get_build_phase()

	# Draw semi-transparent overlay (except when placing tower - need clear view)
	if phase != BuildManager.BuildPhase.SELECTING_POSITION:
		var vp_size := get_viewport().get_visible_rect().size
		draw_rect(Rect2(0, 0, vp_size.x, vp_size.y), COLOR_BG)

	if phase == BuildManager.BuildPhase.SELECTING_TOWER:
		draw_tower_selection()
	elif phase == BuildManager.BuildPhase.SELECTING_UPGRADE:
		draw_upgrade_selection()
	elif phase == BuildManager.BuildPhase.SELECTING_SELL:
		draw_sell_selection()
	else:
		draw_position_selection()

	# Always draw build points
	draw_build_points()

func draw_build_command_hint() -> void:
	# Show BUILD command in bottom right with typing progress
	var font := ThemeDB.fallback_font
	var build_word := "BUILD"
	var typed_buffer := TypingManager.build_buffer
	var vp := get_viewport().get_visible_rect().size
	var x := vp.x - 180
	var y := vp.y - 20

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
	var center_x := get_viewport().get_visible_rect().size.x / 2.0
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

	# Draw SELL option
	y += 40
	var sell_word := "SELL"
	var all_towers := BuildManager.get_towers()
	var can_sell := not all_towers.is_empty()
	char_x = center_x - 120

	for i in range(sell_word.length()):
		var char_str := sell_word[i]
		var color: Color
		if i < buffer.length() and buffer[i] == char_str:
			color = COLOR_TYPED
		elif sell_word.begins_with(buffer) and buffer.length() > 0:
			color = COLOR_UNTYPED
		else:
			color = COLOR_SELL  # Always orange - SELL costs nothing
		draw_string(font, Vector2(char_x, y), char_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, color)
		char_x += 20

	# Show sell info
	if can_sell:
		draw_string(font, Vector2(center_x + 80, y), "%d towers" % all_towers.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_SELL)
	else:
		draw_string(font, Vector2(center_x + 80, y), "no towers", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_DIM)
	draw_string(font, Vector2(center_x - 120, y + 22), "Refund: base cost only", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_DIM)

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
	var center_x := get_viewport().get_visible_rect().size.x / 2.0
	var buffer := BuildManager.get_build_buffer()

	# Title with selected tower
	var tower_type := BuildManager.get_selected_tower_type()
	var command: String = BuildManager.TOWER_COMMANDS.get(tower_type, "")
	var stats: Dictionary = BuildManager.TOWER_STATS.get(tower_type, {})
	draw_string(font, Vector2(center_x - 100, 80), "PLACE " + command, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, COLOR_TITLE)

	# Cost info
	draw_string(font, Vector2(center_x - 60, 110), "Cost: %d pts" % stats.get("cost", 0), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_HIGHLIGHT)

	# Instructions
	draw_string(font, Vector2(center_x - 150, 150), "Move player to position | ENTER: place", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_TEXT)

	# Draw cursor crosshair with tower-sized circle
	var cursor_pos := BuildManager.get_cursor_position()
	var tower_radius := BuildManager.TOWER_RADIUS
	var is_valid := BuildManager.is_position_valid()
	
	# Circle color based on validity
	var circle_color := Color(0.0, 1.0, 0.5, 0.4) if is_valid else Color(1.0, 0.2, 0.2, 0.4)
	var border_color := Color(0.0, 1.0, 0.5, 0.9) if is_valid else Color(1.0, 0.2, 0.2, 0.9)
	
	# Draw filled circle (tower preview)
	draw_circle(cursor_pos, tower_radius, circle_color)
	
	# Draw circle border
	for i in range(32):
		var angle := float(i) / 32 * TAU
		var next_angle := float(i + 1) / 32 * TAU
		var p1 := cursor_pos + Vector2(cos(angle), sin(angle)) * tower_radius
		var p2 := cursor_pos + Vector2(cos(next_angle), sin(next_angle)) * tower_radius
		draw_line(p1, p2, border_color, 2)
	
	# Draw crosshair
	var cross_size := 20.0
	var cross_color := Color(1.0, 1.0, 0.0, 0.9)
	draw_line(Vector2(cursor_pos.x - cross_size, cursor_pos.y), Vector2(cursor_pos.x + cross_size, cursor_pos.y), cross_color, 2)
	draw_line(Vector2(cursor_pos.x, cursor_pos.y - cross_size), Vector2(cursor_pos.x, cursor_pos.y + cross_size), cross_color, 2)

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
	var center_x := get_viewport().get_visible_rect().size.x / 2.0
	var buffer := BuildManager.get_build_buffer()

	# Title
	draw_string(font, Vector2(center_x - 100, 80), "UPGRADE MODE", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, COLOR_UPGRADE)

	# Instructions
	draw_string(font, Vector2(center_x - 150, 120), "Move player to tower | ENTER: upgrade", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_TEXT)

	# Draw cursor crosshair
	var cursor_pos := BuildManager.get_cursor_position()
	var tower_radius := BuildManager.TOWER_RADIUS

	# Find nearest tower to show upgrade info
	var nearest_tower = BuildManager.get_nearest_tower_to_cursor()
	var dist_to_nearest := 999999.0
	if not nearest_tower.is_empty():
		dist_to_nearest = cursor_pos.distance_to(Vector2(nearest_tower.x, nearest_tower.y))

	var can_upgrade_nearest := dist_to_nearest < tower_radius * 3 and not nearest_tower.is_empty()

	# Crosshair color based on selection
	var cross_color := Color(1.0, 0.85, 0.0, 0.9) if can_upgrade_nearest else Color(0.5, 0.5, 0.5, 0.7)

	# Draw crosshair
	var cross_size := 20.0
	draw_line(Vector2(cursor_pos.x - cross_size, cursor_pos.y), Vector2(cursor_pos.x + cross_size, cursor_pos.y), cross_color, 2)
	draw_line(Vector2(cursor_pos.x, cursor_pos.y - cross_size), Vector2(cursor_pos.x, cursor_pos.y + cross_size), cross_color, 2)

	# Draw selection circle around nearest tower if close enough
	if can_upgrade_nearest:
		var tower_pos := Vector2(nearest_tower.x, nearest_tower.y)
		var select_radius := tower_radius + 10
		for i in range(32):
			var angle := float(i) / 32 * TAU
			var next_angle := float(i + 1) / 32 * TAU
			var p1 := tower_pos + Vector2(cos(angle), sin(angle)) * select_radius
			var p2 := tower_pos + Vector2(cos(next_angle), sin(next_angle)) * select_radius
			draw_line(p1, p2, COLOR_UPGRADE, 3)

		# Show upgrade info
		var level: int = nearest_tower.level
		var is_max := level >= BuildManager.MAX_TOWER_LEVEL
		var info_y := tower_pos.y + 60

		if is_max:
			draw_string(font, Vector2(tower_pos.x - 30, info_y), "MAX LEVEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_MAX_LEVEL)
		else:
			var upgrade_cost := BuildManager.get_upgrade_cost(nearest_tower)
			var can_afford := BuildManager.get_build_points() >= upgrade_cost
			var cost_color := COLOR_AFFORDABLE if can_afford else COLOR_UNAFFORDABLE
			draw_string(font, Vector2(tower_pos.x - 40, info_y), "Lv%d -> Lv%d" % [level, level + 1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_UPGRADE)
			draw_string(font, Vector2(tower_pos.x - 25, info_y + 18), "%d pts" % upgrade_cost, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, cost_color)

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

func draw_sell_selection() -> void:
	var font := ThemeDB.fallback_font
	var center_x := get_viewport().get_visible_rect().size.x / 2.0
	var buffer := BuildManager.get_build_buffer()

	# Title
	draw_string(font, Vector2(center_x - 80, 80), "SELL MODE", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, COLOR_SELL)

	# Instructions
	draw_string(font, Vector2(center_x - 180, 120), "Move to tower | ENTER: sell (base cost refund)", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_TEXT)

	# Draw cursor crosshair
	var cursor_pos := BuildManager.get_cursor_position()
	var tower_radius := BuildManager.TOWER_RADIUS

	# Find nearest tower to show sell info
	var nearest_tower = BuildManager.get_nearest_tower_to_cursor()
	var dist_to_nearest := 999999.0
	if not nearest_tower.is_empty():
		dist_to_nearest = cursor_pos.distance_to(Vector2(nearest_tower.x, nearest_tower.y))

	var can_sell_nearest := dist_to_nearest < tower_radius * 3 and not nearest_tower.is_empty()

	# Crosshair color based on selection
	var cross_color := COLOR_SELL if can_sell_nearest else Color(0.5, 0.5, 0.5, 0.7)

	# Draw crosshair
	var cross_size := 20.0
	draw_line(Vector2(cursor_pos.x - cross_size, cursor_pos.y), Vector2(cursor_pos.x + cross_size, cursor_pos.y), cross_color, 2)
	draw_line(Vector2(cursor_pos.x, cursor_pos.y - cross_size), Vector2(cursor_pos.x, cursor_pos.y + cross_size), cross_color, 2)

	# Draw selection circle around nearest tower if close enough
	if can_sell_nearest:
		var tower_pos := Vector2(nearest_tower.x, nearest_tower.y)
		var select_radius := tower_radius + 10
		for i in range(32):
			var angle := float(i) / 32 * TAU
			var next_angle := float(i + 1) / 32 * TAU
			var p1 := tower_pos + Vector2(cos(angle), sin(angle)) * select_radius
			var p2 := tower_pos + Vector2(cos(next_angle), sin(next_angle)) * select_radius
			draw_line(p1, p2, COLOR_SELL, 3)

		# Show sell info
		var refund := BuildManager.get_tower_base_cost(nearest_tower)
		var info_y := tower_pos.y + 60
		draw_string(font, Vector2(tower_pos.x - 30, info_y), "SELL", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_SELL)
		draw_string(font, Vector2(tower_pos.x - 30, info_y + 18), "+%d pts" % refund, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_AFFORDABLE)

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

		# Draw targeting line for gun towers (calculated locally)
		if tower.has("type") and tower.type == BuildManager.TowerType.GUN:
			var target_pos: Vector2 = Vector2.ZERO
			var has_target := false

			# Check local target first (HOST)
			if tower.has("target") and tower.target != null and is_instance_valid(tower.target):
				target_pos = tower.target.global_position
				has_target = true
			else:
				# Calculate nearest enemy locally (CLIENT)
				var effect_radius: float = 150.0
				if tower.has("stats") and tower.stats.has("effect_radius"):
					effect_radius = tower.stats.effect_radius
				var nearest = find_nearest_enemy_in_range(pos, effect_radius)
				if nearest != null:
					target_pos = nearest.global_position
					has_target = true

			if has_target:
				draw_line(pos, target_pos, Color(1, 0.3, 0.3, 0.6), 2)

		# Draw level indicator for upgraded towers (level 2+)
		if tower.has("level") and tower.level > 1:
			var level: int = tower.level
			var level_color := COLOR_MAX_LEVEL if level >= BuildManager.MAX_TOWER_LEVEL else COLOR_UPGRADE
			var level_text := "Lv%d" % level if level < BuildManager.MAX_TOWER_LEVEL else "MAX"
			var font := ThemeDB.fallback_font
			draw_string(font, Vector2(pos.x - 12, pos.y + 35), level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, level_color)
