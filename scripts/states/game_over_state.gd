## game_over_state.gd
## Game Over screen - shows detailed session stats
extends Control

# Command keys for translation lookup
const COMMAND_KEYS := {
	"RETRY": "retry_game",
	"MENU": "go_to_menu",
	"STATS": "view_stats"
}

# Dynamic commands rebuilt on language change
var commands := {}

@onready var typed_display: Label = $CenterContainer/VBoxContainer/TypedDisplay
@onready var title_label: Label = $CenterContainer/VBoxContainer/Title
@onready var score_label: Label = $CenterContainer/VBoxContainer/StatsContainer/ScoreValue
@onready var wave_label: Label = $CenterContainer/VBoxContainer/StatsContainer/WaveValue
@onready var accuracy_label: Label = $CenterContainer/VBoxContainer/StatsContainer/AccuracyValue
@onready var enemies_label: Label = $CenterContainer/VBoxContainer/StatsContainer/EnemiesValue
@onready var wpm_label: Label = $CenterContainer/VBoxContainer/StatsContainer/WpmValue
@onready var combo_label: Label = $CenterContainer/VBoxContainer/StatsContainer/ComboValue
@onready var time_label: Label = $CenterContainer/VBoxContainer/StatsContainer/TimeValue
@onready var retry_prompt: Label = $CenterContainer/VBoxContainer/CommandsContainer/RetryPrompt
@onready var menu_prompt: Label = $CenterContainer/VBoxContainer/CommandsContainer/MenuPrompt
@onready var stats_prompt: Label = $CenterContainer/VBoxContainer/CommandsContainer/StatsPrompt
@onready var video_player: VideoStreamPlayer = $VideoBackground

var typed_buffer: String = ""
var final_stats: Dictionary = {}
var session_stats: Dictionary = {}
var is_coop_mode: bool = false
var is_vs_mode: bool = false
var is_wordwar_mode: bool = false
var is_network_host: bool = false
var is_disconnected: bool = false

func _ready() -> void:
	typed_buffer = ""
	rebuild_commands()
	update_display()
	update_ui_labels()

	if video_player:
		video_player.finished.connect(_on_video_finished)

	# Connect language change signal
	if SignalBus.has_signal("language_changed"):
		SignalBus.language_changed.connect(_on_language_changed)

func on_enter(params: Dictionary) -> void:
	DebugHelper.log_info("GameOverState entered")
	MenuBackground.show_background()
	typed_buffer = ""
	final_stats = params.get("stats", {})

	# Check if this is COOP, VS, or WORDWAR mode
	var mode = params.get("mode", final_stats.get("mode", ""))
	is_coop_mode = (mode == "COOP")
	is_vs_mode = (mode == "VS")
	is_wordwar_mode = (mode == "WORDWAR")
	var is_network_mode = is_coop_mode or is_vs_mode or is_wordwar_mode
	is_network_host = NetworkManager.is_host if is_network_mode else false
	is_disconnected = params.get("disconnected", final_stats.get("disconnected", false))

	DebugHelper.log_info("GameOver - Mode: %s, is_host: %s, disconnected: %s" % [mode, is_network_host, is_disconnected])

	# In network mode, CLIENT listens for HOST's retry (game_start)
	if is_network_mode and not is_network_host:
		if not SignalBus.network_game_start.is_connected(_on_network_game_start):
			SignalBus.network_game_start.connect(_on_network_game_start)

	rebuild_commands()

	# Get detailed session stats from StatisticsManager
	if StatisticsManager:
		session_stats = StatisticsManager.get_session_stats()

	update_display()
	update_ui_labels()
	display_stats()
	save_results()

	if video_player:
		video_player.play()

func on_exit() -> void:
	DebugHelper.log_info("GameOverState exiting")
	if SignalBus.has_signal("language_changed") and SignalBus.language_changed.is_connected(_on_language_changed):
		SignalBus.language_changed.disconnect(_on_language_changed)
	# Disconnect network game start signal
	if SignalBus.network_game_start.is_connected(_on_network_game_start):
		SignalBus.network_game_start.disconnect(_on_network_game_start)

