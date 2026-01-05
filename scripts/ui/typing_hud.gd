## typing_hud.gd
## Displays game stats: score, combo, wave, accuracy, active word
extends Control

@onready var score_label: Label = $TopBar/ScoreLabel
@onready var wave_label: Label = $TopBar/WaveLabel
@onready var combo_label: Label = $TopBar/ComboLabel
@onready var accuracy_label: Label = $TopBar/AccuracyLabel
@onready var active_word_label: Label = $BottomBar/ActiveWordLabel
@onready var enemies_label: Label = $BottomBar/EnemiesLabel
@onready var errors_label: Label = $BottomBar/ErrorsLabel

var combo_pulse_tween: Tween = null

func _ready() -> void:
	# Connect to signals for real-time updates
	SignalBus.combo_updated.connect(_on_combo_updated)
	SignalBus.combo_reset.connect(_on_combo_reset)
	SignalBus.char_typed.connect(_on_char_typed)

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
		# Color based on accuracy
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

	# Active word display
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

func _on_combo_updated(combo: int) -> void:
	update_combo(combo)

	# Pulse effect for high combos
	if combo > 0 and combo % 10 == 0:
		pulse_combo_label()

func _on_combo_reset() -> void:
	if combo_label:
		combo_label.text = "COMBO: 0"
		# Flash red on reset
		combo_label.add_theme_color_override("font_color", GameConfig.COLORS.magenta)
		var tween = create_tween()
		tween.tween_property(combo_label, "theme_override_colors/font_color", GameConfig.COLORS.acid_green, 0.3)

func _on_char_typed(char: String, correct: bool) -> void:
	if correct:
		# Brief flash on correct type
		pass
	else:
		# Flash active word red on error
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
