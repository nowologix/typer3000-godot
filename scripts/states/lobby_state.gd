## lobby_state.gd
## Multiplayer lobby - create or join games
extends Control

# Command keys for translation lookup
const COMMAND_KEYS := {
	"HOST": "create_lobby",
	"JOIN": "start_join_mode",
	"READY": "toggle_ready",
	"START": "start_game",
	"INVITE": "invite_friend",
	"SETTINGS": "open_settings",
	"BACK": "go_back"
}

# Dynamic commands rebuilt on language change
var commands := {}

@onready var typed_display: Label = $CenterContainer/VBoxContainer/TypedDisplay
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var players_label: Label = $CenterContainer/VBoxContainer/PlayersLabel
@onready var code_label: Label = $CenterContainer/VBoxContainer/CodeLabel
@onready var host_prompt: Label = $CenterContainer/VBoxContainer/HostPrompt
@onready var join_prompt: Label = $CenterContainer/VBoxContainer/JoinPrompt
@onready var ready_prompt: Label = $CenterContainer/VBoxContainer/ReadyPrompt
@onready var start_prompt: Label = $CenterContainer/VBoxContainer/StartPrompt
@onready var settings_prompt: Label = $CenterContainer/VBoxContainer/SettingsPrompt
@onready var invite_prompt: Label = $CenterContainer/VBoxContainer/InvitePrompt
@onready var copy_prompt: Label = $CenterContainer/VBoxContainer/CopyPrompt
@onready var mode_title: Label = $CenterContainer/VBoxContainer/ModeTitle
@onready var paste_hint: Label = $CenterContainer/VBoxContainer/PasteHint

var typed_buffer: String = ""
var current_mode: String = ""
var current_mode_title: String = ""
var join_mode: bool = false
var lobby_code_buffer: String = ""
var is_ready: bool = false
var ctrl_held: bool = false

func _ready() -> void:
	typed_buffer = ""
	rebuild_commands()
	update_display()

	# Connect language change signal
	if SignalBus.has_signal("language_changed"):
		SignalBus.language_changed.connect(_on_language_changed)

	# Connect network signals
	SignalBus.network_connected.connect(_on_network_connected)
	SignalBus.network_disconnected.connect(_on_network_disconnected)
	SignalBus.lobby_created.connect(_on_lobby_created)
	SignalBus.lobby_joined.connect(_on_lobby_joined)
	SignalBus.lobby_join_failed.connect(_on_lobby_join_failed)
	SignalBus.player_joined.connect(_on_player_joined)
	SignalBus.player_left.connect(_on_player_left)
	SignalBus.player_ready_changed.connect(_on_player_ready_changed)
	SignalBus.network_game_start.connect(_on_game_start)

func on_enter(params: Dictionary) -> void:
	DebugHelper.log_info("LobbyState entered")
	typed_buffer = ""
	join_mode = false
	lobby_code_buffer = ""
	is_ready = false

	# Store mode info from mode select (if coming from HOST flow)
	current_mode = params.get("mode", "")
	current_mode_title = params.get("mode_title", "")
	update_mode_display()

	update_display()
	update_status()
	update_prompts()

	# If returning from mode_select with action="host", create lobby now
	if params.get("action", "") == "host" and current_mode != "":
		DebugHelper.log_info("Creating lobby for mode: %s" % current_mode)
		call_deferred("create_lobby")

	# Show message if passed (e.g., from disconnect)
	if params.has("message") and status_label:
		status_label.text = params.message
		status_label.add_theme_color_override("font_color", GameConfig.COLORS.magenta)

