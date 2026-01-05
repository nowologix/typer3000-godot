## word_war_manager.gd
## Core VS mode "Word War" manager
## Handles: production words, units, bases, rounds, power-ups
extends Node

# ============================================
# CONFIGURATION
# ============================================
const SCREEN_WIDTH: int = 1280
const SCREEN_HEIGHT: int = 720

# Gate dimensions
const GATE_WIDTH: int = 80
const GATE_HEIGHT: int = 720

# Base positions
const BASE_P1_X: int = 60  # Left gate center
const BASE_P2_X: int = 1220  # Right gate center
const BASE_HP: int = 100

# Neutral zone (word spawn area)
const NEUTRAL_ZONE_START: int = 300
const NEUTRAL_ZONE_END: int = 980
const NEUTRAL_ZONE_Y_MIN: int = 100
const NEUTRAL_ZONE_Y_MAX: int = 620

# Production words
const PRODUCTION_WORD_COUNT: int = 6
const PRODUCTION_SPAWN_INTERVAL: float = 2.0
const WORD_MIN_LENGTH: int = 3
const WORD_MAX_LENGTH: int = 8

# Units
const UNIT_BASE_SPEED: float = 60.0  # pixels per second
const UNIT_DAMAGE_PER_LETTER: int = 2

# Power-ups
const POWERUP_SPAWN_INTERVAL: float = 5.0  # seconds
const POWERUP_MAX_ACTIVE: int = 2
const SMOKE_DURATION: float = 8.0  # seconds

# Match settings
const ROUNDS_TO_WIN: int = 2  # Best of 3
const ROUND_START_DELAY: float = 3.0
const ROUND_END_DELAY: float = 2.0

# ============================================
# ENUMS
# ============================================
enum GameState { IDLE, COUNTDOWN, PLAYING, ROUND_END, MATCH_END }
enum PowerUpType { SMOKE, SHIELD, HEAL }

# ============================================
# GAME STATE
# ============================================
var state: GameState = GameState.IDLE
var match_active: bool = false
var round_active: bool = false
var current_round: int = 0
var p1_wins: int = 0
var p2_wins: int = 0
var match_winner: int = 0

# Base HP
var p1_base_hp: int = BASE_HP
var p2_base_hp: int = BASE_HP

# Production words
var production_words: Array = []  # [{word, x, y, typed_chars_p1, typed_chars_p2}]
var last_word_spawn: float = 0.0

# Units
var units: Array = []  # [{word, owner, x, y, target_x, speed, direction, damage, typed_chars, alive}]

# Power-ups
var active_powerups: Array = []
var p1_effects: Array = []  # Active effects on P1
var p2_effects: Array = []  # Active effects on P2
var last_powerup_spawn: float = 0.0

# Smoke clouds
var smoke_clouds: Array = []  # [{x, y, owner, start_time, duration}]

# Typing buffers (buffer-based like singleplayer)
var p1_buffer: String = ""
var p2_buffer: String = ""

# Timing
var countdown_timer: float = 0.0
var round_end_timer: float = 0.0
var game_time: float = 0.0
var sync_timer: float = 0.0
const SYNC_INTERVAL: float = 0.1  # 100ms sync rate

# Network/Local
var is_host: bool = true
var local_player: int = 1  # 1 or 2
var is_networked: bool = false

# Word pool
var word_pool: Array = []

# ============================================
# SIGNALS
# ============================================
signal word_spawned(word_data: Dictionary)
signal word_completed(word: String, player: int)
signal unit_spawned(unit_data: Dictionary)
signal unit_killed(unit_data: Dictionary, killed_by: int)
signal base_damaged(player: int, damage: int, remaining_hp: int)
signal round_started(round_num: int)
signal round_ended(winner: int)
signal match_ended(winner: int)
signal powerup_spawned(powerup_data: Dictionary)
signal powerup_collected(powerup_type: int, player: int)
signal smoke_spawned(smoke_data: Dictionary)
signal countdown_tick(seconds: int)
signal game_state_changed(new_state: GameState)