func display_stats() -> void:
	var score = final_stats.get("score", 0)
	var wave = final_stats.get("wave", 1)
	var acc = session_stats.get("accuracy", final_stats.get("accuracy", 0.0))
	var enemies = final_stats.get("enemies_destroyed", 0)
	var wpm = session_stats.get("wpm", 0.0)
	var max_combo = session_stats.get("max_combo", final_stats.get("max_combo", 0))
	var duration = session_stats.get("duration_seconds", 0.0)

	# Get opponent stats for VS mode
	var opp = final_stats.get("opponent_stats", {})
	var opp_acc = opp.get("accuracy", 0.0)
	var opp_enemies = opp.get("enemies_destroyed", 0)
	var opp_wpm = opp.get("wpm", 0.0)
	var opp_combo = opp.get("max_combo", opp.get("combo", 0))
	var opp_wave = opp.get("wave", 0)

	# Get lifetime stats for comparison (non-VS modes)
	var lifetime = StatisticsManager.get_lifetime_stats() if StatisticsManager else {}

	# Check if this is a competitive mode (VS or WORDWAR)
	var is_competitive = (is_vs_mode or is_wordwar_mode) and not is_disconnected

	# Score - special display for competitive modes
	if score_label:
		if is_competitive:
			var opponent_score = final_stats.get("opponent_score", 0)
			var label_text = "%d vs %d" % [score, opponent_score]
			if is_wordwar_mode:
				label_text = "%d - %d ROUNDS" % [score, opponent_score]
			score_label.text = label_text
			_color_vs_stat(score_label, score, opponent_score)
		else:
			var high_score = lifetime.get("best_score", SaveManager.get_high_score())
			if score > high_score:
				score_label.text = "%d NEW HIGH!" % score
				score_label.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
			elif score == high_score and score > 0:
				score_label.text = "%d (TIED)" % score
			else:
				score_label.text = "%d (Best: %d)" % [score, high_score]

	# Wave / Round
	if wave_label:
		if is_competitive:
			if is_wordwar_mode:
				# For WORDWAR, show final HP comparison instead of wave
				var my_hp = final_stats.get("final_hp", 0)
				var opp_hp = final_stats.get("opponent_hp", opp.get("final_hp", 0))
				wave_label.text = "%d vs %d HP" % [my_hp, opp_hp]
				_color_vs_stat(wave_label, my_hp, opp_hp)
			else:
				wave_label.text = "%d vs %d" % [wave, opp_wave]
				_color_vs_stat(wave_label, wave, opp_wave)
		else:
			var max_wave = lifetime.get("best_wave", SaveManager.get_max_wave())
			if wave > max_wave:
				wave_label.text = "%d NEW RECORD!" % wave
				wave_label.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
			else:
				wave_label.text = "%d (Best: %d)" % [wave, max_wave]

	# Accuracy (only for VS mode, WORDWAR doesn't track this)
	if accuracy_label:
		if is_vs_mode and not is_disconnected:
			accuracy_label.text = "%.1f%% vs %.1f%%" % [acc, opp_acc]
			_color_vs_stat(accuracy_label, acc, opp_acc)
		elif is_wordwar_mode:
			accuracy_label.text = "-"
		else:
			var best_acc = lifetime.get("best_accuracy", 0)
			if acc > best_acc and acc > 0:
				accuracy_label.text = "%.1f%% NEW BEST!" % acc
				accuracy_label.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
			else:
				accuracy_label.text = "%.1f%%" % acc
				if acc >= 95:
					accuracy_label.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
				elif acc >= 80:
					accuracy_label.add_theme_color_override("font_color", GameConfig.COLORS.amber)
				else:
					accuracy_label.add_theme_color_override("font_color", GameConfig.COLORS.magenta)

	# Enemies (only for VS mode, WORDWAR doesn't track this)
	if enemies_label:
		if is_vs_mode and not is_disconnected:
			enemies_label.text = "%d vs %d" % [enemies, opp_enemies]
			_color_vs_stat(enemies_label, enemies, opp_enemies)
		elif is_wordwar_mode:
			enemies_label.text = "-"
		else:
			enemies_label.text = str(enemies)

	# WPM (only for VS mode, WORDWAR doesn't track this)
	if wpm_label:
		if is_vs_mode and not is_disconnected:
			wpm_label.text = "%.1f vs %.1f" % [wpm, opp_wpm]
			_color_vs_stat(wpm_label, wpm, opp_wpm)
		elif is_wordwar_mode:
			wpm_label.text = "-"
		else:
			var best_wpm = lifetime.get("best_wpm", 0)
			if wpm > best_wpm and wpm > 0:
				wpm_label.text = "%.1f NEW BEST!" % wpm
				wpm_label.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
			else:
				wpm_label.text = "%.1f (Best: %.1f)" % [wpm, best_wpm]

	# Max Combo (only for VS mode, WORDWAR doesn't track this)
	if combo_label:
		if is_vs_mode and not is_disconnected:
			combo_label.text = "%d vs %d" % [max_combo, opp_combo]
			_color_vs_stat(combo_label, max_combo, opp_combo)
		elif is_wordwar_mode:
			combo_label.text = "-"
		else:
			var best_combo = lifetime.get("best_combo", 0)
			if max_combo > best_combo:
				combo_label.text = "%d NEW RECORD!" % max_combo
				combo_label.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
			else:
				combo_label.text = "%d (Best: %d)" % [max_combo, best_combo]

	# Time
	if time_label:
		if is_wordwar_mode:
			time_label.text = "-"
		else:
			time_label.text = format_time(duration)

