## statistics_manager.gd
## Comprehensive statistics tracking with SQLite-like JSON persistence
## Tracks session stats, lifetime aggregates, and detailed typing analytics
## Autoload singleton: StatisticsManager
extends Node

# Save file paths
const STATS_FILE := "user://statistics.json"
const SESSIONS_FILE := "user://sessions.json"
const BACKUP_INTERVAL := 60.0  # Auto-save every 60 seconds

# ============================================================================
# SESSION DATA (Current game session)
# ============================================================================
var session: Dictionary = {}

# ============================================================================
# LIFETIME DATA (Persistent across all sessions)
# ============================================================================
var lifetime: Dictionary = {}

# ============================================================================
# DETAILED TRACKING (For deep analysis)
# ============================================================================
var letter_stats: Dictionary = {}  # {A: {typed: 0, errors: 0, total_time_ms: 0}}
var bigram_stats: Dictionary = {}  # {TH: {typed: 0, total_time_ms: 0}}
var word_length_stats: Dictionary = {}  # {3: {completed: 0, failed: 0, total_time_ms: 0}}
var combo_history: Array = []  # Array of combo lengths achieved
var session_history: Array = []  # Last 100 sessions for trends

# Tracking state
var session_start_time: float = 0.0
var last_char_time: float = 0.0
var last_char: String = ""
var current_word_start_time: float = 0.0
var words_this_session: Array = []  # [{word, time_ms, errors, first_try}]

# Auto-save timer
var save_timer: Timer = null

func _ready() -> void:
	load_all_data()
	setup_save_timer()
	connect_signals()
	DebugHelper.log_info("StatisticsManager initialized")

func setup_save_timer() -> void:
	save_timer = Timer.new()
	save_timer.wait_time = BACKUP_INTERVAL
	save_timer.autostart = true
	save_timer.timeout.connect(_on_save_timer)
	add_child(save_timer)

func connect_signals() -> void:
	SignalBus.char_typed.connect(_on_char_typed)
	SignalBus.word_completed.connect(_on_word_completed)
	SignalBus.word_failed.connect(_on_word_failed)
	SignalBus.combo_updated.connect(_on_combo_updated)
	SignalBus.combo_reset.connect(_on_combo_reset)
	SignalBus.enemy_killed.connect(_on_enemy_killed)
	SignalBus.enemy_reached_portal.connect(_on_enemy_reached_portal)
	SignalBus.wave_completed.connect(_on_wave_completed)
	SignalBus.powerup_collected.connect(_on_powerup_collected)
	SignalBus.game_started.connect(_on_game_started)
	SignalBus.game_over.connect(_on_game_over)

# ============================================================================
# SESSION MANAGEMENT
# ============================================================================

func start_session() -> void:
	session = {
		"start_time": Time.get_unix_time_from_system(),
		"duration_seconds": 0.0,
		"wave_reached": 0,
		"score": 0,

		# Speed metrics
		"total_chars": 0,
		"correct_chars": 0,
		"errors": 0,
		"total_time_typing_ms": 0,

		# Combo metrics
		"max_combo": 0,
		"combo_count": 0,  # Number of combos achieved
		"combo_sum": 0,  # Sum of all combo lengths

		# Game metrics
		"enemies_killed": 0,
		"enemies_escaped": 0,
		"powerups_collected": 0,
		"powerups_missed": 0,
		"towers_built": 0,

		# Word metrics
		"words_completed": 0,
		"words_failed": 0,
		"first_try_words": 0,

		# Error position tracking
		"errors_at_start": 0,  # First 33% of word
		"errors_at_middle": 0,  # Middle 33%
		"errors_at_end": 0,  # Last 33%

		# Per-letter errors this session
		"letter_errors": {},

		# Timestamps for analysis
		"keystroke_times": [],  # For rhythm analysis (limited to last 1000)

		# Reaction times
		"reaction_times": [],  # Time from word appear to first keystroke
	}

	session_start_time = Time.get_ticks_msec() / 1000.0
	last_char_time = 0.0
	last_char = ""
	current_word_start_time = 0.0
	words_this_session = []
	combo_history = []

	DebugHelper.log_info("Statistics session started")

