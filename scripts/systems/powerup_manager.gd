## powerup_manager.gd
## Manages powerup spawning, collection, and active effects
## Autoload singleton: PowerUpManager
extends Node

# Powerup types and their effects
enum PowerUpType {
	FREEZE,
	SHIELD,
	DOUBLE_SCORE,
	HEAL,
	NUKE,
	SLOW_MO,
	MAGNET
}

# Powerup definitions
const POWERUPS := {
	PowerUpType.FREEZE: {
		"name": "FREEZE",
		"word_en": "FREEZE",
		"word_de": "FRIEREN",
		"duration": 5.0,
		"color": Color(0.0, 0.9, 1.0),
		"description": "Freeze all enemies"
	},
	PowerUpType.SHIELD: {
		"name": "SHIELD",
		"word_en": "SHIELD",
		"word_de": "SCHILD",
		"duration": 8.0,
		"color": Color(0.3, 0.5, 1.0),
		"description": "Portal invincibility"
	},
	PowerUpType.DOUBLE_SCORE: {
		"name": "DOUBLE",
		"word_en": "DOUBLE",
		"word_de": "DOPPEL",
		"duration": 10.0,
		"color": Color(1.0, 0.84, 0.0),
		"description": "2x score multiplier"
	},
	PowerUpType.HEAL: {
		"name": "HEAL",
		"word_en": "HEAL",
		"word_de": "HERZ",
		"duration": 0.0,
		"color": Color(0.0, 1.0, 0.5),
		"description": "Restore 5 HP"
	},
	PowerUpType.NUKE: {
		"name": "NUKE",
		"word_en": "NUKE",
		"word_de": "ATOM",
		"duration": 0.0,
		"color": Color(1.0, 0.3, 0.0),
		"description": "Destroy all enemies"
	},
	PowerUpType.SLOW_MO: {
		"name": "SLOW",
		"word_en": "SLOW",
		"word_de": "ZEIT",
		"duration": 6.0,
		"color": Color(0.6, 0.3, 0.9),
		"description": "Slow enemy movement"
	},
	PowerUpType.MAGNET: {
		"name": "MAGNET",
		"word_en": "MAGNET",
		"word_de": "MAGNET",
		"duration": 0.0,  # Instant - triggers placement mode
		"color": Color(0.9, 0.2, 0.6),
		"description": "Place a magnet that deflects enemies"
	}
}

# Get the powerup word based on current language
func get_powerup_word(type: PowerUpType) -> String:
	var data = POWERUPS.get(type, {})
	var lang = WordSetLoader.get_language_string() if WordSetLoader else "EN"
	if lang == "DE":
		return data.get("word_de", data.get("word_en", "POWERUP"))
	return data.get("word_en", "POWERUP")

var active_powerups: Dictionary = {}
var shield_sprite: Sprite2D = null
var shield_tween: Tween = null
var portal_ref: Node2D = null
var spawn_chance_per_wave: float = 1.0
var spawn_chance_per_kill: float = 0.3
var powerup_scene: PackedScene = null
var spawn_container: Node2D = null

# Magnet placement system
var magnet_placement_mode: bool = false
var magnet_cursor_position: Vector2 = Vector2.ZERO
var placed_magnets: Array = []  # Track all active magnets
const MagnetScript = preload("res://scripts/entities/magnet.gd")

signal magnet_placement_started
signal magnet_placement_cancelled
signal magnet_placed(position: Vector2)

# Network mode - when true, this client doesn't spawn powerups (receives from host)
var network_client_mode: bool = false

func _ready() -> void:
	powerup_scene = load("res://scenes/entities/powerup.tscn")
	if powerup_scene == null:
		DebugHelper.log_warning("PowerUpManager: powerup.tscn not found")
	SignalBus.enemy_killed.connect(_on_enemy_killed)
	SignalBus.wave_started.connect(_on_wave_started)
	DebugHelper.log_info("PowerUpManager initialized")

func _process(delta: float) -> void:
	var expired: Array = []
	for type in active_powerups:
		active_powerups[type] -= delta
		if active_powerups[type] <= 0:
			expired.append(type)
	for type in expired:
		deactivate_powerup(type)

func set_spawn_container(container: Node2D) -> void:
	spawn_container = container

