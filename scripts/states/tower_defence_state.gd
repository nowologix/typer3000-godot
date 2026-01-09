## tower_defence_state.gd
## Tower Defence game mode state
## Enemies follow a path, player types to attack and build towers
extends Node2D

const TDWaveConfigClass = preload("res://scripts/systems/td_wave_config.gd")

const PAUSE_COMMANDS := {
	"RESUME": "resume_game",
	"QUIT": "quit_to_menu"
}

# Map scenes (fallback if no scene path provided)
const AVAILABLE_MAPS := {
	"tokyo": "res://scenes/maps/td_map_tokyo.tscn",
	"berlin": "res://scenes/maps/td_map_berlin.tscn",
	"newyork": "res://scenes/maps/td_map_newyork.tscn"
}

# Current map info
var current_map_name: String = "tokyo"
var current_difficulty: int = 1

# Node references
@onready var game_layer: Node2D = $GameLayer
# No camera needed - direct positioning
@onready var ui_layer: CanvasLayer = $UILayer
@onready var pause_layer: CanvasLayer = $PauseLayer
@onready var typing_hud = $UILayer/TypingHUD
@onready var pause_panel: Control = $PauseLayer/PausePanel
@onready var pause_typed_display: Label = $PauseLayer/PausePanel/CenterContainer/VBoxContainer/TypedDisplay

# Map and path references (set when map loads)
var td_map: Node2D = null
var enemy_path: Path2D = null
var enemy_container: Node2D = null
var spawn_point: Marker2D = null
var portal_point: Marker2D = null
var build_zones: Node2D = null
var portal: Node2D = null
var weather_layer: CanvasLayer = null
var weather_sprite: AnimatedSprite2D = null

# Game state
var score: int = 0
var enemies_killed: int = 0
var lives: int = 20
var game_active: bool = false
var is_paused: bool = false
var pause_typed_buffer: String = ""
var score_multiplier: float = 1.0
var current_wave: int = 0
var enemies_in_wave: int = 0
var enemies_spawned: int = 0
var wave_active: bool = false

# Wave configuration
var spawn_timer: Timer = null
var wave_delay_timer: Timer = null
var wave_config: Array = []

# Enemy scenes
var enemy_scene: PackedScene

# Hit effect scenes
const BlueHitEffect = preload("res://scenes/effects/blue_hit_effect.tscn")
const ElectricHitEffect = preload("res://scenes/effects/electric_hit_effect.tscn")

# Player scene and reference (invisible cursor for tower placement)
const PlayerScene = preload("res://scenes/entities/player.tscn")
var player: CharacterBody2D = null

func _ready() -> void:
	DebugHelper.log_info("TowerDefenceState ready")

	# Allow this node to receive input when paused
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Set process mode for pause panel
	if pause_panel:
		pause_panel.process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	# Preload enemy scene - TODO: create TD-specific enemy
	enemy_scene = load("res://scenes/entities/enemy_word.tscn")
	if enemy_scene == null:
		DebugHelper.log_error("Failed to load enemy_word.tscn!")

	# Create timers
	spawn_timer = Timer.new()
	spawn_timer.one_shot = true
	spawn_timer.timeout.connect(_spawn_next_enemy)
	add_child(spawn_timer)

	wave_delay_timer = Timer.new()
	wave_delay_timer.one_shot = true
	wave_delay_timer.timeout.connect(_start_wave)
	add_child(wave_delay_timer)

	# Connect signals
	SignalBus.enemy_killed.connect(_on_enemy_killed)
	SignalBus.combo_updated.connect(_on_combo_updated)
	SignalBus.word_completed.connect(_on_word_completed)
	SignalBus.score_multiplier_changed.connect(_on_score_multiplier_changed)

