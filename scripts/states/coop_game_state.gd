## coop_game_state.gd
## COOP Mode - Host-Authoritative Online Multiplayer
## Both players see the SAME synchronized battlefield
## HOST runs the game simulation, CLIENT receives and renders state
extends Node2D

const COLORS := {
	"p1": Color("#00E5FF"),      # Cyan - P1
	"p2": Color("#FF2A8A"),      # Magenta - P2
	"neutral": Color.WHITE,
	"nuke_ready": Color("#FF6600"),  # Orange - NUKE ready to activate
}

# Tower hit effects
const BlueHitEffect = preload("res://scenes/effects/blue_hit_effect.tscn")
const ElectricHitEffect = preload("res://scenes/effects/electric_hit_effect.tscn")

# Network sync interval
const SYNC_INTERVAL: float = 0.05  # 20 updates per second

@onready var enemy_container: Node2D = $GameLayer/EnemyContainer
@onready var portal: Node2D = $GameLayer/Portal
@onready var player: CharacterBody2D = $GameLayer/Player
@onready var wave_manager: Node = $WaveManager
@onready var typing_hud = $UILayer/TypingHUD
@onready var coop_overlay: Control = $UILayer/CoopOverlay
@onready var switch_overlay: ColorRect = $UILayer/SwitchOverlay
@onready var switch_label: Label = $UILayer/SwitchOverlay/SwitchLabel

# Game state
var game_active: bool = false
var game_seed: int = 0
var is_host: bool = false
var local_role: int = 1  # 1 = P1, 2 = P2

# Score tracking (shared team score)
var total_score: int = 0
var p1_contribution: int = 0
var p2_contribution: int = 0
var combo: int = 0
var max_combo: int = 0

# Typing state - each player has their own
var typed_buffer: String = ""
var active_enemy: Node = null
var word_reservations: Dictionary = {}  # enemy_id -> player_id

# Enemy tracking (for network sync)
var enemy_id_counter: int = 0
var enemies_by_id: Dictionary = {}  # id -> enemy node
var powerups_by_id: Dictionary = {}  # id -> powerup node
var powerup_id_counter: int = 0

# NUKE dual-type tracking
var nuke_p1_ready: bool = false
var nuke_p2_ready: bool = false
var nuke_timeout: float = 0.0
const NUKE_TIMEOUT: float = 3.0  # Both must type within 3 seconds

# Switch system
var switch_effect_active: bool = false
var switch_effect_timer: float = 0.0
const SWITCH_EFFECT_DURATION: float = 1.0
const SWITCH_COOLDOWN: float = 30.0
var switch_cooldown_timer: float = 0.0

# Network sync
var sync_timer: float = 0.0
var last_synced_state: Dictionary = {}

var enemy_scene: PackedScene

func _ready() -> void:
	DebugHelper.log_info("CoopGameState ready (Host-Authoritative)")
	enemy_scene = load("res://scenes/entities/enemy_word.tscn")

	# Connect signals
	SignalBus.portal_destroyed.connect(_on_portal_destroyed)
	SignalBus.player_died.connect(_on_player_died)
	SignalBus.wave_completed.connect(_on_wave_completed)
	SignalBus.enemy_reached_portal.connect(_on_enemy_reached_portal)

	if switch_overlay:
		switch_overlay.visible = false