func _ready() -> void:
	load_word_pool()
	DebugHelper.log_info("WordWarManager initialized")

func load_word_pool() -> void:
	word_pool = [
		"SWIFT", "BLAZE", "STORM", "QUICK", "FLASH", "SPARK", "POWER", "SPEED",
		"BRAVE", "FORCE", "SHARP", "LIGHT", "STEEL", "FLAME", "FROST", "RAPID",
		"STRIKE", "CLASH", "BURST", "SURGE", "BLAST", "CRASH", "SMASH", "DODGE",
		"BLOCK", "GUARD", "CHARGE", "COMBO", "PULSE", "DRIVE", "GLIDE", "CYBER",
		"NEXUS", "PROXY", "CACHE", "DEBUG", "PARSE", "STACK", "QUEUE", "CRYPT",
		"VIRUS", "PATCH", "CODEC", "PIXEL", "VOXEL", "RENDER", "SHADER", "BUFFER"
	]

func _process(delta: float) -> void:
	if not match_active:
		return

	game_time += delta

	match state:
		GameState.COUNTDOWN:
			update_countdown(delta)
		GameState.PLAYING:
			update_playing(delta)
		GameState.ROUND_END:
			update_round_end(delta)
	
	# Network sync (host broadcasts state)
	if is_networked and is_host:
		sync_timer += delta
		if sync_timer >= SYNC_INTERVAL:
			sync_timer = 0.0
			broadcast_state()

# ============================================
# GAME FLOW
# ============================================
func init_match(options: Dictionary = {}) -> void:
	reset()

	is_host = options.get("is_host", true)
	local_player = options.get("local_player", 1)
	is_networked = options.get("networked", false)

	var game_seed = options.get("seed", randi())
	seed(game_seed)

	match_active = true
	current_round = 1
	state = GameState.COUNTDOWN
	countdown_timer = ROUND_START_DELAY

	emit_signal("game_state_changed", state)
	DebugHelper.log_info("WordWarManager: Match initialized (host=%s, player=%d)" % [is_host, local_player])

func reset() -> void:
	state = GameState.IDLE
	match_active = false
	round_active = false
	current_round = 0
	p1_wins = 0
	p2_wins = 0
	match_winner = 0
	p1_base_hp = BASE_HP
	p2_base_hp = BASE_HP
	production_words.clear()
	units.clear()
	active_powerups.clear()
	p1_effects.clear()
	p2_effects.clear()
	smoke_clouds.clear()
	p1_buffer = ""
	p2_buffer = ""
	game_time = 0.0

func start_round() -> void:
	p1_base_hp = BASE_HP
	p2_base_hp = BASE_HP
	production_words.clear()
	units.clear()
	active_powerups.clear()
	smoke_clouds.clear()
	p1_buffer = ""
	p2_buffer = ""
	last_word_spawn = game_time
	last_powerup_spawn = game_time

	# Spawn initial words (host only in networked)
	if is_host or not is_networked:
		for i in range(PRODUCTION_WORD_COUNT):
			spawn_production_word()

	round_active = true
	state = GameState.PLAYING
	emit_signal("round_started", current_round)
	emit_signal("game_state_changed", state)
	DebugHelper.log_info("WordWarManager: Round %d started" % current_round)

func end_round(winner: int) -> void:
	round_active = false
	state = GameState.ROUND_END
	round_end_timer = ROUND_END_DELAY

	if winner == 1:
		p1_wins += 1
	else:
		p2_wins += 1

	emit_signal("round_ended", winner)
	emit_signal("game_state_changed", state)
	DebugHelper.log_info("WordWarManager: Round %d won by Player %d" % [current_round, winner])

	# Check for match win
	if p1_wins >= ROUNDS_TO_WIN:
		end_match(1)
	elif p2_wins >= ROUNDS_TO_WIN:
		end_match(2)