func end_session(won: bool, final_stats: Dictionary) -> void:
	if session.is_empty():
		return

	session["duration_seconds"] = (Time.get_ticks_msec() / 1000.0) - session_start_time
	session["won"] = won
	session["wave_reached"] = final_stats.get("wave", 0)
	session["score"] = final_stats.get("score", 0)
	session["death_reason"] = final_stats.get("death_reason", "")

	# Calculate derived metrics
	calculate_session_metrics()

	# Update lifetime stats
	update_lifetime_stats()

	# Add to session history
	add_to_session_history()

	# Save everything
	save_all_data()

	DebugHelper.log_info("Statistics session ended - WPM: %.1f, Accuracy: %.1f%%" % [
		session.get("wpm", 0), session.get("accuracy", 0)
	])

func calculate_session_metrics() -> void:
	var duration_minutes = session["duration_seconds"] / 60.0
	if duration_minutes < 0.01:
		duration_minutes = 0.01  # Prevent division by zero

	# WPM (standard: 5 chars = 1 word)
	session["wpm"] = (session["correct_chars"] / 5.0) / duration_minutes

	# CPM
	session["cpm"] = session["correct_chars"] / duration_minutes

	# Accuracy
	if session["total_chars"] > 0:
		session["accuracy"] = (float(session["correct_chars"]) / float(session["total_chars"])) * 100.0
	else:
		session["accuracy"] = 0.0

	# Adjusted WPM (penalize errors)
	session["adjusted_wpm"] = maxf(0, session["wpm"] - (session["errors"] * 0.5))

	# Error rate (per 100 chars)
	if session["total_chars"] > 0:
		session["error_rate"] = (float(session["errors"]) / float(session["total_chars"])) * 100.0
	else:
		session["error_rate"] = 0.0

	# First-try rate
	if session["words_completed"] > 0:
		session["first_try_rate"] = (float(session["first_try_words"]) / float(session["words_completed"])) * 100.0
	else:
		session["first_try_rate"] = 0.0

	# Average combo
	if session["combo_count"] > 0:
		session["avg_combo"] = float(session["combo_sum"]) / float(session["combo_count"])
	else:
		session["avg_combo"] = 0.0

	# Kill efficiency
	var total_enemies = session["enemies_killed"] + session["enemies_escaped"]
	if total_enemies > 0:
		session["kill_efficiency"] = (float(session["enemies_killed"]) / float(total_enemies)) * 100.0
	else:
		session["kill_efficiency"] = 0.0

	# Rhythm score (consistency of keystroke timing)
	session["rhythm_score"] = calculate_rhythm_score()

	# Average reaction time
	if session["reaction_times"].size() > 0:
		var sum = 0.0
		for rt in session["reaction_times"]:
			sum += rt
		session["avg_reaction_time"] = sum / session["reaction_times"].size()
	else:
		session["avg_reaction_time"] = 0.0

	# Find most problematic letters
	session["problematic_letters"] = get_problematic_letters(session["letter_errors"])

func calculate_rhythm_score() -> float:
	var times = session["keystroke_times"]
	if times.size() < 10:
		return 0.0

	# Calculate inter-keystroke intervals
	var intervals: Array = []
	for i in range(1, times.size()):
		intervals.append(times[i] - times[i-1])

	if intervals.is_empty():
		return 0.0

	# Calculate mean and standard deviation
	var mean = 0.0
	for interval in intervals:
		mean += interval
	mean /= intervals.size()

	var variance = 0.0
	for interval in intervals:
		variance += pow(interval - mean, 2)
	variance /= intervals.size()

	var std_dev = sqrt(variance)

	# Coefficient of variation (lower = more consistent)
	if mean > 0:
		var cv = std_dev / mean
		# Convert to score (0-100, higher = better)
		return clampf((1.0 - cv) * 100.0, 0.0, 100.0)

	return 0.0

func get_problematic_letters(letter_errors: Dictionary) -> Array:
	var sorted_letters: Array = []
	for letter in letter_errors:
		sorted_letters.append({"letter": letter, "errors": letter_errors[letter]})

	sorted_letters.sort_custom(func(a, b): return a["errors"] > b["errors"])

	var result: Array = []
	for i in range(mini(5, sorted_letters.size())):
		result.append(sorted_letters[i]["letter"])

	return result

