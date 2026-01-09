## progression_manager.gd
## Manages meta-progression: currency, unlockables, evolutions, and start bonuses
## Autoload singleton: ProgressionManager
extends Node

# ============================================================================
# CONSTANTS
# ============================================================================

const PROGRESSION_FILE := "user://progression.json"

# Currency earning rates
const CURRENCY_PER_SCORE_POINT := 0.01        # 1 coin per 100 score
const CURRENCY_PER_KILL := 1                   # 1 coin per enemy killed
const WAVE_COMPLETION_BASE := 10               # Base coins per wave
const WAVE_COMPLETION_MULTIPLIER := 5          # Additional per wave number

# ============================================================================
# ENUMS
# ============================================================================

enum UnlockCategory {
	START_BONUS,
	EVOLUTION
}

enum StartBonus {
	PORTAL_HP,          # +1 Portal HP
	AUTO_SHIELD,        # Shield every X enemies
	TD_RESOURCES        # Starting build points for TD
}

enum Evolution {
	BURST_MODE,         # 3 kills in 5s = 4th random kill
	VAMPIRE             # Every 20th word heals
}

# ============================================================================
# UNLOCKABLE DEFINITIONS
# ============================================================================

const UNLOCKABLES := {
	# Start Bonuses - Portal HP
	"portal_hp_1": {
		"category": UnlockCategory.START_BONUS,
		"type": StartBonus.PORTAL_HP,
		"name": "Portal Fortification I",
		"name_de": "Portal-Verstärkung I",
		"description": "+1 Portal HP at game start",
		"description_de": "+1 Portal HP bei Spielstart",
		"cost": 100,
		"effect": {"hp_bonus": 1},
		"requires": null,
		"tier": 1
	},
	"portal_hp_2": {
		"category": UnlockCategory.START_BONUS,
		"type": StartBonus.PORTAL_HP,
		"name": "Portal Fortification II",
		"name_de": "Portal-Verstärkung II",
		"description": "+2 Portal HP at game start",
		"description_de": "+2 Portal HP bei Spielstart",
		"cost": 250,
		"effect": {"hp_bonus": 2},
		"requires": "portal_hp_1",
		"tier": 2
	},
	"portal_hp_3": {
		"category": UnlockCategory.START_BONUS,
		"type": StartBonus.PORTAL_HP,
		"name": "Portal Fortification III",
		"name_de": "Portal-Verstärkung III",
		"description": "+3 Portal HP at game start",
		"description_de": "+3 Portal HP bei Spielstart",
		"cost": 500,
		"effect": {"hp_bonus": 3},
		"requires": "portal_hp_2",
		"tier": 3
	},

	# Start Bonuses - Auto Shield
	"auto_shield_20": {
		"category": UnlockCategory.START_BONUS,
		"type": StartBonus.AUTO_SHIELD,
		"name": "Auto-Shield I",
		"name_de": "Auto-Schild I",
		"description": "Gain a shield every 20 enemies killed",
		"description_de": "Erhalte einen Schild alle 20 getöteten Feinde",
		"cost": 150,
		"effect": {"kill_interval": 20},
		"requires": null,
		"tier": 1
	},
	"auto_shield_15": {
		"category": UnlockCategory.START_BONUS,
		"type": StartBonus.AUTO_SHIELD,
		"name": "Auto-Shield II",
		"name_de": "Auto-Schild II",
		"description": "Gain a shield every 15 enemies killed",
		"description_de": "Erhalte einen Schild alle 15 getöteten Feinde",
		"cost": 350,
		"effect": {"kill_interval": 15},
		"requires": "auto_shield_20",
		"tier": 2
	},
	"auto_shield_10": {
		"category": UnlockCategory.START_BONUS,
		"type": StartBonus.AUTO_SHIELD,
		"name": "Auto-Shield III",
		"name_de": "Auto-Schild III",
		"description": "Gain a shield every 10 enemies killed",
		"description_de": "Erhalte einen Schild alle 10 getöteten Feinde",
		"cost": 600,
		"effect": {"kill_interval": 10},
		"requires": "auto_shield_15",
		"tier": 3
	},

	# Start Bonuses - TD Resources
	"td_resources_1": {
		"category": UnlockCategory.START_BONUS,
		"type": StartBonus.TD_RESOURCES,
		"name": "Supply Cache I",
		"name_de": "Vorratslager I",
		"description": "+25 starting build points in TD mode",
		"description_de": "+25 Baupunkte in TD-Modus",
		"cost": 100,
		"effect": {"build_points": 25},
		"requires": null,
		"tier": 1
	},
	"td_resources_2": {
		"category": UnlockCategory.START_BONUS,
		"type": StartBonus.TD_RESOURCES,
		"name": "Supply Cache II",
		"name_de": "Vorratslager II",
		"description": "+50 starting build points in TD mode",
		"description_de": "+50 Baupunkte in TD-Modus",
		"cost": 250,
		"effect": {"build_points": 50},
		"requires": "td_resources_1",
		"tier": 2
	},
	"td_resources_3": {
		"category": UnlockCategory.START_BONUS,
		"type": StartBonus.TD_RESOURCES,
		"name": "Supply Cache III",
		"name_de": "Vorratslager III",
		"description": "+100 starting build points in TD mode",
		"description_de": "+100 Baupunkte in TD-Modus",
		"cost": 500,
		"effect": {"build_points": 100},
		"requires": "td_resources_2",
		"tier": 3
	},

	# Evolutions
	"burst_mode": {
		"category": UnlockCategory.EVOLUTION,
		"type": Evolution.BURST_MODE,
		"name": "Burst Mode",
		"name_de": "Burst-Modus",
		"description": "Kill 3 enemies in 5s to trigger a 4th random kill",
		"description_de": "Töte 3 Feinde in 5s für einen 4. zufälligen Kill",
		"cost": 300,
		"effect": {},
		"requires": null,
		"tier": 1
	},
	"vampire": {
		"category": UnlockCategory.EVOLUTION,
		"type": Evolution.VAMPIRE,
		"name": "Vampire",
		"name_de": "Vampir",
		"description": "Every 20th word typed heals the portal",
		"description_de": "Jedes 20. Wort heilt das Portal",
		"cost": 400,
		"effect": {},
		"requires": null,
		"tier": 1
	}
}