func _color_vs_stat(label: Label, my_val: float, opp_val: float) -> void:
	if my_val > opp_val:
		label.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
	elif my_val < opp_val:
		label.add_theme_color_override("font_color", GameConfig.COLORS.magenta)
	else:
		label.add_theme_color_override("font_color", GameConfig.COLORS.amber)

func format_time(seconds: float) -> String:
	var mins = int(seconds / 60)
	var secs = int(fmod(seconds, 60))
	return "%d:%02d" % [mins, secs]

func save_results() -> void:
	var score = final_stats.get("score", 0)
	var wave = final_stats.get("wave", 0)
	var max_combo = final_stats.get("max_combo", 0)
	var words = final_stats.get("enemies_destroyed", 0)

	var records = SaveManager.update_game_stats(score, wave, max_combo, words)

	if records.get("high_score", false):
		DebugHelper.log_info("New high score achieved!")
		# Play impressive voice when new personal best on game over
		SoundManager.play_voice_impressive()
	if records.get("max_wave", false):
		DebugHelper.log_info("New wave record achieved!")
	if records.get("best_combo", false):
		DebugHelper.log_info("New combo record achieved!")

	# Check Steam achievements
	SteamManager.check_word_count_achievements(SaveManager.save_data.get("total_words_typed", 0))
	SteamManager.check_wave_achievements(wave)
	SteamManager.check_combo_achievements(max_combo)
	SteamManager.check_score_achievements(score)

	# Submit to leaderboards
	SteamManager.submit_leaderboard_score("HighScore", score)
	SteamManager.submit_leaderboard_score("MaxWave", wave)

func _input(event: InputEvent) -> void:
	# Mouse back button
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_XBUTTON1:
			go_to_menu()
			return

	if event is InputEventKey and event.pressed and not event.is_echo():
		var char_code = event.unicode

		if event.keycode == KEY_BACKSPACE:
			if typed_buffer.length() > 0:
				typed_buffer = typed_buffer.substr(0, typed_buffer.length() - 1)
				SoundManager.play_menu_select()
				update_display()
			return

		# A-Z and German umlauts (Ä=196, Ö=214, Ü=220, ä=228, ö=246, ü=252)
		var is_letter = (char_code >= 65 and char_code <= 90) or (char_code >= 97 and char_code <= 122)
		var is_umlaut = char_code in [196, 214, 220, 228, 246, 252]
		if is_letter or is_umlaut:
			typed_buffer += char(char_code).to_upper()
			SoundManager.play_menu_select()
			update_display()
			check_commands()

func update_display() -> void:
	if typed_display:
		typed_display.text = typed_buffer

func check_commands() -> void:
	for command in commands:
		if typed_buffer == command:
			SoundManager.play_word_complete()
			call(commands[command])
			return

	var could_match = false
	for command in commands:
		if command.begins_with(typed_buffer):
			could_match = true
			break

	if not could_match and typed_buffer.length() > 0:
		SoundManager.play_type_error()
		typed_buffer = ""
		update_display()

func rebuild_commands() -> void:
	commands.clear()
	var is_network_mode = is_coop_mode or is_vs_mode or is_wordwar_mode
	for key in COMMAND_KEYS:
		# No RETRY if disconnected (no opponent to play with)
		if key == "RETRY" and is_disconnected:
			continue
		# In network mode, CLIENT cannot retry - only HOST can
		if key == "RETRY" and is_network_mode and not is_network_host:
			continue
		var translated = Tr.t(key, key)
		commands[translated] = COMMAND_KEYS[key]

