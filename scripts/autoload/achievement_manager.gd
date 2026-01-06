## achievement_manager.gd
## Manages achievements with Steam integration support
## Autoload singleton: AchievementManager
extends Node

# Achievement tiers
enum Tier { BRONZE, SILVER, GOLD, PLATINUM, DIAMOND }

# Achievement categories
enum Category { SPEED, ACCURACY, COMBO, SURVIVAL, SCORE, GRIND, SPECIAL }

# Achievement condition types
enum Condition { THRESHOLD, CUMULATIVE, SPECIAL }

const ACHIEVEMENTS_FILE := "user://achievements.json"

# ============================================================================
# ACHIEVEMENT DEFINITIONS
# ============================================================================

var ACHIEVEMENTS: Dictionary = {
	# === SPEED ACHIEVEMENTS ===
	"speed_novice": {
		"name": "Typing Novice",
		"description": "Reach 20 WPM in a session",
		"category": Category.SPEED,
		"tier": Tier.BRONZE,
		"condition": Condition.THRESHOLD,
		"stat": "session_wpm",
		"target": 20,
		"steam_id": "speed_novice"
	},
	"speed_intermediate": {
		"name": "Keyboard Warrior",
		"description": "Reach 40 WPM in a session",
		"category": Category.SPEED,
		"tier": Tier.SILVER,
		"condition": Condition.THRESHOLD,
		"stat": "session_wpm",
		"target": 40,
		"steam_id": "speed_intermediate"
	},
	"speed_advanced": {
		"name": "Speed Demon",
		"description": "Reach 60 WPM in a session",
		"category": Category.SPEED,
		"tier": Tier.GOLD,
		"condition": Condition.THRESHOLD,
		"stat": "session_wpm",
		"target": 60,
		"steam_id": "speed_advanced"
	},
	"speed_expert": {
		"name": "Finger Fury",
		"description": "Reach 80 WPM in a session",
		"category": Category.SPEED,
		"tier": Tier.PLATINUM,
		"condition": Condition.THRESHOLD,
		"stat": "session_wpm",
		"target": 80,
		"steam_id": "speed_expert"
	},
	"speed_master": {
		"name": "Transcendent Typist",
		"description": "Reach 100 WPM in a session",
		"category": Category.SPEED,
		"tier": Tier.DIAMOND,
		"condition": Condition.THRESHOLD,
		"stat": "session_wpm",
		"target": 100,
		"steam_id": "speed_master"
	},

	# === ACCURACY ACHIEVEMENTS ===
	"accuracy_decent": {
		"name": "Careful Keystroker",
		"description": "Finish a session with 80% accuracy",
		"category": Category.ACCURACY,
		"tier": Tier.BRONZE,
		"condition": Condition.THRESHOLD,
		"stat": "session_accuracy",
		"target": 80,
		"steam_id": "accuracy_decent"
	},
	"accuracy_good": {
		"name": "Precision Typist",
		"description": "Finish a session with 90% accuracy",
		"category": Category.ACCURACY,
		"tier": Tier.SILVER,
		"condition": Condition.THRESHOLD,
		"stat": "session_accuracy",
		"target": 90,
		"steam_id": "accuracy_good"
	},
	"accuracy_great": {
		"name": "Surgical Strikes",
		"description": "Finish a session with 95% accuracy",
		"category": Category.ACCURACY,
		"tier": Tier.GOLD,
		"condition": Condition.THRESHOLD,
		"stat": "session_accuracy",
		"target": 95,
		"steam_id": "accuracy_great"
	},
	"accuracy_perfect": {
		"name": "Flawless Fingers",
		"description": "Finish a session with 99% accuracy",
		"category": Category.ACCURACY,
		"tier": Tier.PLATINUM,
		"condition": Condition.THRESHOLD,
		"stat": "session_accuracy",
		"target": 99,
		"steam_id": "accuracy_perfect"
	},
	"accuracy_god": {
		"name": "Zero Errors",
		"description": "Complete a wave 10+ session with 100% accuracy",
		"category": Category.ACCURACY,
		"tier": Tier.DIAMOND,
		"condition": Condition.SPECIAL,
		"stat": "perfect_session",
		"target": 1,
		"steam_id": "accuracy_god"
	},

	# === COMBO ACHIEVEMENTS ===
	"combo_5": {
		"name": "Warming Up",
		"description": "Reach a 5x combo",
		"category": Category.COMBO,
		"tier": Tier.BRONZE,
		"condition": Condition.THRESHOLD,
		"stat": "session_combo",
		"target": 5,
		"steam_id": "combo_5"
	},
	"combo_10": {
		"name": "On Fire",
		"description": "Reach a 10x combo",
		"category": Category.COMBO,
		"tier": Tier.BRONZE,
		"condition": Condition.THRESHOLD,
		"stat": "session_combo",
		"target": 10,
		"steam_id": "combo_10"
	},
	"combo_25": {
		"name": "Unstoppable",
		"description": "Reach a 25x combo",
		"category": Category.COMBO,
		"tier": Tier.SILVER,
		"condition": Condition.THRESHOLD,
		"stat": "session_combo",
		"target": 25,
		"steam_id": "combo_25"
	},
	"combo_50": {
		"name": "Combo King",
		"description": "Reach a 50x combo",
		"category": Category.COMBO,
		"tier": Tier.GOLD,
		"condition": Condition.THRESHOLD,
		"stat": "session_combo",
		"target": 50,
		"steam_id": "combo_50"
	},
	"combo_100": {
		"name": "Century Streak",
		"description": "Reach a 100x combo",
		"category": Category.COMBO,
		"tier": Tier.PLATINUM,
		"condition": Condition.THRESHOLD,
		"stat": "session_combo",
		"target": 100,
		"steam_id": "combo_100"
	},
	"combo_200": {
		"name": "Legendary Streak",
		"description": "Reach a 200x combo",
		"category": Category.COMBO,
		"tier": Tier.DIAMOND,
		"condition": Condition.THRESHOLD,
		"stat": "session_combo",
		"target": 200,
		"steam_id": "combo_200"
	},

	# === SURVIVAL ACHIEVEMENTS ===
	"wave_5": {
		"name": "First Steps",
		"description": "Reach wave 5",
		"category": Category.SURVIVAL,
		"tier": Tier.BRONZE,
		"condition": Condition.THRESHOLD,
		"stat": "session_wave",
		"target": 5,
		"steam_id": "wave_5"
	},
	"wave_10": {
		"name": "Boss Slayer",
		"description": "Reach wave 10",
		"category": Category.SURVIVAL,
		"tier": Tier.BRONZE,
		"condition": Condition.THRESHOLD,
		"stat": "session_wave",
		"target": 10,
		"steam_id": "wave_10"
	},
	"wave_20": {
		"name": "Veteran Defender",
		"description": "Reach wave 20",
		"category": Category.SURVIVAL,
		"tier": Tier.SILVER,
		"condition": Condition.THRESHOLD,
		"stat": "session_wave",
		"target": 20,
		"steam_id": "wave_20"
	},
	"wave_30": {
		"name": "Elite Guardian",
		"description": "Reach wave 30",
		"category": Category.SURVIVAL,
		"tier": Tier.GOLD,
		"condition": Condition.THRESHOLD,
		"stat": "session_wave",
		"target": 30,
		"steam_id": "wave_30"
	},
	"wave_50": {
		"name": "Endurance Master",
		"description": "Reach wave 50",
		"category": Category.SURVIVAL,
		"tier": Tier.PLATINUM,
		"condition": Condition.THRESHOLD,
		"stat": "session_wave",
		"target": 50,
		"steam_id": "wave_50"
	},
	"wave_100": {
		"name": "Immortal Typist",
		"description": "Reach wave 100",
		"category": Category.SURVIVAL,
		"tier": Tier.DIAMOND,
		"condition": Condition.THRESHOLD,
		"stat": "session_wave",
		"target": 100,
		"steam_id": "wave_100"
	},

	# === SCORE ACHIEVEMENTS ===
	"score_1k": {
		"name": "First Blood",
		"description": "Score 1,000 points in a session",
		"category": Category.SCORE,
		"tier": Tier.BRONZE,
		"condition": Condition.THRESHOLD,
		"stat": "session_score",
		"target": 1000,
		"steam_id": "score_1k"
	},
	"score_5k": {
		"name": "Point Collector",
		"description": "Score 5,000 points in a session",
		"category": Category.SCORE,
		"tier": Tier.BRONZE,
		"condition": Condition.THRESHOLD,
		"stat": "session_score",
		"target": 5000,
		"steam_id": "score_5k"
	},
	"score_10k": {
		"name": "High Scorer",
		"description": "Score 10,000 points in a session",
		"category": Category.SCORE,
		"tier": Tier.SILVER,
		"condition": Condition.THRESHOLD,
		"stat": "session_score",
		"target": 10000,
		"steam_id": "score_10k"
	},
	"score_25k": {
		"name": "Score Hunter",
		"description": "Score 25,000 points in a session",
		"category": Category.SCORE,
		"tier": Tier.GOLD,
		"condition": Condition.THRESHOLD,
		"stat": "session_score",
		"target": 25000,
		"steam_id": "score_25k"
	},
	"score_50k": {
		"name": "Point Master",
		"description": "Score 50,000 points in a session",
		"category": Category.SCORE,
		"tier": Tier.PLATINUM,
		"condition": Condition.THRESHOLD,
		"stat": "session_score",
		"target": 50000,
		"steam_id": "score_50k"
	},
	"score_100k": {
		"name": "Score Legend",
		"description": "Score 100,000 points in a session",
		"category": Category.SCORE,
		"tier": Tier.DIAMOND,
		"condition": Condition.THRESHOLD,
		"stat": "session_score",
		"target": 100000,
		"steam_id": "score_100k"
	},

	# === GRIND ACHIEVEMENTS ===
	"games_10": {
		"name": "Getting Started",
		"description": "Play 10 games",
		"category": Category.GRIND,
		"tier": Tier.BRONZE,
		"condition": Condition.CUMULATIVE,
		"stat": "total_games",
		"target": 10,
		"steam_id": "games_10"
	},
	"games_50": {
		"name": "Regular Player",
		"description": "Play 50 games",
		"category": Category.GRIND,
		"tier": Tier.SILVER,
		"condition": Condition.CUMULATIVE,
		"stat": "total_games",
		"target": 50,
		"steam_id": "games_50"
	},
	"games_100": {
		"name": "Dedicated Typist",
		"description": "Play 100 games",
		"category": Category.GRIND,
		"tier": Tier.GOLD,
		"condition": Condition.CUMULATIVE,
		"stat": "total_games",
		"target": 100,
		"steam_id": "games_100"
	},
	"games_500": {
		"name": "Typing Addict",
		"description": "Play 500 games",
		"category": Category.GRIND,
		"tier": Tier.PLATINUM,
		"condition": Condition.CUMULATIVE,
		"stat": "total_games",
		"target": 500,
		"steam_id": "games_500"
	},
	"chars_10k": {
		"name": "Ten Thousand Keys",
		"description": "Type 10,000 characters total",
		"category": Category.GRIND,
		"tier": Tier.BRONZE,
		"condition": Condition.CUMULATIVE,
		"stat": "total_chars",
		"target": 10000,
		"steam_id": "chars_10k"
	},
	"chars_100k": {
		"name": "Hundred Thousand Keys",
		"description": "Type 100,000 characters total",
		"category": Category.GRIND,
		"tier": Tier.SILVER,
		"condition": Condition.CUMULATIVE,
		"stat": "total_chars",
		"target": 100000,
		"steam_id": "chars_100k"
	},
	"chars_1m": {
		"name": "Million Key Club",
		"description": "Type 1,000,000 characters total",
		"category": Category.GRIND,
		"tier": Tier.GOLD,
		"condition": Condition.CUMULATIVE,
		"stat": "total_chars",
		"target": 1000000,
		"steam_id": "chars_1m"
	},
	"kills_100": {
		"name": "Enemy Eliminator",
		"description": "Kill 100 enemies by typing",
		"category": Category.GRIND,
		"tier": Tier.BRONZE,
		"condition": Condition.CUMULATIVE,
		"stat": "total_kills",
		"target": 100,
		"steam_id": "kills_100"
	},
	"kills_1000": {
		"name": "Word Warrior",
		"description": "Kill 1,000 enemies by typing",
		"category": Category.GRIND,
		"tier": Tier.SILVER,
		"condition": Condition.CUMULATIVE,
		"stat": "total_kills",
		"target": 1000,
		"steam_id": "kills_1000"
	},
	"kills_10000": {
		"name": "Typing Annihilator",
		"description": "Kill 10,000 enemies by typing",
		"category": Category.GRIND,
		"tier": Tier.GOLD,
		"condition": Condition.CUMULATIVE,
		"stat": "total_kills",
		"target": 10000,
		"steam_id": "kills_10000"
	},
	"playtime_1h": {
		"name": "One Hour In",
		"description": "Play for 1 hour total",
		"category": Category.GRIND,
		"tier": Tier.BRONZE,
		"condition": Condition.CUMULATIVE,
		"stat": "total_playtime",
		"target": 3600,
		"steam_id": "playtime_1h"
	},
	"playtime_10h": {
		"name": "Dedicated Player",
		"description": "Play for 10 hours total",
		"category": Category.GRIND,
		"tier": Tier.SILVER,
		"condition": Condition.CUMULATIVE,
		"stat": "total_playtime",
		"target": 36000,
		"steam_id": "playtime_10h"
	},
	"playtime_100h": {
		"name": "Typing Veteran",
		"description": "Play for 100 hours total",
		"category": Category.GRIND,
		"tier": Tier.GOLD,
		"condition": Condition.CUMULATIVE,
		"stat": "total_playtime",
		"target": 360000,
		"steam_id": "playtime_100h"
	},
	"streak_7": {
		"name": "Week Warrior",
		"description": "Play 7 days in a row",
		"category": Category.GRIND,
		"tier": Tier.SILVER,
		"condition": Condition.THRESHOLD,
		"stat": "daily_streak",
		"target": 7,
		"steam_id": "streak_7"
	},
	"streak_30": {
		"name": "Monthly Master",
		"description": "Play 30 days in a row",
		"category": Category.GRIND,
		"tier": Tier.GOLD,
		"condition": Condition.THRESHOLD,
		"stat": "daily_streak",
		"target": 30,
		"steam_id": "streak_30"
	},

	# === SPECIAL ACHIEVEMENTS ===
	"first_tower": {
		"name": "Builder",
		"description": "Build your first tower",
		"category": Category.SPECIAL,
		"tier": Tier.BRONZE,
		"condition": Condition.CUMULATIVE,
		"stat": "total_towers",
		"target": 1,
		"steam_id": "first_tower"
	},
	"tower_master": {
		"name": "Tower Master",
		"description": "Build 50 towers total",
		"category": Category.SPECIAL,
		"tier": Tier.SILVER,
		"condition": Condition.CUMULATIVE,
		"stat": "total_towers",
		"target": 50,
		"steam_id": "tower_master"
	},
	"powerup_collector": {
		"name": "Power Collector",
		"description": "Collect 100 powerups total",
		"category": Category.SPECIAL,
		"tier": Tier.SILVER,
		"condition": Condition.CUMULATIVE,
		"stat": "total_powerups",
		"target": 100,
		"steam_id": "powerup_collector"
	},
	"no_damage": {
		"name": "Untouchable",
		"description": "Complete wave 10 without portal taking damage",
		"category": Category.SPECIAL,
		"tier": Tier.GOLD,
		"condition": Condition.SPECIAL,
		"stat": "no_damage_run",
		"target": 1,
		"steam_id": "no_damage"
	},
	"speed_accuracy": {
		"name": "The Complete Package",
		"description": "Achieve 60 WPM with 95% accuracy in a session",
		"category": Category.SPECIAL,
		"tier": Tier.PLATINUM,
		"condition": Condition.SPECIAL,
		"stat": "speed_accuracy_combo",
		"target": 1,
		"steam_id": "speed_accuracy"
	},
	"long_word": {
		"name": "Spell It Out",
		"description": "Type a 10+ letter word without errors",
		"category": Category.SPECIAL,
		"tier": Tier.SILVER,
		"condition": Condition.SPECIAL,
		"stat": "long_word_perfect",
		"target": 1,
		"steam_id": "long_word"
	},
	"comeback": {
		"name": "Clutch Player",
		"description": "Survive a wave with portal at 1 HP",
		"category": Category.SPECIAL,
		"tier": Tier.GOLD,
		"condition": Condition.SPECIAL,
		"stat": "clutch_survival",
		"target": 1,
		"steam_id": "comeback"
	},
}

