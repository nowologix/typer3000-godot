## steam_manager.gd
## Steam integration using GodotSteam addon
## Reference: https://godotsteam.com/
## Setup: See STEAM_SETUP.txt in project root
## NOTE: Works without GodotSteam installed (offline mode)
extends Node

# Steam status
var steam_initialized: bool = false
var steam_app_id: int = 0
var steam_username: String = ""
var steam_id: int = 0

# Steam singleton reference (null if not available)
var _steam = null

# Leaderboard caching
var leaderboards: Dictionary = {}
var pending_leaderboard_requests: Array = []

# Achievement definitions (mirror of NeoSphere achievements)
const ACHIEVEMENTS := {
	# Word count achievements
	"FIRST_BLOOD": {"id": "first_blood", "name": "First Blood", "desc": "Destroy your first enemy"},
	"WORDSMITH_BRONZE": {"id": "wordsmith_bronze", "name": "Bronze Wordsmith", "desc": "Type 100 words"},
	"WORDSMITH_SILVER": {"id": "wordsmith_silver", "name": "Silver Wordsmith", "desc": "Type 500 words"},
	"WORDSMITH_GOLD": {"id": "wordsmith_gold", "name": "Gold Wordsmith", "desc": "Type 1000 words"},
	"WORDSMITH_DIAMOND": {"id": "wordsmith_diamond", "name": "Diamond Wordsmith", "desc": "Type 5000 words"},

	# Wave achievements
	"SURVIVOR_5": {"id": "survivor_5", "name": "Survivor", "desc": "Survive 5 waves"},
	"SURVIVOR_10": {"id": "survivor_10", "name": "Veteran", "desc": "Survive 10 waves"},
	"SURVIVOR_20": {"id": "survivor_20", "name": "Champion", "desc": "Survive 20 waves"},
	"SURVIVOR_50": {"id": "survivor_50", "name": "Legend", "desc": "Survive 50 waves"},

	# Combo achievements
	"COMBO_10": {"id": "combo_10", "name": "On Fire", "desc": "Reach a 10x combo"},
	"COMBO_25": {"id": "combo_25", "name": "Blazing", "desc": "Reach a 25x combo"},
	"COMBO_50": {"id": "combo_50", "name": "Unstoppable", "desc": "Reach a 50x combo"},
	"COMBO_100": {"id": "combo_100", "name": "Godlike", "desc": "Reach a 100x combo"},

	# Score achievements
	"SCORE_1K": {"id": "score_1k", "name": "Getting Started", "desc": "Score 1,000 points"},
	"SCORE_10K": {"id": "score_10k", "name": "Rising Star", "desc": "Score 10,000 points"},
	"SCORE_100K": {"id": "score_100k", "name": "Master Typist", "desc": "Score 100,000 points"},

	# Special achievements
	"PERFECT_WAVE": {"id": "perfect_wave", "name": "Perfect Wave", "desc": "Complete a wave with 100% accuracy"},
	"SPEED_DEMON": {"id": "speed_demon", "name": "Speed Demon", "desc": "Type a 10+ letter word in under 2 seconds"},
	"COMEBACK_KID": {"id": "comeback_kid", "name": "Comeback Kid", "desc": "Win with portal HP at 1"},
	"MARATHON": {"id": "marathon", "name": "Marathon", "desc": "Play for 30 minutes in a single session"},
}

func _ready() -> void:
	init_steam()

func _process(_delta: float) -> void:
	# Required: Run Steam callbacks every frame
	if steam_initialized and _steam != null:
		_steam.run_callbacks()

