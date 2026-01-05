## game_state.gd
## Main gameplay state - handles the core game loop
extends Node2D

const PAUSE_COMMANDS := {
	"RESUME": "resume_game",
	"QUIT": "quit_to_menu"
}

@onready var enemy_container: Node2D = $GameLayer/EnemyContainer
@onready var portal: Node2D = $GameLayer/Portal
@onready var player: CharacterBody2D = $GameLayer/Player
@onready var wave_manager: Node = $WaveManager
@onready var typing_hud = $UILayer/TypingHUD
@onready var pause_panel: Control = $PauseLayer/PausePanel
@onready var pause_typed_display: Label = $PauseLayer/PausePanel/CenterContainer/VBoxContainer/TypedDisplay

var score: int = 0
var enemies_killed: int = 0
var game_active: bool = false
var is_paused: bool = false
var pause_typed_buffer: String = ""
var score_multiplier: float = 1.0

# Enemy scene for spawning
var enemy_scene: PackedScene

# Collision constants
const PLAYER_COLLISION_RADIUS: float = 20.0
const ENEMY_COLLISION_RADIUS: float = 15.0

func _ready() -> void:
	DebugHelper.log_info("GameState ready")

	# Set process mode for pause panel
	if pause_panel:
		pause_panel.process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	# Preload enemy scene
	enemy_scene = load("res://scenes/entities/enemy_word.tscn")
	if enemy_scene == null:
		DebugHelper.log_error("Failed to load enemy_word.tscn!")

	# Connect signals
	SignalBus.enemy_killed.connect(_on_enemy_killed)
	SignalBus.enemy_reached_portal.connect(_on_enemy_reached_portal)
	SignalBus.portal_destroyed.connect(_on_portal_destroyed)
	SignalBus.player_died.connect(_on_player_died)
	SignalBus.wave_completed.connect(_on_wave_completed)
	SignalBus.combo_updated.connect(_on_combo_updated)
	SignalBus.word_completed.connect(_on_word_completed)
	SignalBus.score_multiplier_changed.connect(_on_score_multiplier_changed)
	SignalBus.powerup_collected.connect(_on_powerup_collected)

func on_enter(_params: Dictionary) -> void:
	DebugHelper.log_info("GameState entered")

	# Reset game state
	score = 0
	enemies_killed = 0
	game_active = true
	is_paused = false
	score_multiplier = 1.0

	# Make sure pause panel is hidden
	if pause_panel:
		pause_panel.visible = false

	# Setup typing manager
	TypingManager.set_enemy_container(enemy_container)
	TypingManager.reset_stats()
	TypingManager.enable_typing()

	# Setup WordSetLoader with saved language
	var language = SaveManager.get_setting("language", "EN")
	WordSetLoader.set_language_string(language)
	WordSetLoader.reset_used_words()

	# Setup wave manager
	if wave_manager:
		wave_manager.setup(enemy_container, portal)
		wave_manager.start_waves()

	# Setup powerup manager
	PowerUpManager.set_spawn_container(enemy_container)
	PowerUpManager.reset()

	# Setup tower manager (legacy mouse-based)
	TowerManager.setup(enemy_container)

	# Setup build manager (typing-based)
	var portal_pos = portal.global_position if portal else Vector2(640, 360)
	BuildManager.setup(enemy_container, portal_pos)
	BuildManager.reset()
	BuildManager.add_build_points(100)  # Starting build points

	# Reset portal
	if portal and portal.has_method("reset"):
		portal.reset()

	# Reset player
	if player and player.has_method("reset"):
		player.reset()

	# Update HUD
	update_hud()

	# Start game music
	SoundManager.play_game_music()

	SignalBus.game_started.emit()

func on_exit() -> void:
	DebugHelper.log_info("GameState exiting")
	game_active = false
	is_paused = false
	get_tree().paused = false
	TypingManager.disable_typing()

	# Disconnect signals
	if SignalBus.enemy_killed.is_connected(_on_enemy_killed):
		SignalBus.enemy_killed.disconnect(_on_enemy_killed)
	if SignalBus.enemy_reached_portal.is_connected(_on_enemy_reached_portal):
		SignalBus.enemy_reached_portal.disconnect(_on_enemy_reached_portal)
	if SignalBus.portal_destroyed.is_connected(_on_portal_destroyed):
		SignalBus.portal_destroyed.disconnect(_on_portal_destroyed)
	if SignalBus.player_died.is_connected(_on_player_died):
		SignalBus.player_died.disconnect(_on_player_died)
	if SignalBus.wave_completed.is_connected(_on_wave_completed):
		SignalBus.wave_completed.disconnect(_on_wave_completed)
	if SignalBus.combo_updated.is_connected(_on_combo_updated):
		SignalBus.combo_updated.disconnect(_on_combo_updated)
	if SignalBus.word_completed.is_connected(_on_word_completed):
		SignalBus.word_completed.disconnect(_on_word_completed)
	if SignalBus.score_multiplier_changed.is_connected(_on_score_multiplier_changed):
		SignalBus.score_multiplier_changed.disconnect(_on_score_multiplier_changed)
	if SignalBus.powerup_collected.is_connected(_on_powerup_collected):
		SignalBus.powerup_collected.disconnect(_on_powerup_collected)

