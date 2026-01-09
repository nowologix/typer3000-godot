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
signal sniper_fired(sniper: Node, target: Node)

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
# BOSS SIGNALS
# ============================================
signal boss_spawned(boss: Node, level: int)
signal boss_phase_complete(boss: Node, remaining_hp: int)
signal boss_defeated(boss: Node)

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
signal network_game_start(seed: int, mode: String, language: String)
signal network_score_update(player_id: int, score: int)
signal network_word_completed(player_id: int, word: String)
signal network_game_over(winner_id: int, final_scores: Dictionary)

# ============================================
# VS MODE SIGNALS
# ============================================
signal opponent_score_update(score: int)
signal opponent_died(reason: String)
signal vs_opponent_game_over(data: Dictionary)

# ============================================
# COOP MODE SIGNALS (Host-Authoritative)
# ============================================
signal coop_partner_score(score: int)
signal coop_enemy_killed(word: String, points: int)
signal coop_enemy_killed_v2(data: Dictionary)  # New format with enemy_id
signal coop_word_reserved(word: String, player_id: int)
signal coop_word_released(word: String)
signal coop_player_moved(position: Vector2)
signal coop_switch_triggered()
signal coop_switch()

# Host -> Client sync signals
signal coop_spawn_enemy(data: Dictionary)
signal coop_spawn_powerup(data: Dictionary)
signal coop_state(data: Dictionary)
signal coop_typing(data: Dictionary)
signal coop_nuke_typed(data: Dictionary)
signal coop_powerup_collected(data: Dictionary)
signal coop_game_over(data: Dictionary)
signal coop_reserve(data: Dictionary)
signal coop_release(data: Dictionary)
signal coop_tower_placed(data: Dictionary)
signal coop_tower_effect(data: Dictionary)

# ============================================
# STEAM SIGNALS
# ============================================
signal achievement_unlocked(achievement_key: String, achievement_name: String)
signal leaderboard_received(entries: Array)

# UI/Settings signals
signal language_changed()

func _ready() -> void:
	DebugHelper.log_info("SignalBus initialized")
