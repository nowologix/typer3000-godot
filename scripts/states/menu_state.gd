## menu_state.gd
## Main menu state - type commands to navigate
extends Control

# Command keys -> function mapping (keys are translation keys)
const COMMAND_KEYS := {
	"START": "start_game",
	"MULTIPLAYER": "start_multiplayer",
	"STATS": "open_stats",
	"SETTINGS": "open_settings",
	"QUIT": "quit_game"
}

# Colors for menu display
const COLOR_TYPED := "#7cff00"      # Acid green - typed characters
const COLOR_OPTION := "#ffffff"      # White
const COLOR_INACTIVE := "#444455"   # Dark gray for non-matching

# Effect settings for typed characters (wave animation)
const TYPED_EFFECT_START := "[wave amp=3.0 freq=8.0]"
const TYPED_EFFECT_END := "[/wave]"

@onready var typed_display: Label = $CenterContainer/VBoxContainer/TypedDisplay
@onready var start_prompt: Label = $CenterContainer/VBoxContainer/StartPrompt
@onready var multiplayer_prompt: Label = $CenterContainer/VBoxContainer/MultiplayerPrompt
@onready var stats_prompt: Label = $CenterContainer/VBoxContainer/StatsPrompt
@onready var settings_prompt: Label = $CenterContainer/VBoxContainer/SettingsPrompt
@onready var quit_prompt: Label = $CenterContainer/VBoxContainer/QuitPrompt
@onready var instructions: Label = $CenterContainer/VBoxContainer/Instructions
@onready var video_player: VideoStreamPlayer = $VideoBackground

var typed_buffer: String = ""
var pulse_time: float = 0.0

# Translated commands cache - rebuilt when language changes
var commands: Dictionary = {}  # translated_text -> function_name

func _ready() -> void:
	DebugHelper.log_info("MenuState ready")
	typed_buffer = ""
	rebuild_commands()
	update_display()
	
	# Connect language change signal
	SignalBus.language_changed.connect(_on_language_changed)
	
	# Connect video loop signal
	if video_player:
		video_player.finished.connect(_on_video_finished)

func on_enter(_params: Dictionary) -> void:
	DebugHelper.log_info("MenuState entered")
	typed_buffer = ""
	rebuild_commands()
	update_display()
	SoundManager.play_menu_music()
	
	# Start background video
	if video_player:
		video_player.play()

func on_exit() -> void:
	DebugHelper.log_info("MenuState exiting")
	if SignalBus.language_changed.is_connected(_on_language_changed):
		SignalBus.language_changed.disconnect(_on_language_changed)

func _on_language_changed() -> void:
	rebuild_commands()
	update_display()

func rebuild_commands() -> void:
	commands.clear()
	for key in COMMAND_KEYS:
		var translated = Tr.t(key, key)  # Fallback to key itself
		commands[translated] = COMMAND_KEYS[key]

func _process(delta: float) -> void:
	pulse_time += delta * 3.0

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		var char_code = event.unicode

		# Backspace
		if event.keycode == KEY_BACKSPACE:
			if typed_buffer.length() > 0:
				typed_buffer = typed_buffer.substr(0, typed_buffer.length() - 1)
				SoundManager.play_menu_select()
				update_display()
			return

		# Escape to quit
		if event.keycode == KEY_ESCAPE:
			quit_game()
			return

		# A-Z and umlauts
		if (char_code >= 65 and char_code <= 90) or (char_code >= 97 and char_code <= 122):
			var typed_char = char(char_code).to_upper()
			typed_buffer += typed_char
			SoundManager.play_menu_select()
			update_display()
			check_commands()

func update_display() -> void:
	if typed_display:
		typed_display.text = typed_buffer

		var matches_any = false
		for command in commands:
			if command.begins_with(typed_buffer) and typed_buffer.length() > 0:
				matches_any = true
				break

		if matches_any:
			typed_display.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
		elif typed_buffer.length() > 0:
			typed_display.add_theme_color_override("font_color", GameConfig.COLORS.magenta)
		else:
			typed_display.add_theme_color_override("font_color", GameConfig.COLORS.cyan)

	# Update menu items with translated text
	update_menu_item(start_prompt, Tr.t("START", "START"))
	update_menu_item(multiplayer_prompt, Tr.t("MULTIPLAYER", "MULTIPLAYER"))
	update_menu_item(stats_prompt, Tr.t("STATS", "STATS"))
	update_menu_item(settings_prompt, Tr.t("SETTINGS", "SETTINGS"))
	update_menu_item(quit_prompt, Tr.t("QUIT", "QUIT"))
	
	if instructions:
		instructions.text = Tr.t("DEBUG_TOGGLE", "F3 = Toggle Debug")

func update_menu_item(label: Label, command: String) -> void:
	if not label:
		return

	var typed_len = typed_buffer.length()

	if typed_len == 0:
		label.text = command
		label.add_theme_color_override("font_color", Color(COLOR_OPTION))
	elif command.begins_with(typed_buffer):
		label.text = command
		label.add_theme_color_override("font_color", Color(COLOR_TYPED))
	else:
		label.text = command
		label.add_theme_color_override("font_color", Color(COLOR_INACTIVE))

func check_commands() -> void:
	for command in commands:
		if typed_buffer == command:
			DebugHelper.log_info("%s typed - executing command" % command)
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

func start_game() -> void:
	StateManager.change_state("game")

func start_multiplayer() -> void:
	StateManager.change_state("lobby")

func open_stats() -> void:
	StateManager.change_state("statistics")

func open_settings() -> void:
	StateManager.change_state("settings")

func quit_game() -> void:
	DebugHelper.log_info("Quitting game")
	get_tree().quit()

func _on_video_finished() -> void:
	if video_player:
		video_player.play()
