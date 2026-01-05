## build_manager.gd
## Manages the typing-based BUILD system for tower placement
## Flow: Type BUILD -> Select tower (GUN/FREEZE/TESLA) -> Select position (0-9)
extends Node

# Build phases
enum BuildPhase {
	SELECTING_TOWER,   # Type tower name
	SELECTING_POSITION # Type 0-9 for position
}

# Tower types matching original game
enum TowerType {
	GUN,    # Auto-attacks nearby enemies
	FREEZE, # Slows enemies in range
	TESLA   # Pushes enemies away periodically
}

# Tower commands (what player types)
const TOWER_COMMANDS := {
	TowerType.GUN: "GUN",
	TowerType.FREEZE: "FREEZE",
	TowerType.TESLA: "TESLA"
}

# Tower definitions
const TOWER_STATS := {
	TowerType.GUN: {
		"name": "Gun Turret",
		"name_de": "Geschuetzturm",
		"description": "Auto-attacks nearby enemies",
		"description_de": "Greift nahe Gegner automatisch an",
		"cost": 100,
		"max_per_wave": 2,
		"effect_radius": 120.0,
		"cooldown": 2.0,
		"damage": 1,
		"color": Color("#ff4444"),
		"inner_color": Color("#aa0000")
	},
	TowerType.FREEZE: {
		"name": "Freeze Turret",
		"name_de": "Gefrierturm",
		"description": "Slows enemies in range",
		"description_de": "Verlangsamt Gegner im Bereich",
		"cost": 75,
		"max_per_wave": 3,
		"effect_radius": 100.0,
		"slow_factor": 0.5,
		"color": Color("#44ffff"),
		"inner_color": Color("#008888")
	},
	TowerType.TESLA: {
		"name": "Tesla Turret",
		"name_de": "Teslaturm",
		"description": "Pushes enemies away periodically",
		"description_de": "Stoesst Gegner periodisch zurueck",
		"cost": 90,
		"max_per_wave": 2,
		"effect_radius": 110.0,
		"cooldown": 3.0,
		"push_force": 80.0,
		"color": Color("#aa88ff"),
		"inner_color": Color("#6644aa")
	}
}

const CANCEL_WORD := "CANCEL"
const EXIT_WORD := "EXIT"
const POSITION_RADIUS := 120.0  # Distance from portal center

# State
var is_in_build_mode: bool = false
var build_phase: BuildPhase = BuildPhase.SELECTING_TOWER
var build_buffer: String = ""
var selected_tower_type: int = -1
var build_points: int = 0
var towers: Array = []
var towers_built_this_wave: Dictionary = {}
var build_positions: Array = []  # [{index, x, y, occupied}]
var enemy_container: Node2D = null
var portal_position: Vector2 = Vector2(640, 360)

# Signals
signal build_mode_entered
signal build_mode_exited
signal tower_selected(tower_type: int, tower_data: Dictionary)
signal tower_placed(tower: Dictionary)
signal build_points_changed(points: int)

func _ready() -> void:
	calculate_build_positions()
	DebugHelper.log_info("BuildManager initialized")

func setup(container: Node2D, portal_pos: Vector2) -> void:
	enemy_container = container
	portal_position = portal_pos
	calculate_build_positions()

func reset() -> void:
	is_in_build_mode = false
	build_phase = BuildPhase.SELECTING_TOWER
	build_buffer = ""
	selected_tower_type = -1
	towers.clear()
	towers_built_this_wave.clear()
	build_points = 0
	calculate_build_positions()

func reset_wave() -> void:
	towers_built_this_wave.clear()
	update_position_occupancy()

func calculate_build_positions() -> void:
	build_positions.clear()
	var num_positions := 10

	for i in range(num_positions):
		# Start at top (12 o'clock) and go clockwise
		var angle := (float(i) / num_positions) * TAU - PI / 2
		var x := portal_position.x + cos(angle) * POSITION_RADIUS
		var y := portal_position.y + sin(angle) * POSITION_RADIUS

		build_positions.append({
			"index": i,
			"x": x,
			"y": y,
			"angle": angle,
			"occupied": false
		})

func update_position_occupancy() -> void:
	for pos in build_positions:
		pos.occupied = false
		for tower in towers:
			var dist := sqrt(pow(pos.x - tower.x, 2) + pow(pos.y - tower.y, 2))
			if dist < 40:
				pos.occupied = true
				break

func add_build_points(points: int) -> void:
	build_points += points
	build_points_changed.emit(build_points)

func get_build_points() -> int:
	return build_points

func is_building() -> bool:
	return is_in_build_mode

func get_build_buffer() -> String:
	return build_buffer

func get_build_phase() -> BuildPhase:
	return build_phase

func get_selected_tower_type() -> int:
	return selected_tower_type

func get_build_positions() -> Array:
	return build_positions

func get_towers() -> Array:
	return towers