func on_enter(params: Dictionary) -> void:
	DebugHelper.log_info("TowerDefenceState entered")
	MenuBackground.hide_background()

	# Reset game state
	score = 0
	enemies_killed = 0
	lives = 20
	game_active = true
	is_paused = false
	score_multiplier = 1.0
	current_wave = 0
	wave_active = false

	# Hide pause panel
	if pause_panel:
		pause_panel.visible = false

	# Load map from params
	current_map_name = params.get("map", "tokyo")
	current_difficulty = params.get("difficulty", 1)
	var map_scene_path = params.get("map_scene", "")
	load_map(current_map_name, map_scene_path)
	# Camera disabled - using direct screen positioning
	#if camera:
	#	camera.make_current()
	# Setup typing manager
	if enemy_container:
		TypingManager.set_enemy_container(enemy_container)
	TypingManager.reset_stats()
	TypingManager.enable_typing()

	# Setup word loader
	var language = SaveManager.get_setting("language", "EN")
	WordSetLoader.set_language_string(language)
	WordSetLoader.reset_used_words()

	# Create invisible player for cursor/tower placement
	player = PlayerScene.instantiate()
	player.position = Vector2(GameConfig.SCREEN_WIDTH / 2, GameConfig.SCREEN_HEIGHT / 2)
	game_layer.add_child(player)
	player.setup_tower_defence_mode()  # Makes player invisible, disables collision

	# Setup build manager for TD mode
	var portal_pos = portal_point.global_position if portal_point else Vector2(3050, 720)
	BuildManager.setup(enemy_container, portal_pos)
	BuildManager.set_player_reference(player)  # Enable cursor movement
	BuildManager.reset()
	BuildManager.add_build_points(150)  # More starting points for TD

	# Generate wave config
	generate_wave_config()

	# Update HUD
	update_hud()

	# Start map-specific music
	SoundManager.play_td_map_music(current_map_name)

	# Start first wave after delay
	wave_delay_timer.start(3.0)

	SignalBus.game_started.emit()

func on_exit() -> void:
	DebugHelper.log_info("TowerDefenceState exiting")
	game_active = false
	is_paused = false
	get_tree().paused = false
	TypingManager.disable_typing()

	# Stop timers
	if spawn_timer:
		spawn_timer.stop()
	if wave_delay_timer:
		wave_delay_timer.stop()

	# Disconnect signals
	if SignalBus.enemy_killed.is_connected(_on_enemy_killed):
		SignalBus.enemy_killed.disconnect(_on_enemy_killed)
	if SignalBus.combo_updated.is_connected(_on_combo_updated):
		SignalBus.combo_updated.disconnect(_on_combo_updated)
	if SignalBus.word_completed.is_connected(_on_word_completed):
		SignalBus.word_completed.disconnect(_on_word_completed)
	if SignalBus.score_multiplier_changed.is_connected(_on_score_multiplier_changed):
		SignalBus.score_multiplier_changed.disconnect(_on_score_multiplier_changed)

	# Cleanup player
	if player:
		player.queue_free()
		player = null

	# Cleanup map
	if td_map:
		td_map.queue_free()
		td_map = null


func load_map(map_name: String, scene_path: String = "") -> void:
	# Load map scene - prefer explicit path, fallback to lookup
	var map_path = scene_path if scene_path != "" else AVAILABLE_MAPS.get(map_name, AVAILABLE_MAPS["tokyo"])
	var map_scene = load(map_path)
	if map_scene == null:
		DebugHelper.log_error("Failed to load map: %s" % map_path)
		return

	td_map = map_scene.instantiate()
	game_layer.add_child(td_map)
	DebugHelper.log_info("TD Map added, children: %s" % str(td_map.get_children()))

	# Scale map to fit viewport height, then center
	var viewport_size = get_viewport().get_visible_rect().size
	var bg_sprite = td_map.get_node_or_null("Background")
	DebugHelper.log_info("bg_sprite found: %s" % [bg_sprite != null])
	if bg_sprite:
		DebugHelper.log_info("bg_sprite texture: %s, visible: %s, z_index: %s" % [bg_sprite.texture != null, bg_sprite.visible, bg_sprite.z_index])
	if bg_sprite and bg_sprite.texture:
		var map_texture_size = bg_sprite.texture.get_size()
		var scale_factor = viewport_size.y / map_texture_size.y

		# Apply scale
		td_map.scale = Vector2(scale_factor, scale_factor)

		# Background sprite center is at (1720, 720) in map coords
		var bg_center_scaled = bg_sprite.position * scale_factor
		var viewport_center = viewport_size / 2.0
		td_map.position = viewport_center - bg_center_scaled

		DebugHelper.log_info("TD Map: viewport=%s, scale=%s, map_pos=%s, bg_global=%s" % [viewport_size, scale_factor, td_map.position, bg_sprite.global_position])

	# Get references from map
	enemy_path = td_map.get_node_or_null("EnemyPath")
	spawn_point = td_map.get_node_or_null("SpawnPoint")
	portal_point = td_map.get_node_or_null("PortalPoint")
	build_zones = td_map.get_node_or_null("BuildZones")

	# Create enemy container
	enemy_container = Node2D.new()
	enemy_container.name = "EnemyContainer"
	enemy_container.z_index = td_map.Z_GAME_OBJECTS if td_map.get("Z_GAME_OBJECTS") else 0
	game_layer.add_child(enemy_container)

	# Reparent overlay to game_layer so it renders above enemies
	var overlay = td_map.get_node_or_null("Overlay")
	if overlay:
		overlay.reparent(game_layer)
		overlay.z_index = 100
		DebugHelper.log_info("Overlay reparented to game_layer")

	# Create portal at portal point
	var portal_scene = load("res://scenes/entities/portal.tscn")
	if portal_scene and portal_point:
		portal = portal_scene.instantiate()
		portal.position = portal_point.global_position
		portal.z_index = 50  # Above enemies, below overlay
		game_layer.add_child(portal)
		DebugHelper.log_info("Portal created at %s" % portal.position)

	# Setup weather effect
	setup_weather()

	DebugHelper.log_info("Loaded TD map: %s (difficulty: %d)" % [map_name, current_difficulty])

