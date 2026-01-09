## wordwar_state.gd
## WordWar VS mode - 1v1 competitive typing battle
## Two players, shared screen, gates on each side, spawn units by typing words
extends Control

# ============================================
# CONFIGURATION
# ============================================
const GATE_CONFIG = {
	"frame_width": 120,
	"frame_height": 1080,
	"columns": 10,
	"total_frames": 78,
	"fps": 24,
	"scale": 0.667  # Scale to fit 720 height
}

const SMOKE_CONFIG = {
	"frame_width": 256,
	"frame_height": 256,
	"columns": 12,
	"total_frames": 216,
	"fps": 24
}

# Colors
const COLOR_P1 := Color("#00E5FF")  # Cyan
const COLOR_P1_DIM := Color("#007A99")
const COLOR_P2 := Color("#FF2A8A")  # Magenta
const COLOR_P2_DIM := Color("#991A54")
const COLOR_NEUTRAL := Color.WHITE
const COLOR_POWERUP := Color("#7CFF00")  # Acid green
const COLOR_DEFENSE := Color("#FFB000")  # Amber
const COLOR_BG := Color("#05070D")
const COLOR_GRID := Color("#0F1420")

# ============================================
# STATE
# ============================================
var is_multiplayer: bool = false
var game_seed: int = 0
var local_player: int = 1
var pulse_phase: float = 0.0

# Gate animation
var gate_p1_texture: Texture2D = null
var gate_p2_texture: Texture2D = null
var gate_frame: int = 0
var gate_frame_timer: float = 0.0

# Smoke animation
var smoke_texture: Texture2D = null

func _ready() -> void:
	# Load gate textures
	gate_p1_texture = load("res://assets/sprites/gates/gate_p1_sheet.png")
	gate_p2_texture = load("res://assets/sprites/gates/gate_p2_sheet.png")

	# Load smoke texture - try normal load first, fallback to runtime Image loading
	smoke_texture = load("res://assets/sprites/effects/smokescreen_sheet.png")
	if not smoke_texture:
		# Fallback: Load PNG directly at runtime (bypasses import system)
		var img = Image.load_from_file("res://assets/sprites/effects/smokescreen_sheet.png")
		if img:
			smoke_texture = ImageTexture.create_from_image(img)
			DebugHelper.log_info("WordWarState: Smoke texture loaded via Image fallback")
		else:
			DebugHelper.log_warning("WordWarState: Failed to load smoke texture")

	if gate_p1_texture:
		DebugHelper.log_info("WordWarState: Gate textures loaded")
	else:
		DebugHelper.log_warning("WordWarState: Failed to load gate textures")

	if smoke_texture:
		DebugHelper.log_info("WordWarState: Smoke texture loaded (%dx%d)" % [smoke_texture.get_width(), smoke_texture.get_height()])
	else:
		DebugHelper.log_warning("WordWarState: Smoke texture not available")

func on_enter(params: Dictionary) -> void:
	DebugHelper.log_info("WordWarState entered")
	MenuBackground.hide_background()

	is_multiplayer = params.get("multiplayer", false)
	game_seed = params.get("seed", randi())

	# Determine local player
	if is_multiplayer:
		local_player = NetworkManager.player_id
	else:
		local_player = 1

	# Initialize WordWar
	WordWarManager.init_match({
		"is_host": not is_multiplayer or NetworkManager.is_host,
		"local_player": local_player,
		"networked": is_multiplayer,
		"seed": game_seed
	})

	# Connect signals
	WordWarManager.countdown_tick.connect(_on_countdown_tick)
	WordWarManager.round_started.connect(_on_round_started)
	WordWarManager.round_ended.connect(_on_round_ended)
	WordWarManager.match_ended.connect(_on_match_ended)
	WordWarManager.base_damaged.connect(_on_base_damaged)

	# Connect network signals for disconnect handling
	if is_multiplayer:
		SignalBus.network_disconnected.connect(_on_network_disconnected)
		SignalBus.player_left.connect(_on_player_left)

	SoundManager.play_game_start()

