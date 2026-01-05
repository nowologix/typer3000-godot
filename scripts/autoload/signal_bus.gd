## signal_bus.gd
## Global signal bus for decoupled communication
## Autoload singleton: SignalBus
extends Node

# ============================================
# TYPING SIGNALS
# ============================================
signal char_typed(char: String, correct: bool)
signal word_started(enemy: Node)
signal word_completed(enemy: Node, combo: int)
signal word_failed(enemy: Node)
signal combo_updated(combo: int)
signal combo_reset()

# ============================================
# ENEMY SIGNALS
# ============================================
signal enemy_spawned(enemy: Node)
signal enemy_killed(enemy: Node, typed: bool)
signal enemy_reached_portal(enemy: Node)

# ============================================
# PLAYER SIGNALS
# ============================================
signal player_damaged(damage: int, current_hp: int)
signal player_died()
signal player_healed(amount: int)

# ============================================
# PORTAL SIGNALS
# ============================================
signal portal_damaged(damage: int, current_hp: int)
signal portal_destroyed()

# ============================================
# WAVE SIGNALS
# ============================================
signal wave_started(wave_number: int)
signal wave_completed(wave_number: int)
signal all_waves_completed()

# ============================================
# GAME STATE SIGNALS
# ============================================
signal game_started()
signal game_paused()
signal game_resumed()
signal game_over(won: bool, stats: Dictionary)

# ============================================
# UI SIGNALS
# ============================================
signal score_updated(score: int)
signal stats_updated(stats: Dictionary)

# ============================================
# POWERUP SIGNALS
# ============================================
signal powerup_spawned(powerup: Node)
signal powerup_collected(type: int, name: String)
signal powerup_expired(type: int, name: String)
signal shield_activated(duration: float)
signal shield_deactivated()
signal score_multiplier_changed(multiplier: float)
signal rapid_mode_activated(duration: float)
signal rapid_mode_deactivated()
signal portal_heal(amount: int)

# ============================================
# TOWER SIGNALS
# ============================================
signal tower_built(tower: Node, position: Vector2)
signal tower_destroyed(tower: Node)
signal tower_upgraded(tower: Node, level: int)

# ============================================
# NETWORK SIGNALS
# ============================================
signal network_connected()
signal network_disconnected(reason: String)
signal lobby_created(code: String)
signal lobby_joined(code: String)
signal lobby_join_failed(reason: String)
signal player_joined(player_id: int, player_name: String)
signal player_left(player_id: int)
signal player_ready_changed(player_id: int, ready: bool)
signal network_game_start(seed: int)
signal network_score_update(player_id: int, score: int)
signal network_word_completed(player_id: int, word: String)
signal network_game_over(winner_id: int, final_scores: Dictionary)

# ============================================
# STEAM SIGNALS
# ============================================
signal achievement_unlocked(achievement_key: String, achievement_name: String)
signal leaderboard_received(entries: Array)

func _ready() -> void:
	DebugHelper.log_info("SignalBus initialized")