func generate_wave_config() -> void:
	wave_config.clear()
	# Use TDWaveConfig to generate waves based on difficulty
	var waves = TDWaveConfigClass.generate_waves(current_difficulty)
	for wave_data in waves:
		var config = {
			"enemy_count": wave_data.enemy_count,
			"spawn_interval": wave_data.spawn_interval,
			"speed_multiplier": wave_data.speed_multiplier,
			"min_word_length": wave_data.min_word_length,
			"max_word_length": wave_data.max_word_length,
			"boss_wave": wave_data.boss_wave
		}
		wave_config.append(config)
	DebugHelper.log_info("Generated %d waves for difficulty %d" % [wave_config.size(), current_difficulty])

func _start_wave() -> void:
	current_wave += 1
	if current_wave > wave_config.size():
		# Victory!
		_trigger_victory()
		return

	var config = wave_config[current_wave - 1]
	enemies_in_wave = config.enemy_count
	enemies_spawned = 0
	wave_active = true

	DebugHelper.log_info("Wave %d started: %d enemies" % [current_wave, enemies_in_wave])

	# Start spawning
	spawn_timer.start(config.spawn_interval)

func _spawn_next_enemy() -> void:
	if not wave_active or not game_active:
		return

	if enemies_spawned >= enemies_in_wave:
		return

	spawn_enemy()
	enemies_spawned += 1

	# Continue spawning
	if enemies_spawned < enemies_in_wave:
		var config = wave_config[current_wave - 1]
		spawn_timer.start(config.spawn_interval)

func spawn_enemy() -> void:
	if not enemy_scene or not enemy_container or not enemy_path:
		return

	var enemy = enemy_scene.instantiate()

	# Position at spawn point
	if spawn_point:
		enemy.position = spawn_point.global_position
	else:
		enemy.position = Vector2(390, 720)

	# Get word based on wave config
	var config = wave_config[current_wave - 1] if current_wave > 0 else {}
	var min_len = config.get("min_word_length", 3)
	var max_len = config.get("max_word_length", 5)
	var word = get_word_for_wave(min_len, max_len)

	# Setup enemy with path following
	enemy.setup(word, null)  # No portal target - will use path

	# Set speed based on wave
	var speed_mult = config.get("speed_multiplier", 1.0)
	if enemy.has_method("set_speed_multiplier"):
		enemy.set_speed_multiplier(speed_mult)

	# Store path reference for enemy movement
	if enemy.has_method("set_path"):
		enemy.set_path(enemy_path)
	else:
		# Fallback: make enemy move along path points manually
		enemy.set_meta("td_path", enemy_path)
		enemy.set_meta("td_path_progress", 0.0)
		# Random offset from path center (-30 to +30 pixels)
		enemy.set_meta("td_path_offset", randf_range(-30.0, 30.0))

	enemy_container.add_child(enemy)

	# Connect to enemy reaching end signal
	if enemy.has_signal("reached_portal"):
		enemy.reached_portal.connect(_on_enemy_reached_end.bind(enemy))

