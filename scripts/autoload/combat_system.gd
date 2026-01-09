## combat_system.gd
## Manages combo multiplier, word rush, and combat bonuses
## Autoload singleton: CombatSystem
extends Node

# ============================================
# COMBO MULTIPLIER SYSTEM
# ============================================
# Multiplier increases at combo milestones
const MULTIPLIER_THRESHOLDS := {
	10: 2,   # x2 at 10 combo
	25: 3,   # x3 at 25 combo
	50: 4,   # x4 at 50 combo
	100: 5,  # x5 at 100 combo
}

var current_multiplier: int = 1
var combo_count: int = 0

# ============================================
# WORD RUSH SYSTEM
# ============================================
# Bar fills with each character, drains constantly
# When full, triggers slow-mo and instant kills

const RUSH_MAX: float = 100.0
const RUSH_GAIN_PER_CHAR: float = 3.0      # Gain per correct character
const RUSH_DRAIN_PER_SECOND: float = 8.0   # Drain per second
const RUSH_DURATION: float = 5.0            # How long word rush lasts
const RUSH_INSTANT_KILLS: int = 5           # Number of instant kills during rush

var rush_value: float = 0.0
var rush_active: bool = false
var rush_timer: float = 0.0
var rush_kills_remaining: int = 0

# ============================================
# BURST MODE EVOLUTION
# ============================================
# Kill 3 enemies in 5 seconds = 4th random enemy dies
const BURST_WINDOW: float = 5.0  # Time window for 3 kills
const BURST_KILLS_NEEDED: int = 3

var burst_enabled: bool = false  # Enabled via ProgressionManager
var burst_kill_times: Array[float] = []  # Timestamps of recent kills

# ============================================
# VAMPIRE EVOLUTION
# ============================================
# Every 20th word heals the portal
const VAMPIRE_HEAL_INTERVAL: int = 20
const VAMPIRE_HEAL_AMOUNT: int = 1

var vampire_enabled: bool = false  # Enabled via ProgressionManager
var vampire_kill_count: int = 0

# ============================================
# SIGNALS
# ============================================
signal multiplier_changed(multiplier: int)
signal rush_value_changed(value: float, max_value: float)
signal rush_activated(duration: float, instant_kills: int)
signal rush_deactivated()
signal rush_kill_used(remaining: int)
signal burst_triggered(killed_enemy: Node)
signal vampire_heal(amount: int)

# ============================================
# LIFECYCLE
# ============================================
func _ready() -> void:
	SignalBus.combo_updated.connect(_on_combo_updated)
	SignalBus.combo_reset.connect(_on_combo_reset)
	SignalBus.char_typed.connect(_on_char_typed)
	SignalBus.word_completed.connect(_on_word_completed)
	DebugHelper.log_info("CombatSystem initialized")

func _process(delta: float) -> void:
	# Drain rush bar when not in rush mode
	if not rush_active and rush_value > 0:
		rush_value = maxf(0.0, rush_value - RUSH_DRAIN_PER_SECOND * delta)
		rush_value_changed.emit(rush_value, RUSH_MAX)

	# Handle rush timer
	if rush_active:
		rush_timer -= delta
		if rush_timer <= 0:
			_deactivate_rush()

# ============================================
# COMBO MULTIPLIER
# ============================================
func _on_combo_updated(combo: int) -> void:
	combo_count = combo
	_update_multiplier()

func _on_combo_reset() -> void:
	combo_count = 0
	if current_multiplier > 1:
		current_multiplier = 1
		multiplier_changed.emit(current_multiplier)
		SignalBus.score_multiplier_changed.emit(1.0)

func _update_multiplier() -> void:
	var new_multiplier := 1

	for threshold in MULTIPLIER_THRESHOLDS.keys():
		if combo_count >= threshold:
			new_multiplier = MULTIPLIER_THRESHOLDS[threshold]

	if new_multiplier != current_multiplier:
		var old_multiplier = current_multiplier
		current_multiplier = new_multiplier
		multiplier_changed.emit(current_multiplier)
		SignalBus.score_multiplier_changed.emit(float(current_multiplier))

		# Play sound on multiplier increase
		if new_multiplier > old_multiplier:
			SoundManager.play_combo_milestone(combo_count)
			DebugHelper.log_info("Multiplier increased to x%d at combo %d" % [new_multiplier, combo_count])

func get_multiplier() -> int:
	return current_multiplier

