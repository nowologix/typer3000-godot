## enemy_word.gd
## Enemy entity that moves toward the portal with an attached word
extends CharacterBody2D
class_name EnemyWord

# Exported properties
@export var speed: float = 80.0
@export var damage: int = 1
@export var word: String = "TEST"

# Enemy types
enum EnemyType { NORMAL, SWARM, TANK, STALKER, SPLITTER, SNIPER, SHIELD, BOSS }

# Internal state
var target: Node2D = null
var alive: bool = true
var typed_progress: int = 0
var frozen: bool = false
var speed_multiplier: float = 1.0
var base_speed: float = 80.0

# Enemy type
var enemy_type: EnemyType = EnemyType.NORMAL

# Shield-specific
var is_shield: bool = false
var shield_radius: float = 150.0
var is_shielded: bool = false  # True if this enemy is protected by a Shield enemy

# Tank-specific
var is_tank: bool = false
var tank_hits_remaining: int = 1  # How many more words needed to kill

# Sniper-specific
var is_sniper: bool = false
var charge_time: float = 2.5
var charge_progress: float = 0.0
var has_fired: bool = false
var player_ref: Node2D = null

# Splitter-specific
var is_splitter: bool = false
var splitter_generation: int = 0  # 0 = parent, 1 = child (children don't split further)
const SPLITTER_MAX_GENERATION: int = 1  # Only split once

# Node references
@onready var word_label: RichTextLabel = $WordLabel
@onready var sprite: Sprite2D = $Sprite
@onready var shadow: Sprite2D = $Shadow

# Shadow settings
const SHADOW_OFFSET := Vector2(4, 4)
const SHADOW_SCALE_MULT := 1.1
const SHADOW_COLOR := Color(0, 0, 0, 0.6)

# Sprite textures (preloaded)
const TEXTURE_NORMAL = preload("res://assets/sprites/enemies/enemy_normal_01.png")
const TEXTURE_TANK = preload("res://assets/sprites/enemies/enemy_tank_01.png")
const TEXTURE_SHIELD = preload("res://assets/sprites/enemies/enemy_shield_01.png")
const TEXTURE_SNIPER = preload("res://assets/sprites/enemies/enemy_sniper_01.png")
const TEXTURE_SPLITTER = preload("res://assets/sprites/enemies/enemy_splitter_01.png")
const TEXTURE_SPLITTER_CHILD = preload("res://assets/sprites/enemies/enemy_splitter-child_01.png")

# Sprite scale
const ENEMY_SPRITE_SCALE := 0.5
const ENEMY_TANK_SCALE := 0.5 * 1.3  # Tank is bigger
const ENEMY_CHILD_SCALE := 0.5 * 0.8  # Splitter children are smaller

func _ready() -> void:
	add_to_group("enemies")
	update_word_display()

func update_shadow() -> void:
	# Note: @onready vars may be null if called before tree entry
	# Use get_node_or_null in setup() functions instead
	pass

func setup(new_word: String, portal_target: Node2D) -> void:
	word = new_word.to_upper()
	target = portal_target
	typed_progress = 0
	alive = true
	frozen = false
	speed_multiplier = 1.0
	base_speed = speed
	enemy_type = EnemyType.NORMAL

	# Set normal texture - use get_node since @onready not available yet
	var spr = get_node_or_null("Sprite")
	var shd = get_node_or_null("Shadow")
	if spr:
		spr.texture = TEXTURE_NORMAL
		spr.modulate = Color.WHITE
		spr.scale = Vector2(ENEMY_SPRITE_SCALE, ENEMY_SPRITE_SCALE)
	if shd and spr:
		shd.texture = spr.texture
		shd.scale = spr.scale * SHADOW_SCALE_MULT
		shd.position = SHADOW_OFFSET
		shd.modulate = SHADOW_COLOR
		shd.z_index = 5  # Above background, below sprite
		shd.rotation = spr.rotation  # Match initial rotation
		spr.z_index = 6

	update_word_display()
	DebugHelper.log_debug("Enemy spawned with word: %s" % word)

