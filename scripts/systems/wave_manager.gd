## wave_manager.gd
## Manages enemy wave spawning - difficulty scales gradually to wave 50+
extends Node

# Base configuration (Wave 1 values)
const BASE_ENEMIES: int = 3
const BASE_SPAWN_INTERVAL: float = 2.5
const BASE_ENEMY_SPEED: float = 25.0
const WAVE_DELAY: float = 3.0

# Maximum values (reached at wave 50)
const MAX_ENEMIES: int = 25
const MIN_SPAWN_INTERVAL: float = 0.5
const MAX_ENEMY_SPEED: float = 70.0

# Boss waves (every 10 waves)
const BOSS_WAVE_INTERVAL: int = 10
const BOSS_SPAWN_DELAY: float = 2.0  # Delay before boss appears

# Special enemy spawning
const SHIELD_START_WAVE: int = 8  # Shield enemies start appearing
const SHIELD_CHANCE_BASE: float = 0.05  # 5% at first, increases with wave
const SHIELD_ESCORT_COUNT: int = 4  # Number of escort enemies to spawn with shield
const TANK_START_WAVE: int = 5  # Tank enemies start appearing
const TANK_CHANCE_BASE: float = 0.08  # 8% at first, increases with wave
const SPLITTER_START_WAVE: int = 6  # Splitter enemies start appearing
const SPLITTER_CHANCE_BASE: float = 0.06  # 6% at first, increases with wave

# State
var current_wave: int = 0
var enemies_to_spawn: int = 0
var enemies_spawned_this_wave: int = 0
var wave_active: bool = false
var manager_active: bool = false
var is_boss_wave: bool = false
var boss_spawned: bool = false
var current_boss: Node = null

# References
var enemy_container: Node2D = null
var portal: Node2D = null
var enemy_scene: PackedScene = null
var boss_scene: PackedScene = null

# Timers
var spawn_timer: Timer = null
var wave_timer: Timer = null

# Fallback word list
var fallback_words: Array[String] = [
	"CAT", "DOG", "RUN", "JUMP", "FIRE", "CODE", "GAME", "TYPE", "WORD", "FAST"
]

func _ready() -> void:
	spawn_timer = Timer.new()
	spawn_timer.one_shot = true
	spawn_timer.timeout.connect(_on_spawn_timer)
	add_child(spawn_timer)

	wave_timer = Timer.new()
	wave_timer.one_shot = true
	wave_timer.timeout.connect(_on_wave_timer)
	add_child(wave_timer)

	enemy_scene = load("res://scenes/entities/enemy_word.tscn")
	if enemy_scene == null:
		DebugHelper.log_error("WaveManager: Failed to load enemy scene!")

	boss_scene = load("res://scenes/entities/enemy_boss.tscn")
	if boss_scene == null:
		DebugHelper.log_error("WaveManager: Failed to load boss scene!")

func setup(container: Node2D, portal_ref: Node2D) -> void:
	enemy_container = container
	portal = portal_ref
	current_wave = 0
	wave_active = false
	manager_active = false
	DebugHelper.log_info("WaveManager setup complete")

func start_waves() -> void:
	if enemy_container == null or portal == null:
		DebugHelper.log_error("WaveManager: Not set up properly!")
		return

	manager_active = true
	current_wave = 0
	start_next_wave()

func stop_waves() -> void:
	manager_active = false
	wave_active = false
	spawn_timer.stop()
	wave_timer.stop()

# Calculate difficulty progress (0.0 at wave 1, 1.0 at wave 50)
func get_difficulty_progress() -> float:
	return clampf((current_wave - 1) / 49.0, 0.0, 1.0)

# Get number of enemies for current wave
func get_enemy_count() -> int:
	var progress := get_difficulty_progress()
	var curved_progress := ease(progress, 0.6)
	var count := int(lerpf(float(BASE_ENEMIES), float(MAX_ENEMIES), curved_progress))

	# Boss waves have fewer but stronger enemies
	if is_boss_wave:
		count = maxi(int(count * 0.6), 5)

	# Waves beyond 50 can have slightly more
	if current_wave > 50:
		count += (current_wave - 50) / 5

	return mini(count, 35)

# Get spawn interval for current wave
func get_spawn_interval() -> float:
	var progress := get_difficulty_progress()
	var curved_progress := ease(progress, 0.4)
	var interval := lerpf(BASE_SPAWN_INTERVAL, MIN_SPAWN_INTERVAL, curved_progress)

	if current_wave > 50:
		interval = maxf(interval - (current_wave - 50) * 0.01, 0.3)

	return interval

