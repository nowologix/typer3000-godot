## td_wave_config.gd
## Wave configuration for Tower Defence mode
## Defines enemy counts, word lengths, speeds per wave and difficulty
class_name TDWaveConfig
extends RefCounted

# Difficulty presets
enum Difficulty { EASY = 1, MEDIUM = 2, HARD = 3 }

# Wave data structure
class WaveData:
	var enemy_count: int = 5
	var min_word_length: int = 3
	var max_word_length: int = 5
	var spawn_interval: float = 2.0
	var speed_multiplier: float = 1.0
	var boss_wave: bool = false

	func _init(count: int, min_len: int, max_len: int, interval: float, speed: float, is_boss: bool = false):
		enemy_count = count
		min_word_length = min_len
		max_word_length = max_len
		spawn_interval = interval
		speed_multiplier = speed
		boss_wave = is_boss

# Generate waves based on difficulty
static func generate_waves(difficulty: int, total_waves: int = 20) -> Array[WaveData]:
	var waves: Array[WaveData] = []

	# Base values per difficulty
	var base_enemies: int
	var base_interval: float
	var base_speed: float
	var word_length_offset: int

	match difficulty:
		Difficulty.EASY:
			base_enemies = 4
			base_interval = 2.5
			base_speed = 0.8
			word_length_offset = 0
		Difficulty.MEDIUM:
			base_enemies = 6
			base_interval = 2.0
			base_speed = 1.0
			word_length_offset = 1
		Difficulty.HARD:
			base_enemies = 8
			base_interval = 1.5
			base_speed = 1.2
			word_length_offset = 2
		_:
			base_enemies = 5
			base_interval = 2.0
			base_speed = 1.0
			word_length_offset = 0

	for wave_num in range(1, total_waves + 1):
		var is_boss = wave_num % 5 == 0  # Every 5th wave is a boss wave

		# Calculate wave parameters
		var enemy_count = base_enemies + int(wave_num * 1.5)
		if is_boss:
			enemy_count = int(enemy_count * 0.5)  # Fewer but harder enemies in boss waves

		# Word length increases over time
		var wave_tier = int((wave_num - 1) / 5)  # 0-3 for 20 waves
		var min_len = 3 + wave_tier + word_length_offset
		var max_len = 5 + wave_tier + word_length_offset
		if is_boss:
			min_len += 2
			max_len += 3

		# Clamp word lengths
		min_len = clampi(min_len, 3, 8)
		max_len = clampi(max_len, 4, 12)

		# Spawn interval decreases over time
		var interval = max(0.6, base_interval - wave_num * 0.05)
		if is_boss:
			interval *= 1.5  # Slower spawns in boss waves

		# Speed increases over time
		var speed = base_speed + wave_num * 0.05
		if is_boss:
			speed *= 0.8  # Slower but tankier in boss waves

		waves.append(WaveData.new(enemy_count, min_len, max_len, interval, speed, is_boss))

	return waves

# Get a summary of wave config (for debugging)
static func get_wave_summary(wave: WaveData) -> String:
	var boss_str = " [BOSS]" if wave.boss_wave else ""
	return "Enemies: %d, Words: %d-%d, Interval: %.1fs, Speed: %.1fx%s" % [
		wave.enemy_count,
		wave.min_word_length,
		wave.max_word_length,
		wave.spawn_interval,
		wave.speed_multiplier,
		boss_str
	]

# Predefined wave sets for specific maps (optional override)
static func get_tokyo_waves() -> Array[WaveData]:
	return generate_waves(Difficulty.EASY, 15)

static func get_berlin_waves() -> Array[WaveData]:
	return generate_waves(Difficulty.MEDIUM, 20)

static func get_newyork_waves() -> Array[WaveData]:
	return generate_waves(Difficulty.HARD, 25)