func update_ui_labels() -> void:
	if title_label:
		if is_disconnected:
			title_label.text = Tr.t("OPPONENT_DISCONNECTED", "OPPONENT LEFT")
			title_label.add_theme_color_override("font_color", GameConfig.COLORS.amber)
		elif is_vs_mode or is_wordwar_mode:
			var opponent_score = final_stats.get("opponent_score", 0)
			var my_score = final_stats.get("score", 0)
			if my_score > opponent_score:
				title_label.text = Tr.t("VS_VICTORY", "VICTORY!")
				title_label.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
			elif my_score < opponent_score:
				title_label.text = Tr.t("VS_DEFEAT", "DEFEAT")
				title_label.add_theme_color_override("font_color", GameConfig.COLORS.magenta)
			else:
				title_label.text = Tr.t("VS_TIE", "TIE GAME")
				title_label.add_theme_color_override("font_color", GameConfig.COLORS.amber)
		else:
			title_label.text = Tr.t("GAME_OVER_TITLE", "GAME OVER")
	if retry_prompt:
		# Hide RETRY if disconnected or if network client
		var is_network_mode = is_coop_mode or is_vs_mode or is_wordwar_mode
		if is_disconnected or (is_network_mode and not is_network_host):
			retry_prompt.visible = false
		else:
			retry_prompt.visible = true
			retry_prompt.text = Tr.t("RETRY", "RETRY")
	if menu_prompt:
		menu_prompt.text = Tr.t("MENU", "MENU")
	if stats_prompt:
		stats_prompt.text = Tr.t("STATS", "STATS")

func _on_language_changed() -> void:
	rebuild_commands()
	update_display()
	update_ui_labels()

func _on_network_game_start(game_seed: int, mode: String, language: String) -> void:
	# CLIENT: HOST started a new game via RETRY
	# Apply host's language
	WordSetLoader.set_language_string(language)
	AphorismLoader.set_language_string(language)
	DebugHelper.log_info("CLIENT: Using host language: %s" % language)

	if mode == "COOP":
		DebugHelper.log_info("CLIENT: HOST started new COOP session, joining...")
		StateManager.change_state("coop_game", {"seed": game_seed, "language": language})
	elif mode == "VS":
		DebugHelper.log_info("CLIENT: HOST started new VS session, joining...")
		StateManager.change_state("vs_battle", {"seed": game_seed, "multiplayer": true, "language": language})
	elif mode == "WORDWAR":
		DebugHelper.log_info("CLIENT: HOST started new WORDWAR session, joining...")
		StateManager.change_state("wordwar", {"seed": game_seed, "multiplayer": true, "language": language})

func retry_game() -> void:
	DebugHelper.log_info("Retrying game")

	# In network mode, HOST needs to check if partner is still connected
	var is_network_mode = is_coop_mode or is_vs_mode or is_wordwar_mode
	if is_network_mode:
		if not is_network_host:
			# Shouldn't happen - CLIENT can't retry
			DebugHelper.log_warning("Network Client tried to retry - not allowed")
			return

		# Check if partner is still connected
		if NetworkManager.get_player_count() < 2:
			# No partner connected
			DebugHelper.log_warning("Retry failed - no partner connected")
			show_no_partner_error()
			return

		# Partner is connected, start new game
		var game_seed = randi()
		var host_language = SaveManager.get_setting("language", "EN")
		if is_coop_mode:
			DebugHelper.log_info("COOP HOST: Starting new session with partner")
			NetworkManager.send_message("start_game", {"seed": game_seed, "mode": "COOP", "language": host_language})
			StateManager.change_state("coop_game", {"seed": game_seed, "language": host_language})
		elif is_vs_mode:
			DebugHelper.log_info("VS HOST: Starting new session with opponent")
			NetworkManager.send_message("start_game", {"seed": game_seed, "mode": "VS", "language": host_language})
			StateManager.change_state("vs_battle", {"seed": game_seed, "multiplayer": true, "language": host_language})
		elif is_wordwar_mode:
			DebugHelper.log_info("WORDWAR HOST: Starting new session with opponent")
			NetworkManager.send_message("start_game", {"seed": game_seed, "mode": "WORDWAR", "language": host_language})
			StateManager.change_state("wordwar", {"seed": game_seed, "multiplayer": true, "language": host_language})
	else:
		# Solo mode - just restart
		StateManager.change_state("game")

func show_no_partner_error() -> void:
	# Temporarily show error message
	if typed_display:
		typed_display.text = "NO PARTNER CONNECTED"
		typed_display.add_theme_color_override("font_color", GameConfig.COLORS.magenta)

	# Reset after delay
	var timer = get_tree().create_timer(2.0)
	timer.timeout.connect(func():
		typed_buffer = ""
		if typed_display:
			typed_display.text = ""
			typed_display.remove_theme_color_override("font_color")
	)

func go_to_menu() -> void:
	DebugHelper.log_info("Going to menu")
	# In network mode, leave the lobby when going to menu
	var is_network_mode = is_coop_mode or is_vs_mode or is_wordwar_mode
	if is_network_mode and NetworkManager.is_in_lobby():
		NetworkManager.leave_lobby()
	StateManager.change_state("menu")

func view_stats() -> void:
	DebugHelper.log_info("Viewing full stats")
	StateManager.change_state("statistics")

func _on_video_finished() -> void:
	if video_player:
		video_player.play()