# ============================================================================
# LIFETIME STATS
# ============================================================================

func init_lifetime_stats() -> void:
	lifetime = {
		"total_games": 0,
		"total_wins": 0,
		"total_play_time_seconds": 0,
		"total_chars_typed": 0,
		"total_correct_chars": 0,
		"total_errors": 0,
		"total_words_completed": 0,
		"total_words_failed": 0,
		"total_enemies_killed": 0,
		"total_enemies_escaped": 0,
		"total_powerups_collected": 0,
		"total_towers_built": 0,
		"total_score": 0,

		# Personal bests
		"best_wpm": 0.0,
		"best_accuracy": 0.0,
		"best_combo": 0,
		"best_wave": 0,
		"best_score": 0,
		"best_kill_streak": 0,

		# Personal best dates
		"best_wpm_date": "",
		"best_accuracy_date": "",
		"best_combo_date": "",
		"best_wave_date": "",
		"best_score_date": "",

		# Streaks
		"current_daily_streak": 0,
		"best_daily_streak": 0,
		"last_play_date": "",

		# First play date
		"first_play_date": "",

		# Averages (calculated)
		"avg_wpm": 0.0,
		"avg_accuracy": 0.0,
		"avg_wave": 0.0,
		"avg_score": 0.0,
	}

func update_lifetime_stats() -> void:
	var today = Time.get_date_string_from_system()

	# Update totals
	lifetime["total_games"] += 1
	if session.get("won", false):
		lifetime["total_wins"] += 1
	lifetime["total_play_time_seconds"] += session["duration_seconds"]
	lifetime["total_chars_typed"] += session["total_chars"]
	lifetime["total_correct_chars"] += session["correct_chars"]
	lifetime["total_errors"] += session["errors"]
	lifetime["total_words_completed"] += session["words_completed"]
	lifetime["total_words_failed"] += session["words_failed"]
	lifetime["total_enemies_killed"] += session["enemies_killed"]
	lifetime["total_enemies_escaped"] += session["enemies_escaped"]
	lifetime["total_powerups_collected"] += session["powerups_collected"]
	lifetime["total_towers_built"] += session["towers_built"]
	lifetime["total_score"] += session["score"]

	# Check personal bests
	if session.get("wpm", 0) > lifetime["best_wpm"]:
		lifetime["best_wpm"] = session["wpm"]
		lifetime["best_wpm_date"] = today

	if session.get("accuracy", 0) > lifetime["best_accuracy"]:
		lifetime["best_accuracy"] = session["accuracy"]
		lifetime["best_accuracy_date"] = today

	if session.get("max_combo", 0) > lifetime["best_combo"]:
		lifetime["best_combo"] = session["max_combo"]
		lifetime["best_combo_date"] = today

	if session.get("wave_reached", 0) > lifetime["best_wave"]:
		lifetime["best_wave"] = session["wave_reached"]
		lifetime["best_wave_date"] = today

	if session.get("score", 0) > lifetime["best_score"]:
		lifetime["best_score"] = session["score"]
		lifetime["best_score_date"] = today

	# Update daily streak
	var last_date = lifetime["last_play_date"]
	if last_date == "":
		lifetime["current_daily_streak"] = 1
		lifetime["first_play_date"] = today
	elif last_date == today:
		pass  # Same day, no change
	else:
		# Check if yesterday
		var yesterday = get_yesterday_date()
		if last_date == yesterday:
			lifetime["current_daily_streak"] += 1
		else:
			lifetime["current_daily_streak"] = 1

	lifetime["last_play_date"] = today

	if lifetime["current_daily_streak"] > lifetime["best_daily_streak"]:
		lifetime["best_daily_streak"] = lifetime["current_daily_streak"]

	# Calculate averages
	if lifetime["total_games"] > 0:
		lifetime["avg_wave"] = float(lifetime["total_enemies_killed"]) / float(lifetime["total_games"])  # Approximation
		lifetime["avg_score"] = float(lifetime["total_score"]) / float(lifetime["total_games"])

	if lifetime["total_chars_typed"] > 0:
		lifetime["avg_accuracy"] = (float(lifetime["total_correct_chars"]) / float(lifetime["total_chars_typed"])) * 100.0

	# Update letter stats
	for letter in session["letter_errors"]:
		if not letter_stats.has(letter):
			letter_stats[letter] = {"typed": 0, "errors": 0}
		letter_stats[letter]["errors"] += session["letter_errors"][letter]