# ============================================
# WORD RUSH
# ============================================
func _on_char_typed(char: String, correct: bool) -> void:
	if correct and not rush_active:
		rush_value = minf(RUSH_MAX, rush_value + RUSH_GAIN_PER_CHAR)
		rush_value_changed.emit(rush_value, RUSH_MAX)

		# Check if rush bar is full
		if rush_value >= RUSH_MAX:
			_activate_rush()

func _on_word_completed(enemy: Node, combo: int) -> void:
	# Handle instant kill during rush
	if rush_active and rush_kills_remaining > 0:
		rush_kills_remaining -= 1
		rush_kill_used.emit(rush_kills_remaining)

		if rush_kills_remaining <= 0:
			_deactivate_rush()

	# Handle Burst Mode
	if burst_enabled:
		_check_burst_mode()

	# Handle Vampire
	if vampire_enabled:
		_check_vampire_heal()

func _activate_rush() -> void:
	if rush_active:
		return

	rush_active = true
	rush_timer = RUSH_DURATION
	rush_kills_remaining = RUSH_INSTANT_KILLS
	rush_value = RUSH_MAX

	# Activate slow-mo
	Engine.time_scale = 0.5

	rush_activated.emit(RUSH_DURATION, RUSH_INSTANT_KILLS)
	SoundManager.play_voice_king_of_combo()  # Use existing epic sound
	DebugHelper.log_info("WORD RUSH ACTIVATED! %d instant kills available" % RUSH_INSTANT_KILLS)

func _deactivate_rush() -> void:
	if not rush_active:
		return

	rush_active = false
	rush_timer = 0.0
	rush_kills_remaining = 0
	rush_value = 0.0

	# Restore normal speed
	Engine.time_scale = 1.0

	rush_deactivated.emit()
	rush_value_changed.emit(rush_value, RUSH_MAX)
	DebugHelper.log_info("Word Rush ended")

func is_rush_active() -> bool:
	return rush_active

func get_rush_value() -> float:
	return rush_value

func get_rush_kills_remaining() -> int:
	return rush_kills_remaining

# ============================================
# INSTANT KILL (for rush mode)
# ============================================
func should_instant_kill() -> bool:
	return rush_active and rush_kills_remaining > 0

# ============================================
# BURST MODE
# ============================================
func _check_burst_mode() -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	burst_kill_times.append(current_time)

	# Remove old kills outside the window
	while burst_kill_times.size() > 0 and (current_time - burst_kill_times[0]) > BURST_WINDOW:
		burst_kill_times.remove_at(0)

	# Check if we have enough kills in window
	if burst_kill_times.size() >= BURST_KILLS_NEEDED:
		_trigger_burst()

func _trigger_burst() -> void:
	# Clear burst kills
	burst_kill_times.clear()

	# Find a random enemy to kill
	var enemies = get_tree().get_nodes_in_group("enemies")
	var valid_enemies: Array = []

	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.has_method("is_alive") and enemy.is_alive():
			# Don't burst-kill Shield enemies (must be typed manually)
			if "is_shield" in enemy and enemy.is_shield:
				continue
			valid_enemies.append(enemy)

	if valid_enemies.size() > 0:
		var target = valid_enemies[randi() % valid_enemies.size()]
		DebugHelper.log_info("BURST MODE! Random kill: %s" % target.word)

		# Kill the enemy
		if target.has_method("die"):
			target.die()

		# Signal and effects
		burst_triggered.emit(target)
		SoundManager.play_sfx("nuke_explosion")
		EffectsManager.screen_shake(5.0, 0.2)

# ============================================
# VAMPIRE
# ============================================
func _check_vampire_heal() -> void:
	vampire_kill_count += 1

	if vampire_kill_count >= VAMPIRE_HEAL_INTERVAL:
		vampire_kill_count = 0
		_trigger_vampire_heal()

func _trigger_vampire_heal() -> void:
	DebugHelper.log_info("VAMPIRE HEAL! +%d HP" % VAMPIRE_HEAL_AMOUNT)
	SignalBus.portal_heal.emit(VAMPIRE_HEAL_AMOUNT)
	vampire_heal.emit(VAMPIRE_HEAL_AMOUNT)
	SoundManager.play_sfx("powerup_heal")

# ============================================
# RESET
# ============================================
func reset() -> void:
	current_multiplier = 1
	combo_count = 0
	rush_value = 0.0
	rush_active = false
	rush_timer = 0.0
	rush_kills_remaining = 0
	Engine.time_scale = 1.0

	# Reset burst mode
	burst_kill_times.clear()

	# Reset vampire
	vampire_kill_count = 0

	multiplier_changed.emit(1)
	rush_value_changed.emit(0.0, RUSH_MAX)
	SignalBus.score_multiplier_changed.emit(1.0)
