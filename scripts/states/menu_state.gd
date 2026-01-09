## menu_state.gd
## Main menu state - type commands to navigate
extends Control

# Command keys -> function mapping (keys are translation keys)
const COMMAND_KEYS := {
	"START": "start_game",
	"MULTIPLAYER": "start_multiplayer",
	"STATS": "open_stats",
	"SETTINGS": "open_settings",
	"EVOLUTIONS": "open_evolutions",
	"QUIT": "quit_game"
}

# Colors for menu display
const COLOR_TYPED := "#7cff00"      # Acid green - typed characters
const COLOR_OPTION := "#ffffff"      # White
const COLOR_INACTIVE := "#444455"   # Dark gray for non-matching
const COLOR_HOVER := "#00e5ff"      # Cyan - hover highlight

# Effect settings for typed characters (wave animation)
const TYPED_EFFECT_START := "[wave amp=3.0 freq=8.0]"
const TYPED_EFFECT_END := "[/wave]"

@onready var typed_display: Label = $CenterContainer/VBoxContainer/TypedDisplay
@onready var start_prompt: Label = $CenterContainer/VBoxContainer/StartPrompt
@onready var multiplayer_prompt: Label = $CenterContainer/VBoxContainer/MultiplayerPrompt
@onready var stats_prompt: Label = $CenterContainer/VBoxContainer/StatsPrompt
@onready var settings_prompt: Label = $CenterContainer/VBoxContainer/SettingsPrompt
@onready var evolutions_prompt: Label = $CenterContainer/VBoxContainer/EvolutionsPrompt
@onready var quit_prompt: Label = $CenterContainer/VBoxContainer/QuitPrompt
@onready var instructions: Label = $CenterContainer/VBoxContainer/Instructions

var typed_buffer: String = ""
var pulse_time: float = 0.0

# Translated commands cache - rebuilt when language changes
var commands: Dictionary = {}  # translated_text -> function_name
var label_to_key: Dictionary = {}  # Label -> COMMAND_KEY
var hovered_command: String = ""  # Currently hovered menu item

func _ready() -> void:
	DebugHelper.log_info("MenuState ready")
	typed_buffer = ""
	rebuild_commands()
	setup_mouse_support()
	update_display()
	
	# Connect language change signal
	SignalBus.language_changed.connect(_on_language_changed)
	

func on_enter(_params: Dictionary) -> void:
	DebugHelper.log_info("MenuState entered")
	typed_buffer = ""
	hovered_command = ""
	rebuild_commands()
	update_display()
	SoundManager.play_menu_music()
	MenuBackground.show_background()

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


func setup_mouse_support() -> void:
	label_to_key[start_prompt] = "START"
	label_to_key[multiplayer_prompt] = "MULTIPLAYER"
	label_to_key[stats_prompt] = "STATS"
	label_to_key[settings_prompt] = "SETTINGS"
	label_to_key[evolutions_prompt] = "EVOLUTIONS"
	label_to_key[quit_prompt] = "QUIT"
	for label in label_to_key.keys():
		if label:
			label.mouse_filter = Control.MOUSE_FILTER_STOP
			label.mouse_entered.connect(_on_label_mouse_entered.bind(label))
			label.mouse_exited.connect(_on_label_mouse_exited.bind(label))
			label.gui_input.connect(_on_label_gui_input.bind(label))

func _on_label_mouse_entered(label: Label) -> void:
	if InputMode.is_keyboard_mode():
		return
	var key = label_to_key.get(label, "")
	if key:
		hovered_command = Tr.t(key, key)
		SoundManager.play_menu_select()
		update_display()

func _on_label_mouse_exited(_label: Label) -> void:
	hovered_command = ""
	update_display()

func _on_label_gui_input(event: InputEvent, label: Label) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var key = label_to_key.get(label, "")
		if key:
			var translated = Tr.t(key, key)
			typed_buffer = translated
			SoundManager.play_word_complete()
			update_display()
			execute_command(translated)

func _process(delta: float) -> void:
	pulse_time += delta * 3.0

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		var char_code = event.unicode

		# Enter - autofill and execute best match
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			var best_match = get_best_match()
			if best_match != "":
				typed_buffer = best_match
				SoundManager.play_word_complete()
				update_display()
				execute_command(best_match)
			return

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

		# A-Z and German umlauts (Ä=196, Ö=214, Ü=220, ä=228, ö=246, ü=252)
		var is_letter = (char_code >= 65 and char_code <= 90) or (char_code >= 97 and char_code <= 122)
		var is_umlaut = char_code in [196, 214, 220, 228, 246, 252]
		if is_letter or is_umlaut:
			var typed_char = char(char_code).to_upper()
			typed_buffer += typed_char
			SoundManager.play_menu_select()
			update_display()
			check_commands()

func get_best_match() -> String:
	if typed_buffer.length() == 0 and hovered_command != "":
		return hovered_command
	for command in commands:
		if command.begins_with(typed_buffer) and typed_buffer.length() > 0:
			return command
	return ""

func execute_command(command: String) -> void:
	if commands.has(command):
		DebugHelper.log_info("%s - executing command" % command)
		call(commands[command])

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
	update_menu_item(evolutions_prompt, Tr.t("EVOLUTIONS", "EVOLUTIONS"))
	update_menu_item(quit_prompt, Tr.t("QUIT", "QUIT"))
	
	if instructions:
		instructions.text = Tr.t("DEBUG_TOGGLE", "F3 = Toggle Debug")

func update_menu_item(label: Label, command: String) -> void:
	if not label:
		return

	var typed_len = typed_buffer.length()
	var is_hovered = (command == hovered_command)

	if is_hovered:
		label.text = command
		label.add_theme_color_override("font_color", Color(COLOR_HOVER))
	elif typed_len == 0:
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
	StateManager.change_state("solo_mode_select")

func start_multiplayer() -> void:
	StateManager.change_state("lobby")

func open_stats() -> void:
	StateManager.change_state("statistics")

func open_settings() -> void:
	StateManager.change_state("settings")

func open_evolutions() -> void:
	StateManager.change_state("evolution_tree")

func quit_game() -> void:
	DebugHelper.log_info("Quitting game")
	get_tree().quit()