func set_portal_reference(portal: Node2D) -> void:
	portal_ref = portal

func reset() -> void:
	active_powerups.clear()
	hide_shield_visual()
	_cleanup_magnets()
	magnet_placement_mode = false
	network_client_mode = false

func set_network_client_mode(enabled: bool) -> void:
	network_client_mode = enabled
	DebugHelper.log_info("PowerUpManager: network_client_mode = %s" % enabled)

func _on_enemy_killed(_enemy: Node, typed: bool) -> void:
	# Don't spawn if in network client mode (host handles spawning)
	if network_client_mode:
		return
	if typed and spawn_container and randf() < spawn_chance_per_kill:
		spawn_random_powerup()

func _on_wave_started(wave: int) -> void:
	# Don't spawn if in network client mode (host handles spawning)
	if network_client_mode:
		return
	if spawn_container and wave > 1 and randf() < spawn_chance_per_wave:
		spawn_random_powerup()

func spawn_random_powerup() -> void:
	if spawn_container == null or network_client_mode:
		return
	var types = POWERUPS.keys()
	var random_type = types[randi() % types.size()]
	spawn_powerup(random_type)

func spawn_powerup(type: PowerUpType) -> void:
	if spawn_container == null:
		return
	if powerup_scene == null:
		DebugHelper.log_error("PowerUpManager: powerup_scene is null!")
		return

	var powerup_data = POWERUPS[type]
	var powerup_word = get_powerup_word(type)

	# Use the scene file for proper instantiation
	var powerup = powerup_scene.instantiate()

	# Setup the powerup with correct type and word
	powerup.powerup_type = type
	powerup.word = powerup_word

	# Also set metadata for network sync
	powerup.set_meta("powerup_type", type)
	powerup.set_meta("powerup_word", powerup_word)
	powerup.set_meta("powerup_color", powerup_data.color)

	var spawn_x = randf_range(100, GameConfig.SCREEN_WIDTH - 100)
	var spawn_y = randf_range(100, 300)
	powerup.position = Vector2(spawn_x, spawn_y)
	spawn_container.add_child(powerup)

	# Set fallback color after adding to tree
	if powerup.has_node("FallbackSprite"):
		powerup.get_node("FallbackSprite").color = powerup_data.color

	SoundManager.play_powerup_spawn()

	# Emit signal for network sync
	SignalBus.powerup_spawned.emit(powerup)
	DebugHelper.log_info("PowerUpManager: Spawned %s (type=%d) at (%.0f, %.0f)" % [powerup_word, type, spawn_x, spawn_y])

func create_powerup_node(type: PowerUpType, data: Dictionary) -> Node2D:
	var powerup = Node2D.new()
	var powerup_word = get_powerup_word(type)

	# Create animated sprite
	var sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.scale = Vector2(0.25, 0.25)
	powerup.add_child(sprite)

	# Create fallback sprite (ColorRect for types without animations)
	var fallback = ColorRect.new()
	fallback.name = "FallbackSprite"
	fallback.visible = false
	fallback.size = Vector2(60, 30)
	fallback.position = Vector2(-30, -15)
	fallback.color = data.color
	powerup.add_child(fallback)

	# Create word label (RichTextLabel for BBCode support)
	var label = RichTextLabel.new()
	label.name = "WordLabel"
	label.bbcode_enabled = true
	label.text = "[center]" + powerup_word + "[/center]"
	label.size = Vector2(100, 25)
	label.position = Vector2(-50, -50)
	label.add_theme_font_size_override("normal_font_size", 16)
	label.add_theme_color_override("default_color", Color.WHITE)
	label.scroll_active = false
	label.fit_content = true
	powerup.add_child(label)

	# Set script AFTER adding children so @onready works
	powerup.set_script(load("res://scripts/entities/powerup.gd"))

	# Set properties AFTER script is attached (more reliable than metadata)
	powerup.powerup_type = type
	powerup.word = powerup_word

	# Also set metadata for backward compatibility
	powerup.set_meta("powerup_type", type)
	powerup.set_meta("powerup_word", powerup_word)
	powerup.set_meta("powerup_color", data.color)

	return powerup