func _process(delta: float) -> void:
	if not game_active or is_paused:
		return

	# Update build towers
	if enemy_container:
		var enemies = []
		for child in enemy_container.get_children():
			if child.has_method("is_alive") and child.is_alive():
				enemies.append(child)
		BuildManager.update_towers(delta, enemies)

	# Check player-enemy collisions
	check_player_collisions()

	update_hud()

func check_player_collisions() -> void:
	if not player or not enemy_container:
		return

	for enemy in enemy_container.get_children():
		if not is_instance_valid(enemy):
			continue

		var distance = player.global_position.distance_to(enemy.global_position)
		if distance < PLAYER_COLLISION_RADIUS + ENEMY_COLLISION_RADIUS:
			# Player collided with enemy
			if player.has_method("take_damage"):
				player.take_damage(1)
			# Also kill the enemy on collision
			if enemy.has_method("die"):
				enemy.die(false)  # false = not killed by typing

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		# ESC - check build mode first, then pause
		if event.keycode == KEY_ESCAPE:
			if BuildManager.is_building():
				BuildManager.exit_build_mode()
				get_viewport().set_input_as_handled()
				return
			if is_paused:
				resume_game()
			else:
				pause_game()
			get_viewport().set_input_as_handled()
			return

		# Handle pause menu input
		if is_paused:
			handle_pause_input(event)
			get_viewport().set_input_as_handled()
			return

	if not game_active or is_paused:
		return

	# Debug: F1 = spawn enemy
	if event.is_action_pressed("debug_spawn_enemy"):
		debug_spawn_enemy()

	# Debug: F2 = damage portal
	if event.is_action_pressed("debug_damage_portal"):
		debug_damage_portal()

func handle_pause_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return

	var char_code = event.unicode

	# Backspace
	if event.keycode == KEY_BACKSPACE:
		if pause_typed_buffer.length() > 0:
			pause_typed_buffer = pause_typed_buffer.substr(0, pause_typed_buffer.length() - 1)
			update_pause_display()
		return

	# A-Z
	if (char_code >= 65 and char_code <= 90) or (char_code >= 97 and char_code <= 122):
		pause_typed_buffer += char(char_code).to_upper()
		update_pause_display()
		check_pause_commands()

func update_pause_display() -> void:
	if pause_typed_display:
		pause_typed_display.text = pause_typed_buffer

func check_pause_commands() -> void:
	for command in PAUSE_COMMANDS:
		if pause_typed_buffer == command:
			call(PAUSE_COMMANDS[command])
			return

	# Check if could still match any command
	var could_match = false
	for command in PAUSE_COMMANDS:
		if command.begins_with(pause_typed_buffer):
			could_match = true
			break

	if not could_match and pause_typed_buffer.length() > 0:
		pause_typed_buffer = ""
		update_pause_display()

func pause_game() -> void:
	if is_paused:
		return
	DebugHelper.log_info("Pausing game")
	is_paused = true
	pause_typed_buffer = ""
	update_pause_display()
	TypingManager.disable_typing()
	get_tree().paused = true
	if pause_panel:
		pause_panel.visible = true
	SoundManager.play_pause_music()

func resume_game() -> void:
	if not is_paused:
		return
	DebugHelper.log_info("Resuming game")
	is_paused = false
	get_tree().paused = false
	if pause_panel:
		pause_panel.visible = false
	TypingManager.enable_typing()
	SoundManager.play_game_music()

func quit_to_menu() -> void:
	DebugHelper.log_info("Quitting to menu")
	is_paused = false
	get_tree().paused = false
	StateManager.change_state("menu")

func debug_spawn_enemy() -> void:
	if enemy_scene and enemy_container:
		var enemy = enemy_scene.instantiate()
		var spawn_x = randf_range(100, GameConfig.SCREEN_WIDTH - 100)
		var spawn_y = randf_range(50, 150)
		enemy.position = Vector2(spawn_x, spawn_y)
		enemy.setup(get_random_word(), portal)
		enemy_container.add_child(enemy)
		DebugHelper.log_debug("Debug: Spawned enemy at (%d, %d)" % [spawn_x, spawn_y])

