## statistics_state.gd
## Modern Statistics Dashboard with card-based layout
extends Node2D

enum Tab { SPEED, ACCURACY, CONSISTENCY, ANALYSIS, GAME, ACHIEVEMENTS }

const TAB_NAMES := ["SPEED", "ACCURACY", "CONSISTENCY", "ANALYSIS", "GAME", "ACHIEVEMENTS"]

var current_tab: int = Tab.SPEED
var scroll_offset: float = 0.0
var max_scroll: float = 0.0
var target_scroll: float = 0.0

var MARGIN: float = 40.0
var CONTENT_START_Y: float = 140.0

const BG_DARK := Color(0.08, 0.09, 0.12)
const BG_CARD := Color(0.12, 0.13, 0.18)
const BG_CARD_HOVER := Color(0.15, 0.16, 0.22)
const ACCENT_PRIMARY := Color(0.4, 0.8, 1.0)
const ACCENT_SECONDARY := Color(0.98, 0.7, 0.2)
const ACCENT_SUCCESS := Color(0.3, 0.9, 0.4)
const ACCENT_DANGER := Color(1.0, 0.35, 0.4)
const ACCENT_PURPLE := Color(0.7, 0.5, 1.0)
const TEXT_PRIMARY := Color(1.0, 1.0, 1.0)
const TEXT_SECONDARY := Color(0.6, 0.63, 0.7)
const TEXT_MUTED := Color(0.4, 0.42, 0.48)
const BORDER_COLOR := Color(0.2, 0.22, 0.28)

func _ready() -> void:
	DebugHelper.log_info("StatisticsState ready")

func on_enter(_params: Dictionary) -> void:
	DebugHelper.log_info("StatisticsState entered")
	current_tab = Tab.SPEED
	scroll_offset = 0.0
	target_scroll = 0.0
	queue_redraw()

func on_exit() -> void:
	DebugHelper.log_info("StatisticsState exiting")

func _process(delta: float) -> void:
	if abs(scroll_offset - target_scroll) > 0.5:
		scroll_offset = lerp(scroll_offset, target_scroll, delta * 12.0)
		queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode >= KEY_1 and event.keycode <= KEY_6:
			current_tab = event.keycode - KEY_1
			scroll_offset = 0.0
			target_scroll = 0.0
			queue_redraw()
			SoundManager.play_menu_select()
			get_viewport().set_input_as_handled()
			return

		if event.keycode == KEY_LEFT or event.keycode == KEY_A:
			current_tab = (current_tab - 1 + TAB_NAMES.size()) % TAB_NAMES.size()
			scroll_offset = 0.0
			target_scroll = 0.0
			queue_redraw()
			SoundManager.play_menu_select()
			return

		if event.keycode == KEY_RIGHT or event.keycode == KEY_D:
			current_tab = (current_tab + 1) % TAB_NAMES.size()
			scroll_offset = 0.0
			target_scroll = 0.0
			queue_redraw()
			SoundManager.play_menu_select()
			return

		if event.keycode == KEY_ESCAPE:
			StateManager.change_state("menu")
			SoundManager.play_menu_back()
			get_viewport().set_input_as_handled()
			return

		if event.keycode == KEY_UP or event.keycode == KEY_W:
			target_scroll = maxf(0, target_scroll - 60)
			return

		if event.keycode == KEY_DOWN or event.keycode == KEY_S:
			target_scroll = minf(max_scroll, target_scroll + 60)
			return

func _draw() -> void:
	var width = GameConfig.SCREEN_WIDTH
	var height = GameConfig.SCREEN_HEIGHT

	# Background
	draw_rect(Rect2(0, 0, width, height), BG_DARK)

	# Draw content FIRST (so header can mask it)
	draw_content_area()

	# Mask header area - content scrolls BEHIND this
	draw_rect(Rect2(0, 0, width, 120), BG_DARK)

	# Gradient overlay at top
	for i in range(80):
		var alpha = 0.025 * (1.0 - float(i) / 80.0)
		draw_line(Vector2(0, i), Vector2(width, i), Color(ACCENT_PRIMARY.r, ACCENT_PRIMARY.g, ACCENT_PRIMARY.b, alpha))

	# Header and tabs drawn ON TOP
	draw_header()
	draw_modern_tab_bar()
	draw_footer()

func draw_header() -> void:
	var font = ThemeDB.fallback_font
	var width = GameConfig.SCREEN_WIDTH
	draw_string(font, Vector2(MARGIN, 45), "STATISTICS", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, TEXT_PRIMARY)
	var steam_text = "OFFLINE"
	var steam_color = TEXT_MUTED
	if SteamManager and SteamManager.is_steam_running():
		steam_text = SteamManager.get_steam_username()
		steam_color = ACCENT_SUCCESS
	draw_string(font, Vector2(width - MARGIN - 150, 45), steam_text, HORIZONTAL_ALIGNMENT_RIGHT, 150, 14, steam_color)