func on_exit() -> void:
	DebugHelper.log_info("WordWarState exiting")

	# Disconnect signals
	if WordWarManager.countdown_tick.is_connected(_on_countdown_tick):
		WordWarManager.countdown_tick.disconnect(_on_countdown_tick)
	if WordWarManager.round_started.is_connected(_on_round_started):
		WordWarManager.round_started.disconnect(_on_round_started)
	if WordWarManager.round_ended.is_connected(_on_round_ended):
		WordWarManager.round_ended.disconnect(_on_round_ended)
	if WordWarManager.match_ended.is_connected(_on_match_ended):
		WordWarManager.match_ended.disconnect(_on_match_ended)
	if WordWarManager.base_damaged.is_connected(_on_base_damaged):
		WordWarManager.base_damaged.disconnect(_on_base_damaged)

	# Disconnect network signals
	if SignalBus.network_disconnected.is_connected(_on_network_disconnected):
		SignalBus.network_disconnected.disconnect(_on_network_disconnected)
	if SignalBus.player_left.is_connected(_on_player_left):
		SignalBus.player_left.disconnect(_on_player_left)

func _process(delta: float) -> void:
	# Update animations
	pulse_phase = fmod(pulse_phase + delta * 5.0, TAU)

	# Gate animation
	gate_frame_timer += delta
	if gate_frame_timer >= 1.0 / GATE_CONFIG.fps:
		gate_frame_timer = 0
		gate_frame = (gate_frame + 1) % GATE_CONFIG.total_frames

	# Redraw
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		var char_code = event.unicode

		if event.keycode == KEY_ESCAPE:
			exit_to_menu()
			return

		# A-Z only
		var is_letter = (char_code >= 65 and char_code <= 90) or (char_code >= 97 and char_code <= 122)
		if is_letter and WordWarManager.is_playing():
			var typed_char = char(char_code).to_upper()
			var result = WordWarManager.process_char(typed_char, local_player)

			# Play sounds
			match result.action:
				"hit":
					SoundManager.play_type_correct()
				"word_completed", "powerup_collected", "unit_killed":
					SoundManager.play_word_complete()
				"miss":
					SoundManager.play_type_error()

			# Network sync
			if is_multiplayer:
				NetworkManager.send_message("player_input", {
					"char": typed_char,
					"playerId": local_player
				})

func _draw() -> void:
	var game_state = WordWarManager.get_state()

	# Background
	draw_rect(Rect2(0, 0, 1280, 720), COLOR_BG)

	# Grid
	draw_grid()

	# Gates
	draw_gates(game_state)

	# HP bars
	draw_hp_bars(game_state)

	# Production words
	draw_production_words(game_state)

	# Power-ups
	draw_powerups(game_state)

	# Units
	draw_units(game_state)

	# Smoke clouds
	draw_smoke_clouds(game_state)

	# HUD
	draw_hud(game_state)

	# State overlays
	match game_state.state:
		WordWarManager.GameState.COUNTDOWN:
			draw_countdown(game_state)
		WordWarManager.GameState.ROUND_END:
			draw_round_end(game_state)
		WordWarManager.GameState.MATCH_END:
			draw_match_end(game_state)

# ============================================
# DRAWING FUNCTIONS
# ============================================
func draw_grid() -> void:
	for x in range(0, 1280, 64):
		draw_line(Vector2(x, 0), Vector2(x, 720), COLOR_GRID, 1.0)
	for y in range(0, 720, 64):
		draw_line(Vector2(0, y), Vector2(1280, y), COLOR_GRID, 1.0)