# ============================================================================
# STATE
# ============================================================================

var currency: int = 0
var unlocked: Dictionary = {}        # {id: true}
var active_bonuses: Dictionary = {}  # {id: true} - which unlocks are enabled
var active_evolutions: Dictionary = {} # {id: true} - which evolutions are enabled

# Session tracking for currency
var session_score: int = 0
var session_kills: int = 0
var session_waves_completed: int = 0

# Auto-shield tracking
var kills_since_last_shield: int = 0

# ============================================================================
# SIGNALS
# ============================================================================

signal currency_changed(new_amount: int)
signal unlockable_purchased(id: String)
signal bonus_toggled(id: String, active: bool)
signal evolution_toggled(id: String, active: bool)
signal auto_shield_triggered()

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	load_progression()
	connect_signals()
	DebugHelper.log_info("ProgressionManager initialized - Currency: %d" % currency)

func connect_signals() -> void:
	SignalBus.game_over.connect(_on_game_over)
	SignalBus.game_started.connect(_on_game_started)
	SignalBus.enemy_killed.connect(_on_enemy_killed)
	SignalBus.wave_completed.connect(_on_wave_completed)

# ============================================================================
# CURRENCY SYSTEM
# ============================================================================

func _on_game_started() -> void:
	session_score = 0
	session_kills = 0
	session_waves_completed = 0
	kills_since_last_shield = 0

func _on_game_over(won: bool, stats: Dictionary) -> void:
	# Calculate currency earned
	var earned := calculate_currency_earned(stats)
	add_currency(earned)
	DebugHelper.log_info("Currency earned this session: %d (total: %d)" % [earned, currency])

func _on_enemy_killed(enemy: Node, typed: bool) -> void:
	if typed:
		session_kills += 1
		check_auto_shield()

func _on_wave_completed(wave_number: int) -> void:
	session_waves_completed = wave_number

func calculate_currency_earned(stats: Dictionary) -> int:
	var score_currency := int(stats.get("score", 0) * CURRENCY_PER_SCORE_POINT)
	var kill_currency: int = int(stats.get("enemies_destroyed", 0)) * CURRENCY_PER_KILL
	var wave_currency := 0

	var waves: int = int(stats.get("wave", 0))
	for i in range(1, waves + 1):
		wave_currency += WAVE_COMPLETION_BASE + (i * WAVE_COMPLETION_MULTIPLIER)

	return score_currency + kill_currency + wave_currency

func calculate_currency(final_score: int, kills: int, waves_completed: int) -> int:
	var score_currency := int(final_score * CURRENCY_PER_SCORE_POINT)
	var kill_currency := kills * CURRENCY_PER_KILL
	var wave_currency := 0

	for i in range(1, waves_completed + 1):
		wave_currency += WAVE_COMPLETION_BASE + (i * WAVE_COMPLETION_MULTIPLIER)

	return score_currency + kill_currency + wave_currency