# Enter build mode (called when BUILD is typed)
func enter_build_mode() -> void:
	if is_in_build_mode:
		return

	is_in_build_mode = true
	build_phase = BuildPhase.SELECTING_TOWER
	build_buffer = ""
	selected_tower_type = -1

	calculate_build_positions()
	update_position_occupancy()

	build_mode_entered.emit()
	DebugHelper.log_info("Build mode entered")

func exit_build_mode() -> void:
	is_in_build_mode = false
	build_phase = BuildPhase.SELECTING_TOWER
	build_buffer = ""
	selected_tower_type = -1

	build_mode_exited.emit()
	DebugHelper.log_info("Build mode exited")

# Process a typed character in build mode
func process_char(c: String) -> Dictionary:
	var result := {"action": "", "data": null}

	if not is_in_build_mode:
		return result

	var upper_char := c.to_upper()

	# Phase 2: Position selection (0-9)
	if build_phase == BuildPhase.SELECTING_POSITION:
		return process_position_selection(upper_char)

	# Phase 1: Tower selection
	build_buffer += upper_char

	# Check for CANCEL or EXIT
	if CANCEL_WORD.begins_with(build_buffer) or EXIT_WORD.begins_with(build_buffer):
		if build_buffer == CANCEL_WORD or build_buffer == EXIT_WORD:
			exit_build_mode()
			result["action"] = "cancel"
			return result
		result["action"] = "typing"
		result["data"] = {"buffer": build_buffer}
		return result

	# Check for tower commands
	var tower_result := check_tower_command()
	if tower_result["action"] != "":
		return tower_result

	# Check if buffer matches any command prefix
	if not buffer_matches_any_command():
		build_buffer = ""
		result["action"] = "invalid"
		return result

	result["action"] = "typing"
	result["data"] = {"buffer": build_buffer}
	return result

func process_position_selection(c: String) -> Dictionary:
	var result := {"action": "", "data": null}

	# Check if it's a digit 0-9
	if c.is_valid_int():
		var pos_index := int(c)
		if pos_index >= 0 and pos_index <= 9:
			var pos = build_positions[pos_index]

			if pos.occupied:
				result["action"] = "position_occupied"
				result["data"] = {"position": pos_index}
				return result

			# Place tower at this position
			var place_result := attempt_place_tower(selected_tower_type, pos.x, pos.y)

			if place_result.success:
				result["action"] = "tower_placed"
				result["data"] = place_result
				result["data"].position = pos_index
				exit_build_mode()
				update_position_occupancy()
			else:
				result["action"] = "tower_failed"
				result["data"] = place_result

			return result

	# Not a digit - check for CANCEL
	build_buffer += c
	if CANCEL_WORD.begins_with(build_buffer):
		if build_buffer == CANCEL_WORD:
			exit_build_mode()
			result["action"] = "cancel"
			return result
	else:
		# Invalid - go back to tower selection
		build_phase = BuildPhase.SELECTING_TOWER
		selected_tower_type = -1
		build_buffer = ""
		result["action"] = "position_cancelled"

	return result

func check_tower_command() -> Dictionary:
	var result := {"action": "", "data": null}

	for type in TOWER_COMMANDS:
		var command: String = TOWER_COMMANDS[type]
		if build_buffer == command:
			# Command complete - check cost and limits
			var stats: Dictionary = TOWER_STATS[type]
			var built_this_wave: int = towers_built_this_wave.get(type, 0)

			if build_points < stats.cost:
				result["action"] = "insufficient_points"
				result["data"] = {"required": stats.cost, "available": build_points}
				build_buffer = ""
				return result

			if built_this_wave >= stats.max_per_wave:
				result["action"] = "wave_limit"
				result["data"] = {"max": stats.max_per_wave}
				build_buffer = ""
				return result

			# Tower selected - switch to phase 2
			selected_tower_type = type
			build_phase = BuildPhase.SELECTING_POSITION
			build_buffer = ""
			update_position_occupancy()

			result["action"] = "tower_selected"
			result["data"] = {
				"type": type,
				"command": command,
				"stats": stats,
				"positions": build_positions
			}

			tower_selected.emit(type, stats)
			return result

		# Prefix match?
		if command.begins_with(build_buffer):
			result["action"] = "typing"
			result["data"] = {"buffer": build_buffer, "target": command, "type": type}

	return result

func buffer_matches_any_command() -> bool:
	if CANCEL_WORD.begins_with(build_buffer) or EXIT_WORD.begins_with(build_buffer):
		return true

	for command in TOWER_COMMANDS.values():
		if command.begins_with(build_buffer):
			return true

	return false