func get_word_for_wave(min_len: int, max_len: int) -> String:
	# Get word with length in the specified range
	return WordSetLoader.get_random_word({"min_length": min_len, "max_length": max_len})

func _process(delta: float) -> void:
	if not game_active or is_paused:
		return

	# Update path-following enemies
	update_path_enemies(delta)

	# Update towers
	if enemy_container:
		var enemies = []
		for child in enemy_container.get_children():
			if child.is_in_group("enemies") and child.has_method("is_alive") and child.is_alive():
				enemies.append(child)
		var tower_results = BuildManager.update_towers(delta, enemies)
		process_tower_results(tower_results)

	# Check wave completion
	if wave_active and enemies_spawned >= enemies_in_wave:
		var alive_enemies = 0
		for enemy in enemy_container.get_children():
			if enemy.has_method("is_alive") and enemy.is_alive():
				alive_enemies += 1
		if alive_enemies == 0:
			wave_completed()

	update_hud()

func update_path_enemies(delta: float) -> void:
	if not enemy_path or not enemy_container:
		return

	var curve = enemy_path.curve
	if not curve:
		return

	var path_length = curve.get_baked_length()

	for enemy in enemy_container.get_children():
		if not enemy.has_meta("td_path"):
			continue
		if not enemy.has_method("is_alive") or not enemy.is_alive():
			continue

		# Get current progress
		var progress = enemy.get_meta("td_path_progress", 0.0)

		# Calculate speed
		var base_speed = 50.0  # pixels per second
		var speed_mult = 1.0
		if enemy.has_method("get_speed_multiplier"):
			speed_mult = enemy.get_speed_multiplier()
		elif enemy.has_meta("speed_multiplier"):
			speed_mult = enemy.get_meta("speed_multiplier", 1.0)

		# Apply slow effects
		var slow_factor = 1.0
		if enemy.has_method("get_slow_factor"):
			slow_factor = enemy.get_slow_factor()

		var speed = base_speed * speed_mult * slow_factor

		# Update progress
		progress += speed * delta
		enemy.set_meta("td_path_progress", progress)

		# Check if reached end
		if progress >= path_length:
			_on_enemy_reached_end(enemy)
			continue

		# Update position along path with offset
		var new_pos = curve.sample_baked(progress)

		# Get direction at this point on the path (for offset and rotation)
		var next_pos = curve.sample_baked(min(progress + 5.0, path_length))
		var direction = (next_pos - new_pos).normalized()

		# Apply perpendicular offset for path variation
		var path_offset = enemy.get_meta("td_path_offset", 0.0)
		if path_offset != 0.0:
			# Perpendicular vector (rotate 90 degrees)
			var perpendicular = Vector2(-direction.y, direction.x)
			new_pos += perpendicular * path_offset

		enemy.position = enemy_path.to_global(new_pos)

		# Rotate sprite and shadow toward movement direction (0° = up in sprite)
		if direction.length() > 0.1:
			var target_rotation = direction.angle() + PI / 2
			var sprite = enemy.get_node_or_null("Sprite")
			var shadow = enemy.get_node_or_null("Shadow")
			if sprite:
				sprite.rotation = target_rotation
			if shadow:
				shadow.rotation = target_rotation

func wave_completed() -> void:
	wave_active = false
	DebugHelper.log_info("Wave %d completed!" % current_wave)

	# Reset wave limits for towers
	BuildManager.reset_wave()
	# Wave completion bonus
	BuildManager.add_build_points(25 + current_wave * 5)

	# Start next wave after delay
	wave_delay_timer.start(5.0)

func _on_enemy_reached_end(enemy: Node) -> void:
	lives -= 1
	DebugHelper.log_info("Enemy reached end! Lives: %d" % lives)
	SoundManager.play_portal_hit()

	# Remove enemy
	if is_instance_valid(enemy):
		enemy.queue_free()

	# Check game over
	if lives <= 0:
		_trigger_game_over("All lives lost")