func draw_modern_tab_bar() -> void:
	var font = ThemeDB.fallback_font
	var width = GameConfig.SCREEN_WIDTH
	var tab_y = 70
	var tab_height = 50
	draw_rect(Rect2(0, tab_y, width, tab_height), Color(0.1, 0.11, 0.14))
	var content_width = width - (MARGIN * 2)
	var tab_width = content_width / TAB_NAMES.size()
	for i in range(TAB_NAMES.size()):
		var tab_x = MARGIN + (i * tab_width)
		var is_active = i == current_tab
		var tab_text = "%d %s" % [i + 1, TAB_NAMES[i]]
		var text_color = ACCENT_PRIMARY if is_active else TEXT_SECONDARY
		var text_x = tab_x + (tab_width / 2) - 45
		draw_string(font, Vector2(text_x, tab_y + 32), tab_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, text_color)
		if is_active:
			var line_width = 70.0
			var line_x = tab_x + (tab_width / 2) - (line_width / 2)
			draw_rect(Rect2(line_x, tab_y + tab_height - 3, line_width, 3), ACCENT_PRIMARY)
	draw_line(Vector2(0, tab_y + tab_height), Vector2(width, tab_y + tab_height), BORDER_COLOR, 1)

func draw_content_area() -> void:
	match current_tab:
		Tab.SPEED: draw_speed_tab()
		Tab.ACCURACY: draw_accuracy_tab()
		Tab.CONSISTENCY: draw_consistency_tab()
		Tab.ANALYSIS: draw_analysis_tab()
		Tab.GAME: draw_game_tab()
		Tab.ACHIEVEMENTS: draw_achievements_tab()

func draw_footer() -> void:
	var font = ThemeDB.fallback_font
	var width = GameConfig.SCREEN_WIDTH
	var height = GameConfig.SCREEN_HEIGHT
	var footer_y = height - 45
	draw_rect(Rect2(0, footer_y, width, 45), Color(0.06, 0.07, 0.1))
	draw_line(Vector2(0, footer_y), Vector2(width, footer_y), BORDER_COLOR, 1)
	var hints = "ESC Back  |  1-6 Tabs  |  A/D Switch  |  W/S Scroll"
	draw_string(font, Vector2(width / 2 - 160, footer_y + 28), hints, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_MUTED)

func draw_card(rect: Rect2, _highlight: bool = false) -> void:
	draw_rect(rect, BG_CARD)
	draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, 1), BORDER_COLOR)
	draw_rect(Rect2(rect.position.x, rect.position.y + rect.size.y - 1, rect.size.x, 1), BORDER_COLOR)
	draw_rect(Rect2(rect.position.x, rect.position.y, 1, rect.size.y), BORDER_COLOR)
	draw_rect(Rect2(rect.position.x + rect.size.x - 1, rect.position.y, 1, rect.size.y), BORDER_COLOR)

func draw_kpi_card(x: float, y: float, w: float, h: float, label: String, value: String, sub_text: String = "", accent: Color = ACCENT_PRIMARY) -> void:
	var font = ThemeDB.fallback_font
	var adjusted_y = y - scroll_offset
	if adjusted_y > GameConfig.SCREEN_HEIGHT or adjusted_y + h < CONTENT_START_Y:
		return
	draw_card(Rect2(x, adjusted_y, w, h))
	draw_rect(Rect2(x, adjusted_y, 4, h), accent)
	draw_string(font, Vector2(x + 20, adjusted_y + 28), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_SECONDARY)
	draw_string(font, Vector2(x + 20, adjusted_y + 62), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, TEXT_PRIMARY)
	if sub_text != "":
		draw_string(font, Vector2(x + 20, adjusted_y + h - 12), sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_MUTED)

func draw_section_title(text: String, y: float) -> float:
	var font = ThemeDB.fallback_font
	var adjusted_y = y - scroll_offset
	if adjusted_y < CONTENT_START_Y - 30 or adjusted_y > GameConfig.SCREEN_HEIGHT:
		return y + 40
	draw_string(font, Vector2(MARGIN, adjusted_y + 20), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, TEXT_PRIMARY)
	draw_line(Vector2(MARGIN, adjusted_y + 28), Vector2(MARGIN + 180, adjusted_y + 28), BORDER_COLOR, 1)
	return y + 40

