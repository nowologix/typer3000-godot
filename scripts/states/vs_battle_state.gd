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

# VS mode game over tracking
var local_died: bool = false
var opponent_died: bool = false
var local_final_score: int = 0
var opponent_final_score: int = 0
var waiting_for_opponent: bool = false
var opponent_stats: Dictionary = {}

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
	MenuBackground.hide_background()

	game_seed = params.get("seed", randi())
	is_multiplayer = params.get("multiplayer", false)
	seed(game_seed)

	score = 0
	opponent_score = 0
	enemies_killed = 0
	game_active = true
	local_died = false
	opponent_died = false
	local_final_score = 0
	opponent_final_score = 0
	waiting_for_opponent = false
	opponent_stats = {}

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

	# Connect to opponent updates in multiplayer
	if is_multiplayer:
		if not SignalBus.opponent_score_update.is_connected(_on_opponent_score_update):
			SignalBus.opponent_score_update.connect(_on_opponent_score_update)
		if not SignalBus.vs_opponent_game_over.is_connected(_on_opponent_game_over):
			SignalBus.vs_opponent_game_over.connect(_on_opponent_game_over)
		if not SignalBus.network_disconnected.is_connected(_on_network_disconnected):
			SignalBus.network_disconnected.connect(_on_network_disconnected)

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
	if is_multiplayer:
		if SignalBus.opponent_score_update.is_connected(_on_opponent_score_update):
			SignalBus.opponent_score_update.disconnect(_on_opponent_score_update)
		if SignalBus.vs_opponent_game_over.is_connected(_on_opponent_game_over):
			SignalBus.vs_opponent_game_over.disconnect(_on_opponent_game_over)
		if SignalBus.network_disconnected.is_connected(_on_network_disconnected):
			SignalBus.network_disconnected.disconnect(_on_network_disconnected)

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

func _on_opponent_game_over(data: Dictionary) -> void:
	# Opponent died
	opponent_died = true
	opponent_final_score = int(data.get("score", opponent_score))
	opponent_stats = data.get("stats", {})
	DebugHelper.log_info("VS: Opponent died with score %d" % opponent_final_score)

	if local_died:
		# Both players have died, go to final game over
		_show_final_results()
	else:
		# I'm still alive, I win!
		_trigger_game_over(true, "Opponent died first")

func _on_network_disconnected(reason: String) -> void:
	if not game_active:
		return

	DebugHelper.log_warning("VS: Network disconnected - %s" % reason)
	game_active = false
	TypingManager.disable_typing()

	# Go to game over with disconnect flag (no RETRY available)
	var stats = TypingManager.get_stats()
	stats["score"] = score
	stats["enemies_destroyed"] = enemies_killed
	stats["wave"] = wave_manager.current_wave if wave_manager else 0
	stats["death_reason"] = "Opponent disconnected"
	stats["mode"] = "VS"
	stats["disconnected"] = true

	SignalBus.game_over.emit(false, stats)
	StateManager.change_state("game_over", {"won": false, "stats": stats, "mode": "VS", "disconnected": true})

func _trigger_game_over(won: bool, reason: String) -> void:
	game_active = false
	TypingManager.disable_typing()
	local_died = true
	local_final_score = score

	# Collect full stats
	var my_stats = TypingManager.get_stats()
	my_stats["score"] = score
	my_stats["enemies_destroyed"] = enemies_killed
	my_stats["wave"] = wave_manager.current_wave if wave_manager else 0

	# In VS mode, send our game over with full stats to opponent
	if is_multiplayer:
		NetworkManager.send_game_over(false, score, my_stats)

		# If opponent hasn't died yet, wait for them
		if not opponent_died:
			waiting_for_opponent = true
			DebugHelper.log_info("VS: Waiting for opponent...")
			update_hud()
			return

	# Both are done (or solo), show results
	_show_final_results()

func _show_final_results() -> void:
	waiting_for_opponent = false

	# Determine winner
	var won = local_final_score > opponent_final_score
	if not opponent_died:
		# Opponent still alive when we died = we lose
		won = false

	var stats = TypingManager.get_stats()
	stats["score"] = local_final_score
	stats["opponent_score"] = opponent_final_score
	stats["enemies_destroyed"] = enemies_killed
	stats["wave"] = wave_manager.current_wave if wave_manager else 0
	stats["death_reason"] = "VS Match Complete"
	stats["mode"] = "VS"
	stats["opponent_stats"] = opponent_stats

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
		if waiting_for_opponent:
			vs_your_score.text = "YOU: %d (DEAD)" % local_final_score
		else:
			vs_your_score.text = "YOU: %d" % score
	if vs_opponent_score:
		if waiting_for_opponent:
			vs_opponent_score.text = "WAITING FOR OPPONENT..."
		else:
			vs_opponent_score.text = "OPP: %d" % opponent_score

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_ESCAPE:
			_trigger_game_over(false, "Quit")
