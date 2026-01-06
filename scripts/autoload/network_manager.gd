## network_manager.gd
## Handles TCP networking via relay server
## Autoload singleton: NetworkManager
extends Node

# Relay server configuration
const RELAY_HOST: String = "167.99.128.216"
const RELAY_PORT: int = 7777

# Connection state
enum ConnectionState {
	DISCONNECTED,
	CONNECTING,
	CONNECTED,
	IN_LOBBY,
	IN_GAME
}

var state: ConnectionState = ConnectionState.DISCONNECTED
var socket: StreamPeerTCP = null
var lobby_code: String = ""
var player_id: int = 0
var player_name: String = "Player"
var is_host: bool = false

# Other players in lobby
var players: Dictionary = {}  # id -> {name, ready, score}

# Game mode (set by host, synced to clients)
var game_mode: String = ""

# Message buffer
var message_buffer: String = ""

# Reconnection
var reconnect_attempts: int = 0
const MAX_RECONNECT_ATTEMPTS: int = 3

func _ready() -> void:
	DebugHelper.log_info("NetworkManager initialized (relay: %s:%d)" % [RELAY_HOST, RELAY_PORT])

func _process(_delta: float) -> void:
	if socket == null:
		return
	socket.poll()
	var status = socket.get_status()
	match status:
		StreamPeerTCP.STATUS_NONE:
			if state != ConnectionState.DISCONNECTED:
				on_disconnected("Connection lost")
		StreamPeerTCP.STATUS_CONNECTING:
			pass
		StreamPeerTCP.STATUS_CONNECTED:
			if state == ConnectionState.CONNECTING:
				on_connected()
			receive_data()
		StreamPeerTCP.STATUS_ERROR:
			on_disconnected("Connection error")

func connect_to_relay() -> void:
	if socket != null:
		disconnect_from_relay()
	socket = StreamPeerTCP.new()
	state = ConnectionState.CONNECTING
	reconnect_attempts = 0
	var error = socket.connect_to_host(RELAY_HOST, RELAY_PORT)
	if error != OK:
		DebugHelper.log_error("NetworkManager: Failed to initiate connection: %s" % error)
		on_disconnected("Failed to connect")
	else:
		DebugHelper.log_info("NetworkManager: Connecting to relay...")

func disconnect_from_relay() -> void:
	if socket != null:
		socket.disconnect_from_host()
		socket = null
	state = ConnectionState.DISCONNECTED
	lobby_code = ""
	players.clear()
	DebugHelper.log_info("NetworkManager: Disconnected from relay")
	SignalBus.network_disconnected.emit("Manual disconnect")

func on_connected() -> void:
	state = ConnectionState.CONNECTED
	DebugHelper.log_info("NetworkManager: Connected to relay!")
	SignalBus.network_connected.emit()

func on_disconnected(reason: String) -> void:
	state = ConnectionState.DISCONNECTED
	socket = null
	DebugHelper.log_warning("NetworkManager: Disconnected - %s" % reason)
	SignalBus.network_disconnected.emit(reason)
	if reconnect_attempts < MAX_RECONNECT_ATTEMPTS and lobby_code != "":
		reconnect_attempts += 1
		DebugHelper.log_info("NetworkManager: Reconnection attempt %d/%d" % [reconnect_attempts, MAX_RECONNECT_ATTEMPTS])
		call_deferred("connect_to_relay")

func send_message(msg_type: String, msg_data: Dictionary = {}) -> void:
	if socket == null or state == ConnectionState.DISCONNECTED:
		DebugHelper.log_warning("NetworkManager: Cannot send - not connected")
		return
	var packet = {"t": msg_type, "d": msg_data}
	var json_string = JSON.stringify(packet)
	var message = json_string + "\n"
	DebugHelper.log_debug("NetworkManager: Sending %s" % msg_type)
	socket.put_data(message.to_utf8_buffer())

func receive_data() -> void:
	if socket == null:
		return
	var available = socket.get_available_bytes()
	if available <= 0:
		return
	var data = socket.get_data(available)
	if data[0] != OK:
		return
	var text = data[1].get_string_from_utf8()
	message_buffer += text
	while message_buffer.contains("\n"):
		var newline_pos = message_buffer.find("\n")
		var message = message_buffer.substr(0, newline_pos)
		message_buffer = message_buffer.substr(newline_pos + 1)
		if message.length() > 0:
			process_message(message)