func on_exit() -> void:
	DebugHelper.log_info("LobbyState exiting")

	# Disconnect language signal
	if SignalBus.has_signal("language_changed") and SignalBus.language_changed.is_connected(_on_language_changed):
		SignalBus.language_changed.disconnect(_on_language_changed)

	# Disconnect signals
	if SignalBus.network_connected.is_connected(_on_network_connected):
		SignalBus.network_connected.disconnect(_on_network_connected)
	if SignalBus.network_disconnected.is_connected(_on_network_disconnected):
		SignalBus.network_disconnected.disconnect(_on_network_disconnected)
	if SignalBus.lobby_created.is_connected(_on_lobby_created):
		SignalBus.lobby_created.disconnect(_on_lobby_created)
	if SignalBus.lobby_joined.is_connected(_on_lobby_joined):
		SignalBus.lobby_joined.disconnect(_on_lobby_joined)
	if SignalBus.lobby_join_failed.is_connected(_on_lobby_join_failed):
		SignalBus.lobby_join_failed.disconnect(_on_lobby_join_failed)
	if SignalBus.player_joined.is_connected(_on_player_joined):
		SignalBus.player_joined.disconnect(_on_player_joined)
	if SignalBus.player_left.is_connected(_on_player_left):
		SignalBus.player_left.disconnect(_on_player_left)
	if SignalBus.player_ready_changed.is_connected(_on_player_ready_changed):
		SignalBus.player_ready_changed.disconnect(_on_player_ready_changed)
	if SignalBus.network_game_start.is_connected(_on_game_start):
		SignalBus.network_game_start.disconnect(_on_game_start)

func _input(event: InputEvent) -> void:
	# Track CTRL/STRG key state for display
	if event is InputEventKey:
		if event.keycode == KEY_CTRL:
			ctrl_held = event.pressed
			update_display()
	
	if event is InputEventKey and event.pressed and not event.is_echo():
		var char_code = event.unicode

		# STRG+C to copy lobby code
		if event.keycode == KEY_C and event.ctrl_pressed and NetworkManager.is_in_lobby():
			copy_lobby_code()
			return

		if event.keycode == KEY_ESCAPE:
			if join_mode:
				join_mode = false
				lobby_code_buffer = ""
				update_display()
				update_paste_hint()
			else:
				go_back()
			return

		# CTRL+V to paste lobby code
		if event.keycode == KEY_V and event.ctrl_pressed and join_mode:
			paste_lobby_code()
			return

		if event.keycode == KEY_BACKSPACE:
			if join_mode:
				if lobby_code_buffer.length() > 0:
					lobby_code_buffer = lobby_code_buffer.substr(0, lobby_code_buffer.length() - 1)
			else:
				if typed_buffer.length() > 0:
					typed_buffer = typed_buffer.substr(0, typed_buffer.length() - 1)
			update_display()
			return

		if event.keycode == KEY_ENTER and join_mode:
			if lobby_code_buffer.length() == 6:
				join_lobby_with_code()
			return

		# Check for letters (A-Z, a-z)
		var is_letter = (char_code >= 65 and char_code <= 90) or (char_code >= 97 and char_code <= 122)
		# Check for numbers (0-9)
		var is_number = char_code >= 48 and char_code <= 57

		if join_mode:
			# In join mode, accept both letters and numbers for lobby code
			if is_letter or is_number:
				var typed_char = char(char_code).to_upper()
				if lobby_code_buffer.length() < 6:
					lobby_code_buffer += typed_char
					update_display()
					if lobby_code_buffer.length() == 6:
						join_lobby_with_code()
		else:
			# In command mode, only accept letters
			if is_letter:
				var char_upper = char(char_code).to_upper()
				typed_buffer += char_upper
				update_display()
				check_commands()

func update_display() -> void:
	if typed_display:
		if join_mode:
			var prefix = "STRG+" if ctrl_held else ""
			typed_display.text = prefix + "CODE: " + lobby_code_buffer + "_".repeat(6 - lobby_code_buffer.length())
		else:
			var prefix = "STRG+" if ctrl_held else ""
			typed_display.text = prefix + typed_buffer


func check_commands() -> void:
	for command in commands:
		if typed_buffer == command:
			call(commands[command])
			typed_buffer = ""
			update_display()
			return

	var could_match = false
	for command in commands:
		if command.begins_with(typed_buffer):
			could_match = true
			break

	if not could_match and typed_buffer.length() > 0:
		typed_buffer = ""
		update_display()

func rebuild_commands() -> void:
	commands.clear()
	for key in COMMAND_KEYS:
		var translated = Tr.t(key, key)
		commands[translated] = COMMAND_KEYS[key]

