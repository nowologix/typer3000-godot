## lobby_state.gd
## Multiplayer lobby - create or join games
extends Control

const COMMANDS := {
	"HOST": "create_lobby",
	"JOIN": "start_join_mode",
	"READY": "toggle_ready",
	"START": "start_game",
	"SETTINGS": "open_settings",
	"BACK": "go_back"
}

@onready var typed_display: Label = $CenterContainer/VBoxContainer/TypedDisplay
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var players_label: Label = $CenterContainer/VBoxContainer/PlayersLabel
@onready var code_label: Label = $CenterContainer/VBoxContainer/CodeLabel
@onready var host_prompt: Label = $CenterContainer/VBoxContainer/HostPrompt
@onready var join_prompt: Label = $CenterContainer/VBoxContainer/JoinPrompt
@onready var ready_prompt: Label = $CenterContainer/VBoxContainer/ReadyPrompt
@onready var start_prompt: Label = $CenterContainer/VBoxContainer/StartPrompt
@onready var settings_prompt: Label = $CenterContainer/VBoxContainer/SettingsPrompt


var typed_buffer: String = ""
var join_mode: bool = false
var lobby_code_buffer: String = ""
var is_ready: bool = false

func _ready() -> void:
	typed_buffer = ""
	update_display()

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
	update_display()
	update_status()
	update_prompts()

	# Show message if passed (e.g., from disconnect)
	if params.has("message") and status_label:
		status_label.text = params.message
		status_label.add_theme_color_override("font_color", GameConfig.COLORS.magenta)

func on_exit() -> void:
	DebugHelper.log_info("LobbyState exiting")

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
	if event is InputEventKey and event.pressed and not event.is_echo():
		var char_code = event.unicode

		if event.keycode == KEY_ESCAPE:
			if join_mode:
				join_mode = false
				lobby_code_buffer = ""
				update_display()
			else:
				go_back()
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
			typed_display.text = "CODE: " + lobby_code_buffer + "_".repeat(6 - lobby_code_buffer.length())
		else:
			typed_display.text = typed_buffer


func check_commands() -> void:
	for command in COMMANDS:
		if typed_buffer == command:
			call(COMMANDS[command])
			typed_buffer = ""
			update_display()
			return

	var could_match = false
	for command in COMMANDS:
		if command.begins_with(typed_buffer):
			could_match = true
			break

	if not could_match and typed_buffer.length() > 0:
		typed_buffer = ""
		update_display()

func update_status() -> void:
	if status_label:
		if NetworkManager.is_in_lobby():
			status_label.text = "In Lobby"
			status_label.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
		elif NetworkManager.is_network_connected():
			status_label.text = "Connected to Server"
			status_label.add_theme_color_override("font_color", GameConfig.COLORS.cyan)
		else:
			status_label.text = "Disconnected"
			status_label.add_theme_color_override("font_color", GameConfig.COLORS.magenta)

	if code_label:
		if NetworkManager.lobby_code != "":
			code_label.text = "Lobby Code: " + NetworkManager.lobby_code
			code_label.visible = true
		else:
			code_label.visible = false

	if players_label:
		if NetworkManager.is_in_lobby():
			var player_list = "Players:\n"
			var my_status = ""
			if NetworkManager.is_host:
				my_status += " [HOST]"
			if is_ready:
				my_status += " [READY]"
			player_list += "- %s (You)%s\n" % [NetworkManager.player_name, my_status]
			for pid in NetworkManager.players:
				var p = NetworkManager.players[pid]
				player_list += "- %s%s\n" % [p.name, " [READY]" if p.ready else ""]
			players_label.text = player_list
			players_label.visible = true
		else:
			players_label.visible = false

func update_prompts() -> void:
	var in_lobby = NetworkManager.is_in_lobby()
	
	# Before joining lobby: show HOST, JOIN
	# After joining (client): show READY
	# After joining (host): show START
	if host_prompt:
		host_prompt.visible = not in_lobby
	if join_prompt:
		join_prompt.visible = not in_lobby
	if ready_prompt:
		ready_prompt.visible = in_lobby and not NetworkManager.is_host
	if start_prompt:
		start_prompt.visible = in_lobby and NetworkManager.is_host

# ============================================
# Command Handlers
# ============================================

func create_lobby() -> void:
	DebugHelper.log_info("Creating lobby...")
	if status_label:
		status_label.text = "Creating lobby..."
	NetworkManager.create_lobby()

func start_join_mode() -> void:
	join_mode = true
	lobby_code_buffer = ""
	update_display()
	DebugHelper.log_info("Enter 6-character lobby code")

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
	NetworkManager.start_game()

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
		status_label.text = "Join failed: %s" % reason
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

func _on_game_start(seed: int) -> void:
	DebugHelper.log_info("Game starting with seed: %d" % seed)
	SoundManager.play_match_found()
	StateManager.change_state("wordwar", {"seed": seed, "multiplayer": true})
