## build_manager.gd
## Manages the typing-based BUILD system for tower placement and upgrades
## Flow: Type BUILD -> Select tower (GUN/FREEZE/TESLA) -> Select position (0-9)
## Flow: Type UPGRADE -> Select position (0-9) with tower -> Tower upgraded
extends Node

# Build phases
enum BuildPhase {
	SELECTING_TOWER,    # Type tower name
	SELECTING_POSITION, # Move player, ENTER to place
	SELECTING_UPGRADE,  # Move to tower, ENTER to upgrade
	SELECTING_SELL      # Move to tower, ENTER to sell
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

# Tower base definitions (Level 1)
const TOWER_STATS := {
	TowerType.GUN: {
		"name": "Gun Turret",
		"name_de": "Geschuetzturm",
		"description": "Auto-attacks nearby enemies",
		"description_de": "Greift nahe Gegner automatisch an",
		"cost": 100,
		"max_per_wave": 2,
		"effect_radius": 150.0,
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
		"slow_duration": 2.0,
		"color": Color("#88ddff"),
		"inner_color": Color("#44aadd")
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
		"color": Color("#ffdd44"),
		"inner_color": Color("#ddaa00")
	}
}

# Upgrade stats per level (Level 1 = base, Levels 2-5 = upgrades)
# Format: {stat_name: [lvl1, lvl2, lvl3, lvl4, lvl5]}
const UPGRADE_STATS := {
	TowerType.GUN: {
		"cooldown": [2.0, 1.6, 1.2, 0.9, 0.6],      # Faster fire rate
		"effect_radius": [150.0, 160.0, 170.0, 185.0, 200.0],  # Larger range
		"upgrade_cost": [0, 50, 75, 100, 150]       # Cost to reach this level
	},
	TowerType.FREEZE: {
		"slow_factor": [0.5, 0.45, 0.4, 0.3, 0.2],  # Stronger slow
		"slow_duration": [2.0, 2.5, 3.0, 3.5, 4.0], # Longer duration
		"effect_radius": [100.0, 110.0, 120.0, 135.0, 150.0],  # Larger range
		"upgrade_cost": [0, 40, 60, 85, 120]
	},
	TowerType.TESLA: {
		"cooldown": [3.0, 2.6, 2.2, 1.8, 1.4],      # Faster pulse
		"push_force": [80.0, 100.0, 120.0, 150.0, 180.0],  # Stronger push
		"effect_radius": [110.0, 120.0, 135.0, 150.0, 170.0],  # Larger range
		"upgrade_cost": [0, 45, 70, 95, 130]
	}
}

const MAX_TOWER_LEVEL := 5
const UPGRADE_WORD := "UPGRADE"
const SELL_WORD := "SELL"
const CANCEL_WORD := "CANCEL"
const EXIT_WORD := "EXIT"
const TOWER_RADIUS := 40.0  # Visual radius for tower placement cursor

# State
var is_in_build_mode: bool = false
var build_phase: BuildPhase = BuildPhase.SELECTING_TOWER
var build_buffer: String = ""
var selected_tower_type: int = -1
var build_points: int = 0
var towers: Array = []
var towers_built_this_wave: Dictionary = {}
var enemy_container: Node2D = null
var portal_position: Vector2 = Vector2(640, 360)
var player_ref: Node2D = null

# Signals
signal build_mode_entered
signal build_mode_exited
signal upgrade_mode_entered
signal upgrade_mode_exited
signal sell_mode_entered
signal sell_mode_exited
signal tower_selected(tower_type: int, tower_data: Dictionary)
signal tower_placed(tower: Dictionary)
signal tower_upgraded(tower: Dictionary)
signal tower_sold(tower: Dictionary, refund: int)
signal build_points_changed(points: int)
signal towers_reset

func _ready() -> void:
	DebugHelper.log_info("BuildManager initialized")

func _process(_delta: float) -> void:
	# Cursor is now moved via input, no automatic updates needed
	pass

func setup(container: Node2D, portal_pos: Vector2) -> void:
	enemy_container = container
	portal_position = portal_pos

func set_player_reference(player: Node2D) -> void:
	player_ref = player

func reset() -> void:
	is_in_build_mode = false
	build_phase = BuildPhase.SELECTING_TOWER
	build_buffer = ""
	selected_tower_type = -1
	towers.clear()
	towers_built_this_wave.clear()
	build_points = 0
	towers_reset.emit()

func reset_wave() -> void:
	towers_built_this_wave.clear()

func is_position_valid() -> bool:
	# Check if player position overlaps with existing tower
	var pos := get_cursor_position()
	for tower in towers:
		var dist := pos.distance_to(Vector2(tower.x, tower.y))
		if dist < TOWER_RADIUS * 2:  # Towers can't overlap
			return false
	return true

func get_nearest_tower_to_cursor() -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_dist: float = 999999.0
	var pos := get_cursor_position()