# Get enemy speed for current wave
func get_enemy_speed() -> float:
	var progress := get_difficulty_progress()
	var curved_progress := ease(progress, 0.5)
	var base_speed := lerpf(BASE_ENEMY_SPEED, MAX_ENEMY_SPEED, curved_progress)

	if current_wave > 50:
		base_speed += (current_wave - 50) * 0.5

	return base_speed * randf_range(0.9, 1.1)

func start_next_wave() -> void:
	if not manager_active:
		return

	current_wave += 1
	enemies_spawned_this_wave = 0
	wave_active = true
	boss_spawned = false
	current_boss = null
	is_boss_wave = (current_wave % BOSS_WAVE_INTERVAL == 0)

	if is_boss_wave:
		enemies_to_spawn = 0  # No regular enemies in boss wave
		DebugHelper.log_info("=== BOSS WAVE %d ===" % current_wave)
		SignalBus.wave_started.emit(current_wave)
		# Delay before boss spawns for dramatic effect
		await get_tree().create_timer(BOSS_SPAWN_DELAY).timeout
		if manager_active:
			spawn_boss()
	else:
		enemies_to_spawn = get_enemy_count()
		DebugHelper.log_info("Wave %d (%d enemies)" % [current_wave, enemies_to_spawn])
		SignalBus.wave_started.emit(current_wave)
		spawn_enemy()

func spawn_enemy() -> void:
	if not wave_active or enemy_scene == null or enemy_container == null:
		return

	if enemies_spawned_this_wave >= enemies_to_spawn:
		check_wave_complete()
		return

	var enemy = enemy_scene.instantiate()

	# 360° spawning - enemies come from all edges
	var spawn_pos = get_random_edge_spawn_position()
	enemy.position = spawn_pos

	var word = get_word_for_wave()
	var speed = get_enemy_speed()

	# Check special enemy types (priority: Shield > Tank > Splitter > Normal)
	var special_type = get_special_enemy_type()

	match special_type:
		"shield":
			enemy.setup_shield(word, portal)
			DebugHelper.log_debug("Spawned SHIELD enemy %d/%d: %s" % [enemies_spawned_this_wave + 1, enemies_to_spawn, word])
			# Spawn escort enemies around the shield
			spawn_shield_escorts(spawn_pos, speed)
		"tank":
			enemy.setup_tank(word, portal, 3)
			DebugHelper.log_debug("Spawned TANK enemy %d/%d: %s (3 hits)" % [enemies_spawned_this_wave + 1, enemies_to_spawn, word])
		"splitter":
			enemy.setup_splitter(word, portal)
			DebugHelper.log_debug("Spawned SPLITTER enemy %d/%d: %s" % [enemies_spawned_this_wave + 1, enemies_to_spawn, word])
		_:
			enemy.setup(word, portal)
			enemy.speed = speed
			DebugHelper.log_debug("Spawned %d/%d: %s" % [enemies_spawned_this_wave + 1, enemies_to_spawn, word])

	enemy_container.add_child(enemy)
	enemies_spawned_this_wave += 1

	SignalBus.enemy_spawned.emit(enemy)

	spawn_timer.start(get_spawn_interval())

func spawn_shield_escorts(shield_pos: Vector2, base_speed: float) -> void:
	# Spawn escort enemies in a square formation around the shield
	var escort_count = mini(SHIELD_ESCORT_COUNT, enemies_to_spawn - enemies_spawned_this_wave)
	if escort_count <= 0:
		return
	
	# Square formation positions (front, back, left, right)
	var formation_offsets = [
		Vector2(0, -80),   # Front (toward portal)
		Vector2(0, 80),    # Back
		Vector2(-70, 0),   # Left
		Vector2(70, 0),    # Right
	]
	
	for i in range(escort_count):
		var escort = enemy_scene.instantiate()
		
		# Position in square formation with slight randomness
		var base_offset = formation_offsets[i % formation_offsets.size()]
		var random_offset = Vector2(randf_range(-20, 20), randf_range(-20, 20))
		escort.position = shield_pos + base_offset + random_offset
		
		var word = get_word_for_wave()
		escort.setup(word, portal)
		escort.speed = base_speed * 1.1  # Slightly faster to stay with slower shield
		
		enemy_container.add_child(escort)
		enemies_spawned_this_wave += 1
		
		SignalBus.enemy_spawned.emit(escort)
		DebugHelper.log_debug("Spawned SHIELD escort %d: %s" % [i + 1, word])