func add_currency(amount: int) -> void:
	currency += amount
	currency_changed.emit(currency)
	save_progression()

func spend_currency(amount: int) -> bool:
	if currency >= amount:
		currency -= amount
		currency_changed.emit(currency)
		save_progression()
		return true
	return false

func get_currency() -> int:
	return currency

# ============================================================================
# UNLOCK SYSTEM
# ============================================================================

func can_unlock(id: String) -> Dictionary:
	if not UNLOCKABLES.has(id):
		return {"can_unlock": false, "reason": "Invalid unlockable"}

	if unlocked.has(id):
		return {"can_unlock": false, "reason": "Already unlocked"}

	var unlock_data: Dictionary = UNLOCKABLES[id]

	# Check requirements
	if unlock_data.requires != null and not unlocked.has(unlock_data.requires):
		var req_name = UNLOCKABLES[unlock_data.requires].name
		return {"can_unlock": false, "reason": "Requires: %s" % req_name}

	# Check cost
	if currency < unlock_data.cost:
		return {"can_unlock": false, "reason": "Need %d coins (have %d)" % [unlock_data.cost, currency]}

	return {"can_unlock": true, "reason": ""}

func purchase_unlock(id: String) -> bool:
	var check := can_unlock(id)
	if not check.can_unlock:
		return false

	var unlock_data: Dictionary = UNLOCKABLES[id]

	if not spend_currency(unlock_data.cost):
		return false

	unlocked[id] = true

	# Auto-enable the unlockable (with mutual exclusivity for bonuses)
	if unlock_data.category == UnlockCategory.START_BONUS:
		# Deactivate other bonuses of same type first
		var bonus_type = unlock_data.get("type")
		for other_id in UNLOCKABLES:
			var other_data: Dictionary = UNLOCKABLES[other_id]
			if other_data.get("category") == UnlockCategory.START_BONUS and other_data.get("type") == bonus_type:
				if other_id != id and active_bonuses.get(other_id, false):
					active_bonuses[other_id] = false
		active_bonuses[id] = true
	elif unlock_data.category == UnlockCategory.EVOLUTION:
		active_evolutions[id] = true

	unlockable_purchased.emit(id)
	save_progression()

	DebugHelper.log_info("Unlocked: %s" % unlock_data.name)
	return true

func is_unlocked(id: String) -> bool:
	return unlocked.has(id)

# ============================================================================
# TOGGLE SYSTEM
# ============================================================================

func toggle_evolution(id: String) -> bool:
	if not unlocked.has(id):
		return false

	var unlock_data: Dictionary = UNLOCKABLES.get(id, {})
	if unlock_data.get("category") != UnlockCategory.EVOLUTION:
		return false

	var is_active: bool = active_evolutions.get(id, false)
	active_evolutions[id] = not is_active

	evolution_toggled.emit(id, active_evolutions[id])
	save_progression()

	return true

func is_evolution_active(id: String) -> bool:
	return active_evolutions.get(id, false)

func toggle_bonus(id: String) -> bool:
	if not unlocked.has(id):
		return false

	var unlock_data: Dictionary = UNLOCKABLES.get(id, {})
	if unlock_data.get("category") != UnlockCategory.START_BONUS:
		return false

	var is_active: bool = active_bonuses.get(id, false)
	var bonus_type = unlock_data.get("type")

	if not is_active:
		# Activating - deactivate all other bonuses of same type first
		for other_id in UNLOCKABLES:
			var other_data: Dictionary = UNLOCKABLES[other_id]
			if other_data.get("category") == UnlockCategory.START_BONUS and other_data.get("type") == bonus_type:
				if other_id != id and active_bonuses.get(other_id, false):
					active_bonuses[other_id] = false
					bonus_toggled.emit(other_id, false)

	active_bonuses[id] = not is_active

	bonus_toggled.emit(id, active_bonuses[id])
	save_progression()

	return true

func is_bonus_active(id: String) -> bool:
	return active_bonuses.get(id, false)

# ============================================================================
# EFFECT GETTERS (used by game systems)
# ============================================================================

func get_portal_hp_bonus() -> int:
	var bonus := 0
	for id in active_bonuses:
		if not active_bonuses[id]:
			continue
		var data: Dictionary = UNLOCKABLES.get(id, {})
		if data.get("type") == StartBonus.PORTAL_HP:
			bonus = maxi(bonus, data.effect.get("hp_bonus", 0))
	return bonus

func get_auto_shield_interval() -> int:
	var interval := 0  # 0 = disabled
	for id in active_bonuses:
		if not active_bonuses[id]:
			continue
		var data: Dictionary = UNLOCKABLES.get(id, {})
		if data.get("type") == StartBonus.AUTO_SHIELD:
			var this_interval: int = data.effect.get("kill_interval", 999)
			if interval == 0 or this_interval < interval:
				interval = this_interval
	return interval