func _physics_process(delta: float) -> void:
	if not alive or target == null or frozen:
		return

	# Sniper targets player instead of portal
	var move_target = target
	if is_sniper and player_ref != null:
		move_target = player_ref

	# Move toward target with speed multiplier
	var direction = (move_target.global_position - global_position).normalized()
	var current_speed = base_speed * speed_multiplier
	velocity = direction * current_speed
	move_and_slide()

	# Rotate sprite to face movement direction (0° = up)
	if direction.length() > 0.1:
		var target_angle = direction.angle() + PI / 2  # Offset because 0° is up in sprite
		var spr = get_node_or_null("Sprite")
		var shd = get_node_or_null("Shadow")
		if spr:
			spr.rotation = target_angle
		if shd:
			shd.rotation = target_angle

	# Sniper charge mechanic
	if is_sniper and not has_fired:
		charge_progress += delta
		queue_redraw()  # Update charge bar
		if charge_progress >= charge_time:
			has_fired = true
			fire_sniper_shot()

	# Shield protection mechanic
	if is_shield:
		update_shield_protection()
		queue_redraw()  # Update shield radius visual

	# Check if reached portal
	var distance_to_target = global_position.distance_to(target.global_position)
	if distance_to_target < 40:  # Portal collision radius
		reach_portal()
func set_frozen(freeze: bool) -> void:
	frozen = freeze
	if sprite:
		if frozen:
			sprite.modulate = Color(0.5, 0.8, 1.0)  # Icy tint
		else:
			sprite.modulate = Color.WHITE

func set_speed_multiplier(multiplier: float) -> void:
	speed_multiplier = multiplier

func is_slowed() -> bool:
	return speed_multiplier < 1.0

func apply_slow(amount: float, duration: float) -> bool:
	# Return false if already slowed (don't re-apply)
	if speed_multiplier < 1.0:
		return false

	speed_multiplier = amount
	# Create timer to restore speed
	var timer = get_tree().create_timer(duration)
	timer.timeout.connect(func(): speed_multiplier = 1.0)
	return true  # Slow was newly applied

func take_tower_damage(damage: int) -> void:
	# Towers deal damage by removing characters from the word
	# Each damage point removes one character that the player would have typed
	if damage > 0 and word.length() > typed_progress:
		# Effectively "type" characters for the player
		var chars_to_remove = min(damage, word.length() - typed_progress)
		typed_progress += chars_to_remove

		update_word_display()
		DebugHelper.log_debug("Tower damaged %s: %d chars removed" % [word, chars_to_remove])

		# Check if word is now complete
		if typed_progress >= word.length():
			# Tower killed the enemy
			SignalBus.enemy_killed.emit(self, false)  # false = not typed by player
			die()

func reach_portal() -> void:
	if not alive:
		return

	alive = false
	DebugHelper.log_debug("Enemy '%s' reached portal" % word)

	# Damage portal
	if target and target.has_method("take_damage"):
		target.take_damage(damage)

	SignalBus.enemy_reached_portal.emit(self)
	queue_free()

func die() -> void:
	if not alive:
		return

	# Tank enemies regenerate with new word until all hits depleted
	if is_tank and tank_hits_remaining > 1:
		tank_hits_remaining -= 1
		regenerate_tank()
		return

	alive = false
	DebugHelper.log_debug("Enemy '%s' killed by typing" % word)

	# Splitter spawns children when dying (unless it's already a child)
	if is_splitter and splitter_generation < SPLITTER_MAX_GENERATION:
		spawn_splitter_children()

	# If this was a shield, clear protection from all enemies
	if is_shield:
		clear_shield_protection()

	# Visual effects
	if get_parent():
		EffectsManager.enemy_death_effect(global_position, get_parent())

	# Visual feedback (simple scale down)
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2.ZERO, 0.15)
	tween.tween_callback(queue_free)

func is_alive() -> bool:
	return alive

func get_word() -> String:
	return word

func update_typed_progress(progress: int) -> void:
	typed_progress = progress
	update_word_display()

func update_word_display() -> void:
	if word_label == null:
		return

	# Shielded enemies show gray letters (cannot be typed)
	if is_shielded:
		word_label.text = "[center][color=#666666]%s[/color][/center]" % word
		if sprite:
			sprite.modulate = Color(0.5, 0.5, 0.5)  # Dark gray tint
		return

	# Tank enemies show hit indicator
	var tank_suffix = ""
	if is_tank and tank_hits_remaining > 1:
		tank_suffix = " [color=#FF6666][%d][/color]" % tank_hits_remaining

	if typed_progress > 0 and typed_progress < word.length():
		# Show typed portion in cyan, remaining in white
		var typed_part = word.substr(0, typed_progress)
		var remaining_part = word.substr(typed_progress)
		word_label.text = "[center][color=#00E5FF]%s[/color]%s%s[/center]" % [typed_part, remaining_part, tank_suffix]
		# Subtle cyan highlight when being typed
		if sprite:
			sprite.modulate = Color(0.7, 1.0, 1.0)  # Light cyan tint
	elif typed_progress >= word.length():
		word_label.text = "[center]%s%s[/center]" % [word, tank_suffix]
		# Green flash when complete
		if sprite:
			sprite.modulate = Color(0.7, 1.0, 0.7)  # Light green tint
	else:
		word_label.text = "[center]%s%s[/center]" % [word, tank_suffix]
		# Normal state - no tint
		if sprite:
			sprite.modulate = Color.WHITE