# ============================================================================
# STATE
# ============================================================================

var unlocked_achievements: Dictionary = {}  # {id: {unlocked: true, date: "..."}}
var progress: Dictionary = {}  # {id: current_progress}

# Special tracking
var session_no_portal_damage: bool = true
var current_word_no_errors: bool = true
var current_word_length: int = 0

signal achievement_unlocked(achievement_id: String, achievement_data: Dictionary)

func _ready() -> void:
	load_achievements()
	connect_signals()
	init_progress()
	DebugHelper.log_info("AchievementManager initialized - %d/%d unlocked" % [
		get_unlocked_count(), ACHIEVEMENTS.size()
	])

func connect_signals() -> void:
	SignalBus.game_over.connect(_on_game_over)
	SignalBus.combo_updated.connect(_on_combo_updated)
	SignalBus.enemy_killed.connect(_on_enemy_killed)
	SignalBus.enemy_reached_portal.connect(_on_enemy_reached_portal)
	SignalBus.powerup_collected.connect(_on_powerup_collected)
	SignalBus.word_completed.connect(_on_word_completed)
	SignalBus.word_failed.connect(_on_word_failed)
	SignalBus.char_typed.connect(_on_char_typed)
	SignalBus.game_started.connect(_on_game_started)

func init_progress() -> void:
	for id in ACHIEVEMENTS:
		if not progress.has(id):
			progress[id] = 0