func draw_gates(game_state: Dictionary) -> void:
	var gate_width = int(GATE_CONFIG.frame_width * GATE_CONFIG.scale)
	var gate_height = int(GATE_CONFIG.frame_height * GATE_CONFIG.scale)

	if gate_p1_texture and gate_p2_texture:
		# Draw animated gates using sprite sheet
		var col = gate_frame % GATE_CONFIG.columns
		var row = int(gate_frame / GATE_CONFIG.columns)
		var src_rect = Rect2(
			col * GATE_CONFIG.frame_width,
			row * GATE_CONFIG.frame_height,
			GATE_CONFIG.frame_width,
			GATE_CONFIG.frame_height
		)

		# P1 gate (right side - blue)
		var p1_dest = Rect2(1280 - gate_width, 0, gate_width, gate_height)
		draw_texture_rect_region(gate_p1_texture, p1_dest, src_rect)

		# P2 gate (left side - pink)
		var p2_dest = Rect2(0, 0, gate_width, gate_height)
		draw_texture_rect_region(gate_p2_texture, p2_dest, src_rect)
	else:
		# Fallback: colored rectangles
		draw_rect(Rect2(0, 0, gate_width, 720), COLOR_P2_DIM)
		draw_rect(Rect2(0, 0, gate_width, 720), COLOR_P2, false, 3.0)
		draw_rect(Rect2(1280 - gate_width, 0, gate_width, 720), COLOR_P1_DIM)
		draw_rect(Rect2(1280 - gate_width, 0, gate_width, 720), COLOR_P1, false, 3.0)

	# Player labels
	var font = ThemeDB.fallback_font
	draw_string(font, Vector2(40, 30), "P2", HORIZONTAL_ALIGNMENT_CENTER, -1, 20, COLOR_P2)
	draw_string(font, Vector2(1240, 30), "P1", HORIZONTAL_ALIGNMENT_CENTER, -1, 20, COLOR_P1)

func draw_hp_bars(game_state: Dictionary) -> void:
	var bar_width = 80
	var bar_height = 8
	var font = ThemeDB.fallback_font

	# P2 HP (left)
	var p2_x = 40
	var p2_y = 680
	var p2_fill = float(game_state.p2_hp) / float(game_state.max_hp) * bar_width
	draw_rect(Rect2(p2_x - bar_width/2, p2_y, bar_width, bar_height), Color(0.1, 0.1, 0.1))
	draw_rect(Rect2(p2_x - bar_width/2, p2_y, p2_fill, bar_height), COLOR_P2)
	draw_rect(Rect2(p2_x - bar_width/2, p2_y, bar_width, bar_height), COLOR_P2, false, 1.0)
	draw_string(font, Vector2(p2_x - 20, p2_y + bar_height + 15), "%d/%d" % [game_state.p2_hp, game_state.max_hp], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_P2)

	# P1 HP (right)
	var p1_x = 1240
	var p1_y = 680
	var p1_fill = float(game_state.p1_hp) / float(game_state.max_hp) * bar_width
	draw_rect(Rect2(p1_x - bar_width/2, p1_y, bar_width, bar_height), Color(0.1, 0.1, 0.1))
	draw_rect(Rect2(p1_x - bar_width/2, p1_y, p1_fill, bar_height), COLOR_P1)
	draw_rect(Rect2(p1_x - bar_width/2, p1_y, bar_width, bar_height), COLOR_P1, false, 1.0)
	draw_string(font, Vector2(p1_x - 20, p1_y + bar_height + 15), "%d/%d" % [game_state.p1_hp, game_state.max_hp], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_P1)

