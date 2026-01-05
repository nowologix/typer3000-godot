## tower.gd
## Defensive tower that attacks enemies automatically
extends Node2D
class_name Tower

enum TowerType {
	BASIC,      # Single target, moderate damage
	RAPID,      # Fast attack, low damage
	SPLASH,     # AoE damage
	SLOW,       # Slows enemies
	SNIPER      # Long range, high damage, slow attack
}

# Tower stats by type
const TOWER_STATS := {
	TowerType.BASIC: {
		"name": "Basic Tower",
		"cost": 100,
		"damage": 1,
		"range": 200.0,
		"attack_speed": 1.0,
		"color": Color(0.0, 0.9, 1.0)
	},
	TowerType.RAPID: {
		"name": "Rapid Tower",
		"cost": 150,
		"damage": 1,
		"range": 150.0,
		"attack_speed": 3.0,
		"color": Color(1.0, 1.0, 0.0)
	},
	TowerType.SPLASH: {
		"name": "Splash Tower",
		"cost": 200,
		"damage": 1,
		"range": 180.0,
		"attack_speed": 0.5,
		"splash_radius": 80.0,
		"color": Color(1.0, 0.5, 0.0)
	},
	TowerType.SLOW: {
		"name": "Slow Tower",
		"cost": 175,
		"damage": 0,
		"range": 200.0,
		"attack_speed": 2.0,
		"slow_amount": 0.5,
		"slow_duration": 2.0,
		"color": Color(0.6, 0.3, 0.9)
	},
	TowerType.SNIPER: {
		"name": "Sniper Tower",
		"cost": 250,
		"damage": 3,
		"range": 400.0,
		"attack_speed": 0.3,
		"color": Color(1.0, 0.2, 0.2)
	}
}

@export var tower_type: TowerType = TowerType.BASIC
@export var level: int = 1

var stats: Dictionary = {}
var attack_timer: float = 0.0
var target: Node2D = null
var active: bool = true

@onready var sprite: ColorRect = $Sprite
@onready var range_indicator: Node2D = $RangeIndicator

func _ready() -> void:
	add_to_group("towers")
	load_stats()
	update_visuals()

func load_stats() -> void:
	stats = TOWER_STATS[tower_type].duplicate()
	# Apply level scaling
	stats.damage = stats.damage + (level - 1)
	stats.range = stats.range * (1.0 + (level - 1) * 0.1)

func setup(type: TowerType, pos: Vector2) -> void:
	tower_type = type
	position = pos
	level = 1
	load_stats()
	update_visuals()
	DebugHelper.log_info("Tower placed: %s at (%d, %d)" % [stats.name, pos.x, pos.y])

func _process(delta: float) -> void:
	if not active:
		return

	attack_timer += delta

	# Find target if we don't have one
	if target == null or not is_instance_valid(target) or not target.is_alive():
		target = find_target()

	# Attack if we have a target and cooldown is ready
	if target != null and is_instance_valid(target):
		var attack_interval = 1.0 / stats.attack_speed
		if attack_timer >= attack_interval:
			attack_target()
			attack_timer = 0.0

func find_target() -> Node:
	var enemies = get_tree().get_nodes_in_group("enemies")
	var best_target: Node = null
	var best_distance: float = INF

	for enemy in enemies:
		if not enemy.is_alive():
			continue

		var distance = global_position.distance_to(enemy.global_position)
		if distance <= stats.range and distance < best_distance:
			best_distance = distance
			best_target = enemy

	return best_target

func attack_target() -> void:
	if target == null or not is_instance_valid(target):
		return

	match tower_type:
		TowerType.BASIC, TowerType.RAPID, TowerType.SNIPER:
			single_target_attack()
		TowerType.SPLASH:
			splash_attack()
		TowerType.SLOW:
			slow_attack()

	# Visual feedback
	flash_attack()

func single_target_attack() -> void:
	if target.has_method("take_tower_damage"):
		target.take_tower_damage(stats.damage)
	DebugHelper.log_debug("%s attacks %s for %d damage" % [stats.name, target.word, stats.damage])

func splash_attack() -> void:
	var splash_radius = stats.get("splash_radius", 80.0)
	var enemies = get_tree().get_nodes_in_group("enemies")

	for enemy in enemies:
		if not enemy.is_alive():
			continue
		var distance = target.global_position.distance_to(enemy.global_position)
		if distance <= splash_radius:
			if enemy.has_method("take_tower_damage"):
				enemy.take_tower_damage(stats.damage)

	DebugHelper.log_debug("%s splash attack at %s" % [stats.name, target.word])

func slow_attack() -> void:
	var slow_amount = stats.get("slow_amount", 0.5)
	var slow_duration = stats.get("slow_duration", 2.0)

	if target.has_method("apply_slow"):
		target.apply_slow(slow_amount, slow_duration)
	elif target.has_method("set_speed_multiplier"):
		target.set_speed_multiplier(slow_amount)
		# Note: Would need a timer to restore speed

	DebugHelper.log_debug("%s slows %s" % [stats.name, target.word])

func flash_attack() -> void:
	SoundManager.play_tower_shoot()

	if sprite == null:
		return

	var original_color = sprite.color
	sprite.color = Color.WHITE

	var tween = create_tween()
	tween.tween_property(sprite, "color", original_color, 0.1)

func upgrade() -> bool:
	if level >= 3:
		return false

	level += 1
	load_stats()
	update_visuals()

	SignalBus.tower_upgraded.emit(self, level)
	DebugHelper.log_info("%s upgraded to level %d" % [stats.name, level])
	return true

func update_visuals() -> void:
	if sprite:
		sprite.color = stats.color
		# Scale based on level
		sprite.scale = Vector2.ONE * (1.0 + (level - 1) * 0.2)

func get_upgrade_cost() -> int:
	return stats.cost * level

func sell() -> int:
	var sell_value = int(stats.cost * 0.5 * level)
	SignalBus.tower_destroyed.emit(self)
	queue_free()
	return sell_value
