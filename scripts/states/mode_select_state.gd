## mode_select_state.gd
## Multiplayer mode selection - VS, COOP, WORD-WAR
extends Control

# Mode display names and translation keys
const MODE_INFO := {
	"VS": {
		"name": "VS",
		"title_key": "VS",
		"desc_key": "VS_DESC",
		"color": Color(1.0, 0.3, 0.4)
	},
	"COOP": {
		"name": "COOP",
		"title_key": "COOP",
		"desc_key": "COOP_DESC",
		"color": Color(0.3, 0.9, 0.4)
	},
	"WORDWAR": {
		"name": "WORD-WAR",
		"title_key": "WORDWAR",
		"desc_key": "WORDWAR_DESC",
		"color": Color(0.4, 0.7, 1.0)
	}
}

const MODE_KEYS := ["VS", "COOP", "WORDWAR"]

var selected_index: int = 0
var typed_buffer: String = ""

@onready var title_label: Label = $VBoxContainer/Title
@onready var mode_container: HBoxContainer = $VBoxContainer/ModeContainer
@onready var typed_display: Label = $VBoxContainer/TypedDisplay
@onready var hint_label: Label = $VBoxContainer/HintLabel

# Mode column references (title + box)
var mode_columns: Array = []

func _ready() -> void:
	typed_buffer = ""
	setup_mode_columns()
	update_selection()
	update_display()
	update_ui_labels()

	# Connect language change signal
	if SignalBus.has_signal("language_changed"):
		SignalBus.language_changed.connect(_on_language_changed)

func on_enter(_params: Dictionary) -> void:
	DebugHelper.log_info("ModeSelectState entered")
	typed_buffer = ""
	selected_index = 0
	update_selection()
	update_display()

func on_exit() -> void:
	DebugHelper.log_info("ModeSelectState exiting")
	if SignalBus.has_signal("language_changed") and SignalBus.language_changed.is_connected(_on_language_changed):
		SignalBus.language_changed.disconnect(_on_language_changed)

func setup_mode_columns() -> void:
	mode_columns.clear()
	for i in range(mode_container.get_child_count()):
		var column = mode_container.get_child(i)
		if column is VBoxContainer:
			mode_columns.append(column)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		var char_code = event.unicode

		# ESC to go back to lobby
		if event.keycode == KEY_ESCAPE:
			SoundManager.play_menu_back()
			StateManager.change_state("lobby")
			return

		# Arrow keys for selection
		if event.keycode == KEY_LEFT:
			selected_index = (selected_index - 1 + MODE_KEYS.size()) % MODE_KEYS.size()
			SoundManager.play_menu_select()
			update_selection()
			return

		if event.keycode == KEY_RIGHT:
			selected_index = (selected_index + 1) % MODE_KEYS.size()
			SoundManager.play_menu_select()
			update_selection()
			return

		# Enter to confirm
		if event.keycode == KEY_ENTER:
			confirm_selection()
			return

		# Backspace
		if event.keycode == KEY_BACKSPACE:
			if typed_buffer.length() > 0:
				typed_buffer = typed_buffer.substr(0, typed_buffer.length() - 1)
				SoundManager.play_menu_select()
				update_display()
			return

		# Letters for typing mode name
		if (char_code >= 65 and char_code <= 90) or (char_code >= 97 and char_code <= 122):
			typed_buffer += char(char_code).to_upper()
			SoundManager.play_menu_select()
			update_display()
			check_typed_command()
		
		# Handle hyphen for WORD-WAR
		if char_code == 45:  # hyphen
			typed_buffer += "-"
			update_display()
			check_typed_command()

func update_selection() -> void:
	for i in range(mode_columns.size()):
		var column = mode_columns[i]
		var is_selected = i == selected_index
		var mode_color = MODE_INFO[MODE_KEYS[i]].color

		# Update title color (title is first child of column)
		var title = column.get_node_or_null("ModeTitle")
		if title:
			if is_selected:
				title.add_theme_color_override("font_color", mode_color)
			else:
				title.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))

		# Find the PanelContainer (box) in the column and style it
		for child in column.get_children():
			if child is PanelContainer:
				var style = child.get_theme_stylebox("panel")
				if style:
					style = style.duplicate()
				else:
					style = StyleBoxFlat.new()
					style.bg_color = Color(0.1, 0.1, 0.12)

				if is_selected:
					style.border_color = mode_color
					style.set_border_width_all(3)
				else:
					style.border_color = Color(0.3, 0.3, 0.35)
					style.set_border_width_all(1)
				child.add_theme_stylebox_override("panel", style)

func update_ui_labels() -> void:
	# Update title and hint
	if title_label:
		title_label.text = Tr.t("SELECT_MODE", "SELECT MODE")
	if hint_label:
		hint_label.text = Tr.t("CONFIRM_HINT", "Press ENTER to confirm or ESC to go back")

	# Update mode titles and descriptions
	for i in range(mode_columns.size()):
		var column = mode_columns[i]
		var mode_key = MODE_KEYS[i]
		var mode = MODE_INFO[mode_key]

		# Update mode title
		var title = column.get_node_or_null("ModeTitle")
		if title:
			title.text = Tr.t(mode.title_key, mode.name)

		# Find description label in box
		for child in column.get_children():
			if child is PanelContainer:
				var vbox = child.get_node_or_null("VBox")
				if vbox:
					var desc = vbox.get_node_or_null("Description")
					if desc:
						desc.text = Tr.t(mode.desc_key, "")

func _on_language_changed() -> void:
	update_ui_labels()
	update_selection()

func update_display() -> void:
	if typed_display:
		typed_display.text = typed_buffer

		# Check if matches any mode
		var matches = false
		for key in MODE_KEYS:
			var mode_name = MODE_INFO[key].name
			if mode_name.begins_with(typed_buffer) and typed_buffer.length() > 0:
				matches = true
				break

		if matches:
			typed_display.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
		elif typed_buffer.length() > 0:
			typed_display.add_theme_color_override("font_color", GameConfig.COLORS.magenta)
		else:
			typed_display.add_theme_color_override("font_color", GameConfig.COLORS.cyan)

func check_typed_command() -> void:
	# Check for exact match
	for i in range(MODE_KEYS.size()):
		var key = MODE_KEYS[i]
		if typed_buffer == MODE_INFO[key].name:
			selected_index = i
			update_selection()
			confirm_selection()
			return

	# Check if could still match
	var could_match = false
	for key in MODE_KEYS:
		if MODE_INFO[key].name.begins_with(typed_buffer):
			could_match = true
			break

	if not could_match and typed_buffer.length() > 0:
		SoundManager.play_type_error()
		typed_buffer = ""
		update_display()

func confirm_selection() -> void:
	var mode_key = MODE_KEYS[selected_index]
	var mode_data = MODE_INFO[mode_key]

	DebugHelper.log_info("Selected mode: %s" % mode_data.name)
	SoundManager.play_word_complete()
	SoundManager.play_voice_lobby_initiated()

	# Go back to lobby with selected mode and action to create lobby
	StateManager.change_state("lobby", {
		"mode": mode_key,
		"mode_name": mode_data.name,
		"mode_title": Tr.t(mode_data.title_key, mode_data.name),
		"action": "host"  # Tell lobby to create the lobby now
	})