# ============================================================================
# ACHIEVEMENT CHECKING
# ============================================================================

func check_achievement(id: String, value: float) -> void:
	if unlocked_achievements.has(id) and unlocked_achievements[id].get("unlocked", false):
		return  # Already unlocked

	var achievement = ACHIEVEMENTS[id]
	var target = achievement["target"]

	# Update progress
	if achievement["condition"] == Condition.CUMULATIVE:
		progress[id] = value
	else:
		progress[id] = maxi(progress[id], int(value))

	# Check if unlocked
	if value >= target:
		unlock_achievement(id)

func unlock_achievement(id: String) -> void:
	if unlocked_achievements.has(id) and unlocked_achievements[id].get("unlocked", false):
		return

	unlocked_achievements[id] = {
		"unlocked": true,
		"date": Time.get_datetime_string_from_system()
	}

	var achievement = ACHIEVEMENTS[id]
	DebugHelper.log_info("Achievement Unlocked: %s" % achievement["name"])

	# Emit signal for UI notification
	achievement_unlocked.emit(id, achievement)

	# Sync to Steam if available
	if SteamManager and SteamManager.is_steam_running():
		SteamManager.unlock_achievement(achievement["steam_id"])

	save_achievements()

func check_session_achievements(session_stats: Dictionary) -> void:
	# Speed achievements
	var wpm = session_stats.get("wpm", 0)
	check_achievement("speed_novice", wpm)
	check_achievement("speed_intermediate", wpm)
	check_achievement("speed_advanced", wpm)
	check_achievement("speed_expert", wpm)
	check_achievement("speed_master", wpm)

	# Accuracy achievements
	var accuracy = session_stats.get("accuracy", 0)
	check_achievement("accuracy_decent", accuracy)
	check_achievement("accuracy_good", accuracy)
	check_achievement("accuracy_great", accuracy)
	check_achievement("accuracy_perfect", accuracy)

	# Perfect session (100% accuracy at wave 10+)
	if accuracy >= 100.0 and session_stats.get("wave_reached", 0) >= 10:
		check_achievement("accuracy_god", 1)

	# Wave achievements
	var wave = session_stats.get("wave_reached", 0)
	check_achievement("wave_5", wave)
	check_achievement("wave_10", wave)
	check_achievement("wave_20", wave)
	check_achievement("wave_30", wave)
	check_achievement("wave_50", wave)
	check_achievement("wave_100", wave)

	# Score achievements
	var score = session_stats.get("score", 0)
	check_achievement("score_1k", score)
	check_achievement("score_5k", score)
	check_achievement("score_10k", score)
	check_achievement("score_25k", score)
	check_achievement("score_50k", score)
	check_achievement("score_100k", score)

	# Speed + Accuracy combo
	if wpm >= 60 and accuracy >= 95:
		check_achievement("speed_accuracy", 1)

	# No damage run
	if session_no_portal_damage and wave >= 10:
		check_achievement("no_damage", 1)