func on_enter(params: Dictionary) -> void:
	DebugHelper.log_info("CoopGameState entered")
	MenuBackground.hide_background()

	game_seed = params.get("seed", randi())
	is_host = NetworkManager.is_host
	seed(game_seed)

	# Host = P1, Client = P2
	local_role = 1 if is_host else 2

	# Reset state
	total_score = 0
	p1_contribution = 0
	p2_contribution = 0
	combo = 0
	max_combo = 0
	game_active = true
	word_reservations.clear()
	enemies_by_id.clear()
	powerups_by_id.clear()
	enemy_id_counter = 0
	powerup_id_counter = 0
	typed_buffer = ""
	active_enemy = null
	switch_cooldown_timer = 0.0
	sync_timer = 0.0
	nuke_p1_ready = false
	nuke_p2_ready = false
	nuke_timeout = 0.0

	# Setup language
	var language = SaveManager.get_setting("language", "EN")
	WordSetLoader.set_language_string(language)
	WordSetLoader.reset_used_words()

	# Clear existing enemies/powerups
	for child in enemy_container.get_children():
		child.queue_free()

	# HOST ONLY: Run game simulation
	if is_host:
		DebugHelper.log_info("COOP: Running as HOST (P1)")

		# Setup wave manager
		if wave_manager:
			wave_manager.setup(enemy_container, portal)
			wave_manager.start_waves()

		# Setup powerup manager - HOST spawns powerups
		PowerUpManager.set_spawn_container(enemy_container)
		PowerUpManager.set_portal_reference(portal)
		PowerUpManager.reset()
		PowerUpManager.set_network_client_mode(false)

		# Connect to intercept enemy/powerup spawns
		SignalBus.enemy_spawned.connect(_on_host_enemy_spawned)
		SignalBus.powerup_spawned.connect(_on_host_powerup_spawned)
		SignalBus.enemy_killed.connect(_on_host_enemy_killed)
	else:
		DebugHelper.log_info("COOP: Running as CLIENT (P2)")

		# CLIENT: Disable local wave manager, wait for host data
		if wave_manager:
			wave_manager.stop_waves()

		# CLIENT: Disable powerup spawning (receives from host)
		PowerUpManager.set_network_client_mode(true)
		PowerUpManager.set_portal_reference(portal)

	# Setup build manager - only for player movement
	var portal_pos = portal.global_position if portal else Vector2(640, 360)
	BuildManager.setup(enemy_container, portal_pos)
	BuildManager.set_player_reference(player)
	BuildManager.reset()
	BuildManager.add_build_points(100)

	# Reset portal and player HP
	if portal and portal.has_method("reset"):
		portal.reset()
	if player and player.has_method("reset"):
		player.reset()

	# Connect network signals for COOP sync
	SignalBus.coop_spawn_enemy.connect(_on_network_spawn_enemy)
	SignalBus.coop_spawn_powerup.connect(_on_network_spawn_powerup)
	SignalBus.coop_state.connect(_on_network_state)
	SignalBus.coop_enemy_killed_v2.connect(_on_network_enemy_killed)
	SignalBus.coop_reserve.connect(_on_network_reserve)
	SignalBus.coop_release.connect(_on_network_release)
	SignalBus.coop_typing.connect(_on_network_typing)
	SignalBus.coop_nuke_typed.connect(_on_network_nuke_typed)
	SignalBus.coop_powerup_collected.connect(_on_network_powerup_collected)
	SignalBus.coop_switch.connect(_on_network_switch)
	SignalBus.coop_game_over.connect(_on_network_game_over)
	SignalBus.coop_partner_score.connect(_on_network_score)
	SignalBus.coop_player_moved.connect(_on_network_player_moved)
	SignalBus.coop_tower_placed.connect(_on_network_tower_placed)
	SignalBus.coop_tower_effect.connect(_on_network_tower_effect)
	SignalBus.network_disconnected.connect(_on_network_disconnected)

	# ONLY P2 (Client) can move the player!
	# P1 (Host) controls Portal position (stationary) and can only type
	if player:
		var can_move = (local_role == 2)  # Only P2 can move
		player.movement_enabled = can_move
		# Keep physics running on both for collisions and position sync
		player.set_physics_process(true)
		DebugHelper.log_info("COOP: Player movement enabled = %s (local_role=%d)" % [can_move, local_role])

	update_hud()
	SoundManager.play_game_music()
	SignalBus.game_started.emit()

func on_exit() -> void:
	DebugHelper.log_info("CoopGameState exiting")
	game_active = false

	# Disconnect signals safely
	_safe_disconnect(SignalBus.portal_destroyed, _on_portal_destroyed)
	_safe_disconnect(SignalBus.player_died, _on_player_died)
	_safe_disconnect(SignalBus.wave_completed, _on_wave_completed)
	_safe_disconnect(SignalBus.enemy_reached_portal, _on_enemy_reached_portal)

	# Disconnect network signals
	_safe_disconnect(SignalBus.coop_spawn_enemy, _on_network_spawn_enemy)
	_safe_disconnect(SignalBus.coop_spawn_powerup, _on_network_spawn_powerup)
	_safe_disconnect(SignalBus.coop_state, _on_network_state)
	_safe_disconnect(SignalBus.coop_enemy_killed_v2, _on_network_enemy_killed)
	_safe_disconnect(SignalBus.coop_reserve, _on_network_reserve)
	_safe_disconnect(SignalBus.coop_release, _on_network_release)
	_safe_disconnect(SignalBus.coop_typing, _on_network_typing)
	_safe_disconnect(SignalBus.coop_nuke_typed, _on_network_nuke_typed)
	_safe_disconnect(SignalBus.coop_player_moved, _on_network_player_moved)
	_safe_disconnect(SignalBus.coop_powerup_collected, _on_network_powerup_collected)
	_safe_disconnect(SignalBus.coop_switch, _on_network_switch)
	_safe_disconnect(SignalBus.coop_game_over, _on_network_game_over)
	_safe_disconnect(SignalBus.coop_partner_score, _on_network_score)
	_safe_disconnect(SignalBus.coop_tower_placed, _on_network_tower_placed)
	_safe_disconnect(SignalBus.coop_tower_effect, _on_network_tower_effect)
	_safe_disconnect(SignalBus.network_disconnected, _on_network_disconnected)

	if is_host:
		_safe_disconnect(SignalBus.enemy_spawned, _on_host_enemy_spawned)
		_safe_disconnect(SignalBus.powerup_spawned, _on_host_powerup_spawned)
		_safe_disconnect(SignalBus.enemy_killed, _on_host_enemy_killed)

func _safe_disconnect(sig: Signal, callable: Callable) -> void:
	if sig.is_connected(callable):
		sig.disconnect(callable)

func _process(delta: float) -> void:
	if not game_active:
		return

	# Update NUKE timeout
	if nuke_timeout > 0:
		nuke_timeout -= delta
		if nuke_timeout <= 0:
			nuke_p1_ready = false
			nuke_p2_ready = false

	# Update switch cooldown
	if switch_cooldown_timer > 0:
		switch_cooldown_timer -= delta

	# Update switch effect
	if switch_effect_active:
		switch_effect_timer -= delta
		update_switch_effect()
		if switch_effect_timer <= 0:
			end_switch_effect()

	# Network sync
	sync_timer += delta
	if sync_timer >= SYNC_INTERVAL:
		sync_timer = 0.0
		if is_host:
			# HOST: Send full state to client
			send_full_state_to_client()
		else:
			# CLIENT (P2): Send player position to host
			send_player_position_to_host()

	# Update towers - only HOST runs tower logic (effects sync via state)
	if is_host:
		var enemies = get_tree().get_nodes_in_group("enemies")
		var tower_results = BuildManager.update_towers(delta, enemies)
		process_tower_results(tower_results)

	# Update word colors
	update_word_colors()
	update_hud()