func _on_language_changed() -> void:
	rebuild_commands()
	update_display()
	update_status()
	update_prompts()


func update_paste_hint() -> void:
	if paste_hint:
		paste_hint.visible = join_mode

func update_mode_display() -> void:
	if mode_title:
		if current_mode_title != "":
			mode_title.text = Tr.t("MODE", "Mode:") + " " + current_mode_title
			mode_title.visible = true
		else:
			mode_title.visible = false

func update_status() -> void:
	if status_label:
		if NetworkManager.is_in_lobby():
			status_label.text = Tr.t("IN_LOBBY", "In Lobby")
			status_label.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
		elif NetworkManager.is_network_connected():
			status_label.text = Tr.t("CONNECTING", "Connecting to server...")
			status_label.add_theme_color_override("font_color", GameConfig.COLORS.cyan)
		else:
			status_label.text = ""

	if code_label:
		if NetworkManager.lobby_code != "":
			code_label.text = "Lobby Code: " + NetworkManager.lobby_code
			code_label.visible = true
		else:
			code_label.visible = false

	if players_label:
		if NetworkManager.is_in_lobby():
			var player_list = Tr.t("PLAYERS", "Players:") + "\n"
			var my_status = ""
			if NetworkManager.is_host:
				my_status += " [HOST]"
			if is_ready:
				my_status += " [" + Tr.t("READY", "READY") + "]"
			player_list += "- %s (You)%s\n" % [NetworkManager.player_name, my_status]
			for pid in NetworkManager.players:
				var p = NetworkManager.players[pid]
				player_list += "- %s%s\n" % [p.name, " [" + Tr.t("READY", "READY") + "]" if p.ready else ""]
			players_label.text = player_list
			players_label.visible = true
		else:
			players_label.visible = false

func update_prompts() -> void:
	var in_lobby = NetworkManager.is_in_lobby()
	var is_host = NetworkManager.is_host
	
	# Before joining lobby: show HOST, JOIN
	# After joining (client): show READY
	# After joining (host): show START, INVITE, COPY
	if host_prompt:
		host_prompt.visible = not in_lobby
	if join_prompt:
		join_prompt.visible = not in_lobby
	if ready_prompt:
		ready_prompt.visible = in_lobby and not is_host
	if start_prompt:
		start_prompt.visible = in_lobby and is_host
	if invite_prompt:
		invite_prompt.visible = in_lobby and is_host
	if copy_prompt:
		copy_prompt.visible = in_lobby and is_host

# ============================================
# Command Handlers
# ============================================

func create_lobby() -> void:
	# If we don't have a mode yet, go to mode select first
	if current_mode == "":
		DebugHelper.log_info("No mode selected, going to mode select...")
		StateManager.change_state("mode_select", {"from": "lobby"})
		return

	# We have a mode, create the lobby
	DebugHelper.log_info("Creating lobby for mode: %s" % current_mode)
	if status_label:
		status_label.text = Tr.t("CONNECTING", "Connecting to server...")
		status_label.add_theme_color_override("font_color", GameConfig.COLORS.amber)

	# Disable input while connecting
	set_process_input(false)
	await NetworkManager.create_lobby()
	set_process_input(true)

	if not NetworkManager.is_in_lobby():
		if status_label:
			status_label.text = Tr.t("LOBBY_FAILED", "Failed to create lobby. Server unreachable?")
			status_label.add_theme_color_override("font_color", GameConfig.COLORS.magenta)

func start_join_mode() -> void:
	join_mode = true
	lobby_code_buffer = ""
	update_display()
	update_paste_hint()
	DebugHelper.log_info("Enter 6-character lobby code - CTRL+V to paste")

func join_lobby_with_code() -> void:
	var code = lobby_code_buffer.to_upper()
	DebugHelper.log_info("Joining lobby: %s" % code)
	if status_label:
		status_label.text = "Joining lobby %s..." % code
	NetworkManager.join_lobby(code)
	join_mode = false