func end_match(winner: int) -> void:
	match_active = false
	match_winner = winner
	state = GameState.MATCH_END
	emit_signal("match_ended", winner)
	emit_signal("game_state_changed", state)
	DebugHelper.log_info("WordWarManager: Match won by Player %d" % winner)

# ============================================
# UPDATE LOOPS
# ============================================
func update_countdown(delta: float) -> void:
	var prev_seconds = int(countdown_timer)
	countdown_timer -= delta
	var curr_seconds = int(countdown_timer)

	if curr_seconds != prev_seconds and curr_seconds >= 0:
		emit_signal("countdown_tick", curr_seconds + 1)

	if countdown_timer <= 0:
		start_round()

func update_playing(delta: float) -> void:
	# Spawn production words (host only)
	if is_host or not is_networked:
		if game_time - last_word_spawn >= PRODUCTION_SPAWN_INTERVAL:
			if production_words.size() < PRODUCTION_WORD_COUNT:
				spawn_production_word()
			last_word_spawn = game_time

		# Spawn power-ups
		if game_time - last_powerup_spawn >= POWERUP_SPAWN_INTERVAL:
			if active_powerups.size() < POWERUP_MAX_ACTIVE:
				spawn_powerup()
			last_powerup_spawn = game_time

	# Update units
	update_units(delta)

	# Update smoke clouds
	update_smoke_clouds()

	# Update effects
	update_effects()

	# Check win condition
	if p1_base_hp <= 0:
		end_round(2)
	elif p2_base_hp <= 0:
		end_round(1)

func update_round_end(delta: float) -> void:
	round_end_timer -= delta
	if round_end_timer <= 0:
		if match_winner == 0:
			# Start next round
			current_round += 1
			state = GameState.COUNTDOWN
			countdown_timer = ROUND_START_DELAY
			emit_signal("game_state_changed", state)

func update_units(delta: float) -> void:
	for i in range(units.size() - 1, -1, -1):
		var unit = units[i]
		if not unit.alive:
			units.remove_at(i)
			continue

		# Move unit
		unit.x += unit.direction * unit.speed * delta

		# Check if reached target base
		var reached = false
		if unit.direction > 0 and unit.x >= unit.target_x:
			reached = true
		elif unit.direction < 0 and unit.x <= unit.target_x:
			reached = true

		if reached:
			deal_base_damage(unit)
			units.remove_at(i)

func update_smoke_clouds() -> void:
	var current_time = game_time
	for i in range(smoke_clouds.size() - 1, -1, -1):
		var smoke = smoke_clouds[i]
		if current_time - smoke.start_time >= smoke.duration:
			smoke_clouds.remove_at(i)

func update_effects() -> void:
	# Remove expired effects
	for i in range(p1_effects.size() - 1, -1, -1):
		var effect = p1_effects[i]
		if effect.duration > 0 and game_time - effect.start_time >= effect.duration:
			p1_effects.remove_at(i)

	for i in range(p2_effects.size() - 1, -1, -1):
		var effect = p2_effects[i]
		if effect.duration > 0 and game_time - effect.start_time >= effect.duration:
			p2_effects.remove_at(i)

# ============================================
# WORD SPAWNING
# ============================================
func spawn_production_word() -> void:
	var word = get_random_word()
	var x = randf_range(NEUTRAL_ZONE_START, NEUTRAL_ZONE_END)
	var y = randf_range(NEUTRAL_ZONE_Y_MIN, NEUTRAL_ZONE_Y_MAX)

	# Check for overlap with existing words
	var valid = true
	for existing in production_words:
		var dist = Vector2(existing.x - x, existing.y - y).length()
		if dist < 100:
			valid = false
			break

	if not valid:
		return  # Skip this spawn

	var word_data = {
		"word": word,
		"x": x,
		"y": y,
		"typed_chars_p1": 0,
		"typed_chars_p2": 0,
		"claimed_by": 0,  # 0 = unclaimed, 1 = P1, 2 = P2
		"is_powerup": false,
		"powerup_type": -1
	}

	production_words.append(word_data)
	emit_signal("word_spawned", word_data)