func init_steam() -> bool:
	# Check if Steam singleton exists (GodotSteam is installed)
	if not Engine.has_singleton("Steam"):
		DebugHelper.log_info("SteamManager: GodotSteam not installed - running in offline mode")
		steam_initialized = false
		return false

	# Get Steam singleton reference
	_steam = Engine.get_singleton("Steam")
	if _steam == null:
		DebugHelper.log_warning("SteamManager: Could not get Steam singleton")
		steam_initialized = false
		return false

	# Initialize Steam
	var init_result = _steam.steamInitEx()
	DebugHelper.log_info("SteamManager: Init result = %s" % str(init_result))

	if init_result.status == 0:  # OK
		steam_initialized = true
		steam_app_id = _steam.getAppID()
		steam_id = _steam.getSteamID()
		steam_username = _steam.getPersonaName()

		DebugHelper.log_info("SteamManager: Initialized successfully")
		DebugHelper.log_info("  App ID: %d" % steam_app_id)
		DebugHelper.log_info("  User: %s (ID: %d)" % [steam_username, steam_id])

		# Connect Steam signals
		_steam.connect("current_stats_received", _on_stats_received)
		_steam.connect("leaderboard_find_result", _on_leaderboard_found)
		_steam.connect("leaderboard_score_uploaded", _on_score_uploaded)
		_steam.connect("leaderboard_scores_downloaded", _on_scores_downloaded)

		# Request user stats/achievements
		_steam.requestCurrentStats()

		return true
	else:
		DebugHelper.log_warning("SteamManager: Init failed - %s" % init_result.verbal)
		steam_initialized = false
		return false

func is_steam_running() -> bool:
	return steam_initialized

func get_steam_username() -> String:
	return steam_username if steam_initialized else "Player"

func get_steam_id() -> int:
	return steam_id if steam_initialized else 0

func unlock_achievement(achievement_key: String) -> void:
	if not ACHIEVEMENTS.has(achievement_key):
		DebugHelper.log_warning("SteamManager: Unknown achievement '%s'" % achievement_key)
		return

	var achievement = ACHIEVEMENTS[achievement_key]

	if not steam_initialized or _steam == null:
		DebugHelper.log_debug("SteamManager: Achievement '%s' unlocked (offline)" % achievement.name)
		# Still track locally via SaveManager
		SignalBus.achievement_unlocked.emit(achievement_key, achievement.name)
		return

	# Check if already unlocked
	var ach_status = _steam.getAchievement(achievement.id)
	if ach_status.achieved:
		return  # Already unlocked

	# Unlock achievement
	_steam.setAchievement(achievement.id)
	_steam.storeStats()

	DebugHelper.log_info("SteamManager: Achievement unlocked - '%s'" % achievement.name)
	SignalBus.achievement_unlocked.emit(achievement_key, achievement.name)

func check_word_count_achievements(total_words: int) -> void:
	if total_words >= 1:
		unlock_achievement("FIRST_BLOOD")
	if total_words >= 100:
		unlock_achievement("WORDSMITH_BRONZE")
	if total_words >= 500:
		unlock_achievement("WORDSMITH_SILVER")
	if total_words >= 1000:
		unlock_achievement("WORDSMITH_GOLD")
	if total_words >= 5000:
		unlock_achievement("WORDSMITH_DIAMOND")

func check_wave_achievements(wave: int) -> void:
	if wave >= 5:
		unlock_achievement("SURVIVOR_5")
	if wave >= 10:
		unlock_achievement("SURVIVOR_10")
	if wave >= 20:
		unlock_achievement("SURVIVOR_20")
	if wave >= 50:
		unlock_achievement("SURVIVOR_50")

func check_combo_achievements(combo: int) -> void:
	if combo >= 10:
		unlock_achievement("COMBO_10")
	if combo >= 25:
		unlock_achievement("COMBO_25")
	if combo >= 50:
		unlock_achievement("COMBO_50")
	if combo >= 100:
		unlock_achievement("COMBO_100")

func check_score_achievements(score: int) -> void:
	if score >= 1000:
		unlock_achievement("SCORE_1K")
	if score >= 10000:
		unlock_achievement("SCORE_10K")
	if score >= 100000:
		unlock_achievement("SCORE_100K")