func _input(event: InputEvent) -> void:
	if not game_active or switch_effect_active:
		return

	if event is InputEventKey and event.pressed and not event.is_echo():
		var char_code = event.unicode

		# ESC to quit or exit build mode
		if event.keycode == KEY_ESCAPE:
			if BuildManager.is_building():
				BuildManager.exit_build_mode()
			else:
				_trigger_game_over(false, "Quit")
			return

		# BUILD MODE: Redirect all input to BuildManager
		if BuildManager.is_building():
			# Handle backspace in build mode
			if event.keycode == KEY_BACKSPACE:
				# Reset build buffer (go back one step)
				BuildManager.build_buffer = ""
				return

			# Handle numbers (0-9) for position selection
			var is_number = (char_code >= 48 and char_code <= 57)  # ASCII 0-9
			if is_number:
				var result = BuildManager.process_char(char(char_code))
				handle_build_result(result)
				return

			# Handle letters (A-Z)
			var is_letter = (char_code >= 65 and char_code <= 90) or (char_code >= 97 and char_code <= 122)
			if is_letter:
				var typed_char = char(char_code).to_upper()
				var result = BuildManager.process_char(typed_char)
				handle_build_result(result)
				return
			return

		# Normal typing input (A-Z) - not in build mode
		var is_letter = (char_code >= 65 and char_code <= 90) or (char_code >= 97 and char_code <= 122)
		if is_letter:
			var typed_char = char(char_code).to_upper()
			process_typing(typed_char)

		# Backspace
		if event.keycode == KEY_BACKSPACE:
			process_backspace()

func process_typing(typed_char: String) -> void:
	typed_buffer += typed_char

	# Check for SWITCH command
	if typed_buffer == "SWITCH":
		if switch_cooldown_timer <= 0:
			trigger_switch()
			NetworkManager.send_message("coop_switch", {})
		typed_buffer = ""
		return

	# Check for BUILD command - only Player role can build
	if typed_buffer == "BUILD":
		if local_role == 2:
			BuildManager.enter_build_mode()
			DebugHelper.log_info("Player role (P2) entering BUILD mode")
		else:
			DebugHelper.log_info("Portal role (P1) cannot build!")
		typed_buffer = ""
		return

	# Don't match enemies if we're typing a system command
	var typing_system_command = "SWITCH".begins_with(typed_buffer) or "BUILD".begins_with(typed_buffer)

	# If typing an active enemy word
	if active_enemy and is_instance_valid(active_enemy):
		var word = active_enemy.word.to_upper()
		var typed_index = typed_buffer.length() - 1

		if typed_index < word.length() and typed_char == word[typed_index]:
			# Correct character
			SoundManager.play_type_correct()
			combo += 1
			max_combo = max(max_combo, combo)

			if active_enemy.has_method("update_typed_progress"):
				active_enemy.update_typed_progress(typed_buffer.length())

			# Send progress to network
			send_typing_progress(active_enemy, typed_buffer.length())

			if typed_buffer == word:
				# Word completed!
				complete_word(active_enemy)
				typed_buffer = ""
				active_enemy = null
		else:
			# Wrong character
			SoundManager.play_type_error()
			combo = 0
			typed_buffer = typed_buffer.substr(0, typed_buffer.length() - 1)
	else:
		# Don't match enemies/powerups if typing a system command
		if typing_system_command:
			# Still typing BUILD or SWITCH, wait for completion
			SoundManager.play_type_correct()
			return

		# Try to find matching enemy or powerup
		var found = find_target_starting_with(typed_buffer)
		if found:
			if found.is_in_group("enemies"):
				# Reserve this enemy
				var enemy_id = get_enemy_id(found)
				reserve_word(found, local_role)
				active_enemy = found
				SoundManager.play_type_correct()
				combo += 1
				max_combo = max(max_combo, combo)

				if found.has_method("update_typed_progress"):
					found.update_typed_progress(typed_buffer.length())

				send_typing_progress(found, typed_buffer.length())

				if typed_buffer == found.word.to_upper():
					complete_word(found)
					typed_buffer = ""
					active_enemy = null
			elif found.is_in_group("powerups"):
				# Typing a powerup - show progress
				SoundManager.play_type_correct()
				if found.has_method("update_typed_progress"):
					found.update_typed_progress(typed_buffer.length())

				var powerup_word = found.get_meta("powerup_word", "")
				if typed_buffer == powerup_word:
					collect_powerup(found)
					typed_buffer = ""
		else:
			# Check if could still match (including system commands)
			var could_match = check_could_match(typed_buffer)
			if not could_match:
				SoundManager.play_type_error()
				combo = 0
				typed_buffer = ""

func process_backspace() -> void:
	if typed_buffer.length() > 0:
		typed_buffer = typed_buffer.substr(0, typed_buffer.length() - 1)

		if active_enemy and is_instance_valid(active_enemy):
			if active_enemy.has_method("update_typed_progress"):
				active_enemy.update_typed_progress(typed_buffer.length())
			send_typing_progress(active_enemy, typed_buffer.length())

		if typed_buffer.length() == 0 and active_enemy:
			release_word(active_enemy)
			active_enemy = null

