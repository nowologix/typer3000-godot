## sound_manager.gd
## Handles all audio playback
## Autoload singleton: SoundManager
extends Node

# Audio players
var sfx_players: Array[AudioStreamPlayer] = []
var music_player: AudioStreamPlayer

# Volume settings
var master_volume: float = 1.0
var sfx_volume: float = 1.0
var music_volume: float = 0.7

# SFX pool size
const SFX_POOL_SIZE: int = 8

# Preloaded sounds (will be loaded when available)
var sounds: Dictionary = {}

func _ready() -> void:
	# Create SFX player pool
	for i in range(SFX_POOL_SIZE):
		var player = AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		sfx_players.append(player)

	# Create music player
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Master"
	add_child(music_player)

	# Try to load sounds
	_load_sounds()

	DebugHelper.log_info("SoundManager initialized with %d SFX players" % SFX_POOL_SIZE)

func _load_sounds() -> void:
	# Sound files mapping - using original typer3000 MP3 assets
	var sound_paths = {
		# Core typing sounds
		"type_correct": "res://assets/audio/sfx/hit-marker_01.mp3",
		"type_correct_2": "res://assets/audio/sfx/hit-marker_02.mp3",
		"type_correct_3": "res://assets/audio/sfx/hit-marker_03.mp3",
		"type_correct_4": "res://assets/audio/sfx/hit-marker_04.mp3",
		"type_correct_5": "res://assets/audio/sfx/hit-marker_05.mp3",
		"type_error": "res://assets/audio/sfx/short-static.mp3",
		"word_complete": "res://assets/audio/sfx/tech-ok_01.mp3",

		# Combat sounds
		"enemy_kill": "res://assets/audio/sfx/hit-kill_01.mp3",
		"enemy_kill_big": "res://assets/audio/sfx/big-hit-kill_01.mp3",
		"enemy_spawn": "res://assets/audio/sfx/short-tech-loop_01.mp3",
		"portal_hit": "res://assets/audio/sfx/tech-glitch_01.mp3",
		"portal_destroy": "res://assets/audio/sfx/construct-big_01.mp3",

		# Game state sounds
		"game_over": "res://assets/audio/sfx/tech-glitch_01.mp3",
		"game_start": "res://assets/audio/sfx/hi-tech_01.mp3",
		"wave_start": "res://assets/audio/sfx/long-tech-loop_01.mp3",
		"wave_complete": "res://assets/audio/sfx/tech-message_01.mp3",

		# Menu sounds
		"menu_select": "res://assets/audio/sfx/tech-button_01.mp3",
		"menu_back": "res://assets/audio/sfx/boomerang.mp3",

		# PowerUp sounds
		"powerup_spawn": "res://assets/audio/sfx/powerup-drop.mp3",
		"powerup_collect": "res://assets/audio/sfx/tech-upgrade_01.mp3",
		"powerup_freeze": "res://assets/audio/sfx/airy-background-loop.mp3",
		"powerup_shield": "res://assets/audio/sfx/tech-ok_01.mp3",
		"powerup_bomb": "res://assets/audio/sfx/big-hit-kill_01.mp3",
		"powerup_nuke": "res://assets/audio/sfx/nuke-sound.mp3",
		"powerup_heal": "res://assets/audio/sfx/upgrade_01.mp3",
		"powerup_expire": "res://assets/audio/sfx/boomerang.mp3",
		"shield_activate": "res://assets/sounds/typer3000_shield-sound.mp3",
		"slowdown": "res://assets/sounds/typer3000_slowdown.mp3",
		"speedup": "res://assets/sounds/typer3000_speedup.mp3",
		"freeze_effect": "res://assets/sounds/typer3000-freeze.mp3",

		# Tower sounds
		"tower_build": "res://assets/audio/sfx/build_01.mp3",
		"tower_shoot": "res://assets/audio/sfx/hit-marker_01.mp3",
		"tower_upgrade": "res://assets/audio/sfx/tech-upgrade_03.mp3",
		"tower_sell": "res://assets/audio/sfx/build_02.mp3",
		"electric_hit_1": "res://assets/audio/sfx/electric_hit_1.mp3",
		"electric_hit_2": "res://assets/audio/sfx/electric_hit_2.mp3",
		"electric_hit_3": "res://assets/audio/sfx/electric_hit_3.mp3",
		"electric_hit_4": "res://assets/audio/sfx/electric_hit_4.mp3",
		"electric_hit_5": "res://assets/audio/sfx/electric_hit_5.mp3",
		"electric_hit_6": "res://assets/audio/sfx/electric_hit_6.mp3",

		# Combo sounds
		"combo_5": "res://assets/audio/sfx/tech-message_01.mp3",
		"combo_10": "res://assets/audio/sfx/tech-upgrade_01.mp3",
		"combo_25": "res://assets/audio/sfx/hi-tech_01.mp3",
		"combo_break": "res://assets/audio/sfx/tech-glitch_01.mp3",

		# Multiplayer / WordWar sounds
		"match_found": "res://assets/audio/sfx/hi-tech_01.mp3",
		"opponent_score": "res://assets/audio/sfx/tech-message_01.mp3",
		"word_incoming": "res://assets/audio/sfx/short-tech-loop_01.mp3",
		"victory": "res://assets/audio/sfx/construct-big_01.mp3",
		"defeat": "res://assets/audio/sfx/tech-glitch_01.mp3",
		"countdown": "res://assets/audio/sfx/tech-button_01.mp3",

		# Voice announcements
		"voice_welcome": "res://assets/audio/voice/welcometotyper3000.mp3",
		"voice_kingofthecombo": "res://assets/audio/voice/kingofthecombo.mp3",
		"voice_lobby_initiated": "res://assets/audio/voice/lobby-initiated.mp3",
		"voice_impressive": "res://assets/audio/voice/impressive.mp3",
	}

	for key in sound_paths:
		var path = sound_paths[key]
		if ResourceLoader.exists(path):
			sounds[key] = load(path)
		else:
			DebugHelper.log_debug("Sound not found: %s" % path)

