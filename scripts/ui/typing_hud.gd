## typing_hud.gd
## Displays game stats: score, combo, wave, accuracy, active word
## Also displays multiplier and word rush bar
extends Control

@onready var score_label: Label = $TopBar/ScoreLabel
@onready var wave_label: Label = $TopBar/WaveLabel
@onready var combo_label: Label = $TopBar/ComboLabel
@onready var accuracy_label: Label = $TopBar/AccuracyLabel
@onready var active_word_label: Label = $ActiveWordContainer/ActiveWordLabel
@onready var enemies_label: Label = $BottomBar/EnemiesLabel
@onready var errors_label: Label = $BottomBar/ErrorsLabel
@onready var powerup_container: VBoxContainer = $PowerUpContainer

var combo_pulse_tween: Tween = null
var powerup_labels: Dictionary = {}

# Multiplier display
var multiplier_label: Label = null

# Word Rush UI
var rush_container: Control = null
var rush_bar: ColorRect = null
var rush_bar_fill: ColorRect = null
var rush_label: Label = null
var rush_active_label: Label = null

func _ready() -> void:
	SignalBus.combo_updated.connect(_on_combo_updated)
	SignalBus.combo_reset.connect(_on_combo_reset)
	SignalBus.char_typed.connect(_on_char_typed)

	# Connect to CombatSystem
	CombatSystem.multiplier_changed.connect(_on_multiplier_changed)
	CombatSystem.rush_value_changed.connect(_on_rush_value_changed)
	CombatSystem.rush_activated.connect(_on_rush_activated)
	CombatSystem.rush_deactivated.connect(_on_rush_deactivated)
	CombatSystem.rush_kill_used.connect(_on_rush_kill_used)

	# Create multiplier and rush UI
	_create_multiplier_display()
	_create_rush_bar()

var _was_in_magnet_mode: bool = false

func _process(_delta: float) -> void:
	update_powerup_display()
	# Redraw during magnet placement for crosshair
	var in_magnet_mode = PowerUpManager.is_magnet_placement_mode()
	if in_magnet_mode or _was_in_magnet_mode:
		queue_redraw()
	_was_in_magnet_mode = in_magnet_mode

func update_stats(stats: Dictionary) -> void:
	if score_label:
		score_label.text = "SCORE: %d" % stats.get("score", 0)

	if wave_label:
		wave_label.text = "WAVE: %d" % stats.get("wave", 1)

	if combo_label:
		combo_label.text = "COMBO: %d" % stats.get("combo", 0)

	if accuracy_label:
		var acc = stats.get("accuracy", 100.0)
		accuracy_label.text = "ACC: %.1f%%" % acc
		if acc >= 95:
			accuracy_label.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
		elif acc >= 80:
			accuracy_label.add_theme_color_override("font_color", GameConfig.COLORS.amber)
		else:
			accuracy_label.add_theme_color_override("font_color", GameConfig.COLORS.magenta)

	if enemies_label:
		enemies_label.text = "ENEMIES: %d" % stats.get("enemies_remaining", 0)

	if errors_label:
		errors_label.text = "ERRORS: %d" % stats.get("errors", 0)

	if active_word_label:
		var active_word = stats.get("active_word", "")
		var typed_index = stats.get("typed_index", 0)

		if active_word.length() > 0:
			if typed_index > 0 and typed_index < active_word.length():
				var typed_part = active_word.substr(0, typed_index)
				var remaining = active_word.substr(typed_index)
				active_word_label.text = "%s|%s" % [typed_part, remaining]
				active_word_label.add_theme_color_override("font_color", GameConfig.COLORS.cyan)
			else:
				active_word_label.text = active_word
				active_word_label.add_theme_color_override("font_color", GameConfig.COLORS.cyan)
		else:
			active_word_label.text = "Type to attack!"
			active_word_label.add_theme_color_override("font_color", GameConfig.COLORS.text_dim)

func update_combo(combo: int) -> void:
	if combo_label:
		combo_label.text = "COMBO: %d" % combo

func update_powerup_display() -> void:
	if powerup_container == null:
		return

	var active = PowerUpManager.get_active_powerups()

	for type in powerup_labels.keys():
		if not active.has(type):
			powerup_labels[type].queue_free()
			powerup_labels.erase(type)

	for type in active:
		var remaining = active[type]
		var data = PowerUpManager.POWERUPS.get(type, {})
		var pname = data.get("name", "UNKNOWN")
		var color = data.get("color", Color.WHITE)

		if powerup_labels.has(type):
			powerup_labels[type].text = "%s: %.1fs" % [pname, remaining]
		else:
			var label = Label.new()
			label.text = "%s: %.1fs" % [pname, remaining]
			label.add_theme_font_size_override("font_size", 18)
			label.add_theme_color_override("font_color", color)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			powerup_container.add_child(label)
			powerup_labels[type] = label

func _on_combo_updated(combo: int) -> void:
	update_combo(combo)
	if combo > 0 and combo % 10 == 0:
		pulse_combo_label()