func find_target_starting_with(prefix: String) -> Node:
	if prefix.length() == 0:
		return null

	# Check enemies first
	for child in enemy_container.get_children():
		if not child.is_in_group("enemies"):
			continue
		if not child.has_method("is_alive") or not child.is_alive():
			continue

		var word = child.word.to_upper()
		var reservation = word_reservations.get(get_enemy_id(child), 0)

		# Can only target unreserved words or our own
		if reservation != 0 and reservation != local_role:
			continue

		if word.begins_with(prefix):
			return child

	# Check powerups
	for child in enemy_container.get_children():
		if not child.is_in_group("powerups"):
			continue
		var word = child.get_meta("powerup_word", "").to_upper()
		if word.begins_with(prefix):
			return child

	return null

func check_could_match(prefix: String) -> bool:
	# System commands always match
	if "SWITCH".begins_with(prefix) or "BUILD".begins_with(prefix):
		return true

	for child in enemy_container.get_children():
		if child.is_in_group("enemies") and child.has_method("is_alive") and child.is_alive():
			var word = child.word.to_upper()
			var reservation = word_reservations.get(get_enemy_id(child), 0)
			if (reservation == 0 or reservation == local_role) and word.begins_with(prefix):
				return true
		elif child.is_in_group("powerups"):
			var word = child.get_meta("powerup_word", "").to_upper()
			if word.begins_with(prefix):
				return true
	return false

func get_enemy_id(enemy: Node) -> int:
	for id in enemies_by_id:
		if enemies_by_id[id] == enemy:
			return id
	return -1

func get_powerup_id(powerup: Node) -> int:
	for id in powerups_by_id:
		if powerups_by_id[id] == powerup:
			return id
	return -1

# ============================================
# WORD RESERVATION SYSTEM
# ============================================

func reserve_word(enemy: Node, player_id: int) -> void:
	var enemy_id = get_enemy_id(enemy)
	if enemy_id >= 0:
		word_reservations[enemy_id] = player_id
		NetworkManager.send_message("coop_reserve", {"enemy_id": enemy_id, "player": player_id})

func release_word(enemy: Node) -> void:
	var enemy_id = get_enemy_id(enemy)
	if enemy_id >= 0 and word_reservations.has(enemy_id):
		word_reservations.erase(enemy_id)
		NetworkManager.send_message("coop_release", {"enemy_id": enemy_id})

func complete_word(enemy: Node) -> void:
	var word_score = enemy.word.length() * 10
	var combo_bonus = combo * 5
	var points = word_score + combo_bonus

	# Add to contribution
	if local_role == 1:
		p1_contribution += points
	else:
		p2_contribution += points
	total_score = p1_contribution + p2_contribution

	SoundManager.play_word_complete()
	release_word(enemy)

	# Kill the enemy
	var enemy_id = get_enemy_id(enemy)
	if enemy.has_method("die"):
		enemy.die()

	# Build points
	BuildManager.add_build_points(5)

	# Send to network
	NetworkManager.send_message("coop_enemy_killed", {
		"enemy_id": enemy_id,
		"word": enemy.word,
		"points": points,
		"player": local_role
	})

func collect_powerup(powerup: Node) -> void:
	var powerup_type = powerup.get_meta("powerup_type", -1)
	var powerup_word = powerup.get_meta("powerup_word", "")
	var powerup_id = get_powerup_id(powerup)

	# NUKE requires both players
	if powerup_type == PowerUpManager.PowerUpType.NUKE:
		handle_nuke_typed(local_role)
		NetworkManager.send_message("coop_nuke_typed", {"player": local_role})
		return

	# Regular powerup - collect it
	SoundManager.play_powerup_collect()
	PowerUpManager.collect_powerup(powerup_type)

	# Remove powerup
	if powerups_by_id.has(powerup_id):
		powerups_by_id.erase(powerup_id)
	powerup.queue_free()

	# Sync to partner
	NetworkManager.send_message("coop_powerup_collected", {
		"powerup_id": powerup_id,
		"type": powerup_type,
		"player": local_role
	})

func handle_nuke_typed(player_id: int) -> void:
	if player_id == 1:
		nuke_p1_ready = true
	else:
		nuke_p2_ready = true

	nuke_timeout = NUKE_TIMEOUT

	DebugHelper.log_info("NUKE typed by P%d (P1: %s, P2: %s)" % [player_id, nuke_p1_ready, nuke_p2_ready])

	# Check if both ready
	if nuke_p1_ready and nuke_p2_ready:
		activate_nuke()

func activate_nuke() -> void:
	DebugHelper.log_info("=== NUKE ACTIVATED BY BOTH PLAYERS ===")
	nuke_p1_ready = false
	nuke_p2_ready = false
	nuke_timeout = 0.0

	# Find and remove NUKE powerup
	for id in powerups_by_id:
		var powerup = powerups_by_id[id]
		if is_instance_valid(powerup):
			var ptype = powerup.get_meta("powerup_type", -1)
			if ptype == PowerUpManager.PowerUpType.NUKE:
				powerup.queue_free()
				powerups_by_id.erase(id)
				break

	# Activate nuke effect
	PowerUpManager.collect_powerup(PowerUpManager.PowerUpType.NUKE)

	# Give bonus points to both
	var nuke_bonus = 500
	p1_contribution += nuke_bonus / 2
	p2_contribution += nuke_bonus / 2
	total_score = p1_contribution + p2_contribution

