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
	typed_buffer = ""
	final_stats = params.get("stats", {})
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

func display_stats() -> void:
	var score = final_stats.get("score", 0)
	var wave = final_stats.get("wave", 1)
	var acc = session_stats.get("accuracy", final_stats.get("accuracy", 0.0))
	var enemies = final_stats.get("enemies_destroyed", 0)
	var wpm = session_stats.get("wpm", 0.0)
	var max_combo = session_stats.get("max_combo", final_stats.get("max_combo", 0))
	var duration = session_stats.get("duration_seconds", 0.0)
	
	# Get lifetime stats for comparison
	var lifetime = StatisticsManager.get_lifetime_stats() if StatisticsManager else {}

	# Score
	if score_label:
		var high_score = lifetime.get("best_score", SaveManager.get_high_score())
		if score > high_score:
			score_label.text = "%d NEW HIGH!" % score
			score_label.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
		elif score == high_score and score > 0:
			score_label.text = "%d (TIED)" % score
		else:
			score_label.text = "%d (Best: %d)" % [score, high_score]

	# Wave
	if wave_label:
		var max_wave = lifetime.get("best_wave", SaveManager.get_max_wave())
		if wave > max_wave:
			wave_label.text = "%d NEW RECORD!" % wave
			wave_label.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
		else:
			wave_label.text = "%d (Best: %d)" % [wave, max_wave]

	# Accuracy
	if accuracy_label:
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

	# Enemies
	if enemies_label:
		enemies_label.text = str(enemies)

	# WPM
	if wpm_label:
		var best_wpm = lifetime.get("best_wpm", 0)
		if wpm > best_wpm and wpm > 0:
			wpm_label.text = "%.1f NEW BEST!" % wpm
			wpm_label.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
		else:
			wpm_label.text = "%.1f (Best: %.1f)" % [wpm, best_wpm]

	# Max Combo
	if combo_label:
		var best_combo = lifetime.get("best_combo", 0)
		if max_combo > best_combo:
			combo_label.text = "%d NEW RECORD!" % max_combo
			combo_label.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
		else:
			combo_label.text = "%d (Best: %d)" % [max_combo, best_combo]

	# Time
	if time_label:
		time_label.text = format_time(duration)

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
	if event is InputEventKey and event.pressed and not event.is_echo():
		var char_code = event.unicode

		if event.keycode == KEY_BACKSPACE:
			if typed_buffer.length() > 0:
				typed_buffer = typed_buffer.substr(0, typed_buffer.length() - 1)
				SoundManager.play_menu_select()
				update_display()
			return

		if (char_code >= 65 and char_code <= 90) or (char_code >= 97 and char_code <= 122):
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
	for key in COMMAND_KEYS:
		var translated = Tr.t(key, key)
		commands[translated] = COMMAND_KEYS[key]

func update_ui_labels() -> void:
	if title_label:
		title_label.text = Tr.t("GAME_OVER_TITLE", "GAME OVER")
	if retry_prompt:
		retry_prompt.text = Tr.t("RETRY", "RETRY")
	if menu_prompt:
		menu_prompt.text = Tr.t("MENU", "MENU")
	if stats_prompt:
		stats_prompt.text = Tr.t("STATS", "STATS")

func _on_language_changed() -> void:
	rebuild_commands()
	update_display()
	update_ui_labels()

func retry_game() -> void:
	DebugHelper.log_info("Retrying game")
	StateManager.change_state("game")

func go_to_menu() -> void:
	DebugHelper.log_info("Going to menu")
	StateManager.change_state("menu")

func view_stats() -> void:
	DebugHelper.log_info("Viewing full stats")
	StateManager.change_state("statistics")

func _on_video_finished() -> void:
	if video_player:
		video_player.play()