func get_yesterday_date() -> String:
	var unix = Time.get_unix_time_from_system() - 86400
	var datetime = Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [datetime.year, datetime.month, datetime.day]

func add_to_session_history() -> void:
	var summary = {
		"date": Time.get_datetime_string_from_system(),
		"wpm": session.get("wpm", 0),
		"accuracy": session.get("accuracy", 0),
		"wave": session.get("wave_reached", 0),
		"score": session.get("score", 0),
		"max_combo": session.get("max_combo", 0),
		"duration": session.get("duration_seconds", 0),
		"won": session.get("won", false),
	}

	session_history.append(summary)

	# Keep only last 100 sessions
	while session_history.size() > 100:
		session_history.pop_front()

# ============================================================================
# EVENT HANDLERS
# ============================================================================

func _on_game_started() -> void:
	start_session()

func _on_game_over(won: bool, stats: Dictionary) -> void:
	end_session(won, stats)

func _on_char_typed(char: String, correct: bool) -> void:
	if session.is_empty():
		return

	var current_time = Time.get_ticks_msec()

	session["total_chars"] += 1

	if correct:
		session["correct_chars"] += 1

		# Track keystroke timing (for rhythm analysis)
		if session["keystroke_times"].size() < 1000:
			session["keystroke_times"].append(current_time)

		# Track bigram timing
		if last_char != "" and last_char_time > 0:
			var bigram = last_char + char
			var interval = current_time - last_char_time

			if not bigram_stats.has(bigram):
				bigram_stats[bigram] = {"typed": 0, "total_time_ms": 0}
			bigram_stats[bigram]["typed"] += 1
			bigram_stats[bigram]["total_time_ms"] += interval

		# Update letter stats
		if not letter_stats.has(char):
			letter_stats[char] = {"typed": 0, "errors": 0}
		letter_stats[char]["typed"] += 1

		last_char = char
		last_char_time = current_time
	else:
		session["errors"] += 1

		# Track letter errors
		if not session["letter_errors"].has(char):
			session["letter_errors"][char] = 0
		session["letter_errors"][char] += 1

		# Track error position (requires active word context)
		# This is approximated based on typed_index from TypingManager
		var typed_idx = TypingManager.typed_index if TypingManager else 0
		var word_len = 6  # Default assumption
		if TypingManager and TypingManager.active_enemy:
			word_len = TypingManager.active_enemy.word.length()

		var position_ratio = float(typed_idx) / float(word_len) if word_len > 0 else 0.5
		if position_ratio < 0.33:
			session["errors_at_start"] += 1
		elif position_ratio < 0.67:
			session["errors_at_middle"] += 1
		else:
			session["errors_at_end"] += 1

		# Update letter stats
		if not letter_stats.has(char):
			letter_stats[char] = {"typed": 0, "errors": 0}
		letter_stats[char]["errors"] += 1

		last_char = ""
		last_char_time = 0

func _on_word_completed(enemy: Node, combo: int) -> void:
	if session.is_empty():
		return

	session["words_completed"] += 1

	# Check if first try (no errors during this word)
	# This is tracked per-word
	var word_errors = 0  # TODO: Track per-word errors
	if word_errors == 0:
		session["first_try_words"] += 1

	# Track word length stats
	if is_instance_valid(enemy):
		var word_len = enemy.word.length()
		if not word_length_stats.has(word_len):
			word_length_stats[word_len] = {"completed": 0, "failed": 0, "total_time_ms": 0}
		word_length_stats[word_len]["completed"] += 1

		# Approximate time for this word
		if current_word_start_time > 0:
			var word_time = Time.get_ticks_msec() - current_word_start_time
			word_length_stats[word_len]["total_time_ms"] += word_time

	current_word_start_time = Time.get_ticks_msec()