func process_message(message: String) -> void:
	var json = JSON.new()
	var error = json.parse(message)
	if error != OK:
		DebugHelper.log_error("NetworkManager: Invalid JSON: %s" % message)
		return
	var packet = json.get_data()
	if not packet is Dictionary:
		return
	var msg_type = packet.get("t", "")
	var data = packet.get("d", {})
	if data == null:
		data = {}
	DebugHelper.log_debug("NetworkManager: Received %s" % msg_type)
	match msg_type:
		"lobby_created":
			lobby_code = data.get("code", "")
			player_id = data.get("playerId", 1)
			is_host = true
			state = ConnectionState.IN_LOBBY
			DebugHelper.log_info("NetworkManager: Lobby created with code %s" % lobby_code)
			SignalBus.lobby_created.emit(lobby_code)
		"lobby_joined":
			lobby_code = data.get("code", "")
			player_id = data.get("playerId", 0)
			is_host = false
			state = ConnectionState.IN_LOBBY
			DebugHelper.log_info("NetworkManager: Joined lobby %s" % lobby_code)
			SignalBus.lobby_joined.emit(lobby_code)
		"lobby_info":
			var player_list = data.get("players", [])
			for p in player_list:
				if p.id != player_id:
					players[p.id] = {"name": p.name, "ready": p.ready, "score": 0}
					# Emit player_joined so lobby UI updates
					SignalBus.player_joined.emit(p.id, p.name)
			DebugHelper.log_info("NetworkManager: Received lobby info with %d players" % player_list.size())
		"player_joined":
			var pid = data.get("playerId", 0)
			var pname = data.get("playerName", "Unknown")
			players[pid] = {"name": pname, "ready": false, "score": 0}
			DebugHelper.log_info("NetworkManager: Player joined - %s" % pname)
			SignalBus.player_joined.emit(pid, pname)
		"player_left":
			var pid = data.get("playerId", 0)
			if players.has(pid):
				var pname = players[pid].name
				players.erase(pid)
				DebugHelper.log_info("NetworkManager: Player left - %s" % pname)
				SignalBus.player_left.emit(pid)
			# If host left (player 1), kick everyone from lobby
			if pid == 1 and not is_host:
				DebugHelper.log_warning("NetworkManager: Host left, leaving lobby")
				lobby_code = ""
				players.clear()
				state = ConnectionState.CONNECTED
				SignalBus.network_disconnected.emit("Host left the lobby")
		"join_failed":
			var reason = data.get("reason", "Unknown")
			DebugHelper.log_error("NetworkManager: Join failed - %s" % reason)
			SignalBus.lobby_join_failed.emit(reason)
		"lobby_closed":
			var reason = data.get("reason", "Lobby closed")
			DebugHelper.log_warning("NetworkManager: Lobby closed - %s" % reason)
			lobby_code = ""
			players.clear()
			state = ConnectionState.CONNECTED
			SignalBus.network_disconnected.emit(reason)
		"disconnect":
			var reason = data.get("reason", "Disconnected")
			DebugHelper.log_warning("NetworkManager: Server disconnect - %s" % reason)
			on_disconnected(reason)
		"pong":
			pass
		"set_ready":
			# Another player changed their ready status
			var sender_id = data.get("playerId", data.get("_senderId", 0))
			var ready_status = data.get("ready", false)
			if players.has(sender_id):
				players[sender_id].ready = ready_status
				DebugHelper.log_info("NetworkManager: Player %d ready: %s" % [sender_id, ready_status])
				SignalBus.player_ready_changed.emit(sender_id, ready_status)
		"start_game":
			# Host started the game
			state = ConnectionState.IN_GAME
			var game_seed = data.get("seed", randi())
			var mode = data.get("mode", "")
			game_mode = mode
			DebugHelper.log_info("NetworkManager: Game starting with seed %d, mode %s" % [game_seed, mode])
			SignalBus.network_game_start.emit(game_seed, mode)
		"wordwar_state":
			# Full game state sync from host
			if data.has("state"):
				WordWarManager.apply_network_state(data.state)
		"player_input":
			# Remote player typed a character
			var sender_id = data.get("playerId", data.get("_senderId", 0))
			var typed_char = data.get("char", "")
			if sender_id != player_id and sender_id > 0 and typed_char != "":
				# Use sender_id directly as the remote player
				WordWarManager.process_char(typed_char, sender_id)
		"coop_enemy_killed":
			# Partner killed an enemy in COOP (new format with enemy_id)
			SignalBus.coop_enemy_killed_v2.emit(data)
		"coop_score":
			# Partner score update in COOP
			var partner_score = data.get("score", 0)
			SignalBus.coop_partner_score.emit(partner_score)
		"coop_reserve":
			# Partner reserved a word (new format with enemy_id)
			SignalBus.coop_reserve.emit(data)
		"coop_release":
			# Partner released a word (new format with enemy_id)
			SignalBus.coop_release.emit(data)
		"coop_player_pos":
			# Player position sync (P2 sends, P1 receives)
			var pos_x = data.get("x", 0)
			var pos_y = data.get("y", 0)
			SignalBus.emit_signal("coop_player_moved", Vector2(pos_x, pos_y))
		"coop_switch":
			# Partner triggered SWITCH
			SignalBus.coop_switch.emit()
		"coop_spawn_enemy":
			# Host spawned an enemy - client should create it
			SignalBus.coop_spawn_enemy.emit(data)
		"coop_spawn_powerup":
			# Host spawned a powerup - client should create it
			SignalBus.coop_spawn_powerup.emit(data)
		"coop_state":
			# Full state sync from host
			SignalBus.coop_state.emit(data)
		"coop_typing":
			# Partner is typing an enemy
			SignalBus.coop_typing.emit(data)
		"coop_nuke_typed":
			# Partner typed NUKE
			SignalBus.coop_nuke_typed.emit(data)
		"coop_powerup_collected":
			# Partner collected a powerup
			SignalBus.coop_powerup_collected.emit(data)
		"coop_game_over":
			# Game over sync
			SignalBus.coop_game_over.emit(data)
		"coop_tower_placed":
			# Partner placed a tower (P2 -> Host)
			SignalBus.coop_tower_placed.emit(data)
		_:
			DebugHelper.log_debug("NetworkManager: Unknown message type: %s" % msg_type)