func _on_tree_exiting() -> void:
	# Clean up any references
	target = null

func set_word_color(color: Color) -> void:
	# Set the color for the word label (used for COOP reservation)
	if word_label == null:
		return

	# Convert color to hex for BBCode
	var hex = "#%02X%02X%02X" % [int(color.r * 255), int(color.g * 255), int(color.b * 255)]

	if typed_progress > 0 and typed_progress < word.length():
		var typed_part = word.substr(0, typed_progress)
		var remaining_part = word.substr(typed_progress)
		word_label.text = "[center][color=#00E5FF]%s[/color][color=%s]%s[/color][/center]" % [typed_part, hex, remaining_part]
	else:
		word_label.text = "[center][color=%s]%s[/color][/center]" % [hex, word]

# ============ SNIPER FUNCTIONS ============

func setup_sniper(new_word: String, portal_target: Node2D, player: Node2D) -> void:
	setup(new_word, portal_target)
	is_sniper = true
	enemy_type = EnemyType.SNIPER
	player_ref = player
	charge_progress = 0.0
	has_fired = false
	speed = 50.0  # Slower than normal
	base_speed = speed
	var spr = get_node_or_null("Sprite")
	var shd = get_node_or_null("Shadow")
	if spr:
		spr.texture = TEXTURE_SNIPER
		spr.modulate = Color.WHITE
	if shd and spr:
		shd.texture = spr.texture
	DebugHelper.log_debug("Sniper spawned with word: %s" % word)

func fire_sniper_shot() -> void:
	if player_ref == null or not is_instance_valid(player_ref):
		return
	
	SoundManager.play_sniper_shot()
	DebugHelper.log_debug("Sniper fired at player!")
	
	# Damage player
	if player_ref.has_method("take_damage"):
		player_ref.take_damage(1)
	
	# Signal for visual effects
	SignalBus.sniper_fired.emit(self, player_ref)

func reset_charge() -> void:
	if is_sniper:
		charge_progress = 0.0
		DebugHelper.log_debug("Sniper charge reset")

func get_charge_ratio() -> float:
	if charge_time <= 0:
		return 0.0
	return charge_progress / charge_time

func _draw() -> void:
	# Draw sniper charge bar
	if is_sniper and not has_fired:
		var bar_width = 30.0
		var bar_height = 4.0
		var bar_y = 20.0  # Below the enemy
		var ratio = get_charge_ratio()
		
		# Background
		draw_rect(Rect2(-bar_width/2, bar_y, bar_width, bar_height), Color(0, 0, 0, 0.7))
		
		# Progress (cyan -> magenta when almost full)
		var bar_color = Color(0, 1, 1) if ratio < 0.7 else Color(1, 0.2, 0.5)
		draw_rect(Rect2(-bar_width/2, bar_y, bar_width * ratio, bar_height), bar_color)
		
		# Border
		draw_rect(Rect2(-bar_width/2, bar_y, bar_width, bar_height), bar_color, false, 1.0)
		
		# Targeting line when charging > 50%
		if ratio > 0.5 and player_ref != null and is_instance_valid(player_ref):
			var to_player = player_ref.global_position - global_position
			var alpha = (ratio - 0.5) * 2.0
			draw_line(Vector2.ZERO, to_player, Color(1, 0.2, 0.5, alpha), 1.0)

	# Draw shield radius
	if is_shield:
		draw_arc(Vector2.ZERO, shield_radius, 0, TAU, 32, Color(0.5, 0.5, 0.8, 0.3), 2.0)

# ============ SHIELD FUNCTIONS ============

func setup_shield(new_word: String, portal_target: Node2D) -> void:
	setup(new_word, portal_target)
	is_shield = true
	enemy_type = EnemyType.SHIELD
	speed = 40.0  # Slower than normal
	base_speed = speed
	damage = 2  # Higher damage
	var spr = get_node_or_null("Sprite")
	var shd = get_node_or_null("Shadow")
	if spr:
		spr.texture = TEXTURE_SHIELD
		spr.modulate = Color(0.7, 0.7, 1.0)
	if shd and spr:
		shd.texture = spr.texture
	DebugHelper.log_debug("Shield enemy spawned with word: %s" % word)

