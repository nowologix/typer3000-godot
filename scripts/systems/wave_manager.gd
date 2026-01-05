## wave_manager.gd
## Manages enemy wave spawning with JSON word loading
extends Node

# Configuration
@export var enemies_per_wave: int = 5
@export var spawn_interval: float = 2.0
@export var wave_delay: float = 3.0
@export var difficulty_scale: float = 1.1  # Multiplier per wave
@export var word_set_path: String = "res://assets/data/word_sets/basic.json"

# State
var current_wave: int = 0
var enemies_spawned_this_wave: int = 0
var wave_active: bool = false
var manager_active: bool = false

# References
var enemy_container: Node2D = null
var portal: Node2D = null
var enemy_scene: PackedScene = null

# Timers
var spawn_timer: Timer = null
var wave_timer: Timer = null

# Word lists loaded from JSON
var word_sets: Dictionary = {}
var word_pool_easy: Array[String] = []
var word_pool_medium: Array[String] = []
var word_pool_hard: Array[String] = []
var word_pool_expert: Array[String] = []

# Fallback word list if JSON fails to load
var fallback_words: Array[String] = [
	"CAT", "DOG", "RUN", "JUMP", "FIRE", "CODE", "GAME", "TYPE", "WORD", "FAST",
	"SLOW", "HERO", "ZERO", "BYTE", "DATA", "LOOP", "FUNC", "NODE", "TREE", "PATH"
]

func _ready() -> void:
	# Create timers
	spawn_timer = Timer.new()
	spawn_timer.one_shot = true
	spawn_timer.timeout.connect(_on_spawn_timer)
	add_child(spawn_timer)

	wave_timer = Timer.new()
	wave_timer.one_shot = true
	wave_timer.timeout.connect(_on_wave_timer)
	add_child(wave_timer)

	# Load enemy scene
	enemy_scene = load("res://scenes/entities/enemy_word.tscn")
	if enemy_scene == null:
		DebugHelper.log_error("WaveManager: Failed to load enemy scene!")

	# Load word sets from JSON
	load_word_sets()

func load_word_sets() -> void:
	if not FileAccess.file_exists(word_set_path):
		DebugHelper.log_warning("WaveManager: Word set file not found: %s, using fallback" % word_set_path)
		use_fallback_words()
		return

	var file = FileAccess.open(word_set_path, FileAccess.READ)
	if file == null:
		DebugHelper.log_error("WaveManager: Failed to open word set file: %s" % word_set_path)
		use_fallback_words()
		return

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		DebugHelper.log_error("WaveManager: Failed to parse JSON: %s" % json.get_error_message())
		use_fallback_words()
		return

	var data = json.get_data()
	if not data is Dictionary or not data.has("words"):
		DebugHelper.log_error("WaveManager: Invalid word set format")
		use_fallback_words()
		return

	word_sets = data
	var words = data["words"]

	# Parse word arrays
	if words.has("easy"):
		for word in words["easy"]:
			word_pool_easy.append(word.to_upper())
	if words.has("medium"):
		for word in words["medium"]:
			word_pool_medium.append(word.to_upper())
	if words.has("hard"):
		for word in words["hard"]:
			word_pool_hard.append(word.to_upper())
	if words.has("expert"):
		for word in words["expert"]:
			word_pool_expert.append(word.to_upper())

	var total_words = word_pool_easy.size() + word_pool_medium.size() + word_pool_hard.size() + word_pool_expert.size()
	DebugHelper.log_info("WaveManager: Loaded %d words from %s" % [total_words, word_set_path])

func use_fallback_words() -> void:
	word_pool_easy = fallback_words.duplicate()
	word_pool_medium = fallback_words.duplicate()
	word_pool_hard = fallback_words.duplicate()
	word_pool_expert = fallback_words.duplicate()
	DebugHelper.log_info("WaveManager: Using fallback word list (%d words)" % fallback_words.size())

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

func start_next_wave() -> void:
	if not manager_active:
		return

	current_wave += 1
	enemies_spawned_this_wave = 0
	wave_active = true

	# Scale difficulty
	var scaled_enemies = int(enemies_per_wave * pow(difficulty_scale, current_wave - 1))
	enemies_per_wave = min(scaled_enemies, 20)  # Cap at 20 enemies per wave

	DebugHelper.log_info("Wave %d starting (%d enemies)" % [current_wave, enemies_per_wave])
	SignalBus.wave_started.emit(current_wave)

	# Start spawning
	spawn_enemy()

func spawn_enemy() -> void:
	if not wave_active or enemy_scene == null or enemy_container == null:
		return

	if enemies_spawned_this_wave >= enemies_per_wave:
		# All enemies spawned, wait for them to be cleared
		check_wave_complete()
		return

	# Create enemy
	var enemy = enemy_scene.instantiate()

	# Random spawn position at top of screen
	var spawn_x = randf_range(
		GameConfig.ENEMY_SPAWN_MARGIN,
		GameConfig.SCREEN_WIDTH - GameConfig.ENEMY_SPAWN_MARGIN
	)
	var spawn_y = randf_range(
		GameConfig.ENEMY_SPAWN_Y_MIN,
		GameConfig.ENEMY_SPAWN_Y_MAX
	)

	enemy.position = Vector2(spawn_x, spawn_y)

	# Get word and set speed based on wave
	var word = get_word_for_wave()
	var speed = GameConfig.ENEMY_BASE_SPEED * (1.0 + (current_wave - 1) * 0.1)

	enemy.setup(word, portal)
	enemy.speed = speed

	enemy_container.add_child(enemy)
	enemies_spawned_this_wave += 1

	SignalBus.enemy_spawned.emit(enemy)
	DebugHelper.log_debug("Spawned enemy %d/%d: %s" % [enemies_spawned_this_wave, enemies_per_wave, word])

	# Schedule next spawn
	spawn_timer.start(spawn_interval)

func _on_spawn_timer() -> void:
	spawn_enemy()

func check_wave_complete() -> void:
	if enemy_container == null:
		return

	# Check if all enemies are cleared
	if enemy_container.get_child_count() == 0 and enemies_spawned_this_wave >= enemies_per_wave:
		on_wave_complete()
	else:
		# Check again in a moment
		wave_timer.start(0.5)

func _on_wave_timer() -> void:
	if wave_active:
		check_wave_complete()

func on_wave_complete() -> void:
	wave_active = false
	DebugHelper.log_info("Wave %d completed!" % current_wave)
	SignalBus.wave_completed.emit(current_wave)

	# Start next wave after delay
	if manager_active:
		await get_tree().create_timer(wave_delay).timeout
		if manager_active:  # Check again in case game ended
			start_next_wave()

func get_word_for_wave() -> String:
	# Select word pool based on wave difficulty
	var pool: Array[String]

	if current_wave <= 3:
		pool = word_pool_easy
	elif current_wave <= 6:
		# Mix easy and medium
		pool = word_pool_easy + word_pool_medium
	elif current_wave <= 10:
		# Mix medium and hard
		pool = word_pool_medium + word_pool_hard
	else:
		# Mix hard and expert
		pool = word_pool_hard + word_pool_expert

	if pool.size() == 0:
		pool = fallback_words

	return pool[randi() % pool.size()]

func _process(_delta: float) -> void:
	# Continuously check for wave completion when spawning is done
	if wave_active and enemies_spawned_this_wave >= enemies_per_wave:
		if enemy_container and enemy_container.get_child_count() == 0:
			on_wave_complete()
