extends Node
## MusicManager - Handles playlist management for SURVIVAL and ZEN modes
## Supports importing custom MP3 files from user's filesystem

# Default playlists
const DEFAULT_SURVIVAL_PLAYLIST := [
	"res://assets/audio/music/gameplay_track_01.mp3",
	"res://assets/audio/music/game-music_01.mp3"
]
const DEFAULT_ZEN_PLAYLIST := [
	"res://assets/audio/music/zen/zen_ambient_health_pad.mp3",
	"res://assets/audio/music/zen/zen_cosmic_melodies.mp3",
	"res://assets/audio/music/zen/zen_meditate.mp3",
	"res://assets/audio/music/zen/zen_ambient_01.mp3"
]

const PLAYLISTS_FILE := "user://playlists.json"
const CUSTOM_MUSIC_DIR := "user://custom_music/"

# Validation constants
const MAX_FILE_SIZE_MB := 50  # Maximum file size in MB
const ALLOWED_EXTENSIONS := ["mp3"]
const INVALID_FILENAME_CHARS := ['<', '>', ':', '"', '/', '\\', '|', '?', '*']

var playlists := {
	"survival": [],
	"zen": []
}

var current_playlist: String = ""
var current_track_index: int = 0
var shuffle_enabled: bool = false

# Audio player for preview
var preview_player: AudioStreamPlayer
var current_preview_path: String = ""

# Cache for custom MP3 streams
var custom_stream_cache: Dictionary = {}


func _ready() -> void:
	preview_player = AudioStreamPlayer.new()
	preview_player.bus = "Music"
	add_child(preview_player)

	_ensure_custom_music_dirs()
	load_playlists()


func _ensure_custom_music_dirs() -> void:
	var dir = DirAccess.open("user://")
	if dir:
		if not dir.dir_exists("custom_music"):
			dir.make_dir("custom_music")
		if not dir.dir_exists("custom_music/survival"):
			dir.make_dir("custom_music/survival")
		if not dir.dir_exists("custom_music/zen"):
			dir.make_dir("custom_music/zen")


func load_playlists() -> void:
	if FileAccess.file_exists(PLAYLISTS_FILE):
		var file = FileAccess.open(PLAYLISTS_FILE, FileAccess.READ)
		if file:
			var json_str = file.get_as_text()
			file.close()
			var json = JSON.new()
			var error = json.parse(json_str)
			if error == OK:
				var data = json.get_data()
				if data is Dictionary:
					if data.has("survival"):
						playlists["survival"] = data["survival"]
					if data.has("zen"):
						playlists["zen"] = data["zen"]
					return

	# Load defaults if no file exists or parsing failed
	playlists["survival"] = DEFAULT_SURVIVAL_PLAYLIST.duplicate()
	playlists["zen"] = DEFAULT_ZEN_PLAYLIST.duplicate()
	save_playlists()


func save_playlists() -> void:
	var file = FileAccess.open(PLAYLISTS_FILE, FileAccess.WRITE)
	if file:
		var json_str = JSON.stringify(playlists, "\t")
		file.store_string(json_str)
		file.close()


func get_playlist(mode: String) -> Array:
	if playlists.has(mode):
		return playlists[mode]
	return []


func get_track_count(mode: String) -> int:
	return get_playlist(mode).size()


func add_track_to_playlist(mode: String, path: String) -> void:
	if playlists.has(mode):
		playlists[mode].append(path)
		save_playlists()


func remove_track_from_playlist(mode: String, index: int) -> void:
	if playlists.has(mode) and index >= 0 and index < playlists[mode].size():
		playlists[mode].remove_at(index)
		save_playlists()


func move_track_up(mode: String, index: int) -> bool:
	if playlists.has(mode) and index > 0 and index < playlists[mode].size():
		var track = playlists[mode][index]
		playlists[mode].remove_at(index)
		playlists[mode].insert(index - 1, track)
		save_playlists()
		return true
	return false


func move_track_down(mode: String, index: int) -> bool:
	if playlists.has(mode) and index >= 0 and index < playlists[mode].size() - 1:
		var track = playlists[mode][index]
		playlists[mode].remove_at(index)
		playlists[mode].insert(index + 1, track)
		save_playlists()
		return true
	return false