func collect_powerup(type: PowerUpType) -> void:
	DebugHelper.log_info("=== PowerUpManager.collect_powerup called with type: %d ===" % type)
	if not POWERUPS.has(type):
		DebugHelper.log_error("Unknown powerup type: %d" % type)
		return
	var data = POWERUPS[type]
	DebugHelper.log_info("PowerUp activating: %s (duration: %.1f)" % [data.name, data.duration])
	SoundManager.play_powerup_collect()
	if data.duration > 0:
		DebugHelper.log_info("Activating timed powerup: %s" % data.name)
		activate_powerup(type, data.duration)
	else:
		DebugHelper.log_info("Activating instant powerup: %s" % data.name)
		apply_instant_powerup(type)
	SignalBus.powerup_collected.emit(type, data.name)

func activate_powerup(type: PowerUpType, duration: float) -> void:
	var data = POWERUPS[type]
	var already_active = active_powerups.has(type)

	# Stack duration if already active, otherwise set new duration
	if already_active:
		active_powerups[type] += duration
		DebugHelper.log_info("PowerUp %s extended by %.1fs (total: %.1fs)" % [data.name, duration, active_powerups[type]])
	else:
		active_powerups[type] = duration
		# Only apply effect on first activation
		match type:
			PowerUpType.FREEZE:
				freeze_all_enemies(true)
				SoundManager.play_freeze_effect()
			PowerUpType.SHIELD:
				SignalBus.shield_activated.emit(duration)
				show_shield_visual()
			PowerUpType.DOUBLE_SCORE:
				SignalBus.score_multiplier_changed.emit(2.0)
			PowerUpType.SLOW_MO:
				slow_all_enemies(0.5)
				SoundManager.play_slowdown()
		DebugHelper.log_debug("PowerUp activated: %s for %.1fs" % [data.name, duration])

func deactivate_powerup(type: PowerUpType) -> void:
	active_powerups.erase(type)
	var data = POWERUPS[type]
	SoundManager.play_powerup_expire()
	match type:
		PowerUpType.FREEZE:
			freeze_all_enemies(false)
		PowerUpType.SHIELD:
			SignalBus.shield_deactivated.emit()
			hide_shield_visual()
		PowerUpType.DOUBLE_SCORE:
			SignalBus.score_multiplier_changed.emit(1.0)
		PowerUpType.SLOW_MO:
			slow_all_enemies(1.0)
			SoundManager.play_speedup()

func apply_instant_powerup(type: PowerUpType) -> void:
	match type:
		PowerUpType.HEAL:
			SignalBus.portal_heal.emit(5)
			SignalBus.player_healed.emit(5)
			SoundManager.play_powerup_heal()
		PowerUpType.NUKE:
			destroy_all_enemies()
			SoundManager.play_powerup_nuke()
		PowerUpType.MAGNET:
			_enter_magnet_placement_mode()

func show_shield_visual() -> void:
	DebugHelper.log_info("show_shield_visual called")
	if portal_ref == null:
		DebugHelper.log_warning("Shield: portal_ref is null!")
		return
	if shield_sprite == null:
		shield_sprite = Sprite2D.new()
		shield_sprite.name = "ShieldVisual"
		# Load texture directly from file (bypasses Godot import)
		var tex = _load_image_as_texture("res://assets/sprites/typer3000-portal-shield_02.png")
		if tex:
			shield_sprite.texture = tex
			DebugHelper.log_info("Shield texture loaded!")
		else:
			DebugHelper.log_warning("Shield texture failed to load")
	if shield_sprite.get_parent() == null and portal_ref:
		portal_ref.add_child(shield_sprite)
		shield_sprite.position = Vector2.ZERO
		# Scale shield (243px) to match portal diameter (200px)
		shield_sprite.scale = Vector2(0.82, 0.82)
		shield_sprite.modulate = Color(0.3, 0.5, 1.0, 0.7)
		if shield_tween and shield_tween.is_valid():
			shield_tween.kill()
		shield_tween = create_tween().set_loops()
		shield_tween.tween_property(shield_sprite, "modulate:a", 0.4, 0.5)
		shield_tween.tween_property(shield_sprite, "modulate:a", 0.8, 0.5)
	SoundManager.play_shield_activate()
	shield_sprite.visible = true

