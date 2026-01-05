## pause_state.gd
## Pause menu - type RESUME or QUIT
extends Control

const COMMANDS := {
	"RESUME": "resume_game",
	"QUIT": "quit_to_menu"
}

@onready var typed_display: Label = $CenterContainer/VBoxContainer/TypedDisplay

var typed_buffer: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # Keep processing input while paused
	typed_buffer = ""
	update_display()
	get_tree().paused = true  # Pause the game

func on_enter(_params: Dictionary) -> void:
	DebugHelper.log_info("PauseState entered")
	typed_buffer = ""
	update_display()
	get_tree().paused = true

func on_exit() -> void:
	DebugHelper.log_info("PauseState exiting")
	get_tree().paused = false

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		var char_code = event.unicode

		# ESC to resume
		if event.keycode == KEY_ESCAPE:
			resume_game()
			return

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

func resume_game() -> void:
	DebugHelper.log_info("Resuming game")
	get_tree().paused = false
	StateManager.change_state("game")

func quit_to_menu() -> void:
	DebugHelper.log_info("Quitting to menu")
	get_tree().paused = false
	StateManager.change_state("menu")
