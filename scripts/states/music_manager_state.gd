## music_manager_state.gd
## Music Manager settings submenu - edit playlists for SURVIVAL and ZEN modes
extends Control

enum Section { SURVIVAL, ZEN }

const COLOR_NORMAL := "#ffffff"
const COLOR_SELECTED := "#7cff00"
const COLOR_INACTIVE := "#666677"
const COLOR_SECTION := "#00e5ff"
const MUSIC_ICON := "♪"
const TRACK_FONT_SIZE := 22

# Font reference
var bold_font: Font

# UI References
@onready var title_label: Label = $MarginContainer/VBoxContainer/Title
@onready var instructions: Label = $MarginContainer/VBoxContainer/Instructions

# Playlist containers
@onready var survival_container: VBoxContainer = $MarginContainer/VBoxContainer/SurvivalSection/TrackList
@onready var zen_container: VBoxContainer = $MarginContainer/VBoxContainer/ZenSection/TrackList
@onready var survival_header: RichTextLabel = $MarginContainer/VBoxContainer/SurvivalSection/Header
@onready var zen_header: RichTextLabel = $MarginContainer/VBoxContainer/ZenSection/Header

var current_section: Section = Section.SURVIVAL
var selected_track_index: int = 0
var return_to: String = "settings"

# Track item scene reference (we'll create dynamically)
var track_items_survival: Array = []
var track_items_zen: Array = []

# Currently playing track
var currently_playing_path: String = ""

# File dialog for importing custom MP3s
var file_dialog: FileDialog


func _ready() -> void:
	DebugHelper.log_info("MusicManagerState ready")
	bold_font = load("res://assets/fonts/EurostileBold.tres")
	_setup_file_dialog()
	update_display()


func _setup_file_dialog() -> void:
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = ["*.mp3 ; MP3 Audio Files"]
	file_dialog.title = "Select MP3 File"
	file_dialog.size = Vector2(800, 500)
	file_dialog.exclusive = true
	file_dialog.popup_window = true
	file_dialog.unresizable = false
	file_dialog.file_selected.connect(_on_file_selected)
	add_child(file_dialog)


func on_enter(params: Dictionary) -> void:
	DebugHelper.log_info("MusicManagerState entered")
	MenuBackground.show_background()
	SoundManager.stop_music()  # Stop background music to preview tracks
	return_to = params.get("return_to", "settings")
	current_section = Section.SURVIVAL
	selected_track_index = 0
	currently_playing_path = ""
	MusicManager.stop_preview()
	rebuild_track_lists()
	update_display()


func on_exit() -> void:
	DebugHelper.log_info("MusicManagerState exiting")
	MusicManager.stop_preview()
	currently_playing_path = ""
	SoundManager.play_menu_music()  # Restart background music


func rebuild_track_lists() -> void:
	# Clear existing
	for child in survival_container.get_children():
		child.queue_free()
	for child in zen_container.get_children():
		child.queue_free()

	track_items_survival.clear()
	track_items_zen.clear()

	# Build survival playlist
	var survival_tracks = MusicManager.get_playlist("survival")
	for i in range(survival_tracks.size()):
		var item = _create_track_item(survival_tracks[i], i, Section.SURVIVAL)
		survival_container.add_child(item)
		track_items_survival.append(item)

	# Add "ADD TRACK" button for survival
	var add_btn_survival = _create_add_button(Section.SURVIVAL)
	survival_container.add_child(add_btn_survival)
	track_items_survival.append(add_btn_survival)

	# Build zen playlist
	var zen_tracks = MusicManager.get_playlist("zen")
	for i in range(zen_tracks.size()):
		var item = _create_track_item(zen_tracks[i], i, Section.ZEN)
		zen_container.add_child(item)
		track_items_zen.append(item)

	# Add "ADD TRACK" button for zen
	var add_btn_zen = _create_add_button(Section.ZEN)
	zen_container.add_child(add_btn_zen)
	track_items_zen.append(add_btn_zen)