func get_td_starting_resources() -> int:
	var bonus := 0
	for id in active_bonuses:
		if not active_bonuses[id]:
			continue
		var data: Dictionary = UNLOCKABLES.get(id, {})
		if data.get("type") == StartBonus.TD_RESOURCES:
			bonus = maxi(bonus, data.effect.get("build_points", 0))
	return bonus

func is_burst_mode_enabled() -> bool:
	return is_evolution_active("burst_mode")

func is_vampire_enabled() -> bool:
	return is_evolution_active("vampire")

# ============================================================================
# AUTO-SHIELD LOGIC
# ============================================================================

func check_auto_shield() -> void:
	var interval := get_auto_shield_interval()
	if interval <= 0:
		return

	kills_since_last_shield += 1
	if kills_since_last_shield >= interval:
		kills_since_last_shield = 0
		trigger_auto_shield()

func trigger_auto_shield() -> void:
	SignalBus.shield_activated.emit(5.0)  # 5 second shield
	PowerUpManager.activate_powerup(PowerUpManager.PowerUpType.SHIELD, 5.0)
	auto_shield_triggered.emit()
	SoundManager.play_shield_activate()
	DebugHelper.log_info("Auto-shield triggered!")

# ============================================================================
# PUBLIC API
# ============================================================================

func get_all_unlockables() -> Dictionary:
	return UNLOCKABLES.duplicate(true)

func get_unlockables_by_category(category: int) -> Array:
	var result: Array = []
	for id in UNLOCKABLES:
		var data: Dictionary = UNLOCKABLES[id].duplicate()
		if data.category == category:
			data["id"] = id
			data["unlocked"] = unlocked.has(id)
			data["active"] = active_bonuses.get(id, false) or active_evolutions.get(id, false)
			data["can_unlock_result"] = can_unlock(id)
			result.append(data)
	return result

func get_start_bonuses() -> Array:
	return get_unlockables_by_category(UnlockCategory.START_BONUS)

func get_evolutions() -> Array:
	return get_unlockables_by_category(UnlockCategory.EVOLUTION)

func get_progression_stats() -> Dictionary:
	var total_unlocks := UNLOCKABLES.size()
	var owned_unlocks := unlocked.size()

	return {
		"currency": currency,
		"total_unlocks": total_unlocks,
		"owned_unlocks": owned_unlocks,
		"completion_percent": (float(owned_unlocks) / float(total_unlocks)) * 100.0 if total_unlocks > 0 else 0.0,
		"active_bonuses": active_bonuses.size(),
		"active_evolutions": active_evolutions.size()
	}

func get_unlock_progress() -> Dictionary:
	return {
		"unlocked": unlocked.size(),
		"total": UNLOCKABLES.size()
	}

func get_localized_name(data: Dictionary) -> String:
	var lang = SaveManager.get_setting("language") if SaveManager else "EN"
	if lang == "DE" and data.has("name_de"):
		return data.name_de
	return data.name

func get_localized_description(data: Dictionary) -> String:
	var lang = SaveManager.get_setting("language") if SaveManager else "EN"
	if lang == "DE" and data.has("description_de"):
		return data.description_de
	return data.description

# ============================================================================
# PERSISTENCE
# ============================================================================

func save_progression() -> void:
	var file = FileAccess.open(PROGRESSION_FILE, FileAccess.WRITE)
	if file:
		var data := {
			"currency": currency,
			"unlocked": unlocked,
			"active_bonuses": active_bonuses,
			"active_evolutions": active_evolutions,
			"version": 1
		}
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

func load_progression() -> void:
	if not FileAccess.file_exists(PROGRESSION_FILE):
		currency = 0
		unlocked = {}
		active_bonuses = {}
		active_evolutions = {}
		return

	var file = FileAccess.open(PROGRESSION_FILE, FileAccess.READ)
	if file:
		var json = JSON.new()
		var error = json.parse(file.get_as_text())
		file.close()

		if error == OK:
			var data = json.data
			currency = data.get("currency", 0)
			unlocked = data.get("unlocked", {})
			active_bonuses = data.get("active_bonuses", {})
			active_evolutions = data.get("active_evolutions", {})
		else:
			currency = 0
			unlocked = {}
			active_bonuses = {}
			active_evolutions = {}

func reset_progression() -> void:
	currency = 0
	unlocked = {}
	active_bonuses = {}
	active_evolutions = {}
	save_progression()
	currency_changed.emit(currency)