func get_random_word() -> String:
	# Avoid words already in play
	var active_words = []
	for w in production_words:
		active_words.append(w.word)
	for u in units:
		active_words.append(u.word)

	var attempts = 0
	var word = ""
	while attempts < 20:
		word = word_pool[randi() % word_pool.size()]
		if word not in active_words:
			break
		attempts += 1

	return word

# ============================================
# POWER-UP SPAWNING
# ============================================
func spawn_powerup() -> void:
	var powerup_types = [PowerUpType.SMOKE, PowerUpType.SHIELD, PowerUpType.HEAL]
	var ptype = powerup_types[randi() % powerup_types.size()]
	var pname = PowerUpType.keys()[ptype]

	var x = randf_range(NEUTRAL_ZONE_START, NEUTRAL_ZONE_END)
	var y = randf_range(NEUTRAL_ZONE_Y_MIN, NEUTRAL_ZONE_Y_MAX)

	var powerup_data = {
		"word": pname,
		"x": x,
		"y": y,
		"typed_chars_p1": 0,
		"typed_chars_p2": 0,
		"claimed_by": 0,
		"is_powerup": true,
		"powerup_type": ptype
	}

	active_powerups.append(powerup_data)
	emit_signal("powerup_spawned", powerup_data)

# ============================================
# INPUT PROCESSING
# ============================================
func reset_typed_chars(player_id: int) -> void:
	# Reset typed progress for a player on all entities
	for w in production_words:
		if player_id == 1:
			w.typed_chars_p1 = 0
		else:
			w.typed_chars_p2 = 0
	for p in active_powerups:
		if player_id == 1:
			p.typed_chars_p1 = 0
		else:
			p.typed_chars_p2 = 0
	for u in units:
		if u.owner != player_id:
			u.typed_chars = 0

func process_char(char: String, player_id: int) -> Dictionary:
	if not round_active or state != GameState.PLAYING:
		return {"action": "none"}

	char = char.to_upper()

	# Add to player's buffer
	if player_id == 1:
		p1_buffer += char
	else:
		p2_buffer += char

	var buffer = p1_buffer if player_id == 1 else p2_buffer

	# Find matching entities
	var matching_words = []
	var matching_powerups = []
	var matching_units = []

	for w in production_words:
		if w.claimed_by == 0 and w.word.begins_with(buffer):
			matching_words.append(w)

	for p in active_powerups:
		if p.claimed_by == 0 and p.word.begins_with(buffer):
			matching_powerups.append(p)

	for u in units:
		if u.owner != player_id and u.alive and u.word.begins_with(buffer):
			matching_units.append(u)

	var has_match = matching_words.size() > 0 or matching_powerups.size() > 0 or matching_units.size() > 0

	# No match - reset buffer and typed progress
	if not has_match:
		reset_typed_chars(player_id)
		if player_id == 1:
			p1_buffer = ""
		else:
			p2_buffer = ""
		return {"action": "miss"}

	# Update typed chars on matching entities
	for w in matching_words:
		if player_id == 1:
			w.typed_chars_p1 = buffer.length()
		else:
			w.typed_chars_p2 = buffer.length()

	for p in matching_powerups:
		if player_id == 1:
			p.typed_chars_p1 = buffer.length()
		else:
			p.typed_chars_p2 = buffer.length()

	for u in matching_units:
		u.typed_chars = buffer.length()

	# Check for completed production words
	for w in matching_words:
		var typed = w.typed_chars_p1 if player_id == 1 else w.typed_chars_p2
		if typed >= w.word.length():
			on_word_completed(w, player_id)
			reset_typed_chars(player_id)
			if player_id == 1:
				p1_buffer = ""
			else:
				p2_buffer = ""
			return {"action": "word_completed", "word": w.word}

	# Check for completed power-ups
	for p in matching_powerups:
		var typed = p.typed_chars_p1 if player_id == 1 else p.typed_chars_p2
		if typed >= p.word.length():
			on_powerup_collected(p, player_id)
			reset_typed_chars(player_id)
			if player_id == 1:
				p1_buffer = ""
			else:
				p2_buffer = ""
			return {"action": "powerup_collected", "type": p.powerup_type}

	# Check for killed enemy units
	for u in matching_units:
		if u.typed_chars >= u.word.length():
			u.alive = false
			emit_signal("unit_killed", u, player_id)
			reset_typed_chars(player_id)
			if player_id == 1:
				p1_buffer = ""
			else:
				p2_buffer = ""
			return {"action": "unit_killed", "unit": u}

	return {"action": "hit"}