func process_tower_results(results: Array) -> void:
	for result in results:
		var action = result.get("action", "")
		var data = result.get("data", {})

		match action:
			"gun_fire":
				var target = data.get("target")
				if target and is_instance_valid(target):
					EffectsManager.spawn_hit_effect(target.global_position, self)
					SoundManager.play_tower_shoot()
			"tesla_push":
				var affected_enemies = data.get("enemies", [])
				for enemy in affected_enemies:
					if is_instance_valid(enemy):
						spawn_electric_hit_effect(enemy.global_position)
				if affected_enemies.size() > 0:
					SoundManager.play_tesla_zap()
			"freeze_slow":
				var affected_enemies = data.get("enemies", [])
				for enemy in affected_enemies:
					if is_instance_valid(enemy):
						spawn_blue_hit_effect(enemy.global_position)

func spawn_blue_hit_effect(pos: Vector2) -> void:
	if BlueHitEffect == null:
		return
	var effect = BlueHitEffect.instantiate()
	effect.global_position = pos
	add_child(effect)

func spawn_electric_hit_effect(pos: Vector2) -> void:
	if ElectricHitEffect == null:
		return
	var effect = ElectricHitEffect.instantiate()
	effect.global_position = pos
	add_child(effect)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# ESC - only on first press
		if event.keycode == KEY_ESCAPE and not event.is_echo():
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

		# ENTER to confirm placement/upgrade/sell in build mode
		if BuildManager.is_building():
			var phase := BuildManager.get_build_phase()
			if phase in [BuildManager.BuildPhase.SELECTING_POSITION, BuildManager.BuildPhase.SELECTING_UPGRADE, BuildManager.BuildPhase.SELECTING_SELL]:
				if (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and not event.is_echo():
					var result = BuildManager.confirm_cursor_action()
					if result.action == "tower_placed":
						SoundManager.play_tower_build()
					elif result.action == "tower_upgraded":
						SoundManager.play_tower_build()
					elif result.action == "tower_sold":
						SoundManager.play_tower_build()  # TODO: Add sell sound
					elif result.action in ["position_occupied", "insufficient_points", "tower_too_far", "no_tower_nearby"]:
						SoundManager.play_type_error()
					get_viewport().set_input_as_handled()
					return
				
			# Handle pause menu input
		if is_paused:
			handle_pause_input(event)
			get_viewport().set_input_as_handled()
			return

	if not game_active or is_paused:
		return

	# Debug: F4 = skip wave
	if event is InputEventKey and event.keycode == KEY_F4:
		debug_skip_wave()

func handle_pause_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return

	var char_code = event.unicode

	if event.keycode == KEY_BACKSPACE:
		if pause_typed_buffer.length() > 0:
			pause_typed_buffer = pause_typed_buffer.substr(0, pause_typed_buffer.length() - 1)
			update_pause_display()
		return

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
	SoundManager.play_pause()
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
	SoundManager.play_unpause()
	SoundManager.play_td_map_music(current_map_name)

func quit_to_menu() -> void:
	DebugHelper.log_info("Quitting to menu")
	is_paused = false
	get_tree().paused = false
	StateManager.change_state("menu")

func debug_skip_wave() -> void:
	if enemy_container:
		for enemy in enemy_container.get_children():
			if enemy.has_method("die"):
				enemy.die()
			else:
				enemy.queue_free()
	DebugHelper.log_debug("Debug: Skipped wave")

func _on_enemy_killed(enemy: Node, typed: bool) -> void:
	if typed:
		enemies_killed += 1
		var word_score = enemy.word.length() * 10
		var combo_bonus = TypingManager.combo * 5
		var total_score = int((word_score + combo_bonus) * score_multiplier)
		score += total_score
		SoundManager.play_enemy_kill()
		BuildManager.add_build_points(5)

func _on_combo_updated(combo: int) -> void:
	if typing_hud and typing_hud.has_method("update_combo"):
		typing_hud.update_combo(combo)

func _on_word_completed(enemy: Node, combo: int) -> void:
	if is_instance_valid(enemy) and enemy_container:
		EffectsManager.word_complete_effect(enemy.global_position, enemy.word, combo, enemy_container)

func _on_score_multiplier_changed(multiplier: float) -> void:
	score_multiplier = multiplier

func _trigger_game_over(reason: String) -> void:
	game_active = false
	TypingManager.disable_typing()

	var stats = TypingManager.get_stats()
	stats["score"] = score
	stats["enemies_destroyed"] = enemies_killed
	stats["wave"] = current_wave
	stats["death_reason"] = reason
	stats["mode"] = "TOWER_DEFENCE"

	SignalBus.game_over.emit(false, stats)
	StateManager.change_state("game_over", {"won": false, "stats": stats})

func _trigger_victory() -> void:
	game_active = false
	TypingManager.disable_typing()

	var stats = TypingManager.get_stats()
	stats["score"] = score
	stats["enemies_destroyed"] = enemies_killed
	stats["wave"] = current_wave
	stats["lives_remaining"] = lives
	stats["mode"] = "TOWER_DEFENCE"

	SignalBus.game_over.emit(true, stats)
	StateManager.change_state("game_over", {"won": true, "stats": stats})

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
			"wave": current_wave,
			"portal_hp": lives,
			"portal_max_hp": 20,
			"active_word": TypingManager.active_enemy.word if TypingManager.active_enemy else "",
			"typed_index": TypingManager.typed_index
		})

