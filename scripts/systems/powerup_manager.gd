## powerup_manager.gd
## Manages powerup spawning, collection, and active effects
## Autoload singleton: PowerUpManager
extends Node

# Powerup types and their effects
enum PowerUpType {
	FREEZE,         # Freezes all enemies for duration
	SHIELD,         # Portal takes no damage for duration
	DOUBLE_SCORE,   # 2x score for duration
	HEAL,           # Restore portal HP
	BOMB,           # Destroy all enemies on screen
	SLOW_MO,        # Slow enemy movement for duration
	COMBO_KEEPER,   # Combo doesn't reset on error for duration
	RAPID_SPAWN     # Faster typing = bonus points
}

# Powerup definitions
const POWERUPS := {
	PowerUpType.FREEZE: {
		"name": "FREEZE",
		"word": "FREEZE",
		"duration": 5.0,
		"color": Color(0.0, 0.9, 1.0),  # Cyan
		"description": "Freeze all enemies"
	},
	PowerUpType.SHIELD: {
		"name": "SHIELD",
		"word": "SHIELD",
		"duration": 8.0,
		"color": Color(0.3, 0.5, 1.0),  # Blue
		"description": "Portal invincibility"
	},
	PowerUpType.DOUBLE_SCORE: {
		"name": "DOUBLE",
		"word": "DOUBLE",
		"duration": 10.0,
		"color": Color(1.0, 0.84, 0.0),  # Gold
		"description": "2x score multiplier"
	},
	PowerUpType.HEAL: {
		"name": "HEAL",
		"word": "HEAL",
		"duration": 0.0,  # Instant
		"color": Color(0.0, 1.0, 0.5),  # Green
		"description": "Restore 5 HP"
	},
	PowerUpType.BOMB: {
		"name": "BOMB",
		"word": "BOMB",
		"duration": 0.0,  # Instant
		"color": Color(1.0, 0.3, 0.0),  # Orange
		"description": "Destroy all enemies"
	},
	PowerUpType.SLOW_MO: {
		"name": "SLOW",
		"word": "SLOW",
		"duration": 6.0,
		"color": Color(0.6, 0.3, 0.9),  # Purple
		"description": "Slow enemy movement"
	},
	PowerUpType.COMBO_KEEPER: {
		"name": "KEEPER",
		"word": "KEEPER",
		"duration": 15.0,
		"color": Color(1.0, 0.5, 0.8),  # Pink
		"description": "Combo won't reset"
	},
	PowerUpType.RAPID_SPAWN: {
		"name": "RAPID",
		"word": "RAPID",
		"duration": 8.0,
		"color": Color(1.0, 1.0, 0.0),  # Yellow
		"description": "Speed bonus active"
	}
}

# Active powerups {type: remaining_time}
var active_powerups: Dictionary = {}

# Spawn configuration
var spawn_chance_per_wave: float = 0.3  # 30% chance per wave
var spawn_chance_per_kill: float = 0.05  # 5% chance per kill

# References
var powerup_scene: PackedScene = null
var spawn_container: Node2D = null

func _ready() -> void:
	powerup_scene = load("res://scenes/entities/powerup.tscn")
	if powerup_scene == null:
		DebugHelper.log_warning("PowerUpManager: powerup.tscn not found, will create dynamically")

	SignalBus.enemy_killed.connect(_on_enemy_killed)
	SignalBus.wave_started.connect(_on_wave_started)

	DebugHelper.log_info("PowerUpManager initialized")

func _process(delta: float) -> void:
	# Update active powerup timers
	var expired: Array = []
	for type in active_powerups:
		active_powerups[type] -= delta
		if active_powerups[type] <= 0:
			expired.append(type)

	for type in expired:
		deactivate_powerup(type)

func set_spawn_container(container: Node2D) -> void:
	spawn_container = container

func reset() -> void:
	active_powerups.clear()

func _on_enemy_killed(_enemy: Node, typed: bool) -> void:
	if typed and spawn_container and randf() < spawn_chance_per_kill:
		spawn_random_powerup()

func _on_wave_started(wave: int) -> void:
	if spawn_container and wave > 1 and randf() < spawn_chance_per_wave:
		spawn_random_powerup()

func spawn_random_powerup() -> void:
	if spawn_container == null:
		return

	var types = POWERUPS.keys()
	var random_type = types[randi() % types.size()]
	spawn_powerup(random_type)