func _on_combo_reset() -> void:
	if combo_label:
		combo_label.text = "COMBO: 0"
		combo_label.add_theme_color_override("font_color", GameConfig.COLORS.magenta)
		var tween = create_tween()
		tween.tween_property(combo_label, "theme_override_colors/font_color", GameConfig.COLORS.acid_green, 0.3)

func _on_char_typed(c: String, correct: bool) -> void:
	if correct:
		pass
	else:
		if active_word_label:
			active_word_label.add_theme_color_override("font_color", GameConfig.COLORS.magenta)
			var tween = create_tween()
			tween.tween_property(active_word_label, "theme_override_colors/font_color", GameConfig.COLORS.cyan, 0.2)

func pulse_combo_label() -> void:
	if combo_label == null:
		return

	if combo_pulse_tween and combo_pulse_tween.is_running():
		combo_pulse_tween.kill()

	var original_scale = combo_label.scale
	combo_pulse_tween = create_tween()
	combo_pulse_tween.tween_property(combo_label, "scale", original_scale * 1.3, 0.1)
	combo_pulse_tween.tween_property(combo_label, "scale", original_scale, 0.1)

# ============================================
# MULTIPLIER DISPLAY
# ============================================
func _create_multiplier_display() -> void:
	multiplier_label = Label.new()
	multiplier_label.name = "MultiplierLabel"
	multiplier_label.text = ""
	multiplier_label.add_theme_font_size_override("font_size", 64)
	multiplier_label.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
	multiplier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	multiplier_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Position in top-center
	multiplier_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	multiplier_label.position = Vector2(-50, 60)
	multiplier_label.custom_minimum_size = Vector2(100, 80)
	multiplier_label.visible = false

	add_child(multiplier_label)

func _on_multiplier_changed(multiplier: int) -> void:
	if multiplier_label == null:
		return

	if multiplier > 1:
		multiplier_label.text = "x%d" % multiplier
		multiplier_label.visible = true

		# Color based on multiplier level
		match multiplier:
			2: multiplier_label.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
			3: multiplier_label.add_theme_color_override("font_color", GameConfig.COLORS.amber)
			4: multiplier_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.0))  # Orange
			_: multiplier_label.add_theme_color_override("font_color", GameConfig.COLORS.magenta)

		# Pulse animation
		var tween = create_tween()
		multiplier_label.scale = Vector2(1.5, 1.5)
		tween.tween_property(multiplier_label, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_OUT)
	else:
		multiplier_label.visible = false

# ============================================
# WORD RUSH BAR
# ============================================
func _create_rush_bar() -> void:
	rush_container = Control.new()
	rush_container.name = "RushContainer"
	# Position at bottom, below "Type to attack" label
	rush_container.anchor_top = 1.0
	rush_container.anchor_bottom = 1.0
	rush_container.anchor_left = 0.0
	rush_container.anchor_right = 1.0
	rush_container.offset_top = -26
	rush_container.offset_bottom = -19
	add_child(rush_container)

	# Bar background - 33% width, horizontally centered
	rush_bar = ColorRect.new()
	rush_bar.name = "RushBarBG"
	rush_bar.color = Color(0.1, 0.1, 0.15, 0.35)
	rush_bar.anchor_left = 0.335
	rush_bar.anchor_right = 0.665
	rush_bar.anchor_top = 0.0
	rush_bar.anchor_bottom = 1.0
	rush_bar.offset_left = 0
	rush_bar.offset_right = 0
	rush_bar.offset_top = 0
	rush_bar.offset_bottom = 0
	rush_container.add_child(rush_bar)

	# Bar fill
	rush_bar_fill = ColorRect.new()
	rush_bar_fill.name = "RushBarFill"
	rush_bar_fill.color = Color(1.0, 0.4, 0.1, 0.6)  # Orange/fire color, more transparent
	rush_bar_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	rush_bar_fill.anchor_right = 0.0  # Start empty
	rush_bar_fill.offset_left = 1
	rush_bar_fill.offset_right = -1
	rush_bar_fill.offset_top = 1
	rush_bar_fill.offset_bottom = -1
	rush_bar.add_child(rush_bar_fill)

	# Rush label - hidden for slim bar design
	rush_label = Label.new()
	rush_label.name = "RushLabel"
	rush_label.visible = false
	rush_container.add_child(rush_label)

	# Rush active label (shown when rush is active)
	rush_active_label = Label.new()
	rush_active_label.name = "RushActiveLabel"
	rush_active_label.text = "WORD RUSH!"
	rush_active_label.add_theme_font_size_override("font_size", 48)
	rush_active_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1))
	rush_active_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rush_active_label.set_anchors_preset(Control.PRESET_CENTER)
	rush_active_label.position = Vector2(-150, -100)
	rush_active_label.custom_minimum_size = Vector2(300, 60)
	rush_active_label.visible = false
	add_child(rush_active_label)