func _create_track_item(track_path: String, index: int, section: Section) -> HBoxContainer:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	# Track name label
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.custom_minimum_size = Vector2(400, 0)
	if bold_font:
		label.add_theme_font_override("normal_font", bold_font)
		label.add_theme_font_override("bold_font", bold_font)
	label.add_theme_font_size_override("normal_font_size", TRACK_FONT_SIZE)
	label.add_theme_font_size_override("bold_font_size", TRACK_FONT_SIZE)

	# Check track status and format label accordingly
	var track_name = MusicManager.get_track_name(track_path)
	var status = MusicManager.get_track_status(track_path)
	var is_custom = MusicManager.is_custom_track(track_path)

	if status != "":
		# Error - file missing
		label.text = "[color=#ff4444]%s %d. %s [%s][/color]" % [MUSIC_ICON, index + 1, track_name, status]
	elif is_custom:
		# Custom track indicator
		label.text = "[color=#44aaff]%s %d. %s [CUSTOM][/color]" % [MUSIC_ICON, index + 1, track_name]
	else:
		label.text = "%s %d. %s" % [MUSIC_ICON, index + 1, track_name]
	hbox.add_child(label)

	# Move Up button
	var up_btn = Button.new()
	up_btn.text = "▲"
	up_btn.custom_minimum_size = Vector2(30, 30)
	up_btn.pressed.connect(_on_move_up_pressed.bind(section, index))
	up_btn.disabled = (index == 0)
	hbox.add_child(up_btn)

	# Move Down button
	var down_btn = Button.new()
	down_btn.text = "▼"
	down_btn.custom_minimum_size = Vector2(30, 30)
	var playlist = MusicManager.get_playlist("zen" if section == Section.ZEN else "survival")
	down_btn.pressed.connect(_on_move_down_pressed.bind(section, index))
	down_btn.disabled = (index >= playlist.size() - 1)
	hbox.add_child(down_btn)

	# Play/Stop button
	var play_btn = Button.new()
	play_btn.text = "▶ PLAY"
	play_btn.custom_minimum_size = Vector2(80, 30)
	play_btn.pressed.connect(_on_play_pressed.bind(track_path, play_btn))
	play_btn.disabled = (status != "")  # Disable if file missing
	hbox.add_child(play_btn)

	# Remove button
	var remove_btn = Button.new()
	remove_btn.text = "X"
	remove_btn.custom_minimum_size = Vector2(30, 30)
	remove_btn.pressed.connect(_on_remove_pressed.bind(section, index))
	hbox.add_child(remove_btn)

	# Store metadata
	hbox.set_meta("track_path", track_path)
	hbox.set_meta("track_index", index)
	hbox.set_meta("section", section)
	hbox.set_meta("is_add_button", false)

	# Mouse interaction
	hbox.mouse_filter = Control.MOUSE_FILTER_STOP
	hbox.mouse_entered.connect(_on_track_hover.bind(section, index))
	hbox.gui_input.connect(_on_track_click.bind(section, index))
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.mouse_entered.connect(_on_track_hover.bind(section, index))

	return hbox


func _create_add_button(section: Section) -> HBoxContainer:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)

	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.custom_minimum_size = Vector2(400, 0)
	if bold_font:
		label.add_theme_font_override("normal_font", bold_font)
	label.add_theme_font_size_override("normal_font_size", TRACK_FONT_SIZE)
	label.text = "[color=%s]+ ADD TRACK[/color]" % COLOR_INACTIVE
	hbox.add_child(label)

	hbox.set_meta("is_add_button", true)
	hbox.set_meta("section", section)

	var items = track_items_zen if section == Section.ZEN else track_items_survival
	var add_index = items.size()

	hbox.mouse_filter = Control.MOUSE_FILTER_STOP
	hbox.mouse_entered.connect(_on_track_hover.bind(section, add_index))
	hbox.gui_input.connect(_on_add_track_click.bind(section))
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.mouse_entered.connect(_on_track_hover.bind(section, add_index))
	label.gui_input.connect(_on_add_track_click.bind(section))

	return hbox


func _on_track_hover(section: Section, index: int) -> void:
	if current_section != section or selected_track_index != index:
		current_section = section
		selected_track_index = index
		SoundManager.play_menu_select()
		update_display()


