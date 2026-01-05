## menu_state.gd
## Main menu state - type commands to navigate
extends Control

const COMMANDS := {
	"START": "start_game",
	"VERSUS": "start_versus",
	"SETTINGS": "open_settings",
	"QUIT": "quit_game"
}

# Colors for menu display
const COLOR_TYPED := "#7cff00"      # Acid green - typed characters
const COLOR_START := "#ffffff"      # White
const COLOR_VERSUS := "#ffffff"     # White
const COLOR_SETTINGS := "#ffffff"   # White
const COLOR_QUIT := "#ffffff"       # White
const COLOR_INACTIVE := "#444455"   # Dark gray for non-matching

# Effect settings for typed characters (wave animation)
const TYPED_EFFECT_START := "[wave amp=3.0 freq=8.0]"
const TYPED_EFFECT_END := "[/wave]"

@onready var typed_display: Label = $CenterContainer/VBoxContainer/TypedDisplay
@onready var start_prompt: RichTextLabel = $CenterContainer/VBoxContainer/StartPrompt
@onready var versus_prompt: RichTextLabel = $CenterContainer/VBoxContainer/VersusPrompt
@onready var settings_prompt: RichTextLabel = $CenterContainer/VBoxContainer/SettingsPrompt
@onready var quit_prompt: RichTextLabel = $CenterContainer/VBoxContainer/QuitPrompt
@onready var video_player: VideoStreamPlayer = $VideoBackground

var typed_buffer: String = ""
var pulse_time: float = 0.0

# Menu item configuration
var menu_items: Array = []

func _ready() -> void:
	DebugHelper.log_info("MenuState ready")
	typed_buffer = ""
	update_display()
	
	# Connect video loop signal
	if video_player:
		video_player.finished.connect(_on_video_finished)

func on_enter(_params: Dictionary) -> void:
	DebugHelper.log_info("MenuState entered")
	typed_buffer = ""
	update_display()
	SoundManager.play_menu_music()
	
	# Start background video
	if video_player:
		video_player.play()

func on_exit() -> void:
	DebugHelper.log_info("MenuState exiting")

func _process(delta: float) -> void:
	# Pulse the prompts
	pulse_time += delta * 3.0
	var alpha = 0.7 + 0.3 * sin(pulse_time)
	if start_prompt:
		start_prompt.modulate.a = alpha

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

		# A-Z
		if (char_code >= 65 and char_code <= 90) or (char_code >= 97 and char_code <= 122):
			var typed_char = char(char_code).to_upper()
			typed_buffer += typed_char
			SoundManager.play_menu_select()
			update_display()
			check_commands()

func update_display() -> void:
	# Update typed display
	if typed_display:
		typed_display.text = typed_buffer

		# Check if we could match any command
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

	# Update menu item highlighting
	update_menu_item(start_prompt, "START", COLOR_START)
	update_menu_item(versus_prompt, "VERSUS", COLOR_VERSUS)
	update_menu_item(settings_prompt, "SETTINGS", COLOR_SETTINGS)
	update_menu_item(quit_prompt, "QUIT", COLOR_QUIT)

func update_menu_item(label: RichTextLabel, command: String, base_color: String) -> void:
	if not label:
		return

	var typed_len = typed_buffer.length()

	# Check if this command could still match
	if typed_len == 0:
		# Nothing typed - show in base color
		label.text = "[center][color=%s]%s[/color][/center]" % [base_color, command]
	elif command.begins_with(typed_buffer):
		# This command matches - highlight typed portion with wave effect
		var typed_part = command.substr(0, typed_len)
		var remaining_part = command.substr(typed_len)
		# Apply wave effect and white color to typed characters
		label.text = "[center]%s[color=%s]%s[/color]%s[color=%s]%s[/color][/center]" % [
			TYPED_EFFECT_START, COLOR_TYPED, typed_part, TYPED_EFFECT_END,
			base_color, remaining_part
		]
	else:
		# This command doesn't match - show inactive
		label.text = "[center][color=%s]%s[/color][/center]" % [COLOR_INACTIVE, command]

func check_commands() -> void:
	# Check for exact match
	for command in COMMANDS:
		if typed_buffer == command:
			DebugHelper.log_info("%s typed - executing command" % command)
			SoundManager.play_word_complete()
			call(COMMANDS[command])
			return

	# Check if could still match any command
	var could_match = false
	for command in COMMANDS:
		if command.begins_with(typed_buffer):
			could_match = true
			break

	if not could_match and typed_buffer.length() > 0:
		# Wrong character, reset
		SoundManager.play_type_error()
		typed_buffer = ""
		update_display()

func start_game() -> void:
	StateManager.change_state("game")

func start_versus() -> void:
	StateManager.change_state("lobby")

func open_settings() -> void:
	StateManager.change_state("settings")

func quit_game() -> void:
	DebugHelper.log_info("Quitting game")
	get_tree().quit()

func _on_video_finished() -> void:
	# Loop the video
	if video_player:
		video_player.play()