func draw_production_words(game_state: Dictionary) -> void:
	var font = ThemeDB.fallback_font

	for word_data in game_state.production_words:
		if word_data.claimed_by != 0:
			continue

		var x = word_data.x
		var y = word_data.y
		var word = word_data.word

		# Get typed progress for both players
		var p1_typed = word_data.typed_chars_p1
		var p2_typed = word_data.typed_chars_p2

		# Determine which player's buffer matches
		var local_typed = p1_typed if local_player == 1 else p2_typed
		var remote_typed = p2_typed if local_player == 1 else p1_typed

		# Background glow if being typed
		if local_typed > 0 or remote_typed > 0:
			var glow_pulse = sin(pulse_phase * 3) * 0.3 + 0.7
			var glow_color = COLOR_P1 if local_typed >= remote_typed else COLOR_DEFENSE
			glow_color.a = glow_pulse * 0.4
			draw_circle(Vector2(x, y), 40, glow_color)

		# Draw word character by character
		var word_width = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		var start_x = x - word_width / 2

		for i in range(word.length()):
			var char_x = start_x + font.get_string_size(word.substr(0, i), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			var char_str = word[i]

			var char_color = COLOR_NEUTRAL
			var local_has = i < local_typed
			var remote_has = i < remote_typed

			if local_has and remote_has:
				char_color = COLOR_P2  # Both - contested
			elif local_has:
				char_color = COLOR_P1  # Local player
			elif remote_has:
				char_color = COLOR_DEFENSE  # Remote player

			draw_string(font, Vector2(char_x, y + 8), char_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, char_color)

		# Progress underlines
		if local_typed > 0:
			var line_width = font.get_string_size(word.substr(0, local_typed), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			draw_line(Vector2(start_x, y + 15), Vector2(start_x + line_width, y + 15), COLOR_P1, 3.0)
		if remote_typed > 0:
			var line_width = font.get_string_size(word.substr(0, remote_typed), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			draw_line(Vector2(start_x, y + 20), Vector2(start_x + line_width, y + 20), COLOR_DEFENSE, 3.0)

func draw_powerups(game_state: Dictionary) -> void:
	var font = ThemeDB.fallback_font

	for powerup in game_state.powerups:
		if powerup.claimed_by != 0:
			continue

		var x = powerup.x
		var y = powerup.y

		# Glow
		var pulse = sin(pulse_phase * 2) * 0.3 + 0.7
		var glow_color = COLOR_POWERUP
		glow_color.a = pulse * 0.5
		draw_circle(Vector2(x, y), 50, glow_color)

		# Label
		draw_string(font, Vector2(x - 30, y - 20), "[POWER]", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_POWERUP)

		# Word
		var word = powerup.word
		var word_width = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string(font, Vector2(x - word_width/2, y + 8), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, COLOR_POWERUP)

func draw_units(game_state: Dictionary) -> void:
	var font = ThemeDB.fallback_font

	for unit in game_state.units:
		if not unit.alive:
			continue

		var x = unit.x
		var y = unit.y
		var owner = unit.owner

		# Unit colors
		var unit_color = COLOR_P1 if owner == 1 else COLOR_P2
		var unit_color_dim = COLOR_P1_DIM if owner == 1 else COLOR_P2_DIM

		# Unit body
		draw_circle(Vector2(x, y), 18, unit_color_dim)
		draw_arc(Vector2(x, y), 18, 0, TAU, 32, unit_color, 2.0)

		# Direction arrow
		var arrow_dir = unit.direction
		var arrow_x = x + arrow_dir * 20
		var points = PackedVector2Array([
			Vector2(arrow_x, y),
			Vector2(arrow_x - arrow_dir * 12, y - 10),
			Vector2(arrow_x - arrow_dir * 12, y + 10)
		])
		draw_colored_polygon(points, unit_color)

		# Word above unit
		var word = unit.word
		var word_width = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var word_y = y - 30

		# Own units: gray (can't type them)
		# Enemy units: white with typed progress
		var is_own = owner == local_player

		if is_own:
			var gray = Color(0.5, 0.5, 0.5, 0.6)
			draw_string(font, Vector2(x - word_width/2, word_y), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, gray)
		else:
			# Background plate
			draw_rect(Rect2(x - word_width/2 - 4, word_y - 14, word_width + 8, 20), Color(0, 0, 0, 0.7))

			# Draw with typed progress
			var typed = unit.typed_chars
			for i in range(word.length()):
				var char_x = x - word_width/2 + font.get_string_size(word.substr(0, i), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
				var char_color = COLOR_POWERUP if i < typed else COLOR_NEUTRAL
				draw_string(font, Vector2(char_x, word_y), word[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, char_color)

		# Damage indicator
		draw_string(font, Vector2(x - 10, y + 35), "-%d" % unit.damage, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_DEFENSE)

func draw_smoke_clouds(game_state: Dictionary) -> void:
	if not smoke_texture:
		return

	for smoke in game_state.smoke_clouds:
		var elapsed = WordWarManager.game_time - smoke.start_time
		var remaining = smoke.duration - elapsed

		if remaining <= 0:
			continue

		# Fade in/out
		var alpha = 1.0
		if elapsed < 0.5:
			alpha = elapsed / 0.5
		elif remaining < 1.5:
			alpha = remaining / 1.5

		# Owner sees at 50%, opponent at 100%
		var is_owner = smoke.owner == local_player
		alpha *= 0.5 if is_owner else 1.0

		# Calculate frame
		var frame_idx = int(elapsed * SMOKE_CONFIG.fps) % SMOKE_CONFIG.total_frames
		var col = frame_idx % SMOKE_CONFIG.columns
		var row = int(frame_idx / SMOKE_CONFIG.columns)

		var src_rect = Rect2(
			col * SMOKE_CONFIG.frame_width,
			row * SMOKE_CONFIG.frame_height,
			SMOKE_CONFIG.frame_width,
			SMOKE_CONFIG.frame_height
		)

		var dest_rect = Rect2(
			smoke.x - SMOKE_CONFIG.frame_width / 2,
			smoke.y - SMOKE_CONFIG.frame_height / 2,
			SMOKE_CONFIG.frame_width,
			SMOKE_CONFIG.frame_height
		)

		draw_texture_rect_region(smoke_texture, dest_rect, src_rect, Color(1, 1, 1, alpha))

func draw_hud(game_state: Dictionary) -> void:
	var font = ThemeDB.fallback_font
	var center_x = 640

	# Round indicator
	draw_string(font, Vector2(center_x - 40, 30), "ROUND %d" % game_state.round, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, COLOR_NEUTRAL)

	# Win counters
	draw_string(font, Vector2(center_x - 80, 55), "P1: %d" % game_state.p1_wins, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_P1)
	draw_string(font, Vector2(center_x + 30, 55), "P2: %d" % game_state.p2_wins, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_P2)
	draw_string(font, Vector2(center_x - 5, 55), "/%d" % WordWarManager.ROUNDS_TO_WIN, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_NEUTRAL)

	# Instructions
	var instr = "Type words to spawn units | Type enemy units to defend"
	draw_string(font, Vector2(center_x - 220, 700), instr, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.5, 0.6))

func draw_countdown(game_state: Dictionary) -> void:
	# Darken background
	draw_rect(Rect2(0, 0, 1280, 720), Color(0, 0, 0, 0.85))

	var font = ThemeDB.fallback_font
	var center_x = 640
	var center_y = 360

	# Round number
	draw_string(font, Vector2(center_x - 60, center_y - 80), "ROUND %d" % game_state.round, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, COLOR_NEUTRAL)

	# Countdown number
	var seconds = game_state.countdown
	if seconds > 0:
		var count_color = COLOR_P1 if seconds == 3 else (Color("#FFD700") if seconds == 2 else COLOR_POWERUP)
		draw_string(font, Vector2(center_x - 20, center_y + 30), str(seconds), HORIZONTAL_ALIGNMENT_LEFT, -1, 72, count_color)
	else:
		draw_string(font, Vector2(center_x - 60, center_y + 30), "FIGHT!", HORIZONTAL_ALIGNMENT_LEFT, -1, 48, COLOR_POWERUP)

func draw_round_end(game_state: Dictionary) -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0, 0, 0, 0.8))

	var font = ThemeDB.fallback_font
	var center_x = 640
	var center_y = 360

	var winner = 1 if game_state.p1_hp > 0 else 2
	var winner_color = COLOR_P1 if winner == 1 else COLOR_P2

	draw_string(font, Vector2(center_x - 100, center_y - 20), "PLAYER %d WINS" % winner, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, winner_color)
	draw_string(font, Vector2(center_x - 50, center_y + 30), "ROUND %d" % game_state.round, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, COLOR_NEUTRAL)
	draw_string(font, Vector2(center_x - 30, center_y + 70), "%d - %d" % [game_state.p1_wins, game_state.p2_wins], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, COLOR_NEUTRAL)

func draw_match_end(game_state: Dictionary) -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0, 0, 0, 0.87))

	var font = ThemeDB.fallback_font
	var center_x = 640
	var center_y = 360

	var winner = game_state.match_winner
	var winner_color = COLOR_P1 if winner == 1 else COLOR_P2

	draw_string(font, Vector2(center_x - 80, center_y - 60), "MATCH OVER", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, COLOR_NEUTRAL)
	draw_string(font, Vector2(center_x - 120, center_y), "PLAYER %d WINS!" % winner, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, winner_color)
	draw_string(font, Vector2(center_x - 30, center_y + 50), "%d - %d" % [game_state.p1_wins, game_state.p2_wins], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, COLOR_NEUTRAL)
	draw_string(font, Vector2(center_x - 80, center_y + 120), "ESC to return", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.5, 0.5, 0.6))