func check_lifetime_achievements() -> void:
	if not StatisticsManager:
		return

	var lifetime = StatisticsManager.get_lifetime_stats()

	# Games played
	check_achievement("games_10", lifetime.get("total_games", 0))
	check_achievement("games_50", lifetime.get("total_games", 0))
	check_achievement("games_100", lifetime.get("total_games", 0))
	check_achievement("games_500", lifetime.get("total_games", 0))

	# Characters typed
	check_achievement("chars_10k", lifetime.get("total_chars_typed", 0))
	check_achievement("chars_100k", lifetime.get("total_chars_typed", 0))
	check_achievement("chars_1m", lifetime.get("total_chars_typed", 0))

	# Kills
	check_achievement("kills_100", lifetime.get("total_enemies_killed", 0))
	check_achievement("kills_1000", lifetime.get("total_enemies_killed", 0))
	check_achievement("kills_10000", lifetime.get("total_enemies_killed", 0))

	# Play time
	check_achievement("playtime_1h", lifetime.get("total_play_time_seconds", 0))
	check_achievement("playtime_10h", lifetime.get("total_play_time_seconds", 0))
	check_achievement("playtime_100h", lifetime.get("total_play_time_seconds", 0))

	# Towers
	check_achievement("first_tower", lifetime.get("total_towers_built", 0))
	check_achievement("tower_master", lifetime.get("total_towers_built", 0))

	# Powerups
	check_achievement("powerup_collector", lifetime.get("total_powerups_collected", 0))

	# Daily streak
	check_achievement("streak_7", lifetime.get("current_daily_streak", 0))
	check_achievement("streak_30", lifetime.get("current_daily_streak", 0))

