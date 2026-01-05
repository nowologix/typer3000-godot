## tower_manager.gd
## Manages tower placement, upgrades, and resources
extends Node

# Player resources
var currency: int = 0
var towers: Array[Node] = []

# Tower placement
var tower_scene: PackedScene = null
var tower_container: Node2D = null
var placement_mode: bool = false
var selected_tower_type: int = 0  # Tower.TowerType
var preview_tower: Node2D = null

# Grid settings for tower placement
const GRID_SIZE: int = 40
const MIN_TOWER_DISTANCE: float = 60.0

# Starting currency
const STARTING_CURRENCY: int = 200

func _ready() -> void:
	tower_scene = load("res://scenes/entities/tower.tscn")
	if tower_scene == null:
		DebugHelper.log_warning("TowerManager: tower.tscn not found")

	# Connect signals
	SignalBus.enemy_killed.connect(_on_enemy_killed)
	SignalBus.wave_completed.connect(_on_wave_completed)

	DebugHelper.log_info("TowerManager initialized")

func setup(container: Node2D) -> void:
	tower_container = container
	currency = STARTING_CURRENCY
	towers.clear()
	DebugHelper.log_info("TowerManager setup with %d starting currency" % currency)

func reset() -> void:
	# Remove all towers
	for tower in towers:
		if is_instance_valid(tower):
			tower.queue_free()
	towers.clear()
	currency = STARTING_CURRENCY
	exit_placement_mode()

func get_currency() -> int:
	return currency

func add_currency(amount: int) -> void:
	currency += amount
	DebugHelper.log_debug("Currency: +%d (total: %d)" % [amount, currency])

func spend_currency(amount: int) -> bool:
	if currency >= amount:
		currency -= amount
		DebugHelper.log_debug("Currency: -%d (total: %d)" % [amount, currency])
		return true
	return false

func enter_placement_mode(tower_type: int) -> void:
	if tower_scene == null:
		return

	selected_tower_type = tower_type
	placement_mode = true

	# Create preview tower
	preview_tower = tower_scene.instantiate()
	preview_tower.modulate = Color(1, 1, 1, 0.5)
	preview_tower.tower_type = tower_type
	preview_tower.active = false

	if tower_container:
		tower_container.add_child(preview_tower)

	DebugHelper.log_debug("Entered tower placement mode: type %d" % tower_type)

func exit_placement_mode() -> void:
	placement_mode = false
	if preview_tower:
		preview_tower.queue_free()
		preview_tower = null

func update_preview_position(mouse_pos: Vector2) -> void:
	if preview_tower == null:
		return

	# Snap to grid
	var snapped_pos = snap_to_grid(mouse_pos)
	preview_tower.position = snapped_pos

	# Check if position is valid
	if can_place_tower_at(snapped_pos):
		preview_tower.modulate = Color(0, 1, 0, 0.5)  # Green = valid
	else:
		preview_tower.modulate = Color(1, 0, 0, 0.5)  # Red = invalid

func snap_to_grid(pos: Vector2) -> Vector2:
	return Vector2(
		round(pos.x / GRID_SIZE) * GRID_SIZE,
		round(pos.y / GRID_SIZE) * GRID_SIZE
	)

func can_place_tower_at(pos: Vector2) -> bool:
	# Check bounds
	if pos.x < 50 or pos.x > GameConfig.SCREEN_WIDTH - 50:
		return false
	if pos.y < 100 or pos.y > GameConfig.SCREEN_HEIGHT - 100:
		return false

	# Check distance from other towers
	for tower in towers:
		if not is_instance_valid(tower):
			continue
		if tower.position.distance_to(pos) < MIN_TOWER_DISTANCE:
			return false

	# Check distance from portal (don't block it)
	var portal = get_tree().get_first_node_in_group("portal")
	if portal and portal.global_position.distance_to(pos) < 80:
		return false

	return true

func try_place_tower(mouse_pos: Vector2) -> bool:
	if not placement_mode or tower_scene == null:
		return false

	var pos = snap_to_grid(mouse_pos)

	if not can_place_tower_at(pos):
		DebugHelper.log_warning("Cannot place tower at (%d, %d)" % [pos.x, pos.y])
		return false

	# Check cost
	var tower_type_enum = selected_tower_type
	var cost = get_tower_cost(tower_type_enum)
	if not spend_currency(cost):
		DebugHelper.log_warning("Not enough currency for tower (need %d, have %d)" % [cost, currency])
		return false

	# Place the tower
	var tower = tower_scene.instantiate()
	tower.setup(tower_type_enum, pos)
	tower_container.add_child(tower)
	towers.append(tower)

	SoundManager.play_tower_build()
	SignalBus.tower_built.emit(tower, pos)
	exit_placement_mode()
	return true

func get_tower_cost(tower_type: int) -> int:
	var Tower = load("res://scripts/entities/tower.gd")
	if Tower and Tower.TOWER_STATS.has(tower_type):
		return Tower.TOWER_STATS[tower_type].cost
	return 100

func upgrade_tower(tower: Node) -> bool:
	if not is_instance_valid(tower):
		return false

	var cost = tower.get_upgrade_cost()
	if not spend_currency(cost):
		DebugHelper.log_warning("Not enough currency to upgrade (need %d)" % cost)
		return false

	var success = tower.upgrade()
	if success:
		SoundManager.play_tower_upgrade()
	return success

func sell_tower(tower: Node) -> int:
	if not is_instance_valid(tower):
		return 0

	var refund = tower.sell()
	add_currency(refund)
	towers.erase(tower)
	SoundManager.play_tower_sell()
	return refund

func _on_enemy_killed(_enemy: Node, typed: bool) -> void:
	# Award currency for kills
	if typed:
		add_currency(10)  # Player typed kill
	else:
		add_currency(5)   # Tower kill

func _on_wave_completed(wave: int) -> void:
	# Wave completion bonus
	var bonus = wave * 25
	add_currency(bonus)
	DebugHelper.log_info("Wave %d bonus: +%d currency" % [wave, bonus])

func _input(event: InputEvent) -> void:
	if not placement_mode:
		return

	if event is InputEventMouseMotion:
		update_preview_position(event.position)

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			try_place_tower(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			exit_placement_mode()

	if event.is_action_pressed("ui_cancel"):
		exit_placement_mode()