func get_track_name(path: String) -> String:
	return path.get_file().get_basename()


func is_custom_track(path: String) -> bool:
	return path.begins_with("user://")


func track_exists(path: String) -> bool:
	## Check if track file exists
	if path.begins_with("res://"):
		return ResourceLoader.exists(path)
	elif path.begins_with("user://"):
		return FileAccess.file_exists(path)
	return false


func get_track_status(path: String) -> String:
	## Returns status string for track: "" if OK, error message otherwise
	if not track_exists(path):
		return "FILE MISSING"
	return ""


func preview_track(path: String) -> bool:
	## Preview a track. Returns true if successful.
	stop_preview()
	current_preview_path = path

	var stream: AudioStream = null

	if path.begins_with("res://"):
		# Resource path - use normal loading
		stream = load(path) as AudioStream
	elif path.begins_with("user://"):
		# Custom file - load as AudioStreamMP3
		stream = _load_custom_mp3(path)

	if stream:
		preview_player.stream = stream
		preview_player.play()
		return true

	return false


func _load_custom_mp3(path: String) -> AudioStreamMP3:
	## Load MP3 from user:// directory
	# Check cache first
	if custom_stream_cache.has(path):
		return custom_stream_cache[path]

	if not FileAccess.file_exists(path):
		DebugHelper.log_warning("MusicManager: Custom MP3 not found: %s" % path)
		return null

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		DebugHelper.log_warning("MusicManager: Could not open: %s" % path)
		return null

	var mp3_data = file.get_buffer(file.get_length())
	file.close()

	var stream = AudioStreamMP3.new()
	stream.data = mp3_data

	# Cache the stream
	custom_stream_cache[path] = stream

	return stream


func stop_preview() -> void:
	preview_player.stop()
	current_preview_path = ""


func is_previewing() -> bool:
	return preview_player.playing


func get_current_preview_path() -> String:
	return current_preview_path


func reset_to_defaults(mode: String) -> void:
	match mode:
		"survival":
			playlists["survival"] = DEFAULT_SURVIVAL_PLAYLIST.duplicate()
		"zen":
			playlists["zen"] = DEFAULT_ZEN_PLAYLIST.duplicate()
	save_playlists()


func get_available_tracks() -> Array:
	## Returns list of all available music tracks in res://assets/audio/music/
	var tracks := []
	var dir = DirAccess.open("res://assets/audio/music/")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".mp3"):
				tracks.append("res://assets/audio/music/" + file_name)
			file_name = dir.get_next()
		dir.list_dir_end()

	# Also check zen subfolder
	dir = DirAccess.open("res://assets/audio/music/zen/")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".mp3"):
				tracks.append("res://assets/audio/music/zen/" + file_name)
			file_name = dir.get_next()
		dir.list_dir_end()

	return tracks


# ============ MP3 Import System ============

class ImportResult:
	var success: bool = false
	var error_message: String = ""
	var imported_path: String = ""


func validate_mp3_file(source_path: String) -> ImportResult:
	## Validate an MP3 file before importing
	var result = ImportResult.new()

	# Check file exists
	if not FileAccess.file_exists(source_path):
		result.error_message = "File not found"
		return result

	# Check extension
	var extension = source_path.get_extension().to_lower()
	if extension not in ALLOWED_EXTENSIONS:
		result.error_message = "Invalid file type. Only MP3 files are allowed."
		return result

	# Check filename for invalid characters
	var file_name = source_path.get_file()
	for invalid_char in INVALID_FILENAME_CHARS:
		if invalid_char in file_name:
			result.error_message = "Filename contains invalid character: %s" % invalid_char
			return result

	# Check file size
	var file = FileAccess.open(source_path, FileAccess.READ)
	if not file:
		result.error_message = "Cannot open file for reading"
		return result

	var file_size = file.get_length()
	file.close()

	var max_size = MAX_FILE_SIZE_MB * 1024 * 1024
	if file_size > max_size:
		result.error_message = "File too large. Maximum size is %d MB." % MAX_FILE_SIZE_MB
		return result

	if file_size < 1000:
		result.error_message = "File too small. May be corrupted."
		return result

	# Try to verify it's actually an MP3 by checking header
	file = FileAccess.open(source_path, FileAccess.READ)
	if file:
		var header = file.get_buffer(3)
		file.close()

		# Check for MP3 frame sync or ID3 tag
		var is_mp3 = false
		if header.size() >= 3:
			# ID3v2 tag
			if header[0] == 0x49 and header[1] == 0x44 and header[2] == 0x33:
				is_mp3 = true
			# MP3 frame sync (0xFF followed by 0xFB, 0xFA, or 0xF3)
			elif header[0] == 0xFF and (header[1] & 0xE0) == 0xE0:
				is_mp3 = true

		if not is_mp3:
			result.error_message = "File does not appear to be a valid MP3"
			return result

	result.success = true
	return result