# ============================================================================
# EVENT HANDLERS
# ============================================================================

func _on_game_started() -> void:
	session_no_portal_damage = true

func _on_game_over(won: bool, stats: Dictionary) -> void:
	check_session_achievements(stats)
	check_lifetime_achievements()

func _on_combo_updated(combo: int) -> void:
	check_achievement("combo_5", combo)
	check_achievement("combo_10", combo)
	check_achievement("combo_25", combo)
	check_achievement("combo_50", combo)
	check_achievement("combo_100", combo)
	check_achievement("combo_200", combo)

func _on_enemy_killed(enemy: Node, typed: bool) -> void:
	pass  # Handled by lifetime stats

func _on_enemy_reached_portal(enemy: Node) -> void:
	session_no_portal_damage = false

func _on_powerup_collected(type: int, name: String) -> void:
	pass  # Handled by lifetime stats

func _on_word_completed(enemy: Node, combo: int) -> void:
	# Check long word achievement
	if is_instance_valid(enemy) and current_word_no_errors:
		if enemy.word.length() >= 10:
			check_achievement("long_word", 1)

	current_word_no_errors = true
	current_word_length = 0

func _on_word_failed(enemy: Node) -> void:
	current_word_no_errors = true
	current_word_length = 0

func _on_char_typed(char: String, correct: bool) -> void:
	if not correct:
		current_word_no_errors = false
	current_word_length += 1

