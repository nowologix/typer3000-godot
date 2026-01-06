## vs_battle_state.gd
## VS Mode - Both players play the same game solo, scores compared
## First to die loses, or highest score at timeout wins
extends Node2D

@onready var enemy_container: Node2D = $GameLayer/EnemyContainer
@onready var portal: Node2D = $GameLayer/Portal
@onready var player: CharacterBody2D = $GameLayer/Player
@onready var wave_manager: Node = $WaveManager
@onready var typing_hud = $UILayer/TypingHUD
@onready var vs_your_score: Label = $UILayer/VSOverlay/VSPanel/VBox/ScoreRow/YourScore
@onready var vs_opponent_score: Label = $UILayer/VSOverlay/VSPanel/VBox/ScoreRow/OpponentScore

var score: int = 0
var opponent_score: int = 0
var enemies_killed: int = 0
var game_active: bool = false
var game_seed: int = 0
var is_multiplayer: bool = false

var enemy_scene: PackedScene

func _ready() -> void:
	DebugHelper.log_info("VSBattleState ready")
	enemy_scene = load("res://scenes/entities/enemy_word.tscn")

	SignalBus.enemy_killed.connect(_on_enemy_killed)
	SignalBus.portal_destroyed.connect(_on_portal_destroyed)
	SignalBus.player_died.connect(_on_player_died)
	SignalBus.wave_completed.connect(_on_wave_completed)

func on_enter(params: Dictionary) -> void:
	DebugHelper.log_info("VSBattleState entered")

	game_seed = params.get("seed", randi())
	is_multiplayer = params.get("multiplayer", false)
	seed(game_seed)

	score = 0
	opponent_score = 0
	enemies_killed = 0
	game_active = true

	TypingManager.set_enemy_container(enemy_container)
	TypingManager.reset_stats()
	TypingManager.enable_typing()

	var language = SaveManager.get_setting("language", "EN")
	WordSetLoader.set_language_string(language)
	WordSetLoader.reset_used_words()

	if wave_manager:
		wave_manager.setup(enemy_container, portal)
		wave_manager.start_waves()

	PowerUpManager.set_spawn_container(enemy_container)
	PowerUpManager.set_portal_reference(portal)
	PowerUpManager.reset()

	if portal and portal.has_method("reset"):
		portal.reset()
	if player and player.has_method("reset"):
		player.reset()

	update_hud()
	SoundManager.play_game_music()
	SignalBus.game_started.emit()

	# Connect to opponent score updates
	if is_multiplayer:
		SignalBus.opponent_score_update.connect(_on_opponent_score_update)

func on_exit() -> void:
	DebugHelper.log_info("VSBattleState exiting")
	game_active = false
	TypingManager.disable_typing()

	if SignalBus.enemy_killed.is_connected(_on_enemy_killed):
		SignalBus.enemy_killed.disconnect(_on_enemy_killed)
	if SignalBus.portal_destroyed.is_connected(_on_portal_destroyed):
		SignalBus.portal_destroyed.disconnect(_on_portal_destroyed)
	if SignalBus.player_died.is_connected(_on_player_died):
		SignalBus.player_died.disconnect(_on_player_died)
	if SignalBus.wave_completed.is_connected(_on_wave_completed):
		SignalBus.wave_completed.disconnect(_on_wave_completed)
	if is_multiplayer and SignalBus.opponent_score_update.is_connected(_on_opponent_score_update):
		SignalBus.opponent_score_update.disconnect(_on_opponent_score_update)

func _process(_delta: float) -> void:
	if not game_active:
		return
	update_hud()

	# Send score updates in multiplayer
	if is_multiplayer and Engine.get_frames_drawn() % 30 == 0:
		NetworkManager.send_score_update(score)

func _on_enemy_killed(enemy: Node, typed: bool) -> void:
	if typed:
		enemies_killed += 1
		var word_score = enemy.word.length() * 10
		var combo_bonus = TypingManager.combo * 5
		score += word_score + combo_bonus
		SoundManager.play_enemy_kill()

func _on_portal_destroyed() -> void:
	_trigger_game_over(false, "Portal destroyed")

func _on_player_died() -> void:
	_trigger_game_over(false, "Player died")

func _on_wave_completed(wave_number: int) -> void:
	DebugHelper.log_info("VS Wave %d completed!" % wave_number)

func _on_opponent_score_update(new_score: int) -> void:
	opponent_score = new_score
	update_hud()

func _trigger_game_over(won: bool, reason: String) -> void:
	game_active = false
	TypingManager.disable_typing()

	# In VS mode, dying = losing
	if is_multiplayer:
		NetworkManager.send_game_over(false, score)

	var stats = TypingManager.get_stats()
	stats["score"] = score
	stats["opponent_score"] = opponent_score
	stats["enemies_destroyed"] = enemies_killed
	stats["wave"] = wave_manager.current_wave if wave_manager else 0
	stats["death_reason"] = reason
	stats["mode"] = "VS"

	SignalBus.game_over.emit(won, stats)
	StateManager.change_state("game_over", {"won": won, "stats": stats, "mode": "VS"})

func update_hud() -> void:
	if typing_hud and typing_hud.has_method("update_stats"):
		var stats = TypingManager.get_stats()
		typing_hud.update_stats({
			"score": score,
			"combo": stats.combo,
			"accuracy": stats.accuracy,
			"enemies_remaining": enemy_container.get_child_count() if enemy_container else 0,
			"wave": wave_manager.current_wave if wave_manager else 0,
			"portal_hp": portal.current_hp if portal else 0,
			"portal_max_hp": portal.max_hp if portal else 0,
			"active_word": TypingManager.active_enemy.word if TypingManager.active_enemy else "",
			"typed_index": TypingManager.typed_index
		})

	# Update VS overlay with opponent score
	if vs_your_score:
		vs_your_score.text = "YOU: %d" % score
	if vs_opponent_score:
		vs_opponent_score.text = "OPP: %d" % opponent_score

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_ESCAPE:
			_trigger_game_over(false, "Quit")
