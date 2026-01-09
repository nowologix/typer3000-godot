## word_set_loader.gd
## Manages word sets for different languages, organized by word length
## Loads words from external JSON files in assets/words/{lang}/
## Autoload singleton: WordSetLoader
extends Node

enum Language { EN, DE }
enum Difficulty { COMMON, MEDIUM, ADVANCED }

# Available languages in order (for cycling) - add new languages here
const LANGUAGES := ["EN", "DE"]
const DIFFICULTIES := ["common", "medium", "advanced"]

# Path to word files
const WORDS_BASE_PATH := "res://assets/words/"

# Reserved words that should never be used as enemy words (powerups, commands, etc.)
const RESERVED_WORDS := [
	"FREEZE", "SHIELD", "DOUBLE", "HEAL", "NUKE", "SLOW",  # Powerup words EN
	"FRIEREN", "SCHILD", "DOPPEL", "HERZ", "ATOM", "ZEIT",  # Powerup words DE
	"BUILD", "GUN", "TESLA", "WALL",  # Build commands
	"RESUME", "QUIT"  # Pause menu commands
]

var current_language: Language = Language.EN
var current_difficulty: Difficulty = Difficulty.COMMON
var used_words: Dictionary = {}  # Track used words per length group

# Loaded words organized by language -> difficulty -> length
var loaded_words: Dictionary = {}
var words_loaded: bool = false

func _ready() -> void:
	_load_all_word_files()
	DebugHelper.log_info("WordSetLoader initialized with %d words" % get_total_word_count())

func _load_all_word_files() -> void:
	loaded_words.clear()

	for lang in [Language.EN, Language.DE]:
		loaded_words[lang] = {}
		var lang_str := "en" if lang == Language.EN else "de"

		for diff in DIFFICULTIES:
			var file_path: String = WORDS_BASE_PATH + lang_str + "/" + diff + ".json"
			var words_data := _load_word_file(file_path)

			if not words_data.is_empty():
				loaded_words[lang][diff] = words_data
				DebugHelper.log_info("Loaded %s/%s.json with %d length groups" % [lang_str, diff, words_data.size()])
			else:
				loaded_words[lang][diff] = {}
				DebugHelper.log_warning("Failed to load %s" % file_path)

	words_loaded = true

func _load_word_file(file_path: String) -> Dictionary:
	var result: Dictionary = {}

	if not FileAccess.file_exists(file_path):
		DebugHelper.log_warning("Word file not found: %s" % file_path)
		return result

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		DebugHelper.log_warning("Could not open word file: %s" % file_path)
		return result

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(json_text)

	if parse_result != OK:
		DebugHelper.log_warning("JSON parse error in %s: %s" % [file_path, json.get_error_message()])
		return result

	var data: Dictionary = json.get_data()
	if data.has("words"):
		# Convert string keys to integers for length lookup
		var words_dict: Dictionary = data["words"]
		for length_str in words_dict.keys():
			var length := int(length_str)
			result[length] = words_dict[length_str]

	return result

func set_language(lang: Language) -> void:
	if current_language != lang:
		current_language = lang
		reset_used_words()
		DebugHelper.log_info("Language set to: %s" % ("DE" if lang == Language.DE else "EN"))

func set_language_string(lang_str: String) -> void:
	match lang_str.to_upper():
		"DE", "DEUTSCH", "GERMAN":
			set_language(Language.DE)
		_:
			set_language(Language.EN)

func get_language() -> Language:
	return current_language

func get_language_string() -> String:
	return "DE" if current_language == Language.DE else "EN"

func get_available_languages() -> Array:
	return LANGUAGES

func cycle_language() -> String:
	var current_str: String = get_language_string()
	var current_idx: int = LANGUAGES.find(current_str)
	var next_idx: int = (current_idx + 1) % LANGUAGES.size()
	var next_lang: String = LANGUAGES[next_idx]
	set_language_string(next_lang)
	return next_lang

func set_difficulty(diff: Difficulty) -> void:
	if current_difficulty != diff:
		current_difficulty = diff
		reset_used_words()
		DebugHelper.log_info("Difficulty set to: %s" % DIFFICULTIES[diff])

func set_difficulty_string(diff_str: String) -> void:
	match diff_str.to_lower():
		"medium":
			set_difficulty(Difficulty.MEDIUM)
		"advanced", "hard":
			set_difficulty(Difficulty.ADVANCED)
		_:
			set_difficulty(Difficulty.COMMON)

func get_difficulty() -> Difficulty:
	return current_difficulty

func get_difficulty_string() -> String:
	return DIFFICULTIES[current_difficulty]

func cycle_difficulty() -> String:
	var next_diff := (current_difficulty + 1) % Difficulty.size()
	set_difficulty(next_diff as Difficulty)
	return DIFFICULTIES[next_diff]

func reset_used_words() -> void:
	used_words.clear()

func _get_words_dict_for_current() -> Dictionary:
	# Returns combined words from all difficulties up to current difficulty
	var result: Dictionary = {}

	if not loaded_words.has(current_language):
		return result

	var lang_words: Dictionary = loaded_words[current_language]

	# Include words from common always, and add medium/advanced based on difficulty
	var diffs_to_include: Array = ["common"]
	if current_difficulty >= Difficulty.MEDIUM:
		diffs_to_include.append("medium")
	if current_difficulty >= Difficulty.ADVANCED:
		diffs_to_include.append("advanced")

	for diff in diffs_to_include:
		if lang_words.has(diff):
			var diff_words: Dictionary = lang_words[diff]
			for length in diff_words.keys():
				if not result.has(length):
					result[length] = []
				result[length].append_array(diff_words[length])

	return result