# ============================================================================
# PERSISTENCE
# ============================================================================

func save_achievements() -> void:
	var file = FileAccess.open(ACHIEVEMENTS_FILE, FileAccess.WRITE)
	if file:
		var data = {
			"unlocked": unlocked_achievements,
			"progress": progress,
			"version": 1
		}
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

func load_achievements() -> void:
	if not FileAccess.file_exists(ACHIEVEMENTS_FILE):
		unlocked_achievements = {}
		progress = {}
		return

	var file = FileAccess.open(ACHIEVEMENTS_FILE, FileAccess.READ)
	if file:
		var json = JSON.new()
		var error = json.parse(file.get_as_text())
		file.close()

		if error == OK:
			var data = json.data
			unlocked_achievements = data.get("unlocked", {})
			progress = data.get("progress", {})
		else:
			unlocked_achievements = {}
			progress = {}

# ============================================================================
# PUBLIC API
# ============================================================================

func get_all_achievements() -> Dictionary:
	return ACHIEVEMENTS.duplicate(true)

func get_unlocked_achievements() -> Dictionary:
	return unlocked_achievements.duplicate(true)

func get_achievement_progress(id: String) -> Dictionary:
	if not ACHIEVEMENTS.has(id):
		return {}

	var achievement = ACHIEVEMENTS[id].duplicate()
	achievement["id"] = id
	achievement["progress"] = progress.get(id, 0)
	achievement["unlocked"] = unlocked_achievements.has(id) and unlocked_achievements[id].get("unlocked", false)
	if achievement["unlocked"]:
		achievement["unlock_date"] = unlocked_achievements[id].get("date", "")

	return achievement