func spawn_boss() -> void:
	if not wave_active or boss_scene == null or enemy_container == null:
		return

	if boss_spawned:
		return

	var boss = boss_scene.instantiate()

	# Boss spawns from random edge (360° spawning)
	var spawn_pos = get_random_edge_spawn_position()
	boss.position = spawn_pos

	# Boss level based on wave number (1-4)
	var boss_level = mini((current_wave / BOSS_WAVE_INTERVAL), 4)
	boss.setup(portal, boss_level)

	# Connect boss signals
	boss.boss_defeated.connect(_on_boss_defeated)

	enemy_container.add_child(boss)
	boss_spawned = true
	current_boss = boss

	SignalBus.enemy_spawned.emit(boss)
	SignalBus.boss_spawned.emit(boss, boss_level)
	DebugHelper.log_info("BOSS spawned at wave %d (Level %d)" % [current_wave, boss_level])

	# Screen shake for boss entrance
	EffectsManager.screen_shake(8.0, 0.4)
	SoundManager.play_sfx("nuke_explosion")

func _on_boss_defeated(boss: Node) -> void:
	DebugHelper.log_info("=== BOSS DEFEATED ===")
	current_boss = null
	check_wave_complete()

func _on_spawn_timer() -> void:
	spawn_enemy()

func check_wave_complete() -> void:
	if enemy_container == null:
		return

	# Boss wave: complete when boss is defeated
	if is_boss_wave:
		if boss_spawned and current_boss == null:
			on_wave_complete()
		elif not boss_spawned:
			# Boss not spawned yet
			return
		else:
			wave_timer.start(0.5)
	else:
		# Normal wave: complete when all enemies killed
		if enemy_container.get_child_count() == 0 and enemies_spawned_this_wave >= enemies_to_spawn:
			on_wave_complete()
		else:
			wave_timer.start(0.5)

func _on_wave_timer() -> void:
	if wave_active:
		check_wave_complete()

func on_wave_complete() -> void:
	wave_active = false

	if is_boss_wave:
		DebugHelper.log_info("=== BOSS WAVE %d COMPLETE ===" % current_wave)
	else:
		DebugHelper.log_info("Wave %d complete" % current_wave)

	SignalBus.wave_completed.emit(current_wave)

	if manager_active:
		await get_tree().create_timer(WAVE_DELAY).timeout
		if manager_active:
			start_next_wave()

func get_word_for_wave() -> String:
	if WordSetLoader:
		return WordSetLoader.get_word_for_wave(current_wave)
	return fallback_words[randi() % fallback_words.size()]

# 360° spawning - returns a random position along any screen edge
func get_random_edge_spawn_position() -> Vector2:
	var margin = GameConfig.ENEMY_SPAWN_MARGIN
	var w = GameConfig.SCREEN_WIDTH
	var h = GameConfig.SCREEN_HEIGHT

	# Pick random edge: 0=top, 1=bottom, 2=left, 3=right
	var edge = randi() % 4
	var spawn_x: float
	var spawn_y: float

	match edge:
		0:  # Top edge
			spawn_x = randf_range(margin, w - margin)
			spawn_y = -margin
		1:  # Bottom edge
			spawn_x = randf_range(margin, w - margin)
			spawn_y = h + margin
		2:  # Left edge
			spawn_x = -margin
			spawn_y = randf_range(margin, h - margin)
		3:  # Right edge
			spawn_x = w + margin
			spawn_y = randf_range(margin, h - margin)

	return Vector2(spawn_x, spawn_y)

func _process(_delta: float) -> void:
	if not wave_active:
		return

	if is_boss_wave:
		# Boss wave: check if boss is defeated
		if boss_spawned and current_boss == null:
			on_wave_complete()
	else:
		# Normal wave: check if all enemies killed
		if enemies_spawned_this_wave >= enemies_to_spawn:
			if enemy_container and enemy_container.get_child_count() == 0:
				on_wave_complete()

func get_current_wave() -> int:
	return current_wave

func is_current_wave_boss() -> bool:
	return is_boss_wave

func get_special_enemy_type() -> String:
	# Check for Shield enemy first (highest priority)
	if current_wave >= SHIELD_START_WAVE:
		var wave_progress = float(current_wave - SHIELD_START_WAVE) / 20.0
		var shield_chance = SHIELD_CHANCE_BASE + wave_progress * 0.1
		shield_chance = minf(shield_chance, 0.15)
		if randf() < shield_chance:
			return "shield"

	# Check for Tank enemy
	if current_wave >= TANK_START_WAVE:
		var wave_progress = float(current_wave - TANK_START_WAVE) / 15.0
		var tank_chance = TANK_CHANCE_BASE + wave_progress * 0.1
		tank_chance = minf(tank_chance, 0.18)
		if randf() < tank_chance:
			return "tank"

	# Check for Splitter enemy
	if current_wave >= SPLITTER_START_WAVE:
		var wave_progress = float(current_wave - SPLITTER_START_WAVE) / 15.0
		var splitter_chance = SPLITTER_CHANCE_BASE + wave_progress * 0.08
		splitter_chance = minf(splitter_chance, 0.14)
		if randf() < splitter_chance:
			return "splitter"

	return "normal"