func _on_rush_value_changed(value: float, max_value: float) -> void:
	if rush_bar_fill == null:
		return

	var fill_ratio = value / max_value
	rush_bar_fill.anchor_right = fill_ratio

	# Change color based on fill level
	if fill_ratio > 0.8:
		rush_bar_fill.color = Color(1.0, 0.2, 0.0, 0.7)  # Red-orange when almost full
	elif fill_ratio > 0.5:
		rush_bar_fill.color = Color(1.0, 0.5, 0.1, 0.6)  # Orange
	else:
		rush_bar_fill.color = Color(1.0, 0.7, 0.2, 0.5)  # Yellow-orange

func _on_rush_activated(duration: float, instant_kills: int) -> void:
	if rush_active_label:
		rush_active_label.text = "WORD RUSH!\n%d INSTANT KILLS" % instant_kills
		rush_active_label.visible = true

		# Epic entrance animation
		rush_active_label.modulate.a = 0
		rush_active_label.scale = Vector2(2, 2)
		var tween = create_tween()
		tween.tween_property(rush_active_label, "modulate:a", 1.0, 0.2)
		tween.parallel().tween_property(rush_active_label, "scale", Vector2.ONE, 0.3).set_ease(Tween.EASE_OUT)

	# Make bar glow
	if rush_bar_fill:
		rush_bar_fill.color = Color(1.0, 0.8, 0.3, 0.8)

func _on_rush_deactivated() -> void:
	if rush_active_label:
		var tween = create_tween()
		tween.tween_property(rush_active_label, "modulate:a", 0.0, 0.3)
		tween.tween_callback(func(): rush_active_label.visible = false)

func _on_rush_kill_used(remaining: int) -> void:
	if rush_active_label:
		rush_active_label.text = "WORD RUSH!\n%d INSTANT KILLS" % remaining

		# Flash effect
		var tween = create_tween()
		rush_active_label.modulate = Color(1.5, 1.5, 1.5)
		tween.tween_property(rush_active_label, "modulate", Color.WHITE, 0.1)


# ============================================
# MAGNET PLACEMENT UI
# ============================================

func _draw() -> void:
	if PowerUpManager.is_magnet_placement_mode():
		draw_magnet_placement_overlay()

func draw_magnet_placement_overlay() -> void:
	var cursor_pos = PowerUpManager.get_magnet_cursor_position()
	var magnet_radius = 180.0  # Matches MAGNET_RADIUS in magnet.gd
	var font = ThemeDB.fallback_font
	
	# Semi-transparent overlay
	draw_rect(Rect2(0, 0, GameConfig.SCREEN_WIDTH, GameConfig.SCREEN_HEIGHT), Color(0, 0, 0, 0.3))
	
	# Draw range indicator circle
	for i in range(64):
		var angle = float(i) / 64 * TAU
		var next_angle = float(i + 1) / 64 * TAU
		var p1 = cursor_pos + Vector2(cos(angle), sin(angle)) * magnet_radius
		var p2 = cursor_pos + Vector2(cos(next_angle), sin(next_angle)) * magnet_radius
		draw_line(p1, p2, Color(0.9, 0.2, 0.6, 0.4), 2)
	
	# Crosshair
	var cross_size = 25.0
	var cross_color = Color(0.9, 0.3, 0.7, 1.0)
	draw_line(Vector2(cursor_pos.x - cross_size, cursor_pos.y), Vector2(cursor_pos.x + cross_size, cursor_pos.y), cross_color, 3)
	draw_line(Vector2(cursor_pos.x, cursor_pos.y - cross_size), Vector2(cursor_pos.x, cursor_pos.y + cross_size), cross_color, 3)
	
	# Inner crosshair
	var inner_color = Color(1.0, 0.4, 0.8, 0.7)
	draw_line(Vector2(cursor_pos.x - cross_size * 0.5, cursor_pos.y), Vector2(cursor_pos.x + cross_size * 0.5, cursor_pos.y), inner_color, 1)
	draw_line(Vector2(cursor_pos.x, cursor_pos.y - cross_size * 0.5), Vector2(cursor_pos.x, cursor_pos.y + cross_size * 0.5), inner_color, 1)
	
	# Center dot
	draw_circle(cursor_pos, 5, Color(0.9, 0.2, 0.6, 0.8))
	draw_circle(cursor_pos, 3, Color(1.0, 0.5, 0.8, 1.0))
	
	# Instructions
	var center_x = GameConfig.SCREEN_WIDTH / 2
	draw_string(font, Vector2(center_x - 150, 80), "PLACE MAGNET", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(0.9, 0.2, 0.6))
	draw_string(font, Vector2(center_x - 220, 120), "Move with Arrow keys | ENTER to place | ESC to cancel", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.8, 0.85))
	
	# Active magnets count
	var magnet_count = PowerUpManager.get_magnet_count()
	if magnet_count > 0:
		draw_string(font, Vector2(center_x - 80, 150), "Active magnets: %d" % magnet_count, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.7, 0.75))