func get_achievements_by_category(category: int) -> Array:
	var result: Array = []
	for id in ACHIEVEMENTS:
		if ACHIEVEMENTS[id]["category"] == category:
			result.append(get_achievement_progress(id))
	return result

func get_unlocked_count() -> int:
	var count = 0
	for id in unlocked_achievements:
		if unlocked_achievements[id].get("unlocked", false):
			count += 1
	return count

func get_total_count() -> int:
	return ACHIEVEMENTS.size()

func get_completion_percentage() -> float:
	if ACHIEVEMENTS.size() == 0:
		return 0.0
	return (float(get_unlocked_count()) / float(ACHIEVEMENTS.size())) * 100.0

func get_tier_name(tier: int) -> String:
	match tier:
		Tier.BRONZE: return "Bronze"
		Tier.SILVER: return "Silver"
		Tier.GOLD: return "Gold"
		Tier.PLATINUM: return "Platinum"
		Tier.DIAMOND: return "Diamond"
		_: return "Unknown"

func get_tier_color(tier: int) -> Color:
	match tier:
		Tier.BRONZE: return Color(0.8, 0.5, 0.2)
		Tier.SILVER: return Color(0.75, 0.75, 0.75)
		Tier.GOLD: return Color(1.0, 0.84, 0.0)
		Tier.PLATINUM: return Color(0.9, 0.9, 1.0)
		Tier.DIAMOND: return Color(0.6, 0.9, 1.0)
		_: return Color.WHITE

func get_category_name(category: int) -> String:
	match category:
		Category.SPEED: return "Speed"
		Category.ACCURACY: return "Accuracy"
		Category.COMBO: return "Combo"
		Category.SURVIVAL: return "Survival"
		Category.SCORE: return "Score"
		Category.GRIND: return "Dedication"
		Category.SPECIAL: return "Special"
		_: return "Unknown"