func update_word_colors() -> void:
	for child in enemy_container.get_children():
		if not child.is_in_group("enemies"):
			continue
		if not child.has_method("set_word_color"):
			continue

		var enemy_id = get_enemy_id(child)
		var reservation = word_reservations.get(enemy_id, 0)

		match reservation:
			1:
				child.set_word_color(COLORS.p1)
			2:
				child.set_word_color(COLORS.p2)
			_:
				child.set_word_color(COLORS.neutral)

	# Color NUKE powerup if one player is ready
	for child in enemy_container.get_children():
		if not child.is_in_group("powerups"):
			continue
		var ptype = child.get_meta("powerup_type", -1)
		if ptype == PowerUpManager.PowerUpType.NUKE:
			if nuke_p1_ready or nuke_p2_ready:
				var sprite = child.get_node_or_null("Sprite")
				if sprite and sprite is Line2D:
					sprite.default_color = COLORS.nuke_ready

# ============================================
# HOST-AUTHORITATIVE NETWORK SYNC
# ============================================

func _on_host_enemy_spawned(enemy: Node) -> void:
	# HOST: Assign ID and broadcast to client
	enemy_id_counter += 1
	var enemy_id = enemy_id_counter
	enemies_by_id[enemy_id] = enemy
	enemy.set_meta("network_id", enemy_id)

	DebugHelper.log_info("HOST: Spawned enemy %d: %s at (%.0f, %.0f)" % [enemy_id, enemy.word, enemy.global_position.x, enemy.global_position.y])

	# Send spawn to client
	NetworkManager.send_message("coop_spawn_enemy", {
		"id": enemy_id,
		"word": enemy.word,
		"pos_x": enemy.global_position.x,
		"pos_y": enemy.global_position.y,
		"speed": enemy.speed
	})

func _on_host_powerup_spawned(powerup: Node) -> void:
	# HOST: Assign ID and broadcast to client
	powerup_id_counter += 1
	var powerup_id = powerup_id_counter
	powerups_by_id[powerup_id] = powerup
	powerup.set_meta("network_id", powerup_id)

	NetworkManager.send_message("coop_spawn_powerup", {
		"id": powerup_id,
		"type": powerup.get_meta("powerup_type", 0),
		"word": powerup.get_meta("powerup_word", ""),
		"pos_x": powerup.global_position.x,
		"pos_y": powerup.global_position.y
	})

func _on_host_enemy_killed(enemy: Node, _typed: bool) -> void:
	var enemy_id = get_enemy_id(enemy)
	if enemy_id >= 0:
		enemies_by_id.erase(enemy_id)
		if word_reservations.has(enemy_id):
			word_reservations.erase(enemy_id)

func send_full_state_to_client() -> void:
	# Build state snapshot
	var enemy_states = []
	for id in enemies_by_id:
		var enemy = enemies_by_id[id]
		if is_instance_valid(enemy) and enemy.is_alive():
			enemy_states.append({
				"id": id,
				"x": enemy.global_position.x,
				"y": enemy.global_position.y,
				"typed": enemy.typed_progress if enemy.has_method("is_alive") else 0
			})

	# Build tower states (position and level only - targeting is calculated locally)
	var tower_states = []
	for tower in BuildManager.get_towers():
		tower_states.append({
			"x": tower.x,
			"y": tower.y,
			"type": tower.type,
			"level": tower.level
		})

	var state = {
		"enemies": enemy_states,
		"towers": tower_states,
		"build_points": BuildManager.get_build_points(),
		"portal_hp": portal.current_hp if portal else 0,
		"player_hp": player.current_hp if player else 0,
		"player_x": player.global_position.x if player else 0,
		"player_y": player.global_position.y if player else 0,
		"wave": wave_manager.current_wave if wave_manager else 0,
		"score": total_score,
		"p1_score": p1_contribution,
		"p2_score": p2_contribution,
		"reservations": word_reservations.duplicate(),
		"nuke_p1": nuke_p1_ready,
		"nuke_p2": nuke_p2_ready
	}

	NetworkManager.send_message("coop_state", state)
	# Debug: Log occasionally (every 2 seconds = 40 syncs)
	if enemy_id_counter % 40 == 1:
		DebugHelper.log_debug("HOST: Syncing state - %d enemies, portal HP: %d" % [enemy_states.size(), portal.current_hp if portal else 0])

func send_typing_progress(enemy: Node, progress: int) -> void:
	var enemy_id = get_enemy_id(enemy)
	if enemy_id >= 0:
		NetworkManager.send_message("coop_typing", {
			"enemy_id": enemy_id,
			"progress": progress,
			"player": local_role
		})

func send_player_position_to_host() -> void:
	# CLIENT (P2) sends player position to HOST (P1)
	if player:
		NetworkManager.send_message("coop_player_pos", {
			"x": player.global_position.x,
			"y": player.global_position.y
		})

# ============================================
# CLIENT: RECEIVE NETWORK MESSAGES
# ============================================

func _on_network_spawn_enemy(data: Dictionary) -> void:
	# CLIENT: Spawn enemy as instructed by host
	if is_host:
		return

	var enemy_id = int(data.id)
	DebugHelper.log_info("CLIENT: Received enemy spawn - ID: %d, Word: %s" % [enemy_id, data.word])

	var enemy = enemy_scene.instantiate()
	enemy.position = Vector2(float(data.pos_x), float(data.pos_y))
	enemy.setup(str(data.word), portal)
	enemy.speed = float(data.speed)
	enemy.set_meta("network_id", enemy_id)

	enemy_container.add_child(enemy)
	enemies_by_id[enemy_id] = enemy

	DebugHelper.log_info("CLIENT: Spawned enemy %d: %s at (%.0f, %.0f)" % [enemy_id, data.word, float(data.pos_x), float(data.pos_y)])