func spawn_powerup(type: PowerUpType) -> void:
	if spawn_container == null:
		return

	var powerup_data = POWERUPS[type]

	# Create powerup node dynamically if scene not available
	var powerup = create_powerup_node(type, powerup_data)

	# Random position in upper portion of screen
	var spawn_x = randf_range(100, GameConfig.SCREEN_WIDTH - 100)
	var spawn_y = randf_range(100, 300)
	powerup.position = Vector2(spawn_x, spawn_y)

	spawn_container.add_child(powerup)
	SoundManager.play_powerup_spawn()
	DebugHelper.log_debug("PowerUp spawned: %s at (%d, %d)" % [powerup_data.word, spawn_x, spawn_y])

func create_powerup_node(type: PowerUpType, data: Dictionary) -> Node2D:
	var powerup = Node2D.new()
	powerup.set_script(load("res://scripts/entities/powerup.gd"))
	powerup.set_meta("powerup_type", type)
	powerup.set_meta("powerup_word", data.word)
	powerup.set_meta("powerup_color", data.color)

	# Add visual
	var rect = ColorRect.new()
	rect.name = "Sprite"
	rect.size = Vector2(60, 30)
	rect.position = Vector2(-30, -15)
	rect.color = data.color
	powerup.add_child(rect)

	# Add label
	var label = Label.new()
	label.name = "WordLabel"
	label.text = data.word
	label.position = Vector2(-30, -30)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color.WHITE)
	powerup.add_child(label)

	return powerup

func collect_powerup(type: PowerUpType) -> void:
	var data = POWERUPS[type]
	DebugHelper.log_info("PowerUp collected: %s" % data.name)

	SoundManager.play_powerup_collect()

	if data.duration > 0:
		activate_powerup(type, data.duration)
	else:
		apply_instant_powerup(type)

	SignalBus.powerup_collected.emit(type, data.name)

func activate_powerup(type: PowerUpType, duration: float) -> void:
	active_powerups[type] = duration
	var data = POWERUPS[type]

	match type:
		PowerUpType.FREEZE:
			freeze_all_enemies(true)
			SoundManager.play_powerup_freeze()
		PowerUpType.SHIELD:
			SignalBus.shield_activated.emit(duration)
			SoundManager.play_powerup_shield()
		PowerUpType.DOUBLE_SCORE:
			SignalBus.score_multiplier_changed.emit(2.0)
		PowerUpType.SLOW_MO:
			slow_all_enemies(0.5)
		PowerUpType.COMBO_KEEPER:
			TypingManager.combo_keeper_active = true
		PowerUpType.RAPID_SPAWN:
			SignalBus.rapid_mode_activated.emit(duration)

	DebugHelper.log_debug("PowerUp activated: %s for %.1fs" % [data.name, duration])

func deactivate_powerup(type: PowerUpType) -> void:
	active_powerups.erase(type)
	var data = POWERUPS[type]

	SoundManager.play_powerup_expire()

	match type:
		PowerUpType.FREEZE:
			freeze_all_enemies(false)
		PowerUpType.SHIELD:
			SignalBus.shield_deactivated.emit()
		PowerUpType.DOUBLE_SCORE:
			SignalBus.score_multiplier_changed.emit(1.0)
		PowerUpType.SLOW_MO:
			slow_all_enemies(1.0)
		PowerUpType.COMBO_KEEPER:
			TypingManager.combo_keeper_active = false
		PowerUpType.RAPID_SPAWN:
			SignalBus.rapid_mode_deactivated.emit()

	DebugHelper.log_debug("PowerUp deactivated: %s" % data.name)

func apply_instant_powerup(type: PowerUpType) -> void:
	match type:
		PowerUpType.HEAL:
			SignalBus.portal_heal.emit(5)
			SoundManager.play_powerup_heal()
		PowerUpType.BOMB:
			destroy_all_enemies()
			SoundManager.play_powerup_bomb()

func freeze_all_enemies(freeze: bool) -> void:
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy.has_method("set_frozen"):
			enemy.set_frozen(freeze)
		else:
			enemy.set_process(not freeze)
			enemy.set_physics_process(not freeze)

func slow_all_enemies(speed_multiplier: float) -> void:
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy.has_method("set_speed_multiplier"):
			enemy.set_speed_multiplier(speed_multiplier)

func destroy_all_enemies() -> void:
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy.has_method("die"):
			enemy.die()
	DebugHelper.log_info("BOMB: Destroyed %d enemies" % enemies.size())

func is_powerup_active(type: PowerUpType) -> bool:
	return active_powerups.has(type)

func get_powerup_remaining_time(type: PowerUpType) -> float:
	return active_powerups.get(type, 0.0)

func get_score_multiplier() -> float:
	if is_powerup_active(PowerUpType.DOUBLE_SCORE):
		return 2.0
	return 1.0

func is_shield_active() -> bool:
	return is_powerup_active(PowerUpType.SHIELD)

func is_combo_keeper_active() -> bool:
	return is_powerup_active(PowerUpType.COMBO_KEEPER)