func _load_image_as_texture(res_path: String) -> ImageTexture:
	var abs_path = ProjectSettings.globalize_path(res_path)
	var image = Image.new()
	var err = image.load(abs_path)
	if err != OK:
		DebugHelper.log_warning("Failed to load image: %s (error %d)" % [abs_path, err])
		return null
	return ImageTexture.create_from_image(image)

func hide_shield_visual() -> void:
	if shield_tween and shield_tween.is_valid():
		shield_tween.kill()
		shield_tween = null
	if shield_sprite:
		shield_sprite.visible = false

func load_texture_direct(res_path: String) -> ImageTexture:
	var absolute_path := ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(absolute_path):
		if not FileAccess.file_exists(res_path):
			return null
		absolute_path = res_path
	var image := Image.new()
	var err := image.load(absolute_path)
	if err != OK:
		return null
	return ImageTexture.create_from_image(image)

func freeze_all_enemies(freeze: bool) -> void:
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy.has_method("set_frozen"):
			enemy.set_frozen(freeze)
		else:
			enemy.set_process(not freeze)
			enemy.set_physics_process(not freeze)

func slow_all_enemies(speed_multiplier: float) -> void:
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy.has_method("set_speed_multiplier"):
			enemy.set_speed_multiplier(speed_multiplier)

func destroy_all_enemies() -> void:
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy.has_method("die"):
			enemy.die()
	DebugHelper.log_info("NUKE: Destroyed %d enemies" % enemies.size())

func is_powerup_active(type: PowerUpType) -> bool:
	return active_powerups.has(type)

func get_powerup_remaining_time(type: PowerUpType) -> float:
	return active_powerups.get(type, 0.0)

func get_active_powerups() -> Dictionary:
	return active_powerups.duplicate()

func get_score_multiplier() -> float:
	if is_powerup_active(PowerUpType.DOUBLE_SCORE):
		return 2.0
	return 1.0

func is_shield_active() -> bool:
	return is_powerup_active(PowerUpType.SHIELD)

# ============================================
# MAGNET PLACEMENT SYSTEM
# ============================================

func _enter_magnet_placement_mode() -> void:
	magnet_placement_mode = true
	magnet_cursor_position = Vector2(GameConfig.SCREEN_WIDTH / 2, GameConfig.SCREEN_HEIGHT / 2)
	TypingManager.disable_typing()  # Disable typing during placement
	magnet_placement_started.emit()
	DebugHelper.log_info("MAGNET placement mode - move cursor and press ENTER to place")

func exit_magnet_placement_mode() -> void:
	magnet_placement_mode = false
	magnet_placement_cancelled.emit()
	DebugHelper.log_info("MAGNET placement cancelled")

func is_magnet_placement_mode() -> bool:
	return magnet_placement_mode

func update_magnet_cursor(position: Vector2) -> void:
	magnet_cursor_position = position

func get_magnet_cursor_position() -> Vector2:
	return magnet_cursor_position

func confirm_magnet_placement() -> bool:
	if not magnet_placement_mode:
		return false
	
	# Create magnet at cursor position
	var magnet = _create_magnet_at(magnet_cursor_position)
	if magnet:
		magnet_placement_mode = false
		magnet_placed.emit(magnet_cursor_position)
		SoundManager.play_sfx("powerup_spawn")
		DebugHelper.log_info("MAGNET placed at %s" % magnet_cursor_position)
		return true
	return false

func _create_magnet_at(pos: Vector2) -> Node2D:
	if spawn_container == null:
		DebugHelper.log_warning("Cannot place magnet: no spawn container")
		return null
	
	var magnet = Node2D.new()
	magnet.name = "Magnet_%d" % placed_magnets.size()
	magnet.set_script(MagnetScript)
	magnet.position = pos
	
	spawn_container.add_child(magnet)
	placed_magnets.append(magnet)
	
	return magnet

func _cleanup_magnets() -> void:
	for magnet in placed_magnets:
		if is_instance_valid(magnet):
			magnet.queue_free()
	placed_magnets.clear()

func get_active_magnets() -> Array:
	# Return only valid, active magnets
	var active: Array = []
	for magnet in placed_magnets:
		if is_instance_valid(magnet) and magnet.is_active:
			active.append(magnet)
	return active

func get_magnet_count() -> int:
	return get_active_magnets().size()