func _on_network_spawn_powerup(data: Dictionary) -> void:
	# CLIENT: Spawn powerup as instructed by host
	if is_host:
		return

	var powerup_id = int(data.id)
	var powerup_type = int(data.type)
	var powerup = PowerUpManager.create_powerup_node(powerup_type, PowerUpManager.POWERUPS[powerup_type])
	powerup.position = Vector2(float(data.pos_x), float(data.pos_y))
	powerup.set_meta("network_id", powerup_id)
	powerup.add_to_group("powerups")  # Important for typing detection!

	enemy_container.add_child(powerup)
	powerups_by_id[powerup_id] = powerup

	DebugHelper.log_info("CLIENT: Spawned powerup %d: %s at (%.0f, %.0f)" % [powerup_id, data.word, float(data.pos_x), float(data.pos_y)])

func _on_network_state(data: Dictionary) -> void:
	# CLIENT: Apply state from host
	if is_host:
		return

	# Update enemy positions
	for enemy_data in data.enemies:
		var enemy_id = int(enemy_data.id)
		if enemies_by_id.has(enemy_id):
			var enemy = enemies_by_id[enemy_id]
			if is_instance_valid(enemy):
				enemy.global_position = Vector2(enemy_data.x, enemy_data.y)

	# Update HP
	if portal and portal.has_method("set_hp"):
		portal.set_hp(int(data.portal_hp))
	elif portal:
		portal.current_hp = int(data.portal_hp)

	if player:
		player.current_hp = int(data.player_hp)

	# Update scores
	p1_contribution = int(data.p1_score)
	p2_contribution = int(data.p2_score)
	total_score = int(data.score)

	# Sync build points from host
	if data.has("build_points"):
		var host_points = int(data.build_points)
		var local_points = BuildManager.get_build_points()
		if host_points != local_points:
			# Set build points to match host (use internal variable directly)
			BuildManager.build_points = host_points
			BuildManager.build_points_changed.emit(host_points)

	# Sync tower levels (targeting is calculated locally for visuals)
	if data.has("towers"):
		sync_tower_levels(data.towers)

	# Update reservations (JSON converts int keys to strings, convert back)
	word_reservations.clear()
	if data.has("reservations") and data.reservations is Dictionary:
		for key in data.reservations:
			word_reservations[int(key)] = int(data.reservations[key])

	# Update NUKE status
	nuke_p1_ready = data.nuke_p1
	nuke_p2_ready = data.nuke_p2

func sync_tower_levels(tower_states: Array) -> void:
	# Update local tower levels based on host data
	var local_towers = BuildManager.get_towers()

	for tower_data in tower_states:
		var tx = float(tower_data.x)
		var ty = float(tower_data.y)

		# Find matching local tower by position
		for tower in local_towers:
			if abs(tower.x - tx) < 5 and abs(tower.y - ty) < 5:
				# Update level if changed
				if tower_data.has("level"):
					tower.level = int(tower_data.level)
				break

func _on_network_enemy_killed(data: Dictionary) -> void:
	var enemy_id = int(data.enemy_id)
	if enemies_by_id.has(enemy_id):
		var enemy = enemies_by_id[enemy_id]
		if is_instance_valid(enemy) and enemy.has_method("die"):
			enemy.die()
		enemies_by_id.erase(enemy_id)

	# Update partner's contribution
	var partner_role = 3 - local_role  # 1->2, 2->1
	if int(data.player) == partner_role:
		if partner_role == 1:
			p1_contribution += int(data.points)
		else:
			p2_contribution += int(data.points)
		total_score = p1_contribution + p2_contribution

func _on_network_reserve(data: Dictionary) -> void:
	word_reservations[int(data.enemy_id)] = int(data.player)

func _on_network_release(data: Dictionary) -> void:
	var enemy_id = int(data.enemy_id)
	if word_reservations.has(enemy_id):
		word_reservations.erase(enemy_id)

func _on_network_typing(data: Dictionary) -> void:
	# Partner is typing an enemy - update visual
	var enemy_id = int(data.enemy_id)
	if enemies_by_id.has(enemy_id):
		var enemy = enemies_by_id[enemy_id]
		if is_instance_valid(enemy) and enemy.has_method("update_typed_progress"):
			enemy.update_typed_progress(int(data.progress))

func _on_network_nuke_typed(data: Dictionary) -> void:
	handle_nuke_typed(int(data.player))

func _on_network_powerup_collected(data: Dictionary) -> void:
	var powerup_id = int(data.powerup_id)
	if powerups_by_id.has(powerup_id):
		var powerup = powerups_by_id[powerup_id]
		if is_instance_valid(powerup):
			powerup.queue_free()
		powerups_by_id.erase(powerup_id)

	# Apply powerup effect locally too
	if not is_host:
		PowerUpManager.collect_powerup(int(data.type))

func _on_network_switch() -> void:
	if switch_cooldown_timer <= 0:
		trigger_switch()