# ============================================
# GAME EVENTS
# ============================================
func on_word_completed(word_data: Dictionary, player_id: int) -> void:
	word_data.claimed_by = player_id

	# Remove from production words
	var idx = production_words.find(word_data)
	if idx >= 0:
		production_words.remove_at(idx)

	# Spawn unit
	spawn_unit(word_data.word, player_id)
	emit_signal("word_completed", word_data.word, player_id)

func on_powerup_collected(powerup_data: Dictionary, player_id: int) -> void:
	powerup_data.claimed_by = player_id

	# Remove from active powerups
	var idx = active_powerups.find(powerup_data)
	if idx >= 0:
		active_powerups.remove_at(idx)

	# Apply effect
	apply_powerup(powerup_data.powerup_type, player_id, powerup_data.x, powerup_data.y)
	emit_signal("powerup_collected", powerup_data.powerup_type, player_id)

func spawn_unit(word: String, owner: int) -> void:
	var start_x = BASE_P1_X + GATE_WIDTH if owner == 1 else BASE_P2_X - GATE_WIDTH
	var start_y = SCREEN_HEIGHT / 2 + randf_range(-50, 50)
	var target_x = BASE_P2_X if owner == 1 else BASE_P1_X
	var direction = 1 if owner == 1 else -1

	var unit_data = {
		"word": word,
		"owner": owner,
		"x": start_x,
		"y": start_y,
		"target_x": target_x,
		"speed": UNIT_BASE_SPEED + randf_range(-10, 10),
		"direction": direction,
		"damage": word.length() * UNIT_DAMAGE_PER_LETTER,
		"typed_chars": 0,
		"alive": true
	}

	units.append(unit_data)
	emit_signal("unit_spawned", unit_data)

func deal_base_damage(unit: Dictionary) -> void:
	var target_player = 2 if unit.owner == 1 else 1

	# Check for shield
	var effects = p1_effects if target_player == 1 else p2_effects
	var shield_idx = -1
	for i in range(effects.size()):
		if effects[i].type == PowerUpType.SHIELD:
			shield_idx = i
			break

	if shield_idx >= 0:
		effects.remove_at(shield_idx)
		DebugHelper.log_info("Shield blocked damage!")
		return

	# Apply damage
	if target_player == 1:
		p1_base_hp = max(0, p1_base_hp - unit.damage)
		emit_signal("base_damaged", 1, unit.damage, p1_base_hp)
	else:
		p2_base_hp = max(0, p2_base_hp - unit.damage)
		emit_signal("base_damaged", 2, unit.damage, p2_base_hp)

	DebugHelper.log_debug("Base damage: P%d took %d damage (HP: %d)" % [target_player, unit.damage, p1_base_hp if target_player == 1 else p2_base_hp])