func draw_progress_bar(x: float, y: float, w: float, progress: float, color: Color = ACCENT_PRIMARY) -> void:
	var h = 8.0
	var adjusted_y = y  # y is already scroll-adjusted by caller
	draw_rect(Rect2(x, adjusted_y, w, h), Color(0.15, 0.16, 0.2))
	var fill_width = w * clampf(progress, 0, 1)
	if fill_width > 0:
		draw_rect(Rect2(x, adjusted_y, fill_width, h), color)


# TAB 1: SPEED
func draw_speed_tab() -> void:
	var font = ThemeDB.fallback_font
	var lifetime = StatisticsManager.get_lifetime_stats() if StatisticsManager else {}
	var history = StatisticsManager.get_session_history() if StatisticsManager else []
	var width = GameConfig.SCREEN_WIDTH
	var y = CONTENT_START_Y + 10

	var avg_wpm = 0.0
	var recent_avg = 0.0
	if history.size() > 0:
		var sum = 0.0
		for s in history:
			sum += s.get("wpm", 0)
		avg_wpm = sum / history.size()
		var recent = history.slice(maxi(0, history.size() - 5), history.size())
		var recent_sum = 0.0
		for s in recent:
			recent_sum += s.get("wpm", 0)
		recent_avg = recent_sum / recent.size() if recent.size() > 0 else 0

	var best_wpm = lifetime.get("best_wpm", 0)
	var card_width = (width - MARGIN * 2 - 30) / 3
	var card_height = 95.0

	draw_kpi_card(MARGIN, y, card_width, card_height, "BEST WPM", "%.0f" % best_wpm, "Personal Record", ACCENT_SECONDARY)
	draw_kpi_card(MARGIN + card_width + 15, y, card_width, card_height, "AVERAGE WPM", "%.0f" % avg_wpm, "%d sessions" % history.size(), ACCENT_PRIMARY)
	draw_kpi_card(MARGIN + (card_width + 15) * 2, y, card_width, card_height, "RECENT AVG", "%.0f" % recent_avg, "Last 5 games", ACCENT_SUCCESS if recent_avg > avg_wpm else ACCENT_DANGER)

	y += card_height + 25
	y = draw_section_title("LEARNING CURVE", y)

	if history.size() >= 2:
		var graph_height = 160.0
		var graph_width = width - MARGIN * 2
		var adjusted_y = y - scroll_offset
		if adjusted_y < GameConfig.SCREEN_HEIGHT and adjusted_y + graph_height > CONTENT_START_Y:
			draw_card(Rect2(MARGIN, adjusted_y, graph_width, graph_height))
			draw_modern_graph(history.slice(maxi(0, history.size() - 15), history.size()), "wpm", MARGIN + 50, adjusted_y + 25, graph_width - 80, graph_height - 50)
		y += graph_height + 20
	else:
		var adjusted_y = y - scroll_offset
		draw_card(Rect2(MARGIN, adjusted_y, width - MARGIN * 2, 70))
		draw_string(font, Vector2(MARGIN + 25, adjusted_y + 40), "Play more games to see your learning curve!", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_MUTED)
		y += 90

	y = draw_section_title("SPEED BREAKDOWN", y)
	var half_width = (width - MARGIN * 2 - 15) / 2
	draw_kpi_card(MARGIN, y, half_width, 80, "BEST CPM", "%.0f" % (best_wpm * 5), "Characters/min", ACCENT_PURPLE)
	draw_kpi_card(MARGIN + half_width + 15, y, half_width, 80, "PEAK KPS", "%.1f" % (best_wpm * 5 / 60.0), "Keys/second", ACCENT_PRIMARY)
	max_scroll = maxf(0, y + 120 - GameConfig.SCREEN_HEIGHT + 80)

