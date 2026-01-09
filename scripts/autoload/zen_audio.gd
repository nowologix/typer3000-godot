## zen_audio.gd
## Audio management for ZEN mode
## Handles piano key samples with polyphonic playback and ambient music
extends Node

# Audio configuration
const KEY_SAMPLES_PATH := "res://assets/audio/zen/keys/"
const AUDIO_POOL_SIZE := 12  # Number of simultaneous key sounds
const FADE_DURATION := 1.5  # Fade in/out duration for ambient

# Audio players
var ambient_player: AudioStreamPlayer
var key_players: Array[AudioStreamPlayer] = []
var current_player_index: int = 0

# Playlist tracking
var current_track_index: int = 0

# Sample cache
var key_samples: Dictionary = {}  # char -> AudioStream
var default_sample: AudioStream = null

# Character to filename mapping
const CHAR_TO_FILE := {
	# Letters (lowercase maps to file)
	"a": "a", "b": "b", "c": "c", "d": "d", "e": "e", "f": "f", "g": "g",
	"h": "h", "i": "i", "j": "j", "k": "k", "l": "l", "m": "m", "n": "n",
	"o": "o", "p": "p", "q": "q", "r": "r", "s": "s", "t": "t", "u": "u",
	"v": "v", "w": "w", "x": "x", "y": "y", "z": "z",

	# German umlauts
	"ä": "ae", "ö": "oe", "ü": "ue", "ß": "ss",

	# Numbers
	"0": "0", "1": "1", "2": "2", "3": "3", "4": "4",
	"5": "5", "6": "6", "7": "7", "8": "8", "9": "9",

	# Punctuation
	" ": "space",
	"\n": "enter",
	".": "period",
	",": "comma",
	":": "colon",
	";": "semicolon",
	"!": "exclamation",
	"?": "question",
	"-": "dash",
	"–": "dash",
	"—": "dash",
	"'": "apostrophe",
	"\"": "quote",
	""": "quote",
	""": "quote",
	"„": "quote",
	"(": "paren_open",
	")": "paren_close",
	"/": "slash",
	"…": "ellipsis",
	"«": "quote",
	"»": "quote",
}

var is_initialized: bool = false
var ambient_volume_target: float = 0.0
var ambient_volume_current: float = 0.0

func _ready() -> void:
	_setup_audio_players()
	_preload_samples()
	is_initialized = true
	DebugHelper.log_info("ZenAudio: Initialized with %d samples" % key_samples.size())

func _process(delta: float) -> void:
	# Smooth ambient volume transitions
	if ambient_player and abs(ambient_volume_current - ambient_volume_target) > 0.01:
		ambient_volume_current = lerp(ambient_volume_current, ambient_volume_target, delta / FADE_DURATION * 3)
		ambient_player.volume_db = linear_to_db(ambient_volume_current * SoundManager.music_volume)

func _setup_audio_players() -> void:
	# Create ambient player
	ambient_player = AudioStreamPlayer.new()
	ambient_player.bus = "Master"
	ambient_player.volume_db = -80  # Start silent
	ambient_player.finished.connect(_on_track_finished)
	add_child(ambient_player)

	# Create key sample player pool
	for i in range(AUDIO_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		player.volume_db = linear_to_db(0.6)  # Slightly quieter than full volume
		add_child(player)
		key_players.append(player)

func _preload_samples() -> void:
	# Try to load all mapped samples
	for char_key in CHAR_TO_FILE:
		var filename: String = CHAR_TO_FILE[char_key]
		var path := KEY_SAMPLES_PATH + filename + ".ogg"

		if ResourceLoader.exists(path):
			var stream := load(path) as AudioStream
			if stream:
				key_samples[char_key] = stream

	# Load default fallback sample
	var default_path := KEY_SAMPLES_PATH + "default.ogg"
	if ResourceLoader.exists(default_path):
		default_sample = load(default_path)

	# If no samples exist yet, log a warning
	if key_samples.is_empty() and default_sample == null:
		DebugHelper.log_warning("ZenAudio: No key samples found at %s" % KEY_SAMPLES_PATH)
		DebugHelper.log_info("ZenAudio: Expected files: a.ogg, b.ogg, ..., z.ogg, space.ogg, enter.ogg, period.ogg, etc.")

func get_sample_for_char(c: String) -> AudioStream:
	# Normalize: lowercase
	var normalized := c.to_lower()

	# Direct lookup
	if key_samples.has(normalized):
		return key_samples[normalized]

	# Check original character (for special chars)
	if key_samples.has(c):
		return key_samples[c]

	# Fallback
	return default_sample

func play_key_sound(c: String) -> void:
	var sample := get_sample_for_char(c)
	if sample == null:
		return

	# Get next player from pool (round-robin)
	var player := key_players[current_player_index]
	current_player_index = (current_player_index + 1) % AUDIO_POOL_SIZE

	# Stop if already playing (for fast typing)
	if player.playing:
		player.stop()

	player.stream = sample
	player.pitch_scale = randf_range(0.95, 1.05)  # Slight pitch variation for naturalness
	player.play()

func start_ambient() -> void:
	# Get playlist from MusicManager
	var playlist = MusicManager.get_playlist("zen")
	if playlist.is_empty():
		DebugHelper.log_warning("ZenAudio: Zen playlist is empty")
		return

	current_track_index = 0
	_play_track(playlist[current_track_index])

func _play_track(path: String) -> void:
	if not ResourceLoader.exists(path):
		DebugHelper.log_warning("ZenAudio: Track not found: %s" % path)
		play_next_track()
		return

	ambient_player.stream = load(path)
	ambient_volume_current = 0.0
	ambient_volume_target = 0.7
	ambient_player.volume_db = -80
	ambient_player.play()
	DebugHelper.log_info("ZenAudio: Playing track: %s" % path.get_file())

func play_next_track() -> void:
	var playlist = MusicManager.get_playlist("zen")
	if playlist.is_empty():
		return

	current_track_index = (current_track_index + 1) % playlist.size()
	_play_track(playlist[current_track_index])

func _on_track_finished() -> void:
	# Automatically play next track when current one finishes
	if ambient_volume_target > 0:  # Only if we're supposed to be playing
		play_next_track()

func stop_ambient() -> void:
	ambient_volume_target = 0.0
	# Create tween for smooth fade out then stop
	var tween := create_tween()
	tween.tween_property(ambient_player, "volume_db", -40, FADE_DURATION)
	tween.tween_callback(func(): ambient_player.stop())

func set_ambient_volume(vol: float) -> void:
	ambient_volume_target = clampf(vol, 0.0, 1.0)

func is_ambient_playing() -> bool:
	return ambient_player.playing

# Generate list of expected sample filenames for documentation
func get_expected_sample_files() -> Array:
	var files := []
	for char_key in CHAR_TO_FILE:
		var filename: String = CHAR_TO_FILE[char_key] + ".ogg"
		if filename not in files:
			files.append(filename)
	files.append("default.ogg")
	files.sort()
	return files