# ============================================
# SIGNAL HANDLERS
# ============================================
func _on_countdown_tick(seconds: int) -> void:
	SoundManager.play_countdown() if seconds > 0 else SoundManager.play_game_start()

func _on_round_started(round_num: int) -> void:
	DebugHelper.log_info("Round %d started!" % round_num)

func _on_round_ended(winner: int) -> void:
	DebugHelper.log_info("Round ended, winner: P%d" % winner)
	if winner == local_player:
		SoundManager.play_victory()
	else:
		SoundManager.play_defeat()

func _on_match_ended(winner: int) -> void:
	DebugHelper.log_info("Match ended, winner: P%d" % winner)

	# Wait a moment then go to game over
	await get_tree().create_timer(3.0).timeout
	_go_to_game_over(winner == local_player, false)

func _on_base_damaged(player: int, damage: int, remaining_hp: int) -> void:
	DebugHelper.log_debug("P%d base hit for %d damage (HP: %d)" % [player, damage, remaining_hp])
	if player == local_player:
		SoundManager.play_portal_hit()

func exit_to_menu() -> void:
	if is_multiplayer:
		NetworkManager.leave_lobby()
	StateManager.change_state("menu")

func _on_network_disconnected(reason: String) -> void:
	DebugHelper.log_warning("Network disconnected during game: %s" % reason)
	_go_to_game_over(false, true)