func setup_weather() -> void:
	# Setup weather based on map
	match current_map_name:
		"tokyo":
			setup_weather_rain()
		"freudenberg":
			setup_weather_snow()
		_:
			pass  # No weather for other maps

func setup_weather_rain() -> void:
	# Create weather canvas layer (above vignette=5, below UI=10)
	weather_layer = CanvasLayer.new()
	weather_layer.layer = 8
	weather_layer.name = "WeatherLayer"
	add_child(weather_layer)

	# Load rain frames
	var frames = SpriteFrames.new()
	frames.add_animation("rain")
	frames.set_animation_loop("rain", true)
	frames.set_animation_speed("rain", 24.0)  # 24 FPS

	var frame_count = 0
	for i in range(174):
		var path = "res://assets/weather/rain/raintopdown_%03d.png" % i
		var tex = load(path)
		if tex:
			frames.add_frame("rain", tex)
			frame_count += 1

	if frame_count == 0:
		DebugHelper.log_warning("No rain frames loaded!")
		return

	# Create animated sprite
	weather_sprite = AnimatedSprite2D.new()
	weather_sprite.sprite_frames = frames
	weather_sprite.animation = "rain"
	weather_sprite.centered = false

	# Scale to cover full screen
	var viewport_size = get_viewport().get_visible_rect().size
	var frame_size = Vector2(1720, 720)  # Original frame size
	weather_sprite.scale = viewport_size / frame_size

	weather_layer.add_child(weather_sprite)
	weather_sprite.play()

	DebugHelper.log_info("Rain weather started: %d frames at 24fps" % frame_count)

func setup_weather_snow() -> void:
	# Create weather canvas layer (above vignette=5, below UI=10)
	weather_layer = CanvasLayer.new()
	weather_layer.layer = 8
	weather_layer.name = "WeatherLayer"
	add_child(weather_layer)

	# Load snow frames
	var frames = SpriteFrames.new()
	frames.add_animation("snow")
	frames.set_animation_loop("snow", true)
	frames.set_animation_speed("snow", 24.0)  # 24 FPS

	var frame_count = 0
	for i in range(450):
		var path = "res://assets/weather/snow/typer_snow_%03d.png" % i
		var tex = load(path)
		if tex:
			frames.add_frame("snow", tex)
			frame_count += 1

	if frame_count == 0:
		DebugHelper.log_warning("No snow frames loaded!")
		return

	# Create animated sprite
	weather_sprite = AnimatedSprite2D.new()
	weather_sprite.sprite_frames = frames
	weather_sprite.animation = "snow"
	weather_sprite.centered = false

	# Scale to cover full screen
	var viewport_size = get_viewport().get_visible_rect().size
	var frame_size = Vector2(1720, 720)  # Original frame size
	weather_sprite.scale = viewport_size / frame_size

	weather_layer.add_child(weather_sprite)
	weather_sprite.play()

	DebugHelper.log_info("Snow weather started: %d frames at 24fps" % frame_count)