func apply_powerup(ptype: int, player_id: int, px: float, py: float) -> void:
	var effects = p1_effects if player_id == 1 else p2_effects

	match ptype:
		PowerUpType.SMOKE:
			spawn_smoke(px, py, player_id)
		PowerUpType.SHIELD:
			effects.append({
				"type": PowerUpType.SHIELD,
				"start_time": game_time,
				"duration": 15.0
			})
		PowerUpType.HEAL:
			if player_id == 1:
				p1_base_hp = min(BASE_HP, p1_base_hp + 15)
			else:
				p2_base_hp = min(BASE_HP, p2_base_hp + 15)

	DebugHelper.log_info("Player %d collected %s" % [player_id, PowerUpType.keys()[ptype]])

func spawn_smoke(x: float, y: float, owner: int) -> void:
	var smoke_data = {
		"x": x,
		"y": y,
		"owner": owner,
		"start_time": game_time,
		"duration": SMOKE_DURATION
	}
	smoke_clouds.append(smoke_data)
	emit_signal("smoke_spawned", smoke_data)

# ============================================
# STATE ACCESS
# ============================================
func get_state() -> Dictionary:
	return {
		"state": state,
		"round": current_round,
		"p1_wins": p1_wins,
		"p2_wins": p2_wins,
		"p1_hp": p1_base_hp,
		"p2_hp": p2_base_hp,
		"max_hp": BASE_HP,
		"production_words": production_words,
		"units": units,
		"powerups": active_powerups,
		"smoke_clouds": smoke_clouds,
		"p1_effects": p1_effects,
		"p2_effects": p2_effects,
		"p1_buffer": p1_buffer,
		"p2_buffer": p2_buffer,
		"countdown": int(countdown_timer) + 1,
		"match_winner": match_winner
	}

func is_playing() -> bool:
	return state == GameState.PLAYING and round_active

# ============================================
# NETWORK SYNC
# ============================================
func broadcast_state() -> void:
	if not is_networked or not is_host:
		return

	# Serialize full game state for clients
	var state_data = {
		"state": state,
		"round": current_round,
		"p1_wins": p1_wins,
		"p2_wins": p2_wins,
		"p1_hp": p1_base_hp,
		"p2_hp": p2_base_hp,
		"countdown": countdown_timer,
		"game_time": game_time,
		"p1_buffer": p1_buffer,
		"p2_buffer": p2_buffer,
		"production_words": production_words.duplicate(true),
		"units": units.duplicate(true),
		"powerups": active_powerups.duplicate(true),
		"smoke_clouds": smoke_clouds.duplicate(true),
		"round_active": round_active,
		"match_winner": match_winner
	}

	NetworkManager.send_message("wordwar_state", {"state": state_data})

func apply_network_state(state_data: Dictionary) -> void:
	# Use NetworkManager.is_host to handle state arriving before init_match()
	if NetworkManager.is_host:
		return  # Host doesn't receive state updates

	# Mark as networked client if not already set
	is_networked = true
	is_host = false
	match_active = true

	# Apply state from host
	state = state_data.get("state", GameState.IDLE)
	current_round = state_data.get("round", 1)
	p1_wins = state_data.get("p1_wins", 0)
	p2_wins = state_data.get("p2_wins", 0)
	p1_base_hp = state_data.get("p1_hp", BASE_HP)
	p2_base_hp = state_data.get("p2_hp", BASE_HP)
	countdown_timer = state_data.get("countdown", 0.0)
	game_time = state_data.get("game_time", 0.0)
	p1_buffer = state_data.get("p1_buffer", "")
	p2_buffer = state_data.get("p2_buffer", "")
	round_active = state_data.get("round_active", false)
	match_winner = state_data.get("match_winner", 0)

	# Sync arrays
	if state_data.has("production_words"):
		production_words = state_data.production_words.duplicate(true)
	if state_data.has("units"):
		units = state_data.units.duplicate(true)
	if state_data.has("powerups"):
		active_powerups = state_data.powerups.duplicate(true)
	if state_data.has("smoke_clouds"):
		smoke_clouds = state_data.smoke_clouds.duplicate(true)

	# Set match_active based on state
	match_active = state != GameState.IDLE and state != GameState.MATCH_END