func debug_damage_portal() -> void:
	if portal and portal.has_method("take_damage"):
		portal.take_damage(1)
		DebugHelper.log_debug("Debug: Damaged portal")

func get_random_word() -> String:
	# ASSUMPTION: Simple word list for now, will be replaced with JSON loading
	var words = ["CAT", "DOG", "RUN", "JUMP", "FIRE", "CODE", "GAME", "TYPE", "WORD", "FAST",
				 "SLOW", "HERO", "ZERO", "BYTE", "DATA", "LOOP", "FUNC", "NODE", "TREE", "PATH"]
	return words[randi() % words.size()]

func _on_enemy_killed(enemy: Node, typed: bool) -> void:
	if typed:
		enemies_killed += 1
		# Score based on word length and combo, with multiplier
		var word_score = enemy.word.length() * 10
		var combo_bonus = TypingManager.combo * 5
		var total_score = int((word_score + combo_bonus) * score_multiplier)
		score += total_score
		SoundManager.play_enemy_kill()
		# Build points for kills
		BuildManager.add_build_points(5)
		if score_multiplier > 1.0:
			DebugHelper.log_debug("Enemy killed: %s (+%d score, %.1fx)" % [enemy.word, total_score, score_multiplier])
		else:
			DebugHelper.log_debug("Enemy killed: %s (+%d score)" % [enemy.word, total_score])

func _on_enemy_reached_portal(enemy: Node) -> void:
	DebugHelper.log_debug("Enemy reached portal: %s" % enemy.word)
	SoundManager.play_portal_hit()

func _on_portal_destroyed() -> void:
	DebugHelper.log_info("Portal destroyed - Game Over!")
	_trigger_game_over("Portal destroyed")

func _on_player_died() -> void:
	DebugHelper.log_info("Player died - Game Over!")
	_trigger_game_over("Player died")

func _trigger_game_over(reason: String) -> void:
	game_active = false
	TypingManager.disable_typing()

	var stats = TypingManager.get_stats()
	stats["score"] = score
	stats["enemies_destroyed"] = enemies_killed
	stats["wave"] = wave_manager.current_wave if wave_manager else 0
	stats["death_reason"] = reason

	SignalBus.game_over.emit(false, stats)
	StateManager.change_state("game_over", {"won": false, "stats": stats})

func _on_wave_completed(wave_number: int) -> void:
	DebugHelper.log_info("Wave %d completed!" % wave_number)
	# Reset wave limits for towers
	BuildManager.reset_wave()
	# Wave completion bonus for build points
	BuildManager.add_build_points(25 + wave_number * 5)

func _on_combo_updated(combo: int) -> void:
	# Update HUD combo display
	if typing_hud and typing_hud.has_method("update_combo"):
		typing_hud.update_combo(combo)

func _on_word_completed(enemy: Node, combo: int) -> void:
	# Show word complete effects
	if is_instance_valid(enemy) and enemy_container:
		EffectsManager.word_complete_effect(enemy.global_position, enemy.word, combo, enemy_container)

func _on_score_multiplier_changed(multiplier: float) -> void:
	score_multiplier = multiplier
	DebugHelper.log_info("Score multiplier: %.1fx" % multiplier)

func _on_powerup_collected(type: int, powerup_name: String) -> void:
	DebugHelper.log_info("PowerUp collected: %s" % powerup_name)
	# Could add visual feedback on HUD here

func update_hud() -> void:
	if typing_hud == null:
		return

	var stats = TypingManager.get_stats()

	if typing_hud.has_method("update_stats"):
		typing_hud.update_stats({
			"score": score,
			"combo": stats.combo,
			"max_combo": stats.max_combo,
			"errors": stats.errors,
			"accuracy": stats.accuracy,
			"enemies_remaining": enemy_container.get_child_count() if enemy_container else 0,
			"wave": wave_manager.current_wave if wave_manager else 0,
			"portal_hp": portal.current_hp if portal else 0,
			"portal_max_hp": portal.max_hp if portal else 0,
			"player_hp": player.current_hp if player else 0,
			"player_max_hp": player.max_hp if player else 0,
			"active_word": TypingManager.active_enemy.word if TypingManager.active_enemy else "",
			"typed_index": TypingManager.typed_index
		})

func get_enemy_count() -> int:
	return enemy_container.get_child_count() if enemy_container else 0
