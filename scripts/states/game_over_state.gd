## game_over_state.gd
## Game Over screen - shows final stats, type RETRY or MENU
extends Control

const COMMANDS := {
	"RETRY": "retry_game",
	"MENU": "go_to_menu"
}

@onready var typed_display: Label = $CenterContainer/VBoxContainer/TypedDisplay
@onready var score_label: Label = $CenterContainer/VBoxContainer/StatsContainer/ScoreValue
@onready var wave_label: Label = $CenterContainer/VBoxContainer/StatsContainer/WaveValue
@onready var accuracy_label: Label = $CenterContainer/VBoxContainer/StatsContainer/AccuracyValue
@onready var enemies_label: Label = $CenterContainer/VBoxContainer/StatsContainer/EnemiesValue

var typed_buffer: String = ""
var final_stats: Dictionary = {}

func _ready() -> void:
	typed_buffer = ""
	update_display()

func on_enter(params: Dictionary) -> void:
	DebugHelper.log_info("GameOverState entered")
	typed_buffer = ""
	final_stats = params.get("stats", {})
	update_display()
	display_stats()
	save_results()

func on_exit() -> void:
	DebugHelper.log_info("GameOverState exiting")

func display_stats() -> void:
	var score = final_stats.get("score", 0)
	var wave = final_stats.get("wave", 1)
	var acc = final_stats.get("accuracy", 0.0)
	var enemies = final_stats.get("enemies_destroyed", 0)

	if score_label:
		var high_score = SaveManager.get_high_score()
		if score > high_score:
			score_label.text = "%d NEW HIGH SCORE!" % score
			score_label.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
		elif score == high_score and score > 0:
			score_label.text = "%d (TIED)" % score
		else:
			score_label.text = "%d (Best: %d)" % [score, high_score]

	if wave_label:
		var max_wave = SaveManager.get_max_wave()
		if wave > max_wave:
			wave_label.text = "%d NEW RECORD!" % wave
			wave_label.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
		else:
			wave_label.text = "%d (Best: %d)" % [wave, max_wave]

	if accuracy_label:
		accuracy_label.text = "%.1f%%" % acc

	if enemies_label:
		enemies_label.text = str(enemies)

func save_results() -> void:
	var score = final_stats.get("score", 0)
	var wave = final_stats.get("wave", 0)
	var max_combo = final_stats.get("max_combo", 0)
	var words = final_stats.get("enemies_destroyed", 0)

	var records = SaveManager.update_game_stats(score, wave, max_combo, words)

	if records.get("high_score", false):
		DebugHelper.log_info("New high score achieved!")
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

		# Backspace
		if event.keycode == KEY_BACKSPACE:
			if typed_buffer.length() > 0:
				typed_buffer = typed_buffer.substr(0, typed_buffer.length() - 1)
				update_display()
			return

		# A-Z
		if (char_code >= 65 and char_code <= 90) or (char_code >= 97 and char_code <= 122):
			typed_buffer += char(char_code).to_upper()
			update_display()
			check_commands()

func update_display() -> void:
	if typed_display:
		typed_display.text = typed_buffer

func check_commands() -> void:
	for command in COMMANDS:
		if typed_buffer == command:
			call(COMMANDS[command])
			return

	# Check if could still match any command
	var could_match = false
	for command in COMMANDS:
		if command.begins_with(typed_buffer):
			could_match = true
			break

	if not could_match and typed_buffer.length() > 0:
		typed_buffer = ""
		update_display()

func retry_game() -> void:
	DebugHelper.log_info("Retrying game")
	StateManager.change_state("game")

func go_to_menu() -> void:
	DebugHelper.log_info("Going to menu")
	StateManager.change_state("menu")