func attempt_place_tower(type: int, x: float, y: float) -> Dictionary:
	var stats: Dictionary = TOWER_STATS[type]

	# Check cost
	if build_points < stats.cost:
		return {"success": false, "reason": "insufficient_points"}

	# Check wave limit
	var built_this_wave: int = towers_built_this_wave.get(type, 0)
	if built_this_wave >= stats.max_per_wave:
		return {"success": false, "reason": "wave_limit"}

	# Create tower data
	var tower := {
		"x": x,
		"y": y,
		"type": type,
		"stats": stats.duplicate(),
		"level": 1,
		"last_activation": 0.0,
		"target": null,
		"is_active": true
	}

	towers.append(tower)

	# Deduct cost
	build_points -= stats.cost
	build_points_changed.emit(build_points)

	# Track wave limit
	towers_built_this_wave[type] = built_this_wave + 1

	tower_placed.emit(tower)
	DebugHelper.log_info("Tower placed: %s at (%d, %d)" % [stats.name, x, y])

	return {"success": true, "tower": tower}

# Update all towers (called from game_state)
func update_towers(delta: float, enemies: Array) -> Array:
	var results = []
	var now := Time.get_ticks_msec() / 1000.0

	for tower in towers:
		if not tower.is_active:
			continue

		var result := update_tower(tower, delta, now, enemies)
		if result["action"] != "":
			results.append(result)

	return results

func update_tower(tower: Dictionary, delta: float, now: float, enemies: Array) -> Dictionary:
	var result := {"action": "", "data": null}
	var stats: Dictionary = tower.stats

	match tower.type:
		TowerType.GUN:
			result = update_gun_tower(tower, now, enemies)
		TowerType.FREEZE:
			update_freeze_tower(tower, enemies)
		TowerType.TESLA:
			result = update_tesla_tower(tower, now, enemies)

	return result

func update_gun_tower(tower: Dictionary, now: float, enemies: Array) -> Dictionary:
	var result := {"action": "", "data": null}
	var stats: Dictionary = tower.stats

	# Find target
	if tower.target != null:
		if not is_instance_valid(tower.target) or not tower.target.has_method("is_alive") or not tower.target.is_alive():
			tower.target = null
		else:
			var dist := Vector2(tower.x, tower.y).distance_to(tower.target.global_position)
			if dist > stats.effect_radius:
				tower.target = null

	if tower.target == null:
		var closest: Node = null
		var closest_dist: float = stats.effect_radius
		for enemy in enemies:
			if not is_instance_valid(enemy) or not enemy.has_method("is_alive") or not enemy.is_alive():
				continue
			var dist := Vector2(tower.x, tower.y).distance_to(enemy.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = enemy
		tower.target = closest

	# Check cooldown
	if now - tower.last_activation < stats.cooldown:
		if tower.target:
			result["action"] = "gun_targeting"
			result["data"] = {"tower": tower, "target": tower.target}
		return result

	# Fire at target
	if tower.target:
		tower.last_activation = now
		tower.target.typed_chars += stats.damage
		result["action"] = "gun_fire"
		result["data"] = {"tower": tower, "target": tower.target}

	return result

func update_freeze_tower(tower: Dictionary, enemies: Array) -> void:
	var stats: Dictionary = tower.stats

	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.has_method("is_alive") or not enemy.is_alive():
			continue
		var dist := Vector2(tower.x, tower.y).distance_to(enemy.global_position)
		if dist < stats.effect_radius:
			if enemy.has_method("apply_slow"):
				enemy.apply_slow(stats.slow_factor)

func update_tesla_tower(tower: Dictionary, now: float, enemies: Array) -> Dictionary:
	var result := {"action": "", "data": null}
	var stats: Dictionary = tower.stats

	if now - tower.last_activation < stats.cooldown:
		return result

	var pushed_any := false
	var affected = []

	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.has_method("is_alive") or not enemy.is_alive():
			continue
		var pos := Vector2(tower.x, tower.y)
		var enemy_pos: Vector2 = enemy.global_position
		var dist := pos.distance_to(enemy_pos)

		if dist < stats.effect_radius and dist > 0:
			var push_dir := (enemy_pos - pos).normalized()
			enemy.global_position += push_dir * stats.push_force
			# Clamp to screen
			enemy.global_position.x = clamp(enemy.global_position.x, 50, 1230)
			enemy.global_position.y = clamp(enemy.global_position.y, 50, 670)
			affected.append(enemy)
			pushed_any = true

	if pushed_any:
		tower.last_activation = now
		result["action"] = "tesla_push"
		result["data"] = {"tower": tower, "enemies": affected}

	return result

# Get available towers for UI
func get_available_towers() -> Array:
	var available = []

	for type in TOWER_STATS:
		var stats: Dictionary = TOWER_STATS[type]
		var built_this_wave: int = towers_built_this_wave.get(type, 0)
		var can_build: bool = build_points >= stats.cost and built_this_wave < stats.max_per_wave

		available.append({
			"type": type,
			"command": TOWER_COMMANDS[type],
			"stats": stats,
			"can_build": can_build,
			"remaining": stats.max_per_wave - built_this_wave
		})

	return available