func import_mp3(source_path: String, mode: String) -> ImportResult:
	## Import an MP3 file to the custom music directory
	var result = validate_mp3_file(source_path)
	if not result.success:
		return result

	# Sanitize filename
	var original_name = source_path.get_file()
	var sanitized_name = _sanitize_filename(original_name)

	# Generate unique filename if exists
	var dest_path = CUSTOM_MUSIC_DIR + mode + "/" + sanitized_name
	var counter = 1
	while FileAccess.file_exists(dest_path):
		var base = sanitized_name.get_basename()
		var ext = sanitized_name.get_extension()
		dest_path = CUSTOM_MUSIC_DIR + mode + "/" + base + "_" + str(counter) + "." + ext
		counter += 1

	# Copy file
	var source = FileAccess.open(source_path, FileAccess.READ)
	if not source:
		result.success = false
		result.error_message = "Cannot read source file"
		return result

	var content = source.get_buffer(source.get_length())
	source.close()

	var dest = FileAccess.open(dest_path, FileAccess.WRITE)
	if not dest:
		result.success = false
		result.error_message = "Cannot write to destination"
		return result

	dest.store_buffer(content)
	dest.close()

	# Verify the copy
	if not FileAccess.file_exists(dest_path):
		result.success = false
		result.error_message = "File copy verification failed"
		return result

	# Add to playlist
	add_track_to_playlist(mode, dest_path)

	result.success = true
	result.imported_path = dest_path
	DebugHelper.log_info("MusicManager: Imported MP3: %s -> %s" % [source_path, dest_path])

	return result


func _sanitize_filename(filename: String) -> String:
	## Remove or replace invalid characters from filename
	var result = filename
	for invalid_char in INVALID_FILENAME_CHARS:
		result = result.replace(invalid_char, "_")
	# Remove multiple underscores
	while "__" in result:
		result = result.replace("__", "_")
	# Trim underscores from start/end
	result = result.strip_edges()
	if result.begins_with("_"):
		result = result.substr(1)
	if result.ends_with("_"):
		result = result.substr(0, result.length() - 1)
	return result


func remove_custom_track(path: String, mode: String) -> bool:
	## Remove a custom track file and from playlist
	if not is_custom_track(path):
		return false

	# Find and remove from playlist
	var playlist = playlists.get(mode, [])
	var index = playlist.find(path)
	if index >= 0:
		playlist.remove_at(index)
		save_playlists()

	# Remove from cache
	if custom_stream_cache.has(path):
		custom_stream_cache.erase(path)

	# Delete file
	if FileAccess.file_exists(path):
		var dir = DirAccess.open(path.get_base_dir())
		if dir:
			dir.remove(path.get_file())
			return true

	return false


func clean_missing_tracks() -> int:
	## Remove all missing tracks from playlists. Returns count of removed tracks.
	var removed_count = 0

	for mode in ["survival", "zen"]:
		var playlist = playlists[mode]
		var i = playlist.size() - 1
		while i >= 0:
			if not track_exists(playlist[i]):
				DebugHelper.log_info("MusicManager: Removing missing track: %s" % playlist[i])
				playlist.remove_at(i)
				removed_count += 1
			i -= 1

	if removed_count > 0:
		save_playlists()

	return removed_count