func _on_word_failed(enemy: Node) -> void:
	if session.is_empty():
		return

	session["words_failed"] += 1

	if is_instance_valid(enemy):
		var word_len = enemy.word.length()
		if not word_length_stats.has(word_len):
			word_length_stats[word_len] = {"completed": 0, "failed": 0, "total_time_ms": 0}
		word_length_stats[word_len]["failed"] += 1

	current_word_start_time = Time.get_ticks_msec()

func _on_combo_updated(combo: int) -> void:
	if session.is_empty():
		return

	if combo > session["max_combo"]:
		session["max_combo"] = combo

func _on_combo_reset() -> void:
	if session.is_empty():
		return

	# Record this combo in history
	if session["max_combo"] > 0:
		combo_history.append(session["max_combo"])
		session["combo_count"] += 1
		session["combo_sum"] += session["max_combo"]

func _on_enemy_killed(enemy: Node, typed: bool) -> void:
	if session.is_empty():
		return

	if typed:
		session["enemies_killed"] += 1

func _on_enemy_reached_portal(enemy: Node) -> void:
	if session.is_empty():
		return

	session["enemies_escaped"] += 1

func _on_wave_completed(wave: int) -> void:
	if session.is_empty():
		return

	session["wave_reached"] = wave

func _on_powerup_collected(type: int, name: String) -> void:
	if session.is_empty():
		return

	session["powerups_collected"] += 1

func _on_save_timer() -> void:
	if not session.is_empty():
		save_all_data()

# ============================================================================
# PERSISTENCE
# ============================================================================

func save_all_data() -> void:
	save_lifetime_stats()
	save_session_history()
	save_detailed_stats()

func load_all_data() -> void:
	load_lifetime_stats()
	load_session_history()
	load_detailed_stats()

func save_lifetime_stats() -> void:
	var file = FileAccess.open(STATS_FILE, FileAccess.WRITE)
	if file:
		var data = {
			"lifetime": lifetime,
			"letter_stats": letter_stats,
			"bigram_stats": bigram_stats,
			"word_length_stats": word_length_stats,
			"version": 1
		}
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

func load_lifetime_stats() -> void:
	if not FileAccess.file_exists(STATS_FILE):
		init_lifetime_stats()
		return

	var file = FileAccess.open(STATS_FILE, FileAccess.READ)
	if file:
		var json = JSON.new()
		var error = json.parse(file.get_as_text())
		file.close()

		if error == OK:
			var data = json.data
			if data.has("lifetime"):
				lifetime = data["lifetime"]
			else:
				init_lifetime_stats()

			if data.has("letter_stats"):
				letter_stats = data["letter_stats"]
			if data.has("bigram_stats"):
				bigram_stats = data["bigram_stats"]
			if data.has("word_length_stats"):
				word_length_stats = data["word_length_stats"]
		else:
			init_lifetime_stats()
	else:
		init_lifetime_stats()

func save_session_history() -> void:
	var file = FileAccess.open(SESSIONS_FILE, FileAccess.WRITE)
	if file:
		var data = {
			"sessions": session_history,
			"version": 1
		}
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

func load_session_history() -> void:
	if not FileAccess.file_exists(SESSIONS_FILE):
		session_history = []
		return

	var file = FileAccess.open(SESSIONS_FILE, FileAccess.READ)
	if file:
		var json = JSON.new()
		var error = json.parse(file.get_as_text())
		file.close()

		if error == OK:
			var data = json.data
			if data.has("sessions"):
				session_history = data["sessions"]
		else:
			session_history = []
	else:
		session_history = []

func save_detailed_stats() -> void:
	# Detailed stats are saved with lifetime stats
	pass

func load_detailed_stats() -> void:
	# Detailed stats are loaded with lifetime stats
	pass

# ============================================================================
# PUBLIC API - For UI and other systems
# ============================================================================

func get_session_stats() -> Dictionary:
	return session.duplicate(true)

func get_lifetime_stats() -> Dictionary:
	return lifetime.duplicate(true)

func get_session_history() -> Array:
	return session_history.duplicate(true)

func get_letter_stats() -> Dictionary:
	return letter_stats.duplicate(true)

func get_bigram_stats() -> Dictionary:
	return bigram_stats.duplicate(true)

func get_word_length_stats() -> Dictionary:
	return word_length_stats.duplicate(true)