func toggle_ready() -> void:
	if not NetworkManager.is_in_lobby():
		return
	is_ready = not is_ready
	NetworkManager.set_ready(is_ready)
	DebugHelper.log_info("Ready: %s" % is_ready)

func start_game() -> void:
	if not NetworkManager.is_host:
		DebugHelper.log_warning("Only host can start the game")
		return
	NetworkManager.start_game(current_mode)

func invite_friend() -> void:
	# Placeholder for Steam Friends invite
	DebugHelper.log_info("Steam Friends invite - not yet implemented")
	if status_label:
		status_label.text = Tr.t("STEAM_INVITE_SOON", "Steam invite coming soon!")
		status_label.add_theme_color_override("font_color", GameConfig.COLORS.amber)

func copy_lobby_code() -> void:
	if NetworkManager.lobby_code != "":
		DisplayServer.clipboard_set(NetworkManager.lobby_code)
		DebugHelper.log_info("Lobby code copied: %s" % NetworkManager.lobby_code)
		if status_label:
			status_label.text = Tr.t("CODE_COPIED", "Code copied:") + " " + NetworkManager.lobby_code
			status_label.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
		SoundManager.play_word_complete()


func paste_lobby_code() -> void:
	var clipboard = DisplayServer.clipboard_get()
	# Clean the clipboard - only keep alphanumeric chars
	var clean_code = ""
	for c in clipboard.to_upper():
		if (c >= "A" and c <= "Z") or (c >= "0" and c <= "9"):
			clean_code += c
	
	if clean_code.length() > 0:
		lobby_code_buffer = clean_code.substr(0, 6)
		SoundManager.play_menu_select()
		update_display()
		if lobby_code_buffer.length() == 6:
			join_lobby_with_code()

func open_settings() -> void:
	StateManager.change_state("settings", {"return_to": "lobby"})

func go_back() -> void:
	if NetworkManager.is_in_lobby():
		NetworkManager.leave_lobby()
	NetworkManager.disconnect_from_relay()
	StateManager.change_state("menu")

# ============================================
# Network Signal Handlers
# ============================================

func _on_network_connected() -> void:
	DebugHelper.log_info("Connected to relay server")
	update_status()

func _on_network_disconnected(reason: String) -> void:
	DebugHelper.log_warning("Disconnected: %s" % reason)
	update_status()

func _on_lobby_created(code: String) -> void:
	DebugHelper.log_info("Lobby created: %s" % code)
	update_status()
	update_display()
	update_prompts()

func _on_lobby_joined(code: String) -> void:
	DebugHelper.log_info("Joined lobby: %s" % code)
	update_status()
	update_display()
	update_prompts()

func _on_lobby_join_failed(reason: String) -> void:
	DebugHelper.log_error("Join failed: %s" % reason)
	if status_label:
		status_label.text = Tr.t("JOIN_FAILED", "Join failed:") + " " + reason
		status_label.add_theme_color_override("font_color", GameConfig.COLORS.magenta)
	join_mode = false
	lobby_code_buffer = ""
	update_display()
	update_prompts()

func _on_player_joined(player_id: int, player_name: String) -> void:
	DebugHelper.log_info("Player joined: %s" % player_name)
	update_status()

func _on_player_left(player_id: int) -> void:
	DebugHelper.log_info("Player left: %d" % player_id)
	update_status()

func _on_player_ready_changed(player_id: int, ready: bool) -> void:
	DebugHelper.log_info("Player %d ready: %s" % [player_id, ready])
	update_status()

func _on_game_start(seed: int, mode: String) -> void:
	# Use mode from network if available (important for client!)
	var game_mode = mode if mode != "" else current_mode
	DebugHelper.log_info("Game starting with seed: %d, mode: %s" % [seed, game_mode])
	SoundManager.play_match_found()

	var game_params = {
		"seed": seed,
		"multiplayer": true,
		"mode": game_mode,
		"mode_title": current_mode_title
	}

	# Route to correct game state based on mode
	match game_mode:
		"VS":
			StateManager.change_state("vs_battle", game_params)
		"COOP":
			StateManager.change_state("coop_game", game_params)
		"WORDWAR", _:
			StateManager.change_state("wordwar", game_params)