	for tower in towers:
		var dist := pos.distance_to(Vector2(tower.x, tower.y))
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = tower

	return nearest

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

func get_cursor_position() -> Vector2:
	# Cursor follows player position
	if player_ref and is_instance_valid(player_ref):
		return player_ref.global_position
	return portal_position

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

	build_mode_entered.emit()
	DebugHelper.log_info("Build mode entered - cursor follows player")

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

	# Phase 2: Position selection
	if build_phase == BuildPhase.SELECTING_POSITION:
		return process_position_selection(upper_char)

	# Phase 3: Upgrade selection
	if build_phase == BuildPhase.SELECTING_UPGRADE:
		return process_upgrade_selection(upper_char)

	# Phase 4: Sell selection
	if build_phase == BuildPhase.SELECTING_SELL:
		return process_sell_selection(upper_char)

	# Phase 1: Tower/Upgrade selection
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

	# Check for UPGRADE command
	if UPGRADE_WORD.begins_with(build_buffer):
		if build_buffer == UPGRADE_WORD:
			# Check if any towers can be upgraded
			var upgradeable := get_upgradeable_towers()
			if upgradeable.is_empty():
				result["action"] = "no_upgradeable_towers"
				build_buffer = ""
				return result

			# Enter upgrade selection phase
			build_phase = BuildPhase.SELECTING_UPGRADE
			build_buffer = ""
			upgrade_mode_entered.emit()

			result["action"] = "upgrade_mode"
			result["data"] = {"towers": upgradeable}
			return result
		result["action"] = "typing"
		result["data"] = {"buffer": build_buffer}
		return result

	# Check for SELL command (always available, costs nothing)
	if SELL_WORD.begins_with(build_buffer):
		if build_buffer == SELL_WORD:
			# Enter sell selection phase
			build_phase = BuildPhase.SELECTING_SELL
			build_buffer = ""
			sell_mode_entered.emit()

			result["action"] = "sell_mode"
			result["data"] = {"towers": towers}
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

	# Check for CANCEL/EXIT
	build_buffer += c
	if CANCEL_WORD.begins_with(build_buffer) or EXIT_WORD.begins_with(build_buffer):
		if build_buffer == CANCEL_WORD or build_buffer == EXIT_WORD:
			exit_build_mode()
			result["action"] = "cancel"
			return result
		result["action"] = "typing"
		return result
	
	# Any other key cancels position selection
	build_phase = BuildPhase.SELECTING_TOWER
	selected_tower_type = -1
	build_buffer = ""
	result["action"] = "position_cancelled"
	return result

# Place tower at player position (called via ENTER key)
func place_tower_at_cursor() -> Dictionary:
	var result := {"action": "", "data": null}

	if build_phase != BuildPhase.SELECTING_POSITION:
		result["action"] = "wrong_phase"
		return result

	if not is_position_valid():
		result["action"] = "position_occupied"
		return result

	var pos := get_cursor_position()
	var place_result := attempt_place_tower(selected_tower_type, pos.x, pos.y)