func _on_network_game_over(data: Dictionary) -> void:
	if game_active:
		game_active = false
		var stats = {
			"score": int(data.score),
			"p1_score": int(data.p1_score),
			"p2_score": int(data.p2_score),
			"wave": int(data.wave),
			"death_reason": str(data.reason),
			"mode": "COOP"
		}
		StateManager.change_state("game_over", {"won": bool(data.won), "stats": stats, "mode": "COOP"})

func _on_network_disconnected(reason: String) -> void:
	if not game_active:
		return

	DebugHelper.log_warning("COOP: Network disconnected - %s" % reason)
	game_active = false
	TypingManager.disable_typing()

	# Go to game over with disconnect flag (no RETRY available)
	var typing_stats = TypingManager.get_stats()
	var stats = {
		"score": total_score,
		"p1_score": p1_score,
		"p2_score": p2_score,
		"wave": wave_manager.current_wave if wave_manager else 0,
		"enemies_destroyed": enemies_killed,
		"accuracy": typing_stats.get("accuracy", 0.0),
		"wpm": typing_stats.get("wpm", 0.0),
		"max_combo": typing_stats.get("max_combo", 0),
		"death_reason": "Partner disconnected",
		"mode": "COOP",
		"disconnected": true
	}

	SignalBus.game_over.emit(false, stats)
	StateManager.change_state("game_over", {"won": false, "stats": stats, "mode": "COOP", "disconnected": true})

func _on_network_score(partner_score: int) -> void:
	# Legacy signal handler
	pass

func _on_network_player_moved(pos: Vector2) -> void:
	# HOST receives player position from CLIENT (P2)
	# Update player position on host's screen
	if is_host and player:
		player.global_position = pos

func _on_network_tower_effect(data: Dictionary) -> void:
	# CLIENT receives tower effect from HOST
	if is_host:
		return

	var effect_type = str(data.get("type", ""))

	match effect_type:
		"gun":
			var pos = Vector2(float(data.x), float(data.y))
			EffectsManager.spawn_hit_effect(pos, self)
			SoundManager.play_tower_shoot()
		"tesla":
			var positions = data.get("positions", [])
			for pos_data in positions:
				var pos = Vector2(float(pos_data.x), float(pos_data.y))
				spawn_electric_hit_effect(pos)
			if positions.size() > 0:
				SoundManager.play_tesla_zap()
		"freeze":
			var positions = data.get("positions", [])
			for pos_data in positions:
				var pos = Vector2(float(pos_data.x), float(pos_data.y))
				spawn_blue_hit_effect(pos)

func _on_network_tower_placed(data: Dictionary) -> void:
	# HOST receives tower placement from CLIENT (P2)
	# Add tower to BuildManager so HOST can run tower logic
	if not is_host:
		return

	var tower_type = int(data.type)
	var stats: Dictionary = BuildManager.TOWER_STATS[tower_type].duplicate()

	var tower := {
		"x": float(data.x),
		"y": float(data.y),
		"type": tower_type,
		"stats": stats,
		"level": 1,
		"last_activation": 0.0,
		"target": null,
		"is_active": true
	}

	BuildManager.towers.append(tower)
	BuildManager.tower_placed.emit(tower)  # Trigger visual creation
	DebugHelper.log_info("HOST: Received tower from P2 - %s at (%.0f, %.0f)" % [stats.name, float(data.x), float(data.y)])

# ============================================
# TOWER EFFECTS
# ============================================

func process_tower_results(results: Array) -> void:
	for result in results:
		var action = result.get("action", "")
		var data = result.get("data", {})

		match action:
			"gun_fire":
				var target = data.get("target")
				if target and is_instance_valid(target):
					var pos = target.global_position
					EffectsManager.spawn_hit_effect(pos, self)
					SoundManager.play_tower_shoot()
					# Send to client
					NetworkManager.send_message("coop_tower_effect", {
						"type": "gun",
						"x": pos.x,
						"y": pos.y
					})
			"tesla_push":
				var affected_enemies = data.get("enemies", [])
				var positions = []
				for enemy in affected_enemies:
					if is_instance_valid(enemy):
						var pos = enemy.global_position
						spawn_electric_hit_effect(pos)
						positions.append({"x": pos.x, "y": pos.y})
				if affected_enemies.size() > 0:
					SoundManager.play_tesla_zap()
					# Send to client
					NetworkManager.send_message("coop_tower_effect", {
						"type": "tesla",
						"positions": positions
					})
			"freeze_slow":
				var affected_enemies = data.get("enemies", [])
				var positions = []
				for enemy in affected_enemies:
					if is_instance_valid(enemy):
						var pos = enemy.global_position
						spawn_blue_hit_effect(pos)
						positions.append({"x": pos.x, "y": pos.y})
				if positions.size() > 0:
					# Send to client
					NetworkManager.send_message("coop_tower_effect", {
						"type": "freeze",
						"positions": positions
					})

func spawn_blue_hit_effect(pos: Vector2) -> void:
	if BlueHitEffect == null:
		return
	var effect = BlueHitEffect.instantiate()
	effect.global_position = pos
	add_child(effect)

func spawn_electric_hit_effect(pos: Vector2) -> void:
	if ElectricHitEffect == null:
		return
	var effect = ElectricHitEffect.instantiate()
	effect.global_position = pos
	add_child(effect)

# ============================================
# SWITCH SYSTEM
# ============================================

