## translation_manager.gd
## Handles UI translations for multiple languages
## Autoload singleton: Tr
extends Node

# Current language (EN, DE, etc.)
var current_language: String = "EN"

# Translations dictionary: { "KEY": { "EN": "English text", "DE": "German text" } }
var translations: Dictionary = {}

# Fallback language if translation not found
const FALLBACK_LANGUAGE := "EN"

func _ready() -> void:
	load_translations()
	# Get language from settings
	current_language = SaveManager.get_setting("language", "EN")
	DebugHelper.log_info("TranslationManager ready, language: %s" % current_language)

func load_translations() -> void:
	var path = "res://assets/data/translations.csv"
	if not FileAccess.file_exists(path):
		DebugHelper.log_warning("Translations file not found: %s" % path)
		return

	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		DebugHelper.log_error("Failed to open translations file")
		return

	# First line is header with language codes
	var header_line = file.get_line()
	var languages = header_line.split(",")
	# First column is KEY, rest are language codes
	languages = languages.slice(1)  # Remove "KEY" column

	# Clean language codes
	var lang_codes: Array[String] = []
	for lang in languages:
		lang_codes.append(lang.strip_edges().to_upper())

	# Read translations
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line.is_empty():
			continue

		# Parse CSV line (handle quoted strings with commas)
		var values = parse_csv_line(line)
		if values.size() < 2:
			continue

		var key = values[0].strip_edges()
		if key.is_empty():
			continue

		translations[key] = {}
		for i in range(lang_codes.size()):
			if i + 1 < values.size():
				translations[key][lang_codes[i]] = values[i + 1].strip_edges()

	file.close()
	DebugHelper.log_info("Loaded %d translations" % translations.size())

func parse_csv_line(line: String) -> Array:
	var values: Array = []
	var current_value = ""
	var in_quotes = false

	for c in line:
		if c == '"':
			in_quotes = not in_quotes
		elif c == ',' and not in_quotes:
			values.append(current_value)
			current_value = ""
		else:
			current_value += c

	values.append(current_value)
	return values

func set_language(lang: String) -> void:
	current_language = lang.to_upper()
	SaveManager.set_setting("language", current_language)
	DebugHelper.log_info("Language changed to: %s" % current_language)
	SignalBus.emit_signal("language_changed") if SignalBus.has_signal("language_changed") else null

func get_language() -> String:
	return current_language

func t(key: String, default: String = "") -> String:
	"""Get translated text for key. Returns default or key if not found."""
	if not translations.has(key):
		return default if default != "" else key

	var lang_dict = translations[key]

	# Try current language
	if lang_dict.has(current_language):
		return lang_dict[current_language]

	# Try fallback language
	if lang_dict.has(FALLBACK_LANGUAGE):
		return lang_dict[FALLBACK_LANGUAGE]

	# Return key as last resort
	return default if default != "" else key

# Convenience function - same as t()
func translate(key: String, default: String = "") -> String:
	return t(key, default)
