## settings_state.gd
## Settings menu state - type commands to navigate and adjust settings
extends Control

const COMMANDS := ["RESOLUTION", "FULLSCREEN", "MASTER", "MUSIC", "SFX", "LANGUAGE", "BACK"]
const VOLUME_COMMANDS := ["MASTER", "MUSIC", "SFX"]

const COLOR_TYPED := "#7cff00"
const COLOR_OPTION := "#ffffff"
const COLOR_VALUE := "#00e5ff"
const COLOR_INACTIVE := "#444455"
const TYPED_EFFECT_START := "[wave amp=3.0 freq=8.0]"
const TYPED_EFFECT_END := "[/wave]"

@onready var typed_display: Label = $CenterContainer/VBoxContainer/TypedDisplay
@onready var resolution_prompt: RichTextLabel = $CenterContainer/VBoxContainer/ResolutionPrompt
@onready var fullscreen_prompt: RichTextLabel = $CenterContainer/VBoxContainer/FullscreenPrompt
@onready var master_prompt: RichTextLabel = $CenterContainer/VBoxContainer/MasterPrompt
@onready var music_prompt: RichTextLabel = $CenterContainer/VBoxContainer/MusicPrompt
@onready var sfx_prompt: RichTextLabel = $CenterContainer/VBoxContainer/SfxPrompt
@onready var language_prompt: RichTextLabel = $CenterContainer/VBoxContainer/LanguagePrompt
@onready var back_prompt: RichTextLabel = $CenterContainer/VBoxContainer/BackPrompt
@onready var instructions: Label = $CenterContainer/VBoxContainer/Instructions

var typed_buffer: String = ""
var pulse_time: float = 0.0
var adjust_mode: bool = false
var selected_option: String = ""
var return_to: String = "menu"

func _ready() -> void:
	DebugHelper.log_info("SettingsState ready")
	typed_buffer = ""
	adjust_mode = false
	update_display()

func on_enter(params: Dictionary) -> void:
	DebugHelper.log_info("SettingsState entered")
	typed_buffer = ""
	adjust_mode = false
	return_to = params.get("return_to", "menu")
	update_display()

func on_exit() -> void:
	DebugHelper.log_info("SettingsState exiting")

func _process(delta: float) -> void:
	pulse_time += delta * 3.0

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if adjust_mode:
			handle_adjust_mode(event)
		else:
			handle_navigation(event)

func handle_navigation(event: InputEventKey) -> void:
	var char_code = event.unicode
	if event.keycode == KEY_ESCAPE:
		go_back()
		return
	if event.keycode == KEY_BACKSPACE:
		if typed_buffer.length() > 0:
			typed_buffer = typed_buffer.substr(0, typed_buffer.length() - 1)
			SoundManager.play_menu_select()
			update_display()
		return
	if (char_code >= 65 and char_code <= 90) or (char_code >= 97 and char_code <= 122):
		var typed_char = char(char_code).to_upper()
		typed_buffer += typed_char
		SoundManager.play_menu_select()
		update_display()
		check_commands()

func handle_adjust_mode(event: InputEventKey) -> void:
	var char_code = event.unicode
	if event.keycode == KEY_ENTER or event.keycode == KEY_ESCAPE:
		adjust_mode = false
		selected_option = ""
		typed_buffer = ""
		SoundManager.play_word_complete()
		update_display()
		return
	var char_str = char(char_code) if char_code > 0 else ""
	if char_str == "+" or event.keycode == KEY_UP:
		adjust_volume(selected_option, 0.1)
		SoundManager.play_menu_select()
		update_display()
	elif char_str == "-" or event.keycode == KEY_DOWN:
		adjust_volume(selected_option, -0.1)
		SoundManager.play_menu_select()
		update_display()

func adjust_volume(option: String, delta: float) -> void:
	var key = ""
	match option:
		"MASTER": key = "master_volume"
		"MUSIC": key = "music_volume"
		"SFX": key = "sfx_volume"
	if key != "":
		var current = SaveManager.get_setting(key, 1.0)
		var new_value = clamp(current + delta, 0.0, 1.0)
		SaveManager.set_setting(key, new_value)

func check_commands() -> void:
	for command in COMMANDS:
		if typed_buffer == command:
			SoundManager.play_word_complete()
			execute_command(command)
			return
	var could_match = false
	for command in COMMANDS:
		if command.begins_with(typed_buffer):
			could_match = true
			break
	if not could_match and typed_buffer.length() > 0:
		SoundManager.play_type_error()
		typed_buffer = ""
		update_display()

func execute_command(command: String) -> void:
	typed_buffer = ""
	match command:
		"RESOLUTION": cycle_resolution()
		"FULLSCREEN": toggle_fullscreen()
		"MASTER", "MUSIC", "SFX": enter_adjust_mode(command)
		"LANGUAGE": toggle_language()
		"BACK": go_back()
	update_display()

