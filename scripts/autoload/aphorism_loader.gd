## aphorism_loader.gd
## Loads and manages aphorisms/quotes for boss battles
## Aphorisms are categorized by word count for different boss difficulties
## Autoload singleton: AphorismLoader
extends Node

enum Language { EN, DE }

# Aphorism structure: {text, author, word_count}
var aphorisms_en: Array = []
var aphorisms_de: Array = []

# Categorized by difficulty (word count ranges)
var aphorisms_by_difficulty: Dictionary = {
	Language.EN: {
		"mini": [],    # 2-5 words
		"normal": [],  # 6-9 words
		"hard": [],    # 10-13 words
		"epic": []     # 14+ words
	},
	Language.DE: {
		"mini": [],
		"normal": [],
		"hard": [],
		"epic": []
	}
}

# Track used aphorisms to avoid repetition
var used_aphorisms: Dictionary = {
	Language.EN: [],
	Language.DE: []
}

var current_language: Language = Language.EN

func _ready() -> void:
	_load_aphorisms()
	DebugHelper.log_info("AphorismLoader initialized - EN: %d, DE: %d" % [aphorisms_en.size(), aphorisms_de.size()])

func _load_aphorisms() -> void:
	_load_csv("res://assets/data/word_sets/aphorisms_en.csv", Language.EN)
	_load_csv("res://assets/data/word_sets/aphorisms_de.csv", Language.DE)
	_categorize_aphorisms()

func _load_csv(path: String, lang: Language) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		DebugHelper.log_warning("AphorismLoader: Could not open %s" % path)
		return

	var is_first_line := true
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue

		# Skip header
		if is_first_line:
			is_first_line = false
			continue

		var parsed := _parse_csv_line(line)
		if parsed.is_empty():
			continue

		var aphorism := {
			"text": parsed[0].to_upper().strip_edges(),
			"author": parsed[1].strip_edges() if parsed.size() > 1 else "",
			"word_count": int(parsed[2]) if parsed.size() > 2 else _count_words(parsed[0])
		}

		# Skip empty or too short aphorisms
		if aphorism.text.length() < 5:
			continue

		if lang == Language.EN:
			aphorisms_en.append(aphorism)
		else:
			aphorisms_de.append(aphorism)

	file.close()

func _parse_csv_line(line: String) -> Array:
	# Handle quoted fields with commas inside
	var result: Array = []
	var current_field := ""
	var in_quotes := false

	for i in range(line.length()):
		var c := line[i]

		if c == '"':
			in_quotes = not in_quotes
		elif c == ',' and not in_quotes:
			result.append(current_field)
			current_field = ""
		else:
			current_field += c

	result.append(current_field)
	return result

func _count_words(text: String) -> int:
	var words := text.strip_edges().split(" ", false)
	return words.size()

func _categorize_aphorisms() -> void:
	# Categorize English
	for aph in aphorisms_en:
		var wc: int = aph.word_count
		if wc <= 5:
			aphorisms_by_difficulty[Language.EN]["mini"].append(aph)
		elif wc <= 9:
			aphorisms_by_difficulty[Language.EN]["normal"].append(aph)
		elif wc <= 13:
			aphorisms_by_difficulty[Language.EN]["hard"].append(aph)
		else:
			aphorisms_by_difficulty[Language.EN]["epic"].append(aph)

	# Categorize German
	for aph in aphorisms_de:
		var wc: int = aph.word_count
		if wc <= 5:
			aphorisms_by_difficulty[Language.DE]["mini"].append(aph)
		elif wc <= 9:
			aphorisms_by_difficulty[Language.DE]["normal"].append(aph)
		elif wc <= 13:
			aphorisms_by_difficulty[Language.DE]["hard"].append(aph)
		else:
			aphorisms_by_difficulty[Language.DE]["epic"].append(aph)

	DebugHelper.log_info("Aphorisms categorized - EN: mini=%d, normal=%d, hard=%d, epic=%d" % [
		aphorisms_by_difficulty[Language.EN]["mini"].size(),
		aphorisms_by_difficulty[Language.EN]["normal"].size(),
		aphorisms_by_difficulty[Language.EN]["hard"].size(),
		aphorisms_by_difficulty[Language.EN]["epic"].size()
	])
	DebugHelper.log_info("Aphorisms categorized - DE: mini=%d, normal=%d, hard=%d, epic=%d" % [
		aphorisms_by_difficulty[Language.DE]["mini"].size(),
		aphorisms_by_difficulty[Language.DE]["normal"].size(),
		aphorisms_by_difficulty[Language.DE]["hard"].size(),
		aphorisms_by_difficulty[Language.DE]["epic"].size()
	])

func set_language(lang: Language) -> void:
	current_language = lang

func set_language_string(lang_str: String) -> void:
	match lang_str.to_upper():
		"DE", "DEUTSCH", "GERMAN":
			set_language(Language.DE)
		_:
			set_language(Language.EN)

func get_language() -> Language:
	return current_language

func reset_used() -> void:
	used_aphorisms[Language.EN].clear()
	used_aphorisms[Language.DE].clear()

# Get a random aphorism by difficulty
# difficulty: "mini", "normal", "hard", "epic", or "any"
func get_aphorism(difficulty: String = "any") -> Dictionary:
	var pool: Array = []

	if difficulty == "any":
		pool = aphorisms_en if current_language == Language.EN else aphorisms_de
	else:
		pool = aphorisms_by_difficulty[current_language].get(difficulty, [])

	if pool.is_empty():
		return {"text": "NO APHORISM FOUND", "author": "", "word_count": 3}

	# Filter out used aphorisms
	var available: Array = []
	for aph in pool:
		if aph.text not in used_aphorisms[current_language]:
			available.append(aph)

	# Reset if all used
	if available.is_empty():
		used_aphorisms[current_language].clear()
		available = pool

	# Pick random
	var selected: Dictionary = available[randi() % available.size()]
	used_aphorisms[current_language].append(selected.text)

	return selected

# Get aphorism for a specific boss wave/level
# boss_level: 1-4 maps to mini/normal/hard/epic
func get_boss_aphorism(boss_level: int) -> Dictionary:
	var difficulty: String
	match boss_level:
		1:
			difficulty = "mini"
		2:
			difficulty = "normal"
		3:
			difficulty = "hard"
		_:
			difficulty = "epic"

	return get_aphorism(difficulty)

# Get aphorism with specific word count range
func get_aphorism_by_word_count(min_words: int, max_words: int) -> Dictionary:
	var pool: Array = aphorisms_en if current_language == Language.EN else aphorisms_de

	var matching: Array = []
	for aph in pool:
		if aph.word_count >= min_words and aph.word_count <= max_words:
			if aph.text not in used_aphorisms[current_language]:
				matching.append(aph)

	if matching.is_empty():
		# Try without used filter
		for aph in pool:
			if aph.word_count >= min_words and aph.word_count <= max_words:
				matching.append(aph)

	if matching.is_empty():
		return {"text": "BOSS BATTLE", "author": "", "word_count": 2}

	var selected: Dictionary = matching[randi() % matching.size()]
	used_aphorisms[current_language].append(selected.text)

	return selected

# Get all aphorisms for current language
func get_all_aphorisms() -> Array:
	return aphorisms_en if current_language == Language.EN else aphorisms_de

# Get count by difficulty
func get_count(difficulty: String = "any") -> int:
	if difficulty == "any":
		return aphorisms_en.size() if current_language == Language.EN else aphorisms_de.size()
	return aphorisms_by_difficulty[current_language].get(difficulty, []).size()