func update_shield_protection() -> void:
	if not is_shield or not alive:
		return

	# Find all enemies in range and mark them as shielded
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy == self:
			continue
		if not is_instance_valid(enemy) or not enemy.alive:
			continue

		var distance = global_position.distance_to(enemy.global_position)
		var was_shielded = enemy.is_shielded

		if distance <= shield_radius:
			enemy.is_shielded = true
			if not was_shielded:
				enemy.update_word_display()  # Update to show gray
		# Note: Don't set is_shielded = false here, another shield might protect it

func clear_shield_protection() -> void:
	# Called when shield dies - need to recalculate all shields
	var enemies = get_tree().get_nodes_in_group("enemies")

	# First, clear all shielded status
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.is_shielded = false

	# Then, let remaining shields re-apply their protection
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.is_shield and enemy.alive and enemy != self:
			enemy.update_shield_protection()

# ============ TANK FUNCTIONS ============

func setup_tank(new_word: String, portal_target: Node2D, hits: int = 3) -> void:
	setup(new_word, portal_target)
	is_tank = true
	enemy_type = EnemyType.TANK
	tank_hits_remaining = hits
	speed = 30.0  # Slower than normal
	base_speed = speed
	damage = 3  # Higher damage
	var spr = get_node_or_null("Sprite")
	var shd = get_node_or_null("Shadow")
	if spr:
		spr.texture = TEXTURE_TANK
		spr.modulate = Color.WHITE
		spr.scale = Vector2(ENEMY_TANK_SCALE, ENEMY_TANK_SCALE)
	if shd and spr:
		shd.texture = spr.texture
		shd.scale = spr.scale * SHADOW_SCALE_MULT
	DebugHelper.log_debug("Tank enemy spawned with word: %s (%d hits)" % [word, hits])

func regenerate_tank() -> void:
	# Get a new word for the tank
	var new_word = WordSetLoader.get_word_for_wave(10)  # Get a medium difficulty word
	word = new_word.to_upper()
	typed_progress = 0

	# Visual feedback - flash and pulse
	if sprite:
		var tween = create_tween()
		tween.tween_property(sprite, "modulate", Color(2, 0.5, 0.5), 0.1)
		tween.tween_property(sprite, "modulate", Color.WHITE, 0.2)

	# Sound feedback
	SoundManager.play_sfx("enemy_spawn")

	update_word_display()
	DebugHelper.log_debug("Tank regenerated with word: %s (%d hits remaining)" % [word, tank_hits_remaining])

# ============ SPLITTER FUNCTIONS ============

func setup_splitter(new_word: String, portal_target: Node2D, generation: int = 0) -> void:
	setup(new_word, portal_target)
	is_splitter = true
	enemy_type = EnemyType.SPLITTER
	splitter_generation = generation
	speed = 60.0  # Slightly slower than normal
	base_speed = speed
	damage = 1

	var spr = get_node_or_null("Sprite")
	var shd = get_node_or_null("Shadow")
	if spr:
		if generation == 0:
			spr.texture = TEXTURE_SPLITTER
			spr.modulate = Color.WHITE
			spr.scale = Vector2(ENEMY_SPRITE_SCALE, ENEMY_SPRITE_SCALE)
		else:
			spr.texture = TEXTURE_SPLITTER_CHILD
			spr.modulate = Color.WHITE
			spr.scale = Vector2(ENEMY_CHILD_SCALE, ENEMY_CHILD_SCALE)
	if shd and spr:
		shd.texture = spr.texture
		shd.scale = spr.scale * SHADOW_SCALE_MULT

	DebugHelper.log_debug("Splitter spawned (gen %d) with word: %s" % [generation, word])

func spawn_splitter_children() -> void:
	var parent_container = get_parent()
	if parent_container == null:
		return

	# Load enemy scene
	var enemy_scene = load("res://scenes/entities/enemy_word.tscn")
	if enemy_scene == null:
		DebugHelper.log_error("Splitter: Failed to load enemy scene!")
		return

	# Spawn 2 children at offset positions
	var offsets = [Vector2(-30, -20), Vector2(30, -20)]

	for i in range(2):
		var child = enemy_scene.instantiate()
		child.position = global_position + offsets[i]

		# Children get shorter words (3-5 chars)
		var child_word = WordSetLoader.get_random_word({"min_length": 3, "max_length": 5})
		if child_word.is_empty():
			child_word = "BUG"  # Fallback

		child.setup_splitter(child_word, target, splitter_generation + 1)
		parent_container.add_child(child)

		# Visual effect - children fly outward briefly
		var tween = child.create_tween()
		tween.tween_property(child, "position", child.position + offsets[i] * 0.5, 0.2)

		SignalBus.enemy_spawned.emit(child)

	DebugHelper.log_debug("Splitter split into 2 children!")
	SoundManager.play_sfx("enemy_spawn")