func get_words_for_length(length: int) -> Array:
	var lang_words := _get_words_dict_for_current()
	if lang_words.has(length):
		return lang_words[length]
	return []

func get_words_in_range(min_len: int, max_len: int) -> Array:
	var result: Array = []
	var lang_words := _get_words_dict_for_current()
	for length in lang_words.keys():
		if length >= min_len and length <= max_len:
			result.append_array(lang_words[length])
	return result

func get_random_word(options: Dictionary = {}) -> String:
	var min_length: int = options.get("min_length", 2)
	var max_length: int = options.get("max_length", 20)
	var avoid_letters: Array = options.get("avoid_letters", [])

	# Get all words in the length range
	var available_words: Array = []
	var lang_words := _get_words_dict_for_current()

	# Track used words key
	var range_key := "%d_%d_%d_%d" % [current_language, current_difficulty, min_length, max_length]
	if not used_words.has(range_key):
		used_words[range_key] = []

	# Collect words from appropriate length groups
	for length in lang_words.keys():
		if length >= min_length and length <= max_length:
			for word in lang_words[length]:
				# Skip reserved words (powerups, commands)
				if word in RESERVED_WORDS:
					continue

				# Skip used words
				if word in used_words[range_key]:
					continue

				# Avoid certain starting letters
				var skip := false
				for letter in avoid_letters:
					if word.begins_with(letter):
						skip = true
						break
				if skip:
					continue

				available_words.append(word)

	# Reset if all words used
	if available_words.is_empty():
		used_words[range_key] = []
		for length in lang_words.keys():
			if length >= min_length and length <= max_length:
				for word in lang_words[length]:
					# Skip reserved words
					if word in RESERVED_WORDS:
						continue
					var skip := false
					for letter in avoid_letters:
						if word.begins_with(letter):
							skip = true
							break
					if not skip:
						available_words.append(word)

	if available_words.is_empty():
		return "ERROR"

	# Pick random word
	var word: String = available_words[randi() % available_words.size()]
	used_words[range_key].append(word)
	return word

func get_word_for_wave(wave_number: int, avoid_letters: Array = []) -> String:
	# Calculate length range based on wave (scales to wave 50)
	# Wave 1-5:   2-3 letters (very easy)
	# Wave 6-10:  3-4 letters (easy)
	# Wave 11-15: 3-5 letters (easy-medium)
	# Wave 16-20: 4-5 letters (medium)
	# Wave 21-25: 4-6 letters (medium)
	# Wave 26-30: 5-7 letters (medium-hard)
	# Wave 31-35: 5-8 letters (hard)
	# Wave 36-40: 6-9 letters (hard)
	# Wave 41-45: 7-10 letters (very hard)
	# Wave 46-50: 8-11 letters (extreme)
	# Wave 50+:   9-12 letters (maximum)

	var min_len: int
	var max_len: int

	if wave_number <= 5:
		min_len = 2
		max_len = 3
	elif wave_number <= 10:
		min_len = 3
		max_len = 4
	elif wave_number <= 15:
		min_len = 3
		max_len = 5
	elif wave_number <= 20:
		min_len = 4
		max_len = 5
	elif wave_number <= 25:
		min_len = 4
		max_len = 6
	elif wave_number <= 30:
		min_len = 5
		max_len = 7
	elif wave_number <= 35:
		min_len = 5
		max_len = 8
	elif wave_number <= 40:
		min_len = 6
		max_len = 9
	elif wave_number <= 45:
		min_len = 7
		max_len = 10
	elif wave_number <= 50:
		min_len = 8
		max_len = 11
	else:
		# Wave 50+: Maximum difficulty
		min_len = 9
		max_len = 12

	return get_random_word({
		"min_length": min_len,
		"max_length": max_len,
		"avoid_letters": avoid_letters
	})

func generate_wave_words(wave_number: int, enemy_count: int) -> Array:
	var words: Array = []
	var used_first_letters: Array = []

	for i in range(enemy_count):
		var word := get_word_for_wave(wave_number, used_first_letters)
		words.append(word)

		# Track first letter to avoid conflicts
		if word.length() > 0:
			used_first_letters.append(word[0])

	return words

func get_word_complexity(word: String) -> int:
	var complexity := 1

	# Length adds complexity
	if word.length() >= 4:
		complexity += 1
	if word.length() >= 6:
		complexity += 1
	if word.length() >= 8:
		complexity += 1
	if word.length() >= 10:
		complexity += 1

	return mini(complexity, 5)

func get_total_word_count() -> int:
	var count := 0
	var lang_words := _get_words_dict_for_current()
	for length in lang_words.keys():
		count += lang_words[length].size()
	return count

func get_word_count_by_difficulty(diff: String = "") -> Dictionary:
	var result: Dictionary = {}

	if not loaded_words.has(current_language):
		return result

	var lang_words: Dictionary = loaded_words[current_language]

	for diff_name in lang_words.keys():
		if diff != "" and diff_name != diff:
			continue
		var total := 0
		for length in lang_words[diff_name].keys():
			total += lang_words[diff_name][length].size()
		result[diff_name] = total

	return result

func reload_word_files() -> void:
	_load_all_word_files()
	reset_used_words()
