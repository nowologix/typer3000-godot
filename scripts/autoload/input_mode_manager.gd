## input_mode_manager.gd
## Global input mode manager - automatically switches between keyboard and mouse mode
## Hides cursor when typing, shows it when mouse moves
## Autoload singleton: InputMode
extends Node

signal mode_changed(is_keyboard_mode: bool)

var keyboard_mode: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _input(event: InputEvent) -> void:
	# Mouse movement shows cursor and exits keyboard mode
	if event is InputEventMouseMotion:
		if keyboard_mode:
			keyboard_mode = false
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			mode_changed.emit(false)
		return

	# Mouse click also exits keyboard mode
	if event is InputEventMouseButton and event.pressed:
		if keyboard_mode:
			keyboard_mode = false
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			mode_changed.emit(false)
		return

	# Keyboard input hides cursor and enters keyboard mode
	if event is InputEventKey and event.pressed and not event.is_echo():
		if not keyboard_mode:
			keyboard_mode = true
			Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
			mode_changed.emit(true)

func is_keyboard_mode() -> bool:
	return keyboard_mode

func is_mouse_mode() -> bool:
	return not keyboard_mode

func force_mouse_visible() -> void:
	keyboard_mode = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mode_changed.emit(false)

func force_mouse_hidden() -> void:
	keyboard_mode = true
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	mode_changed.emit(true)