func submit_leaderboard_score(leaderboard_name: String, score: int) -> void:
	if not steam_initialized or _steam == null:
		DebugHelper.log_debug("SteamManager: Leaderboard '%s' score %d (offline)" % [leaderboard_name, score])
		return

	# Queue the score submission
	pending_leaderboard_requests.append({
		"type": "upload",
		"leaderboard": leaderboard_name,
		"score": score
	})

	# Find or create leaderboard
	if leaderboards.has(leaderboard_name):
		_upload_score(leaderboards[leaderboard_name], score)
	else:
		_steam.findOrCreateLeaderboard(leaderboard_name, 2, 1)  # DESCENDING, NUMERIC

	DebugHelper.log_info("SteamManager: Submitting score %d to '%s'" % [score, leaderboard_name])

func request_leaderboard_scores(leaderboard_name: String, start: int = 1, end: int = 10) -> void:
	if not steam_initialized or _steam == null:
		return

	if leaderboards.has(leaderboard_name):
		_steam.downloadLeaderboardEntries(start, end, 0, leaderboards[leaderboard_name])  # GLOBAL
	else:
		pending_leaderboard_requests.append({
			"type": "download",
			"leaderboard": leaderboard_name,
			"start": start,
			"end": end
		})
		_steam.findOrCreateLeaderboard(leaderboard_name, 2, 1)

func request_friend_leaderboard(leaderboard_name: String) -> void:
	if not steam_initialized or _steam == null:
		return

	if leaderboards.has(leaderboard_name):
		_steam.downloadLeaderboardEntries(1, 100, 1, leaderboards[leaderboard_name])  # FRIENDS
	else:
		pending_leaderboard_requests.append({
			"type": "download_friends",
			"leaderboard": leaderboard_name
		})
		_steam.findOrCreateLeaderboard(leaderboard_name, 2, 1)

func _upload_score(leaderboard_handle: int, score: int) -> void:
	if _steam != null:
		_steam.uploadLeaderboardScore(score, true, [], leaderboard_handle)

# Signal callbacks
func _on_stats_received(game_id: int, result: int) -> void:
	if result == 1:  # k_EResultOK
		DebugHelper.log_info("SteamManager: Stats received for game %d" % game_id)
	else:
		DebugHelper.log_warning("SteamManager: Failed to receive stats (result: %d)" % result)

func _on_leaderboard_found(leaderboard_handle: int, found: int) -> void:
	if found == 0:
		DebugHelper.log_warning("SteamManager: Leaderboard not found")
		return

	# Process pending requests for this leaderboard
	var processed: Array = []
	for i in range(pending_leaderboard_requests.size()):
		var request = pending_leaderboard_requests[i]
		if request.type == "upload":
			_upload_score(leaderboard_handle, request.score)
			processed.append(i)
		elif request.type == "download" and _steam != null:
			_steam.downloadLeaderboardEntries(request.start, request.end, 0, leaderboard_handle)
			processed.append(i)
		elif request.type == "download_friends" and _steam != null:
			_steam.downloadLeaderboardEntries(1, 100, 1, leaderboard_handle)
			processed.append(i)

	# Remove processed requests (in reverse order to maintain indices)
	processed.reverse()
	for idx in processed:
		pending_leaderboard_requests.remove_at(idx)

func _on_score_uploaded(success: int, _score_handle: int, _score_changed: int) -> void:
	if success == 1:
		DebugHelper.log_info("SteamManager: Score uploaded successfully")
	else:
		DebugHelper.log_warning("SteamManager: Score upload failed")

func _on_scores_downloaded(_message: String, leaderboard_entries: Array) -> void:
	# Emit signal with leaderboard data
	var entries: Array = []
	for entry in leaderboard_entries:
		entries.append({
			"rank": entry.global_rank,
			"name": _steam.getFriendPersonaName(entry.steam_id) if _steam else "Unknown",
			"score": entry.score,
			"steam_id": entry.steam_id
		})

	SignalBus.leaderboard_received.emit(entries)
	DebugHelper.log_info("SteamManager: Received %d leaderboard entries" % entries.size())
