## settings_state.gd
## Settings menu state - classic layout with sliders, dropdowns, and keyboard/mouse support
extends Control

enum MenuItem { RESOLUTION, FULLSCREEN, MASTER, MUSIC, SFX, LANGUAGE, MUSIC_MANAGER, BACK }

const MENU_ITEMS := ["RESOLUTION", "FULLSCREEN", "MASTER", "MUSIC", "SFX", "LANGUAGE", "MUSIC MANAGER", "BACK"]
const MENU_ITEMS_DE := ["AUFLÖSUNG", "VOLLBILD", "MASTER", "MUSIK", "EFFEKTE", "SPRACHE", "MUSIKMANAGER", "ZURÜCK"]

const COLOR_NORMAL := "#ffffff"
const COLOR_SELECTED := "#7cff00"
const COLOR_INACTIVE := "#666677"

# UI References
@onready var title_label: Label = $MarginContainer/VBoxContainer/Title
@onready var typed_display: Label = $MarginContainer/VBoxContainer/TypedDisplay
@onready var instructions: Label = $MarginContainer/VBoxContainer/Instructions

# Row references
@onready var resolution_row: HBoxContainer = $MarginContainer/VBoxContainer/ResolutionRow
@onready var fullscreen_row: HBoxContainer = $MarginContainer/VBoxContainer/FullscreenRow
@onready var master_row: HBoxContainer = $MarginContainer/VBoxContainer/MasterRow
@onready var music_row: HBoxContainer = $MarginContainer/VBoxContainer/MusicRow
@onready var sfx_row: HBoxContainer = $MarginContainer/VBoxContainer/SfxRow
@onready var language_row: HBoxContainer = $MarginContainer/VBoxContainer/LanguageRow
@onready var music_manager_row: HBoxContainer = $MarginContainer/VBoxContainer/MusicManagerRow
@onready var back_row: HBoxContainer = $MarginContainer/VBoxContainer/BackRow

# Control references
@onready var resolution_dropdown: OptionButton = $MarginContainer/VBoxContainer/ResolutionRow/OptionButton
@onready var fullscreen_check: CheckButton = $MarginContainer/VBoxContainer/FullscreenRow/CheckButton
@onready var master_slider: HSlider = $MarginContainer/VBoxContainer/MasterRow/HSlider
@onready var master_value: Label = $MarginContainer/VBoxContainer/MasterRow/Value
@onready var music_slider: HSlider = $MarginContainer/VBoxContainer/MusicRow/HSlider
@onready var music_value: Label = $MarginContainer/VBoxContainer/MusicRow/Value
@onready var sfx_slider: HSlider = $MarginContainer/VBoxContainer/SfxRow/HSlider
@onready var sfx_value: Label = $MarginContainer/VBoxContainer/SfxRow/Value
@onready var language_dropdown: OptionButton = $MarginContainer/VBoxContainer/LanguageRow/OptionButton

var rows: Array[HBoxContainer] = []
var selected_index: int = 0
var typed_buffer: String = ""
var return_to: String = "menu"

const RESOLUTION_LABELS := ["720p", "Laptop", "900p", "1080p", "UW-1080", "1440p", "UW-1440", "UW-1600", "4K"]
const LANGUAGE_NAMES := {"EN": "English", "DE": "Deutsch"}

func _ready() -> void:
	DebugHelper.log_info("SettingsState ready")
	rows = [resolution_row, fullscreen_row, master_row, music_row, sfx_row, language_row, music_manager_row, back_row]
	setup_controls()
	connect_signals()
	load_settings()
	update_display()

func on_enter(params: Dictionary) -> void:
	DebugHelper.log_info("SettingsState entered")
	MenuBackground.show_background()
	return_to = params.get("return_to", "menu")
	typed_buffer = ""
	selected_index = 0
	load_settings()
	update_display()

func on_exit() -> void:
	DebugHelper.log_info("SettingsState exiting")

func setup_controls() -> void:
	# Setup resolution dropdown
	resolution_dropdown.clear()
	for i in range(SaveManager.RESOLUTIONS.size()):
		var res = SaveManager.RESOLUTIONS[i]
		var label = RESOLUTION_LABELS[i] if i < RESOLUTION_LABELS.size() else ""
		resolution_dropdown.add_item("%dx%d  %s" % [res.x, res.y, label], i)

	# Setup language dropdown
	language_dropdown.clear()
	var languages = WordSetLoader.get_available_languages()
	for i in range(languages.size()):
		var lang = languages[i]
		var display_name = LANGUAGE_NAMES.get(lang, lang)
		language_dropdown.add_item(display_name, i)
		language_dropdown.set_item_metadata(i, lang)  # Store actual lang code

	# Setup sliders
	master_slider.min_value = 0
	master_slider.max_value = 100
	master_slider.step = 5

	music_slider.min_value = 0
	music_slider.max_value = 100
	music_slider.step = 5

	sfx_slider.min_value = 0
	sfx_slider.max_value = 100
	sfx_slider.step = 5