func _on_player_left(player_id: int) -> void:
	DebugHelper.log_warning("Player %d left the game" % player_id)
	_go_to_game_over(false, true)

func _go_to_game_over(won: bool, disconnected: bool) -> void:
	var game_state = WordWarManager.get_state()

	# Build stats for local player
	var my_wins = game_state.p1_wins if local_player == 1 else game_state.p2_wins
	var opp_wins = game_state.p2_wins if local_player == 1 else game_state.p1_wins
	var my_hp = game_state.p1_hp if local_player == 1 else game_state.p2_hp
	var opp_hp = game_state.p2_hp if local_player == 1 else game_state.p1_hp

	var stats = {
		"score": my_wins,
		"opponent_score": opp_wins,
		"wave": game_state.round,
		"rounds_won": my_wins,
		"rounds_lost": opp_wins,
		"final_hp": my_hp,
		"opponent_hp": opp_hp,
		"mode": "WORDWAR",
		"disconnected": disconnected
	}

	# Add opponent stats for comparison (if not disconnected)
	if not disconnected:
		stats["opponent_stats"] = {
			"score": opp_wins,
			"wave": game_state.round,
			"rounds_won": opp_wins,
			"final_hp": opp_hp
		}

	WordWarManager.cleanup()
	SignalBus.game_over.emit(won, stats)
	StateManager.change_state("game_over", {"won": won, "stats": stats, "mode": "WORDWAR", "disconnected": disconnected})