func play_sfx(sound_name: String) -> void:
	if not sounds.has(sound_name):
		DebugHelper.log_debug("Sound '%s' not loaded" % sound_name)
		return

	# Find available player
	for player in sfx_players:
		if not player.playing:
			player.stream = sounds[sound_name]
			player.volume_db = linear_to_db(sfx_volume * master_volume)
			player.play()
			return

	# All players busy, use first one (interrupt)
	sfx_players[0].stream = sounds[sound_name]
	sfx_players[0].volume_db = linear_to_db(sfx_volume * master_volume)
	sfx_players[0].play()

func play_music(music_path: String, loop: bool = true) -> void:
	if not ResourceLoader.exists(music_path):
		DebugHelper.log_warning("Music not found: %s" % music_path)
		return

	var music = load(music_path)
	if music:
		music.loop = loop
		music_player.stream = music
		music_player.volume_db = linear_to_db(music_volume * master_volume)
		music_player.play()

func stop_music() -> void:
	music_player.stop()

func set_master_volume(volume: float) -> void:
	master_volume = clampf(volume, 0.0, 1.0)

func set_sfx_volume(volume: float) -> void:
	sfx_volume = clampf(volume, 0.0, 1.0)

func set_music_volume(volume: float) -> void:
	music_volume = clampf(volume, 0.0, 1.0)
	if music_player.playing:
		music_player.volume_db = linear_to_db(music_volume * master_volume)

# Convenience methods for common sounds
func play_type_correct() -> void:
	# Play random type correct sound for variety
	var variants = ["type_correct", "type_correct_2", "type_correct_3", "type_correct_4", "type_correct_5"]
	var chosen = variants[randi() % variants.size()]
	if sounds.has(chosen):
		play_sfx(chosen)
	else:
		play_sfx("type_correct")

func play_type_error() -> void:
	play_sfx("type_error")

func play_word_complete() -> void:
	play_sfx("word_complete")

func play_enemy_kill() -> void:
	play_sfx("enemy_kill")

func play_enemy_spawn() -> void:
	play_sfx("enemy_spawn")

func play_portal_hit() -> void:
	play_sfx("portal_hit")