func connect_signals() -> void:
	resolution_dropdown.item_selected.connect(_on_resolution_selected)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	master_slider.value_changed.connect(_on_master_changed)
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	language_dropdown.item_selected.connect(_on_language_selected)

	# Mouse hover for rows
	for i in range(rows.size()):
		var row = rows[i]
		row.mouse_entered.connect(_on_row_hover.bind(i))
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		# Make label clickable too
		var label = row.get_node("Label") as RichTextLabel
		if label:
			label.mouse_filter = Control.MOUSE_FILTER_STOP
			label.mouse_entered.connect(_on_row_hover.bind(i))
			label.gui_input.connect(_on_label_click.bind(i))

func _on_row_hover(index: int) -> void:
	if selected_index != index:
		selected_index = index
		SoundManager.play_menu_select()
		update_display()

func _on_label_click(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_index = index
		activate_current()

func load_settings() -> void:
	var settings = SaveManager.get_settings()

	resolution_dropdown.select(settings.get("resolution_index", 0))
	fullscreen_check.button_pressed = settings.get("fullscreen", false)

	master_slider.value = settings.get("master_volume", 1.0) * 100
	music_slider.value = settings.get("music_volume", 0.7) * 100
	sfx_slider.value = settings.get("sfx_volume", 1.0) * 100

	var lang = settings.get("language", "EN")
	for i in range(language_dropdown.item_count):
		if language_dropdown.get_item_metadata(i) == lang:
			language_dropdown.select(i)
			break

	update_value_labels()

func update_value_labels() -> void:
	master_value.text = "%d%%" % int(master_slider.value)
	music_value.text = "%d%%" % int(music_slider.value)
	sfx_value.text = "%d%%" % int(sfx_slider.value)

func _on_resolution_selected(index: int) -> void:
	SaveManager.set_setting("resolution_index", index)
	SoundManager.play_word_complete()

func _on_fullscreen_toggled(pressed: bool) -> void:
	SaveManager.set_setting("fullscreen", pressed)
	SoundManager.play_word_complete()

func _on_master_changed(value: float) -> void:
	SaveManager.set_setting("master_volume", value / 100.0)
	update_value_labels()

func _on_music_changed(value: float) -> void:
	SaveManager.set_setting("music_volume", value / 100.0)
	update_value_labels()

func _on_sfx_changed(value: float) -> void:
	SaveManager.set_setting("sfx_volume", value / 100.0)
	update_value_labels()

func _on_language_selected(index: int) -> void:
	var lang = language_dropdown.get_item_metadata(index)
	if lang == null or lang == "":
		lang = "EN"
	WordSetLoader.set_language_string(lang)
	AphorismLoader.set_language_string(lang)
	SaveManager.set_setting("language", lang)
	Tr.set_language(lang)
	SignalBus.language_changed.emit()
	SoundManager.play_word_complete()
	update_display()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_XBUTTON1:
			go_back()
			return

	if event is InputEventKey and event.pressed and not event.is_echo():
		handle_key_input(event)

func handle_key_input(event: InputEventKey) -> void:
	var keycode = event.keycode

	# Navigation
	if keycode == KEY_UP:
		navigate(-1)
	elif keycode == KEY_DOWN:
		navigate(1)
	elif keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
		activate_current()
	elif keycode == KEY_ESCAPE:
		go_back()

	# Adjust values with +/- or left/right
	if keycode == KEY_LEFT or event.unicode == 45:  # 45 = '-'
		adjust_current(-1)
	elif keycode == KEY_RIGHT or event.unicode == 43:  # 43 = '+'
		adjust_current(1)

	# Typing support
	var char_code = event.unicode
	if keycode == KEY_BACKSPACE:
		if typed_buffer.length() > 0:
			typed_buffer = typed_buffer.substr(0, typed_buffer.length() - 1)
			SoundManager.play_menu_select()
			update_display()

	# Accept A-Z, a-z, and German umlauts
	var is_letter = (char_code >= 65 and char_code <= 90) or (char_code >= 97 and char_code <= 122)
	var is_umlaut = char_code in [196, 214, 220, 228, 246, 252]  # ÄÖÜäöü
	if is_letter or is_umlaut:
		var typed_char = char(char_code).to_upper()
		typed_buffer += typed_char
		SoundManager.play_menu_select()
		check_typed_command()
		update_display()

func navigate(direction: int) -> void:
	selected_index = (selected_index + direction + rows.size()) % rows.size()
	typed_buffer = ""
	SoundManager.play_menu_select()
	update_display()

func activate_current() -> void:
	match selected_index:
		MenuItem.RESOLUTION:
			resolution_dropdown.grab_focus()
			resolution_dropdown.show_popup()
		MenuItem.FULLSCREEN:
			fullscreen_check.button_pressed = not fullscreen_check.button_pressed
		MenuItem.MASTER:
			master_slider.grab_focus()
		MenuItem.MUSIC:
			music_slider.grab_focus()
		MenuItem.SFX:
			sfx_slider.grab_focus()
		MenuItem.LANGUAGE:
			language_dropdown.grab_focus()
			language_dropdown.show_popup()
		MenuItem.MUSIC_MANAGER:
			StateManager.change_state("music_manager", {"return_to": "settings"})
		MenuItem.BACK:
			go_back()

func adjust_current(direction: int) -> void:
	var step := 5.0
	match selected_index:
		MenuItem.RESOLUTION:
			var new_idx = (resolution_dropdown.selected + direction + resolution_dropdown.item_count) % resolution_dropdown.item_count
			resolution_dropdown.select(new_idx)
			_on_resolution_selected(new_idx)
		MenuItem.FULLSCREEN:
			fullscreen_check.button_pressed = not fullscreen_check.button_pressed
		MenuItem.MASTER:
			master_slider.value = clamp(master_slider.value + direction * step, 0, 100)
			SoundManager.play_menu_select()
		MenuItem.MUSIC:
			music_slider.value = clamp(music_slider.value + direction * step, 0, 100)
			SoundManager.play_menu_select()
		MenuItem.SFX:
			sfx_slider.value = clamp(sfx_slider.value + direction * step, 0, 100)
			SoundManager.play_menu_select()
		MenuItem.LANGUAGE:
			if language_dropdown.item_count > 0:
				var current_idx = language_dropdown.selected if language_dropdown.selected >= 0 else 0
				var new_idx = (current_idx + direction + language_dropdown.item_count) % language_dropdown.item_count
				language_dropdown.select(new_idx)
				_on_language_selected(new_idx)

func check_typed_command() -> void:
	var lang = SaveManager.get_setting("language", "EN")
	var commands = MENU_ITEMS_DE if lang == "DE" else MENU_ITEMS

	for i in range(commands.size()):
		if typed_buffer == commands[i]:
			SoundManager.play_word_complete()
			selected_index = i
			typed_buffer = ""
			if i == MenuItem.BACK:
				go_back()
			else:
				activate_current()
			return

	# Check if buffer could still match
	var could_match = false
	for command in commands:
		if command.begins_with(typed_buffer):
			could_match = true
			break

	if not could_match and typed_buffer.length() > 0:
		SoundManager.play_type_error()
		typed_buffer = ""

func go_back() -> void:
	SoundManager.play_menu_select()
	StateManager.change_state(return_to)

func update_display() -> void:
	var lang = SaveManager.get_setting("language", "EN")
	var commands = MENU_ITEMS_DE if lang == "DE" else MENU_ITEMS

	# Update title
	title_label.text = Tr.t("SETTINGS", "SETTINGS")

	# Update row labels with selection highlighting
	for i in range(rows.size()):
		var row = rows[i]
		var label = row.get_node("Label") as RichTextLabel
		if not label:
			continue

		var command_name = commands[i]
		var is_selected = (i == selected_index)
		var typed_len = typed_buffer.length()

		if is_selected:
			# Highlight selected row
			if typed_len > 0 and command_name.begins_with(typed_buffer):
				var typed_part = command_name.substr(0, typed_len)
				var remaining = command_name.substr(typed_len)
				label.text = "[color=%s]%s[/color][color=%s]%s[/color]  ◄" % [COLOR_SELECTED, typed_part, COLOR_NORMAL, remaining]
			else:
				label.text = "[color=%s]%s[/color]  ◄" % [COLOR_SELECTED, command_name]
		else:
			# Non-selected rows
			if typed_len > 0 and command_name.begins_with(typed_buffer):
				var typed_part = command_name.substr(0, typed_len)
				var remaining = command_name.substr(typed_len)
				label.text = "[color=%s]%s[/color][color=%s]%s[/color]" % [COLOR_SELECTED, typed_part, COLOR_INACTIVE, remaining]
			elif typed_len > 0:
				label.text = "[color=%s]%s[/color]" % [COLOR_INACTIVE, command_name]
			else:
				label.text = "[color=%s]%s[/color]" % [COLOR_NORMAL, command_name]

	# Update typed display
	if typed_display:
		typed_display.text = typed_buffer

	# Update instructions
	if instructions:
		if lang == "DE":
			instructions.text = "Pfeiltasten navigieren | Enter auswählen | +/- anpassen | ESC zurück"
		else:
			instructions.text = "Arrow keys to navigate | Enter to select | +/- to adjust | ESC to go back"