func _on_track_click(event: InputEvent, section: Section, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		current_section = section
		selected_track_index = index
		_preview_selected_track()


func _on_add_track_click(event: InputEvent, section: Section) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_show_add_track_menu(section)


func _on_play_pressed(track_path: String, button: Button) -> void:
	if currently_playing_path == track_path and MusicManager.is_previewing():
		# Stop current track
		MusicManager.stop_preview()
		currently_playing_path = ""
		button.text = "▶ PLAY"
	else:
		# Stop any other track and play this one
		MusicManager.preview_track(track_path)
		currently_playing_path = track_path
		SoundManager.play_word_complete()
		_update_all_play_buttons()


func _update_all_play_buttons() -> void:
	# Update all play buttons to show correct state
	# Button order: Label(0), Up(1), Down(2), Play(3), Remove(4)
	for item in track_items_survival:
		if item.get_meta("is_add_button", true):
			continue
		var btn = item.get_child(3) as Button  # Play button is 4th child
		if btn:
			var path = item.get_meta("track_path", "")
			if path == currently_playing_path and MusicManager.is_previewing():
				btn.text = "■ STOP"
			else:
				btn.text = "▶ PLAY"

	for item in track_items_zen:
		if item.get_meta("is_add_button", true):
			continue
		var btn = item.get_child(3) as Button
		if btn:
			var path = item.get_meta("track_path", "")
			if path == currently_playing_path and MusicManager.is_previewing():
				btn.text = "■ STOP"
			else:
				btn.text = "▶ PLAY"


func _on_remove_pressed(section: Section, index: int) -> void:
	var mode = "zen" if section == Section.ZEN else "survival"
	MusicManager.remove_track_from_playlist(mode, index)
	SoundManager.play_menu_select()
	rebuild_track_lists()
	update_display()


func _on_move_up_pressed(section: Section, index: int) -> void:
	var mode = "zen" if section == Section.ZEN else "survival"
	if MusicManager.move_track_up(mode, index):
		SoundManager.play_menu_select()
		selected_track_index = index - 1
		rebuild_track_lists()
		_update_all_play_buttons()
		update_display()


func _on_move_down_pressed(section: Section, index: int) -> void:
	var mode = "zen" if section == Section.ZEN else "survival"
	if MusicManager.move_track_down(mode, index):
		SoundManager.play_menu_select()
		selected_track_index = index + 1
		rebuild_track_lists()
		_update_all_play_buttons()
		update_display()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_XBUTTON1:
			go_back()
			return
		
		if event.button_index == MOUSE_BUTTON_LEFT:
			if is_back_button_area(event.position):
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
	elif keycode == KEY_TAB:
		# Switch sections
		current_section = Section.ZEN if current_section == Section.SURVIVAL else Section.SURVIVAL
		selected_track_index = 0
		SoundManager.play_menu_select()
		update_display()
	elif keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
		activate_current()
	elif keycode == KEY_DELETE or keycode == KEY_BACKSPACE:
		delete_current()
	elif keycode == KEY_ESCAPE:
		go_back()
	elif keycode == KEY_SPACE:
		_preview_selected_track()


func navigate(direction: int) -> void:
	var items = track_items_zen if current_section == Section.ZEN else track_items_survival
	if items.is_empty():
		return

	selected_track_index = (selected_track_index + direction + items.size()) % items.size()
	SoundManager.play_menu_select()
	update_display()


func activate_current() -> void:
	var items = track_items_zen if current_section == Section.ZEN else track_items_survival
	if selected_track_index >= items.size():
		return

	var item = items[selected_track_index]
	if item.get_meta("is_add_button", false):
		_show_add_track_menu(current_section)
	else:
		_preview_selected_track()


func delete_current() -> void:
	var items = track_items_zen if current_section == Section.ZEN else track_items_survival
	if selected_track_index >= items.size():
		return

	var item = items[selected_track_index]
	if item.get_meta("is_add_button", false):
		return

	var mode = "zen" if current_section == Section.ZEN else "survival"
	MusicManager.remove_track_from_playlist(mode, selected_track_index)
	SoundManager.play_menu_select()
	rebuild_track_lists()

	# Adjust selection if needed
	items = track_items_zen if current_section == Section.ZEN else track_items_survival
	if selected_track_index >= items.size():
		selected_track_index = max(0, items.size() - 1)

	update_display()


func _preview_selected_track() -> void:
	var items = track_items_zen if current_section == Section.ZEN else track_items_survival
	if selected_track_index >= items.size():
		return

	var item = items[selected_track_index]
	if item.get_meta("is_add_button", false):
		return

	var track_path = item.get_meta("track_path", "")
	if track_path != "":
		MusicManager.preview_track(track_path)
		SoundManager.play_word_complete()


func _show_add_track_menu(section: Section) -> void:
	# Store which section we're adding to
	file_dialog.set_meta("target_section", section)
	file_dialog.popup_centered()


func _on_file_selected(path: String) -> void:
	var section: Section = file_dialog.get_meta("target_section", Section.SURVIVAL)
	var mode = "zen" if section == Section.ZEN else "survival"

	# Import the MP3 file
	var result = MusicManager.import_mp3(path, mode)

	if result.success:
		DebugHelper.log_info("Successfully imported: %s" % result.imported_path)
		SoundManager.play_word_complete()
	else:
		DebugHelper.log_warning("Import failed: %s" % result.error_message)
		SoundManager.play_type_error()
		# TODO: Show error message to user in UI

	rebuild_track_lists()
	update_display()


func go_back() -> void:
	MusicManager.stop_preview()
	SoundManager.play_menu_select()
	StateManager.change_state(return_to)


func update_display() -> void:
	# Update title
	title_label.text = Tr.t("MUSIC_MANAGER", "MUSIC MANAGER")

	# Update section headers
	if current_section == Section.SURVIVAL:
		survival_header.text = "[color=%s]▼ SURVIVAL PLAYLIST[/color]" % COLOR_SELECTED
		zen_header.text = "[color=%s]▼ ZEN PLAYLIST[/color]" % COLOR_INACTIVE
	else:
		survival_header.text = "[color=%s]▼ SURVIVAL PLAYLIST[/color]" % COLOR_INACTIVE
		zen_header.text = "[color=%s]▼ ZEN PLAYLIST[/color]" % COLOR_SELECTED

	# Update track items
	_update_track_list_display(track_items_survival, Section.SURVIVAL)
	_update_track_list_display(track_items_zen, Section.ZEN)

	# Update instructions
	var lang = SaveManager.get_setting("language", "EN")
	if lang == "DE":
		instructions.text = "[< ZURÜCK]  ↑↓ Navigieren | TAB Wechseln | ENTER Abspielen | ENTF Löschen"
	else:
		instructions.text = "[< BACK]  ↑↓ Navigate | TAB Switch | ENTER Play | DEL Remove"

func is_back_button_area(pos: Vector2) -> bool:
	return pos.x < 120 and pos.y > GameConfig.SCREEN_HEIGHT - 60


func _update_track_list_display(items: Array, section: Section) -> void:
	for i in range(items.size()):
		var item = items[i]
		var label = item.get_child(0) as RichTextLabel
		if not label:
			continue

		var is_selected = (section == current_section and i == selected_track_index)
		var is_add_button = item.get_meta("is_add_button", false)

		if is_add_button:
			if is_selected:
				label.text = "[color=%s]+ ADD TRACK  ◄[/color]" % COLOR_SELECTED
			else:
				label.text = "[color=%s]+ ADD TRACK[/color]" % COLOR_INACTIVE
		else:
			var track_path = item.get_meta("track_path", "")
			var track_name = MusicManager.get_track_name(track_path)
			var track_idx = item.get_meta("track_index", 0)
			var status = MusicManager.get_track_status(track_path)
			var is_custom = MusicManager.is_custom_track(track_path)

			var suffix = ""
			if status != "":
				suffix = " [%s]" % status
			elif is_custom:
				suffix = " [CUSTOM]"

			var color: String
			if status != "":
				color = "#ff4444"  # Error color
			elif is_selected:
				color = COLOR_SELECTED
			elif is_custom:
				color = "#44aaff"  # Custom track color
			elif section == current_section:
				color = COLOR_NORMAL
			else:
				color = COLOR_INACTIVE

			var arrow = "  ◄" if is_selected else ""
			label.text = "[color=%s]%s %d. %s%s%s[/color]" % [color, MUSIC_ICON, track_idx + 1, track_name, suffix, arrow]