func cycle_resolution() -> void:
	var current_idx: int = int(SaveManager.get_setting("resolution_index", 0))
	var new_idx = (current_idx + 1) % SaveManager.RESOLUTIONS.size()
	SaveManager.set_setting("resolution_index", new_idx)

func toggle_fullscreen() -> void:
	var current = SaveManager.get_setting("fullscreen", false)
	SaveManager.set_setting("fullscreen", not current)

func enter_adjust_mode(option: String) -> void:
	adjust_mode = true
	selected_option = option

func toggle_language() -> void:
	var current = SaveManager.get_setting("language", "EN")
	SaveManager.set_setting("language", "DE" if current == "EN" else "EN")

func go_back() -> void:
	SoundManager.play_menu_select()
	StateManager.change_state(return_to)

func update_display() -> void:
	if typed_display:
		if adjust_mode:
			typed_display.text = selected_option + " [+/-]"
			typed_display.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
		else:
			typed_display.text = typed_buffer
			var matches_any = false
			for command in COMMANDS:
				if command.begins_with(typed_buffer) and typed_buffer.length() > 0:
					matches_any = true
					break
			if matches_any:
				typed_display.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
			elif typed_buffer.length() > 0:
				typed_display.add_theme_color_override("font_color", GameConfig.COLORS.magenta)
			else:
				typed_display.add_theme_color_override("font_color", GameConfig.COLORS.cyan)
	var settings = SaveManager.get_settings()
	update_option_with_value(resolution_prompt, "RESOLUTION", SaveManager.get_resolution_string(settings.get("resolution_index", 0)))
	update_option_with_value(fullscreen_prompt, "FULLSCREEN", "ON" if settings.get("fullscreen", false) else "OFF")
	update_option_with_value(master_prompt, "MASTER", "%d%%" % int(settings.get("master_volume", 1.0) * 100), selected_option == "MASTER")
	update_option_with_value(music_prompt, "MUSIC", "%d%%" % int(settings.get("music_volume", 0.7) * 100), selected_option == "MUSIC")
	update_option_with_value(sfx_prompt, "SFX", "%d%%" % int(settings.get("sfx_volume", 1.0) * 100), selected_option == "SFX")
	update_option_with_value(language_prompt, "LANGUAGE", settings.get("language", "EN"))
	update_menu_item(back_prompt, "BACK")
	if instructions:
		if adjust_mode:
			instructions.text = "Type + or - to adjust | ENTER to confirm"
		else:
			instructions.text = "Type command | BACKSPACE to delete | ESC to go back"

func update_menu_item(label: RichTextLabel, command: String) -> void:
	if not label:
		return
	var typed_len = typed_buffer.length()
	if adjust_mode:
		label.text = "[center][color=%s]%s[/color][/center]" % [COLOR_INACTIVE, command]
	elif typed_len == 0:
		label.text = "[center][color=%s]%s[/color][/center]" % [COLOR_OPTION, command]
	elif command.begins_with(typed_buffer):
		var typed_part = command.substr(0, typed_len)
		var remaining_part = command.substr(typed_len)
		label.text = "[center]%s[color=%s]%s[/color]%s[color=%s]%s[/color][/center]" % [TYPED_EFFECT_START, COLOR_TYPED, typed_part, TYPED_EFFECT_END, COLOR_OPTION, remaining_part]
	else:
		label.text = "[center][color=%s]%s[/color][/center]" % [COLOR_INACTIVE, command]

func update_option_with_value(label: RichTextLabel, command: String, value: String, is_adjusting: bool = false) -> void:
	if not label:
		return
	var typed_len = typed_buffer.length()
	var value_color = COLOR_VALUE if not is_adjusting else COLOR_TYPED
	if adjust_mode and not is_adjusting:
		label.text = "[center][color=%s]%s[/color]  [color=%s][%s][/color][/center]" % [COLOR_INACTIVE, command, COLOR_INACTIVE, value]
	elif adjust_mode and is_adjusting:
		label.text = "[center][color=%s]%s[/color]  [wave amp=2.0 freq=6.0][color=%s][%s][/color][/wave][/center]" % [COLOR_TYPED, command, COLOR_TYPED, value]
	elif typed_len == 0:
		label.text = "[center][color=%s]%s[/color]  [color=%s][%s][/color][/center]" % [COLOR_OPTION, command, value_color, value]
	elif command.begins_with(typed_buffer):
		var typed_part = command.substr(0, typed_len)
		var remaining_part = command.substr(typed_len)
		label.text = "[center]%s[color=%s]%s[/color]%s[color=%s]%s[/color]  [color=%s][%s][/color][/center]" % [TYPED_EFFECT_START, COLOR_TYPED, typed_part, TYPED_EFFECT_END, COLOR_OPTION, remaining_part, value_color, value]
	else:
		label.text = "[center][color=%s]%s[/color]  [color=%s][%s][/color][/center]" % [COLOR_INACTIVE, command, COLOR_INACTIVE, value]