func play_portal_destroy() -> void:
	play_sfx("portal_destroy")

func play_menu_select() -> void:
	play_sfx("menu_select")

func play_menu_back() -> void:
	play_sfx("menu_back")

func play_game_start() -> void:
	play_sfx("game_start")

func play_game_over() -> void:
	play_sfx("game_over")

func play_wave_start() -> void:
	play_sfx("wave_start")

func play_wave_complete() -> void:
	play_sfx("wave_complete")

# PowerUp sounds
func play_powerup_spawn() -> void:
	play_sfx("powerup_spawn")

func play_powerup_collect() -> void:
	play_sfx("powerup_collect")

func play_powerup_freeze() -> void:
	play_sfx("powerup_freeze")

func play_powerup_shield() -> void:
	play_sfx("powerup_shield")

func play_powerup_bomb() -> void:
	play_sfx("powerup_bomb")

func play_powerup_heal() -> void:
	play_sfx("powerup_heal")

func play_powerup_expire() -> void:
	play_sfx("powerup_expire")

# Tower sounds
func play_tower_build() -> void:
	play_sfx("tower_build")

func play_tower_shoot() -> void:
	play_sfx("tower_shoot")

func play_tower_upgrade() -> void:
	play_sfx("tower_upgrade")

func play_tower_sell() -> void:
	play_sfx("tower_sell")

func play_tesla_zap() -> void:
	# Play random electric hit sound
	var variants = ["electric_hit_1", "electric_hit_2", "electric_hit_3", "electric_hit_4", "electric_hit_5", "electric_hit_6"]
	var chosen = variants[randi() % variants.size()]
	play_sfx(chosen)

# Combo sounds
func play_combo_milestone(combo: int) -> void:
	if combo >= 25:
		play_sfx("combo_25")
	elif combo >= 10:
		play_sfx("combo_10")
	elif combo >= 5:
		play_sfx("combo_5")

func play_combo_break() -> void:
	play_sfx("combo_break")

# Multiplayer sounds
func play_match_found() -> void:
	play_sfx("match_found")

func play_opponent_score() -> void:
	play_sfx("opponent_score")

func play_word_incoming() -> void:
	play_sfx("word_incoming")

func play_victory() -> void:
	play_sfx("victory")

func play_defeat() -> void:
	play_sfx("defeat")

func play_countdown() -> void:
	play_sfx("countdown")

# Music paths
const MUSIC_PATHS = {
	"menu": "res://assets/audio/music/mainmusic.mp3",
	"game": "res://assets/audio/music/gameplay_track_01.mp3",
	"pause": "res://assets/audio/music/pause-music.mp3",
}

func play_menu_music() -> void:
	play_music(MUSIC_PATHS.menu, true)

func play_game_music() -> void:
	play_music(MUSIC_PATHS.game, true)

func play_pause_music() -> void:
	play_music(MUSIC_PATHS.pause, true)

# Play a random pitch variation for variety
func play_sfx_pitched(sound_name: String, pitch_range: float = 0.1) -> void:
	if not sounds.has(sound_name):
		return

	for player in sfx_players:
		if not player.playing:
			player.stream = sounds[sound_name]
			player.pitch_scale = 1.0 + randf_range(-pitch_range, pitch_range)
			player.volume_db = linear_to_db(sfx_volume * master_volume)
			player.play()
			player.finished.connect(func(): player.pitch_scale = 1.0, CONNECT_ONE_SHOT)
			return

# New powerup sounds
func play_powerup_nuke() -> void:
	play_sfx("powerup_nuke")

func play_shield_activate() -> void:
	play_sfx("shield_activate")

func play_slowdown() -> void:
	play_sfx("slowdown")

func play_speedup() -> void:
	play_sfx("speedup")

func play_freeze_effect() -> void:
	play_sfx("freeze_effect")

# Voice announcements
func play_voice_welcome() -> void:
	play_sfx("voice_welcome")

func play_voice_king_of_combo() -> void:
	play_sfx("voice_kingofthecombo")

func play_voice_lobby_initiated() -> void:
	play_sfx("voice_lobby_initiated")

func play_voice_impressive() -> void:
	play_sfx("voice_impressive")
