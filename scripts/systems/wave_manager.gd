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

# State
var current_wave: int = 0
var enemies_to_spawn: int = 0
var enemies_spawned_this_wave: int = 0
var wave_active: bool = false
var manager_active: bool = false
var is_boss_wave: bool = false

# References
var enemy_container: Node2D = null
var portal: Node2D = null
var enemy_scene: PackedScene = null

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
	is_boss_wave = (current_wave % BOSS_WAVE_INTERVAL == 0)

	enemies_to_spawn = get_enemy_count()

	if is_boss_wave:
		DebugHelper.log_info("=== BOSS WAVE %d === (%d enemies)" % [current_wave, enemies_to_spawn])
	else:
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

	var spawn_x = randf_range(
		GameConfig.ENEMY_SPAWN_MARGIN,
		GameConfig.SCREEN_WIDTH - GameConfig.ENEMY_SPAWN_MARGIN
	)
	var spawn_y = randf_range(
		GameConfig.ENEMY_SPAWN_Y_MIN,
		GameConfig.ENEMY_SPAWN_Y_MAX
	)

	enemy.position = Vector2(spawn_x, spawn_y)

	var word = get_word_for_wave()
	var speed = get_enemy_speed()

	enemy.setup(word, portal)
	enemy.speed = speed

	enemy_container.add_child(enemy)
	enemies_spawned_this_wave += 1

	SignalBus.enemy_spawned.emit(enemy)
	DebugHelper.log_debug("Spawned %d/%d: %s" % [enemies_spawned_this_wave, enemies_to_spawn, word])

	spawn_timer.start(get_spawn_interval())

func _on_spawn_timer() -> void:
	spawn_enemy()

func check_wave_complete() -> void:
	if enemy_container == null:
		return

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

func _process(_delta: float) -> void:
	if wave_active and enemies_spawned_this_wave >= enemies_to_spawn:
		if enemy_container and enemy_container.get_child_count() == 0:
			on_wave_complete()

func get_current_wave() -> int:
	return current_wave

func is_current_wave_boss() -> bool:
	return is_boss_wave