func create_lobby() -> void:
	if state != ConnectionState.CONNECTED:
		connect_to_relay()
		# Wait for either connected or disconnected
		var result = await wait_for_connection()
		if not result:
			DebugHelper.log_error("NetworkManager: Failed to connect for lobby creation")
			SignalBus.lobby_join_failed.emit("Connection failed")
			return
	send_message("create_lobby", {"playerName": player_name})

func wait_for_connection() -> bool:
	# Wait up to 10 seconds for connection
	var timeout := 10.0
	var elapsed := 0.0
	while state == ConnectionState.CONNECTING and elapsed < timeout:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	return state == ConnectionState.CONNECTED

func join_lobby(code: String) -> void:
	if state != ConnectionState.CONNECTED:
		connect_to_relay()
		var result = await wait_for_connection()
		if not result:
			DebugHelper.log_error("NetworkManager: Failed to connect for lobby join")
			SignalBus.lobby_join_failed.emit("Connection failed")
			return
	send_message("join_lobby", {"code": code.to_upper(), "playerName": player_name})

func leave_lobby() -> void:
	send_message("leave_lobby")
	lobby_code = ""
	players.clear()
	state = ConnectionState.CONNECTED

func set_ready(ready: bool) -> void:
	send_message("set_ready", {"ready": ready})

func start_game(mode: String = "") -> void:
	if not is_host:
		return
	# Generate seed and send to all players
	var game_seed = randi()
	game_mode = mode
	send_message("start_game", {"seed": game_seed, "mode": mode})
	# Host also transitions to game
	state = ConnectionState.IN_GAME
	DebugHelper.log_info("NetworkManager: Host starting game with seed %d, mode %s" % [game_seed, mode])
	SignalBus.network_game_start.emit(game_seed, mode)

func send_score_update(score: int) -> void:
	send_message("score_update", {"score": score})

func send_word_completed(word: String) -> void:
	send_message("word_completed", {"word": word})

func send_game_over(won: bool, final_score: int) -> void:
	send_message("game_over", {"won": won, "score": final_score})

func send_coop_score(score: int) -> void:
	send_message("coop_score", {"score": score})

func send_coop_enemy_killed(word: String, points: int) -> void:
	send_message("coop_enemy_killed", {"word": word, "points": points})

func send_ping() -> void:
	send_message("ping", {"time": Time.get_ticks_msec()})

func set_player_name(new_name: String) -> void:
	player_name = new_name

func is_network_connected() -> bool:
	return state != ConnectionState.DISCONNECTED and state != ConnectionState.CONNECTING

func is_in_lobby() -> bool:
	return state == ConnectionState.IN_LOBBY

func is_in_game() -> bool:
	return state == ConnectionState.IN_GAME

func get_player_count() -> int:
	return players.size() + 1