func trigger_switch() -> void:
	DebugHelper.log_info("SWITCH triggered!")
	switch_cooldown_timer = SWITCH_COOLDOWN
	switch_effect_active = true
	switch_effect_timer = SWITCH_EFFECT_DURATION

	if switch_overlay:
		switch_overlay.visible = true
		switch_overlay.color = Color(1, 1, 1, 1)
	if switch_label:
		switch_label.text = "SWITCH!"
		switch_label.modulate = Color(0, 0, 0, 1)

	SoundManager.play_powerup_collect()

func update_switch_effect() -> void:
	if not switch_overlay:
		return

	var progress = 1.0 - (switch_effect_timer / SWITCH_EFFECT_DURATION)
	var alpha: float
	if progress < 0.5:
		alpha = progress * 2.0
	else:
		alpha = (1.0 - progress) * 2.0

	var hue = fmod(progress * 2.0, 1.0)
	var flash_color = Color.from_hsv(hue, 0.8, 1.0, alpha)
	switch_overlay.color = flash_color

func end_switch_effect() -> void:
	switch_effect_active = false
	if switch_overlay:
		switch_overlay.visible = false

	# Swap roles locally
	local_role = 2 if local_role == 1 else 1

	# Update player movement based on new role
	if player:
		var can_move = (local_role == 2)  # Player role can move
		player.movement_enabled = can_move
		DebugHelper.log_info("SWITCH: Role changed to %d, movement_enabled=%s" % [local_role, can_move])

	SoundManager.play_game_start()

# ============================================
# BUILD MODE HANDLING
# ============================================

func handle_build_result(result: Dictionary) -> void:
	match result.action:
		"typing":
			SoundManager.play_type_correct()
		"tower_selected":
			SoundManager.play_word_complete()
			DebugHelper.log_info("Tower selected: %s - Select position 0-9" % result.data.command)
		"tower_placed":
			SoundManager.play_powerup_collect()
			DebugHelper.log_info("Tower placed at position %d!" % result.data.position)
			# Sync tower to partner so HOST can run tower logic
			var tower = result.data.tower
			NetworkManager.send_message("coop_tower_placed", {
				"x": tower.x,
				"y": tower.y,
				"type": tower.type
			})
		"cancel":
			SoundManager.play_menu_back()
			DebugHelper.log_info("Build mode cancelled")
		"invalid":
			SoundManager.play_type_error()
		"insufficient_points":
			SoundManager.play_type_error()
			DebugHelper.log_info("Not enough build points! Need %d, have %d" % [result.data.required, result.data.available])
		"wave_limit":
			SoundManager.play_type_error()
			DebugHelper.log_info("Tower limit reached for this wave (max %d)" % result.data.max)
		"position_occupied":
			SoundManager.play_type_error()
			DebugHelper.log_info("Position %d is occupied!" % result.data.position)
		"tower_failed":
			SoundManager.play_type_error()
			DebugHelper.log_info("Failed to place tower: %s" % result.data.get("reason", "unknown"))
		"position_cancelled":
			SoundManager.play_menu_back()

# ============================================
# SIGNAL HANDLERS
# ============================================

func _on_enemy_reached_portal(enemy: Node) -> void:
	var enemy_id = get_enemy_id(enemy)
	if enemy_id >= 0:
		enemies_by_id.erase(enemy_id)
		if word_reservations.has(enemy_id):
			word_reservations.erase(enemy_id)

func _on_portal_destroyed() -> void:
	_trigger_game_over(false, "Portal destroyed")

func _on_player_died() -> void:
	_trigger_game_over(false, "Player died")

func _on_wave_completed(wave_number: int) -> void:
	DebugHelper.log_info("COOP Wave %d completed!" % wave_number)
	BuildManager.reset_wave()
	BuildManager.add_build_points(25 + wave_number * 5)

func _trigger_game_over(won: bool, reason: String) -> void:
	if not game_active:
		return

	game_active = false

	var stats = {
		"score": total_score,
		"p1_score": p1_contribution,
		"p2_score": p2_contribution,
		"combo": combo,
		"max_combo": max_combo,
		"wave": wave_manager.current_wave if wave_manager else 0,
		"death_reason": reason,
		"mode": "COOP"
	}

	# Send game over to partner
	NetworkManager.send_message("coop_game_over", {
		"won": won,
		"score": total_score,
		"p1_score": p1_contribution,
		"p2_score": p2_contribution,
		"wave": wave_manager.current_wave if wave_manager else 0,
		"reason": reason
	})

	SignalBus.game_over.emit(won, stats)
	StateManager.change_state("game_over", {"won": won, "stats": stats, "mode": "COOP"})

func update_hud() -> void:
	if typing_hud and typing_hud.has_method("update_stats"):
		typing_hud.update_stats({
			"score": total_score,
			"combo": combo,
			"max_combo": max_combo,
			"accuracy": 100.0,
			"enemies_remaining": enemy_container.get_child_count() if enemy_container else 0,
			"wave": wave_manager.current_wave if wave_manager else 0,
			"portal_hp": portal.current_hp if portal else 0,
			"portal_max_hp": portal.max_hp if portal else 0,
			"player_hp": player.current_hp if player else 0,
			"player_max_hp": player.max_hp if player else 0,
			"active_word": active_enemy.word if active_enemy and is_instance_valid(active_enemy) else "",
			"typed_index": typed_buffer.length(),
			"p1_score": p1_contribution,
			"p2_score": p2_contribution,
			"local_role": local_role,
			"nuke_p1": nuke_p1_ready,
			"nuke_p2": nuke_p2_ready
		})
