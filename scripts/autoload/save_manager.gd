## save_manager.gd
## Handles save/load of game data including high scores and settings
## Autoload singleton: SaveManager
extends Node

const SAVE_PATH: String = "user://typer3000_save.json"

# Supported resolutions
const RESOLUTIONS := [
	Vector2i(1280, 720),   # 720p (base)
	Vector2i(1366, 768),   # Common laptop
	Vector2i(1600, 900),   # 900p
	Vector2i(1920, 1080),  # 1080p
	Vector2i(2560, 1080),  # Ultrawide 1080p
	Vector2i(2560, 1440),  # 1440p
	Vector2i(3440, 1440),  # Ultrawide 1440p
	Vector2i(3840, 1600),  # Ultrawide 1600p
	Vector2i(3840, 2160),  # 4K
]

# Default settings
const DEFAULT_SETTINGS := {
	# Display
	"resolution_index": 0,
	"fullscreen": false,
	"vsync": true,
	
	# Audio
	"master_volume": 1.0,
	"sfx_volume": 1.0,
	"music_volume": 0.7,
	
	# Language
	"language": "EN",
	
	# Visual
	"scanlines": true,
	"screen_shake": true,
	
	# Accessibility
	"high_contrast": false,
	"large_text": false
}

# Save data structure
var save_data: Dictionary = {
	"high_score": 0,
	"max_wave": 0,
	"best_combo": 0,
	"total_words_typed": 0,
	"total_play_time": 0.0,
	"settings": DEFAULT_SETTINGS.duplicate(true)
}

signal settings_changed

func _ready() -> void:
	load_data()
	apply_settings()
	DebugHelper.log_info("SaveManager initialized")

func save_data_to_file() -> void:
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		DebugHelper.log_error("SaveManager: Failed to open save file for writing")
		return

	var json_string = JSON.stringify(save_data, "\t")
	file.store_string(json_string)
	file.close()
	DebugHelper.log_info("SaveManager: Data saved to %s" % SAVE_PATH)

func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		DebugHelper.log_info("SaveManager: No save file found, using defaults")
		return

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		DebugHelper.log_error("SaveManager: Failed to open save file for reading")
		return

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		DebugHelper.log_error("SaveManager: Failed to parse save file: %s" % json.get_error_message())
		return

	var loaded_data = json.get_data()
	if loaded_data is Dictionary:
		# Merge loaded data with defaults (preserves new fields)
		for key in loaded_data:
			if key == "settings" and loaded_data[key] is Dictionary:
				# Merge settings with defaults
				for setting_key in DEFAULT_SETTINGS:
					if loaded_data[key].has(setting_key):
						save_data["settings"][setting_key] = loaded_data[key][setting_key]
			else:
				save_data[key] = loaded_data[key]
		DebugHelper.log_info("SaveManager: Data loaded successfully")

func apply_settings() -> void:
	var settings = get_settings()
	
	# Apply resolution
	var res_idx = settings.get("resolution_index", 0)
	if res_idx >= 0 and res_idx < RESOLUTIONS.size():
		var res = RESOLUTIONS[res_idx]
		DisplayServer.window_set_size(res)
	
	# Apply fullscreen
	if settings.get("fullscreen", false):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	
	# Apply VSync
	if settings.get("vsync", true):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	
	# Apply audio volumes
	SoundManager.set_master_volume(settings.get("master_volume", 1.0))
	SoundManager.set_music_volume(settings.get("music_volume", 0.7))
	SoundManager.set_sfx_volume(settings.get("sfx_volume", 1.0))
	
	settings_changed.emit()
	DebugHelper.log_info("SaveManager: Settings applied")

# Score functions
func get_high_score() -> int:
	return save_data.get("high_score", 0)

func get_max_wave() -> int:
	return save_data.get("max_wave", 0)

func get_best_combo() -> int:
	return save_data.get("best_combo", 0)

func update_high_score(score: int) -> bool:
	if score > save_data["high_score"]:
		save_data["high_score"] = score
		save_data_to_file()
		DebugHelper.log_info("SaveManager: New high score: %d" % score)
		return true
	return false

func update_max_wave(wave: int) -> bool:
	if wave > save_data["max_wave"]:
		save_data["max_wave"] = wave
		save_data_to_file()
		DebugHelper.log_info("SaveManager: New max wave: %d" % wave)
		return true
	return false

func update_best_combo(combo: int) -> bool:
	if combo > save_data["best_combo"]:
		save_data["best_combo"] = combo
		save_data_to_file()
		DebugHelper.log_info("SaveManager: New best combo: %d" % combo)
		return true
	return false

func update_game_stats(score: int, wave: int, combo: int, words_typed: int) -> Dictionary:
	var records = {
		"high_score": update_high_score(score),
		"max_wave": update_max_wave(wave),
		"best_combo": update_best_combo(combo)
	}

	save_data["total_words_typed"] = save_data.get("total_words_typed", 0) + words_typed
	save_data_to_file()

	return records

# Settings functions
func get_settings() -> Dictionary:
	return save_data.get("settings", DEFAULT_SETTINGS.duplicate(true))

func get_setting(key: String, default = null):
	var settings = get_settings()
	if default != null:
		return settings.get(key, default)
	return settings.get(key, DEFAULT_SETTINGS.get(key))

func set_setting(key: String, value) -> void:
	save_data["settings"][key] = value
	save_data_to_file()
	apply_settings()

func save_settings(settings: Dictionary) -> void:
	save_data["settings"] = settings
	save_data_to_file()
	apply_settings()

func get_resolution() -> Vector2i:
	var idx = get_setting("resolution_index", 0)
	if idx >= 0 and idx < RESOLUTIONS.size():
		return RESOLUTIONS[idx]
	return RESOLUTIONS[0]

func get_resolution_string(idx: int) -> String:
	if idx >= 0 and idx < RESOLUTIONS.size():
		var res = RESOLUTIONS[idx]
		return "%dx%d" % [res.x, res.y]
	return "1280x720"

func reset_all_data() -> void:
	save_data = {
		"high_score": 0,
		"max_wave": 0,
		"best_combo": 0,
		"total_words_typed": 0,
		"total_play_time": 0.0,
		"settings": DEFAULT_SETTINGS.duplicate(true)
	}
	save_data_to_file()
	apply_settings()
	DebugHelper.log_info("SaveManager: All data reset")