	if place_result.success:
		result["action"] = "tower_placed"
		result["data"] = place_result
		exit_build_mode()
	else:
		result["action"] = "tower_failed"
		result["data"] = place_result

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

			result["action"] = "tower_selected"
			result["data"] = {
				"type": type,
				"command": command,
				"stats": stats
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

	if UPGRADE_WORD.begins_with(build_buffer):
		return true

	if SELL_WORD.begins_with(build_buffer):
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

	# Spawn placement effect
	if enemy_container:
		EffectsManager.spawn_tower_place_effect(Vector2(x, y), enemy_container)

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
			result = update_freeze_tower(tower, enemies)
		TowerType.TESLA:
			result = update_tesla_tower(tower, now, enemies)

	return result

func update_gun_tower(tower: Dictionary, now: float, enemies: Array) -> Dictionary:
	var result := {"action": "", "data": null}
	var stats: Dictionary = tower.stats

	# Get player's active target - GUN should skip enemies being typed
	var player_target: Node = null
	if TypingManager and TypingManager.active_enemy and is_instance_valid(TypingManager.active_enemy):
		player_target = TypingManager.active_enemy

	# Validate current target
	if tower.target != null:
		if not is_instance_valid(tower.target) or not tower.target.has_method("is_alive") or not tower.target.is_alive():
			tower.target = null
		elif tower.target == player_target:
			# Player is typing this enemy - switch to another target
			tower.target = null
		else:
			var dist := Vector2(tower.x, tower.y).distance_to(tower.target.global_position)
			if dist > stats.effect_radius:
				tower.target = null

	# Find new target (skip player's active target)
	if tower.target == null:
		var closest: Node = null
		var closest_dist: float = stats.effect_radius
		for enemy in enemies:
			if not is_instance_valid(enemy) or not enemy.has_method("is_alive") or not enemy.is_alive():
				continue
			# Skip the enemy the player is typing
			if enemy == player_target:
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
		tower.target.take_tower_damage(stats.damage)
		result["action"] = "gun_fire"
		result["data"] = {"tower": tower, "target": tower.target}

	return result

func update_freeze_tower(tower: Dictionary, enemies: Array) -> Dictionary:
	var result := {"action": "", "data": null}
	var stats: Dictionary = tower.stats
	var newly_frozen: Array = []

	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.has_method("is_alive") or not enemy.is_alive():
			continue
		var dist := Vector2(tower.x, tower.y).distance_to(enemy.global_position)
		if dist < stats.effect_radius:
			if enemy.has_method("apply_slow"):
				# apply_slow returns true only if enemy wasn't already slowed
				var was_applied = enemy.apply_slow(stats.slow_factor, stats.get("slow_duration", 2.0))
				if was_applied:
					newly_frozen.append(enemy)

	# Only return action if we newly froze enemies (not already slowed ones)
	if newly_frozen.size() > 0:
		result["action"] = "freeze_slow"
		result["data"] = {"tower": tower, "enemies": newly_frozen}

	return result

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

# ============================================
# UPGRADE SYSTEM
# ============================================

func process_upgrade_selection(c: String) -> Dictionary:
	var result := {"action": "", "data": null}

	# Check for CANCEL/EXIT
	build_buffer += c
	if CANCEL_WORD.begins_with(build_buffer) or EXIT_WORD.begins_with(build_buffer):
		if build_buffer == CANCEL_WORD or build_buffer == EXIT_WORD:
			exit_build_mode()
			result["action"] = "cancel"
			return result
		result["action"] = "typing"
		return result
	
	# Any other key cancels upgrade mode
	build_phase = BuildPhase.SELECTING_TOWER
	build_buffer = ""
	upgrade_mode_exited.emit()
	result["action"] = "upgrade_cancelled"
	return result

# Upgrade tower nearest to player (called via ENTER key)
func upgrade_tower_at_cursor() -> Dictionary:
	var result := {"action": "", "data": null}

	if build_phase != BuildPhase.SELECTING_UPGRADE:
		result["action"] = "wrong_phase"
		return result

	var tower = get_nearest_tower_to_cursor()

	if tower.is_empty():
		result["action"] = "no_tower_nearby"
		return result

	# Check distance - must be close enough to player
	var pos := get_cursor_position()
	var dist := pos.distance_to(Vector2(tower.x, tower.y))
	if dist > TOWER_RADIUS * 3:
		result["action"] = "tower_too_far"
		return result
	
	if tower.level >= MAX_TOWER_LEVEL:
		result["action"] = "tower_max_level"
		result["data"] = {"tower": tower, "max_level": MAX_TOWER_LEVEL}
		return result
	
	var upgrade_cost := get_upgrade_cost(tower)
	if build_points < upgrade_cost:
		result["action"] = "insufficient_points"
		result["data"] = {"required": upgrade_cost, "available": build_points}
		return result
	
	var upgrade_result := upgrade_tower(tower)
	if upgrade_result.success:
		result["action"] = "tower_upgraded"
		result["data"] = upgrade_result
		exit_build_mode()
	else:
		result["action"] = "upgrade_failed"
		result["data"] = upgrade_result
	
	return result

func get_tower_at_position(pos: Vector2) -> Dictionary:
	# Find tower at a specific position
	for tower in towers:
		var dist := pos.distance_to(Vector2(tower.x, tower.y))
		if dist < TOWER_RADIUS * 2:
			return tower
	return {}

func get_upgradeable_towers() -> Array:
	var upgradeable = []

	for tower in towers:
		if tower.level >= MAX_TOWER_LEVEL:
			continue

		var upgrade_cost := get_upgrade_cost(tower)
		upgradeable.append({
			"tower": tower,
			"current_level": tower.level,
			"next_level": tower.level + 1,
			"upgrade_cost": upgrade_cost,
			"can_afford": build_points >= upgrade_cost
		})

	return upgradeable

func get_upgrade_cost(tower: Dictionary) -> int:
	if tower.is_empty() or not tower.has("type") or not tower.has("level"):
		return 0

	var tower_type: int = tower.type
	var current_level: int = tower.level

	if current_level >= MAX_TOWER_LEVEL:
		return 0

	var upgrade_stats = UPGRADE_STATS.get(tower_type, {})
	var costs = upgrade_stats.get("upgrade_cost", [0, 50, 75, 100, 150])

	# Next level index (0-based array, level is 1-based)
	var next_level_index = current_level  # Level 1 -> index 1 for upgrade to level 2
	if next_level_index < costs.size():
		return costs[next_level_index]

	return 999  # Should never happen

func upgrade_tower(tower: Dictionary) -> Dictionary:
	if tower.is_empty():
		return {"success": false, "reason": "invalid_tower"}

	var current_level: int = tower.level
	if current_level >= MAX_TOWER_LEVEL:
		return {"success": false, "reason": "max_level"}

	var upgrade_cost := get_upgrade_cost(tower)
	if build_points < upgrade_cost:
		return {"success": false, "reason": "insufficient_points"}

	# Deduct cost
	build_points -= upgrade_cost
	build_points_changed.emit(build_points)

	# Increase level
	var new_level := current_level + 1
	tower.level = new_level

	# Apply upgraded stats
	apply_upgrade_stats(tower)

	tower_upgraded.emit(tower)
	DebugHelper.log_info("Tower upgraded to level %d at (%d, %d)" % [new_level, tower.x, tower.y])

	return {
		"success": true,
		"tower": tower,
		"new_level": new_level,
		"cost": upgrade_cost
	}

func apply_upgrade_stats(tower: Dictionary) -> void:
	var tower_type: int = tower.type
	var level: int = tower.level
	var level_index: int = level - 1  # Convert to 0-based index

	var upgrade_stats = UPGRADE_STATS.get(tower_type, {})

	# Apply each stat from the upgrade table
	for stat_name in upgrade_stats:
		if stat_name == "upgrade_cost":
			continue  # Skip cost array

		var stat_values = upgrade_stats[stat_name]
		if level_index < stat_values.size():
			tower.stats[stat_name] = stat_values[level_index]

func is_upgrade_mode() -> bool:
	return is_in_build_mode and build_phase == BuildPhase.SELECTING_UPGRADE

func get_tower_level_info(tower: Dictionary) -> Dictionary:
	if tower.is_empty():
		return {}

	var current_level: int = tower.level
	var tower_type: int = tower.type
	var upgrade_stats = UPGRADE_STATS.get(tower_type, {})

	var info := {
		"level": current_level,
		"max_level": MAX_TOWER_LEVEL,
		"can_upgrade": current_level < MAX_TOWER_LEVEL,
		"upgrade_cost": get_upgrade_cost(tower) if current_level < MAX_TOWER_LEVEL else 0,
		"current_stats": tower.stats.duplicate(),
		"next_stats": {}
	}

	# Get next level stats preview
	if current_level < MAX_TOWER_LEVEL:
		var next_index := current_level  # Level 1 -> index 1 for level 2 stats
		for stat_name in upgrade_stats:
			if stat_name == "upgrade_cost":
				continue
			var stat_values = upgrade_stats[stat_name]
			if next_index < stat_values.size():
				info.next_stats[stat_name] = stat_values[next_index]

	return info

# Confirm placement/upgrade/sell at player position (ENTER key)
func confirm_cursor_action() -> Dictionary:
	if build_phase == BuildPhase.SELECTING_POSITION:
		return place_tower_at_cursor()
	elif build_phase == BuildPhase.SELECTING_UPGRADE:
		return upgrade_tower_at_cursor()
	elif build_phase == BuildPhase.SELECTING_SELL:
		return sell_tower_at_cursor()
	return {"action": "", "data": null}

# ============================================
# SELL SYSTEM
# ============================================

func process_sell_selection(c: String) -> Dictionary:
	var result := {"action": "", "data": null}

	# Check for CANCEL/EXIT
	build_buffer += c
	if CANCEL_WORD.begins_with(build_buffer) or EXIT_WORD.begins_with(build_buffer):
		if build_buffer == CANCEL_WORD or build_buffer == EXIT_WORD:
			exit_build_mode()
			result["action"] = "cancel"
			return result
		result["action"] = "typing"
		return result

	# Any other key cancels sell mode
	build_phase = BuildPhase.SELECTING_TOWER
	build_buffer = ""
	sell_mode_exited.emit()
	result["action"] = "sell_cancelled"
	return result

# Sell tower nearest to player (called via ENTER key)
func sell_tower_at_cursor() -> Dictionary:
	var result := {"action": "", "data": null}

	if build_phase != BuildPhase.SELECTING_SELL:
		result["action"] = "wrong_phase"
		return result

	var tower = get_nearest_tower_to_cursor()

	if tower.is_empty():
		result["action"] = "no_tower_nearby"
		return result

	# Check distance - must be close enough to player
	var pos := get_cursor_position()
	var dist := pos.distance_to(Vector2(tower.x, tower.y))
	if dist > TOWER_RADIUS * 3:
		result["action"] = "tower_too_far"
		return result

	# Get base cost refund (not upgrades)
	var refund := get_tower_base_cost(tower)

	# Remove tower from list
	towers.erase(tower)

	# Refund build points
	build_points += refund
	build_points_changed.emit(build_points)

	tower_sold.emit(tower, refund)
	DebugHelper.log_info("Tower sold at (%d, %d) for %d points" % [tower.x, tower.y, refund])

	result["action"] = "tower_sold"
	result["data"] = {"tower": tower, "refund": refund}
	exit_build_mode()

	return result

func get_tower_base_cost(tower: Dictionary) -> int:
	if tower.is_empty() or not tower.has("type"):
		return 0
	var tower_type: int = tower.type
	var stats: Dictionary = TOWER_STATS.get(tower_type, {})
	return stats.get("cost", 0)

func is_sell_mode() -> bool:
	return is_in_build_mode and build_phase == BuildPhase.SELECTING_SELL