# TAB 2: ACCURACY
func draw_accuracy_tab() -> void:
	var font = ThemeDB.fallback_font
	var lifetime = StatisticsManager.get_lifetime_stats() if StatisticsManager else {}
	var width = GameConfig.SCREEN_WIDTH
	var y = CONTENT_START_Y + 10

	var total_chars = lifetime.get("total_chars_typed", 0)
	var correct_chars = lifetime.get("total_correct_chars", 0)
	var total_errors = lifetime.get("total_errors", 0)
	var lifetime_accuracy = (float(correct_chars) / float(total_chars) * 100) if total_chars > 0 else 0
	var best_accuracy = lifetime.get("best_accuracy", 0)

	var card_width = (width - MARGIN * 2 - 30) / 3
	var card_height = 95.0
	var acc_color = ACCENT_SUCCESS if lifetime_accuracy >= 90 else (ACCENT_SECONDARY if lifetime_accuracy >= 75 else ACCENT_DANGER)

	draw_kpi_card(MARGIN, y, card_width, card_height, "LIFETIME ACCURACY", "%.1f%%" % lifetime_accuracy, format_number(total_chars) + " chars", acc_color)
	draw_kpi_card(MARGIN + card_width + 15, y, card_width, card_height, "BEST ACCURACY", "%.1f%%" % best_accuracy, "Personal best", ACCENT_SECONDARY)
	draw_kpi_card(MARGIN + (card_width + 15) * 2, y, card_width, card_height, "TOTAL ERRORS", format_number(total_errors), "%.2f%% rate" % (float(total_errors) / float(total_chars) * 100 if total_chars > 0 else 0), ACCENT_DANGER)

	y += card_height + 25
	y = draw_section_title("ACCURACY METER", y)
	var adjusted_y = y - scroll_offset
	draw_card(Rect2(MARGIN, adjusted_y, width - MARGIN * 2, 70))
	draw_progress_bar(MARGIN + 20, adjusted_y + 32, width - MARGIN * 2 - 40, lifetime_accuracy / 100.0, acc_color)
	draw_string(font, Vector2(MARGIN + 20, adjusted_y + 58), "0%", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_MUTED)
	draw_string(font, Vector2(width - MARGIN - 40, adjusted_y + 58), "100%", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_MUTED)
	y += 90

	y = draw_section_title("ERROR-PRONE LETTERS", y)
	var error_letters = StatisticsManager.get_error_prone_letters(10) if StatisticsManager else []
	adjusted_y = y - scroll_offset

	if error_letters.size() > 0:
		var card_h = mini(error_letters.size(), 6) * 40 + 25
		draw_card(Rect2(MARGIN, adjusted_y, width - MARGIN * 2, card_h))
		var row_y = adjusted_y + 20
		for i in range(mini(6, error_letters.size())):
			var letter_data = error_letters[i]
			var letter = letter_data["letter"]
			var error_rate = letter_data["error_rate"]
			var bar_color = ACCENT_DANGER if error_rate > 10 else (ACCENT_SECONDARY if error_rate > 5 else ACCENT_SUCCESS)
			draw_rect(Rect2(MARGIN + 20, row_y - 10, 28, 28), BG_CARD_HOVER)
			draw_string(font, Vector2(MARGIN + 27, row_y + 8), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT_PRIMARY)
			draw_progress_bar(MARGIN + 60, row_y, 180, error_rate / 20.0, bar_color)
			draw_string(font, Vector2(MARGIN + 260, row_y + 5), "%.1f%%" % error_rate, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_SECONDARY)
			draw_string(font, Vector2(width - MARGIN - 100, row_y + 5), "(%d/%d)" % [letter_data["errors"], letter_data["typed"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_MUTED)
			row_y += 40
		y += card_h + 15
	else:
		draw_card(Rect2(MARGIN, adjusted_y, width - MARGIN * 2, 55))
		draw_string(font, Vector2(MARGIN + 25, adjusted_y + 32), "Type more to analyze error patterns", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_MUTED)
		y += 70
	max_scroll = maxf(0, y - GameConfig.SCREEN_HEIGHT + 80)

# TAB 3: CONSISTENCY
func draw_consistency_tab() -> void:
	var font = ThemeDB.fallback_font
	var width = GameConfig.SCREEN_WIDTH
	var y = CONTENT_START_Y + 10
	var history = StatisticsManager.get_session_history() if StatisticsManager else []

	if history.size() >= 5:
		var wpms: Array = []
		for s in history:
			wpms.append(s.get("wpm", 0))
		var mean = 0.0
		for w in wpms:
			mean += w
		mean /= wpms.size()
		var variance = 0.0
		for w in wpms:
			variance += pow(w - mean, 2)
		variance /= wpms.size()
		var std_dev = sqrt(variance)
		var cv = (std_dev / mean * 100) if mean > 0 else 0

		var card_width = (width - MARGIN * 2 - 30) / 3
		var card_height = 95.0
		var cv_color = ACCENT_SUCCESS if cv < 10 else (ACCENT_SECONDARY if cv < 20 else ACCENT_DANGER)

		draw_kpi_card(MARGIN, y, card_width, card_height, "WPM MEAN", "%.1f" % mean, "Average speed", ACCENT_PRIMARY)
		draw_kpi_card(MARGIN + card_width + 15, y, card_width, card_height, "STD DEVIATION", "%.1f" % std_dev, "Variability", ACCENT_PURPLE)
		draw_kpi_card(MARGIN + (card_width + 15) * 2, y, card_width, card_height, "CV SCORE", "%.1f%%" % cv, "Lower = Better", cv_color)

		y += card_height + 25
		y = draw_section_title("CONSISTENCY RATING", y)
		var adjusted_y = y - scroll_offset
		draw_card(Rect2(MARGIN, adjusted_y, width - MARGIN * 2, 85))
		var rating = "EXCELLENT" if cv < 8 else ("GOOD" if cv < 12 else ("AVERAGE" if cv < 18 else "VARIABLE"))
		var rating_color = ACCENT_SUCCESS if cv < 8 else (ACCENT_PRIMARY if cv < 12 else (ACCENT_SECONDARY if cv < 18 else ACCENT_DANGER))
		draw_string(font, Vector2(MARGIN + 25, adjusted_y + 45), rating, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, rating_color)
		draw_string(font, Vector2(MARGIN + 220, adjusted_y + 45), "Your typing consistency", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_SECONDARY)
		y += 105

		y = draw_section_title("FATIGUE ANALYSIS", y)
		adjusted_y = y - scroll_offset
		var fatigue = StatisticsManager.get_fatigue_analysis() if StatisticsManager else {}
		if fatigue.get("has_data", false):
			draw_card(Rect2(MARGIN, adjusted_y, width - MARGIN * 2, 130))
			var short_wpm = fatigue.get("short_avg_wpm", 0)
			var med_wpm = fatigue.get("medium_avg_wpm", 0)
			var long_wpm = fatigue.get("long_avg_wpm", 0)
			var max_wpm = maxf(maxf(short_wpm, med_wpm), long_wpm)
			var bar_y = adjusted_y + 30
			var bar_width = width - MARGIN * 2 - 200
			draw_string(font, Vector2(MARGIN + 15, bar_y + 5), "Short (<2m)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_SECONDARY)
			draw_progress_bar(MARGIN + 110, bar_y, bar_width, short_wpm / max_wpm if max_wpm > 0 else 0, ACCENT_SUCCESS)
			draw_string(font, Vector2(width - MARGIN - 70, bar_y + 5), "%.0f" % short_wpm, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_PRIMARY)
			bar_y += 32
			draw_string(font, Vector2(MARGIN + 15, bar_y + 5), "Medium (2-5m)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_SECONDARY)
			draw_progress_bar(MARGIN + 110, bar_y, bar_width, med_wpm / max_wpm if max_wpm > 0 else 0, ACCENT_PRIMARY)
			draw_string(font, Vector2(width - MARGIN - 70, bar_y + 5), "%.0f" % med_wpm, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_PRIMARY)
			bar_y += 32
			draw_string(font, Vector2(MARGIN + 15, bar_y + 5), "Long (>5m)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_SECONDARY)
			draw_progress_bar(MARGIN + 110, bar_y, bar_width, long_wpm / max_wpm if max_wpm > 0 else 0, ACCENT_PURPLE)
			draw_string(font, Vector2(width - MARGIN - 70, bar_y + 5), "%.0f" % long_wpm, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_PRIMARY)
			y += 150
		else:
			draw_card(Rect2(MARGIN, adjusted_y, width - MARGIN * 2, 55))
			draw_string(font, Vector2(MARGIN + 25, adjusted_y + 32), "Play varied session lengths", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_MUTED)
			y += 70
	else:
		var adjusted_y = y - scroll_offset
		draw_card(Rect2(MARGIN, adjusted_y, width - MARGIN * 2, 100))
		draw_string(font, Vector2(MARGIN + 25, adjusted_y + 40), "Need at least 5 sessions", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, TEXT_SECONDARY)
		draw_string(font, Vector2(MARGIN + 25, adjusted_y + 65), "Current: %d / 5" % history.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_MUTED)
		draw_progress_bar(MARGIN + 25, adjusted_y + 80, 180, float(history.size()) / 5.0, ACCENT_PRIMARY)
	max_scroll = maxf(0, y - GameConfig.SCREEN_HEIGHT + 80)

# TAB 4: ANALYSIS
func draw_analysis_tab() -> void:
	var font = ThemeDB.fallback_font
	var width = GameConfig.SCREEN_WIDTH
	var y = CONTENT_START_Y + 10
	var half_width = (width - MARGIN * 2 - 20) / 2

	y = draw_section_title("FASTEST BIGRAMS", y)
	var adjusted_y = y - scroll_offset
	var fast_bigrams = StatisticsManager.get_top_bigrams(5) if StatisticsManager else []
	draw_card(Rect2(MARGIN, adjusted_y, half_width, 185))

	if fast_bigrams.size() > 0:
		var row_y = adjusted_y + 20
		for i in range(mini(5, fast_bigrams.size())):
			var bg = fast_bigrams[i]
			draw_string(font, Vector2(MARGIN + 12, row_y + 5), "#%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_MUTED)
			draw_rect(Rect2(MARGIN + 35, row_y - 6, 40, 24), ACCENT_SUCCESS.darkened(0.7))
			draw_string(font, Vector2(MARGIN + 43, row_y + 8), bg["bigram"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ACCENT_SUCCESS)
			draw_string(font, Vector2(MARGIN + 90, row_y + 5), "%.0fms" % bg["avg_time"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_PRIMARY)
			draw_string(font, Vector2(MARGIN + 150, row_y + 5), "(%d)" % bg["count"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_MUTED)
			row_y += 32
	else:
		draw_string(font, Vector2(MARGIN + 15, adjusted_y + 85), "Not enough data", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_MUTED)

	draw_card(Rect2(MARGIN + half_width + 20, adjusted_y, half_width, 185))
	draw_string(font, Vector2(MARGIN + half_width + 35, adjusted_y - 25), "SLOWEST BIGRAMS", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, TEXT_PRIMARY)
	var slow_bigrams = StatisticsManager.get_slow_bigrams(5) if StatisticsManager else []

	if slow_bigrams.size() > 0:
		var row_y = adjusted_y + 20
		for i in range(mini(5, slow_bigrams.size())):
			var bg = slow_bigrams[i]
			draw_string(font, Vector2(MARGIN + half_width + 32, row_y + 5), "#%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_MUTED)
			draw_rect(Rect2(MARGIN + half_width + 55, row_y - 6, 40, 24), ACCENT_DANGER.darkened(0.7))
			draw_string(font, Vector2(MARGIN + half_width + 63, row_y + 8), bg["bigram"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ACCENT_DANGER)
			draw_string(font, Vector2(MARGIN + half_width + 110, row_y + 5), "%.0fms" % bg["avg_time"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_PRIMARY)
			draw_string(font, Vector2(MARGIN + half_width + 170, row_y + 5), "(%d)" % bg["count"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_MUTED)
			row_y += 32
	else:
		draw_string(font, Vector2(MARGIN + half_width + 35, adjusted_y + 85), "Not enough data", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_MUTED)

	y += 210
	y = draw_section_title("WORD LENGTH PERFORMANCE", y)
	adjusted_y = y - scroll_offset
	var word_stats = StatisticsManager.get_word_length_stats() if StatisticsManager else {}

	if word_stats.size() > 0:
		draw_card(Rect2(MARGIN, adjusted_y, width - MARGIN * 2, 180))
		var bar_x = MARGIN + 25
		var bar_width = (width - MARGIN * 2 - 70) / 10
		var bar_max_height = 120.0
		for length in range(3, 13):
			if word_stats.has(length):
				var ws = word_stats[length]
				var total = ws["completed"] + ws["failed"]
				if total > 0:
					var success_rate = float(ws["completed"]) / float(total)
					var bar_height = bar_max_height * success_rate
					var bar_color = ACCENT_SUCCESS if success_rate >= 0.8 else (ACCENT_SECONDARY if success_rate >= 0.5 else ACCENT_DANGER)
					draw_rect(Rect2(bar_x, adjusted_y + 25 + (bar_max_height - bar_height), bar_width - 8, bar_height), bar_color)
					draw_string(font, Vector2(bar_x + 5, adjusted_y + 160), str(length), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_SECONDARY)
			bar_x += bar_width
		y += 200
	else:
		draw_card(Rect2(MARGIN, adjusted_y, width - MARGIN * 2, 55))
		draw_string(font, Vector2(MARGIN + 25, adjusted_y + 32), "Complete more words for analysis", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_MUTED)
		y += 70
	max_scroll = maxf(0, y - GameConfig.SCREEN_HEIGHT + 80)

# TAB 5: GAME
func draw_game_tab() -> void:
	var font = ThemeDB.fallback_font
	var lifetime = StatisticsManager.get_lifetime_stats() if StatisticsManager else {}
	var width = GameConfig.SCREEN_WIDTH
	var y = CONTENT_START_Y + 10

	var total_games = lifetime.get("total_games", 0)
	var total_wins = lifetime.get("total_wins", 0)
	var win_rate = (float(total_wins) / float(total_games) * 100) if total_games > 0 else 0

	var card_width = (width - MARGIN * 2 - 30) / 3
	var card_height = 95.0

	draw_kpi_card(MARGIN, y, card_width, card_height, "TOTAL GAMES", str(total_games), "Sessions played", ACCENT_PRIMARY)
	draw_kpi_card(MARGIN + card_width + 15, y, card_width, card_height, "VICTORIES", str(total_wins), "Games won", ACCENT_SUCCESS)
	var wr_sub = "Above average" if win_rate >= 50 else "Keep practicing!"
	draw_kpi_card(MARGIN + (card_width + 15) * 2, y, card_width, card_height, "WIN RATE", "%.0f%%" % win_rate, wr_sub, ACCENT_SECONDARY if win_rate >= 50 else ACCENT_DANGER)

	y += card_height + 25
	y = draw_section_title("PERSONAL BESTS", y)
	var third_width = (width - MARGIN * 2 - 30) / 3

	draw_kpi_card(MARGIN, y, third_width, 85, "BEST WAVE", str(lifetime.get("best_wave", 0)), "Highest wave", ACCENT_SECONDARY)
	draw_kpi_card(MARGIN + third_width + 15, y, third_width, 85, "BEST SCORE", format_number(lifetime.get("best_score", 0)), "High score", ACCENT_PRIMARY)
	draw_kpi_card(MARGIN + (third_width + 15) * 2, y, third_width, 85, "BEST COMBO", str(lifetime.get("best_combo", 0)) + "x", "Longest streak", ACCENT_PURPLE)

	y += 105
	y = draw_section_title("LIFETIME TOTALS", y)
	var adjusted_y = y - scroll_offset
	draw_card(Rect2(MARGIN, adjusted_y, width - MARGIN * 2, 165))

	var stats_data = [
		["Enemies Destroyed", format_number(lifetime.get("total_enemies_killed", 0)), ACCENT_DANGER],
		["Words Completed", format_number(lifetime.get("total_words_completed", 0)), ACCENT_SUCCESS],
		["PowerUps Collected", str(lifetime.get("total_powerups_collected", 0)), ACCENT_PURPLE],
		["Towers Built", str(lifetime.get("total_towers_built", 0)), ACCENT_PRIMARY],
		["Total Play Time", format_play_time(lifetime.get("total_play_time_seconds", 0)), ACCENT_SECONDARY]
	]

	var row_y = adjusted_y + 20
	for stat in stats_data:
		draw_circle(Vector2(MARGIN + 20, row_y + 3), 4, stat[2])
		draw_string(font, Vector2(MARGIN + 35, row_y + 8), stat[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_SECONDARY)
		draw_string(font, Vector2(width - MARGIN - 130, row_y + 8), str(stat[1]), HORIZONTAL_ALIGNMENT_RIGHT, 110, 13, TEXT_PRIMARY)
		row_y += 28

	y += 185
	y = draw_section_title("STREAKS", y)
	adjusted_y = y - scroll_offset
	var half_width = (width - MARGIN * 2 - 20) / 2

	draw_kpi_card(MARGIN, y, half_width, 85, "CURRENT STREAK", str(lifetime.get("current_daily_streak", 0)) + " days", "Keep it going!", ACCENT_SUCCESS if lifetime.get("current_daily_streak", 0) > 0 else TEXT_MUTED)
	draw_kpi_card(MARGIN + half_width + 20, y, half_width, 85, "BEST STREAK", str(lifetime.get("best_daily_streak", 0)) + " days", "Personal record", ACCENT_SECONDARY)
	max_scroll = maxf(0, y + 120 - GameConfig.SCREEN_HEIGHT + 80)

# TAB 6: ACHIEVEMENTS
func draw_achievements_tab() -> void:
	var font = ThemeDB.fallback_font
	var width = GameConfig.SCREEN_WIDTH
	var y = CONTENT_START_Y + 10

	var unlocked = AchievementManager.get_unlocked_count() if AchievementManager else 0
	var total = AchievementManager.get_total_count() if AchievementManager else 0
	var completion = AchievementManager.get_completion_percentage() if AchievementManager else 0

	var adjusted_y = y - scroll_offset
	draw_card(Rect2(MARGIN, adjusted_y, width - MARGIN * 2, 90))
	draw_string(font, Vector2(MARGIN + 25, adjusted_y + 32), "COMPLETION", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_SECONDARY)
	draw_string(font, Vector2(MARGIN + 25, adjusted_y + 62), "%d / %d" % [unlocked, total], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, TEXT_PRIMARY)
	draw_progress_bar(MARGIN + 180, adjusted_y + 42, width - MARGIN * 2 - 320, completion / 100.0, ACCENT_SECONDARY)
	draw_string(font, Vector2(width - MARGIN - 100, adjusted_y + 52), "%.0f%%" % completion, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ACCENT_SECONDARY)

	y += 110

	var categories = [
		AchievementManager.Category.SPEED,
		AchievementManager.Category.ACCURACY,
		AchievementManager.Category.COMBO,
		AchievementManager.Category.SURVIVAL,
		AchievementManager.Category.SCORE,
		AchievementManager.Category.GRIND,
		AchievementManager.Category.SPECIAL
	] if AchievementManager else []

	for category in categories:
		if not AchievementManager:
			break
		var cat_name = AchievementManager.get_category_name(category)
		var achievements = AchievementManager.get_achievements_by_category(category)
		if achievements.is_empty():
			continue

		y = draw_section_title(cat_name.to_upper(), y)
		adjusted_y = y - scroll_offset
		if adjusted_y > GameConfig.SCREEN_HEIGHT:
			continue

		var card_h = achievements.size() * 50 + 15
		if adjusted_y + card_h > CONTENT_START_Y:
			draw_card(Rect2(MARGIN, adjusted_y, width - MARGIN * 2, card_h))
			var row_y = adjusted_y + 18
			for ach in achievements:
				if row_y > GameConfig.SCREEN_HEIGHT - 70:
					break
				var ach_name = ach.get("name", "Unknown")
				var desc = ach.get("description", "")
				var is_unlocked = ach.get("unlocked", false)
				var progress = ach.get("progress", 0)
				var target = ach.get("target", 1)
				var tier = ach.get("tier", 0)
				var tier_color = AchievementManager.get_tier_color(tier) if AchievementManager else Color.WHITE
				var icon_color = tier_color if is_unlocked else TEXT_MUTED
				draw_rect(Rect2(MARGIN + 15, row_y - 4, 26, 26), icon_color.darkened(0.6) if is_unlocked else BG_CARD_HOVER)
				var icon = "*" if is_unlocked else "-"
				draw_string(font, Vector2(MARGIN + 22, row_y + 13), icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, icon_color)
				draw_string(font, Vector2(MARGIN + 55, row_y + 12), ach_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tier_color if is_unlocked else TEXT_SECONDARY)
				draw_string(font, Vector2(MARGIN + 250, row_y + 12), desc, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_MUTED)
				if not is_unlocked and target > 1:
					draw_progress_bar(width - MARGIN - 165, row_y + 5, 90, float(progress) / float(target), TEXT_MUTED)
					draw_string(font, Vector2(width - MARGIN - 60, row_y + 12), "%d/%d" % [progress, target], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_MUTED)
				elif is_unlocked:
					draw_string(font, Vector2(width - MARGIN - 75, row_y + 12), "DONE", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, tier_color)
				row_y += 50
		y += card_h + 12
	max_scroll = maxf(0, y - GameConfig.SCREEN_HEIGHT + 80)

# MODERN GRAPH
func draw_modern_graph(data: Array, key: String, x: float, y: float, width: float, height: float) -> void:
	if data.is_empty():
		return
	var font = ThemeDB.fallback_font
	var min_val = INF
	var max_val = -INF
	for d in data:
		var v = d.get(key, 0)
		min_val = minf(min_val, v)
		max_val = maxf(max_val, v)
	var range_pad = (max_val - min_val) * 0.1
	min_val = maxf(0, min_val - range_pad)
	max_val = max_val + range_pad
	if max_val == min_val:
		max_val = min_val + 10

	var grid_lines = 4
	for i in range(grid_lines + 1):
		var gy = y + height - (float(i) / float(grid_lines)) * height
		draw_line(Vector2(x, gy), Vector2(x + width, gy), BORDER_COLOR, 1)
		var val = min_val + (float(i) / float(grid_lines)) * (max_val - min_val)
		draw_string(font, Vector2(x - 40, gy + 4), "%.0f" % val, HORIZONTAL_ALIGNMENT_RIGHT, 35, 10, TEXT_MUTED)

	var points: PackedVector2Array = []
	for i in range(data.size()):
		var v = data[i].get(key, 0)
		var px = x + (float(i) / float(data.size() - 1)) * width if data.size() > 1 else x + width / 2
		var py = y + height - ((v - min_val) / (max_val - min_val)) * height
		points.append(Vector2(px, py))

	if points.size() >= 2:
		for i in range(points.size() - 1):
			var p1 = points[i]
			var p2 = points[i + 1]
			var fill_color = Color(ACCENT_PRIMARY.r, ACCENT_PRIMARY.g, ACCENT_PRIMARY.b, 0.12)
			draw_polygon([p1, p2, Vector2(p2.x, y + height), Vector2(p1.x, y + height)], [fill_color, fill_color, fill_color, fill_color])
		for i in range(points.size() - 1):
			draw_line(points[i], points[i + 1], ACCENT_PRIMARY, 2)

	for i in range(points.size()):
		draw_circle(points[i], 5, BG_CARD)
		draw_circle(points[i], 3, ACCENT_PRIMARY)

	draw_string(font, Vector2(x, y + height + 12), "1", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_MUTED)
	draw_string(font, Vector2(x + width - 15, y + height + 12), str(data.size()), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_MUTED)

# UTILITIES
func format_number(num: int) -> String:
	if num >= 1000000:
		return "%.1fM" % (num / 1000000.0)
	elif num >= 1000:
		return "%.1fK" % (num / 1000.0)
	return str(num)

func format_play_time(seconds: float) -> String:
	var hours = int(seconds / 3600)
	var minutes = int(fmod(seconds, 3600) / 60)
	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	elif minutes > 0:
		return "%d min" % minutes
	else:
		return "< 1 min"