func get_learning_curve() -> Array:
	# Return WPM and accuracy trends over last sessions
	var curve: Array = []
	for s in session_history:
		curve.append({
			"wpm": s.get("wpm", 0),
			"accuracy": s.get("accuracy", 0),
			"date": s.get("date", "")
		})
	return curve

func get_top_bigrams(count: int = 10) -> Array:
	var sorted_bigrams: Array = []
	for bigram in bigram_stats:
		var stats = bigram_stats[bigram]
		if stats["typed"] >= 5:  # Minimum sample size
			var avg_time = float(stats["total_time_ms"]) / float(stats["typed"])
			sorted_bigrams.append({"bigram": bigram, "avg_time": avg_time, "count": stats["typed"]})

	sorted_bigrams.sort_custom(func(a, b): return a["avg_time"] < b["avg_time"])
	return sorted_bigrams.slice(0, count)

func get_slow_bigrams(count: int = 10) -> Array:
	var sorted_bigrams: Array = []
	for bigram in bigram_stats:
		var stats = bigram_stats[bigram]
		if stats["typed"] >= 5:  # Minimum sample size
			var avg_time = float(stats["total_time_ms"]) / float(stats["typed"])
			sorted_bigrams.append({"bigram": bigram, "avg_time": avg_time, "count": stats["typed"]})

	sorted_bigrams.sort_custom(func(a, b): return a["avg_time"] > b["avg_time"])
	return sorted_bigrams.slice(0, count)

func get_error_prone_letters(count: int = 10) -> Array:
	var sorted_letters: Array = []
	for letter in letter_stats:
		var stats = letter_stats[letter]
		if stats["typed"] >= 10:  # Minimum sample size
			var error_rate = float(stats["errors"]) / float(stats["typed"]) * 100.0
			sorted_letters.append({"letter": letter, "error_rate": error_rate, "errors": stats["errors"], "typed": stats["typed"]})

	sorted_letters.sort_custom(func(a, b): return a["error_rate"] > b["error_rate"])
	return sorted_letters.slice(0, count)

func get_fatigue_analysis() -> Dictionary:
	# Analyze performance degradation over session duration
	if session_history.size() < 5:
		return {"has_data": false}

	var short_sessions: Array = []  # < 2 min
	var medium_sessions: Array = []  # 2-5 min
	var long_sessions: Array = []  # > 5 min

	for s in session_history:
		var duration = s.get("duration", 0)
		var wpm = s.get("wpm", 0)
		var accuracy = s.get("accuracy", 0)

		if duration < 120:
			short_sessions.append({"wpm": wpm, "accuracy": accuracy})
		elif duration < 300:
			medium_sessions.append({"wpm": wpm, "accuracy": accuracy})
		else:
			long_sessions.append({"wpm": wpm, "accuracy": accuracy})

	return {
		"has_data": true,
		"short_avg_wpm": calculate_avg(short_sessions, "wpm"),
		"short_avg_accuracy": calculate_avg(short_sessions, "accuracy"),
		"medium_avg_wpm": calculate_avg(medium_sessions, "wpm"),
		"medium_avg_accuracy": calculate_avg(medium_sessions, "accuracy"),
		"long_avg_wpm": calculate_avg(long_sessions, "wpm"),
		"long_avg_accuracy": calculate_avg(long_sessions, "accuracy"),
	}

func calculate_avg(arr: Array, key: String) -> float:
	if arr.is_empty():
		return 0.0
	var sum = 0.0
	for item in arr:
		sum += item.get(key, 0)
	return sum / arr.size()

func get_pressure_performance() -> Dictionary:
	# Analyze performance at high vs low combo
	# This would require more detailed per-keystroke tracking
	return {
		"has_data": false,
		"low_combo_accuracy": 0.0,  # When combo < 5
		"high_combo_accuracy": 0.0,  # When combo >= 10
	}

func format_time(seconds: float) -> String:
	var hours = int(seconds / 3600)
	var minutes = int(fmod(seconds, 3600) / 60)
	var secs = int(fmod(seconds, 60))

	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, secs]
	else:
		return "%d:%02d" % [minutes, secs]

func format_play_time(seconds: float) -> String:
	var hours = seconds / 3600.0
	if hours >= 1:
		return "%.1f hours" % hours
	else:
		return "%d min" % int(seconds / 60)
