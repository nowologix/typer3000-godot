## portal.gd
## The portal that enemies try to reach - game over when HP reaches 0
extends Node2D

@export var max_hp: int = 20
var current_hp: int = 20
var shield_active: bool = false

@onready var sprite: ColorRect = $Sprite
@onready var hp_label: Label = $HPLabel

# Animated portal sprite
var animated_sprite: AnimatedSprite2D
var use_animated_sprite: bool = false

# Portal animation config
const PORTAL_SHEET_PATH := "res://assets/sprites/portal/portal_sheet.png"
const PORTAL_FRAME_SIZE := Vector2(256, 256)
const PORTAL_COLUMNS := 22
const PORTAL_TOTAL_FRAMES := 330
const PORTAL_FPS := 30.0
const PORTAL_SCALE := 0.5  # Scale down 256px to ~128px display

# Color thresholds
const HP_HEALTHY_THRESHOLD: float = 0.6
const HP_DAMAGED_THRESHOLD: float = 0.3

func _ready() -> void:
	add_to_group("portal")
	_setup_animated_sprite()

	# Connect powerup signals
	SignalBus.shield_activated.connect(_on_shield_activated)
	SignalBus.shield_deactivated.connect(_on_shield_deactivated)
	SignalBus.portal_heal.connect(_on_portal_heal)

	reset()

func _setup_animated_sprite() -> void:
	if not ResourceLoader.exists(PORTAL_SHEET_PATH):
		DebugHelper.log_debug("Portal spritesheet not found, using fallback")
		return

	var texture = load(PORTAL_SHEET_PATH)
	if texture == null:
		return

	# Create animated sprite
	animated_sprite = AnimatedSprite2D.new()
	animated_sprite.scale = Vector2(PORTAL_SCALE, PORTAL_SCALE)

	# Create sprite frames
	var frames = SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_speed("idle", PORTAL_FPS)
	frames.set_animation_loop("idle", true)

	# Extract frames from spritesheet
	for frame_idx in range(PORTAL_TOTAL_FRAMES):
		var atlas = AtlasTexture.new()
		atlas.atlas = texture
		var col = frame_idx % PORTAL_COLUMNS
		var row = frame_idx / PORTAL_COLUMNS
		atlas.region = Rect2(
			col * PORTAL_FRAME_SIZE.x,
			row * PORTAL_FRAME_SIZE.y,
			PORTAL_FRAME_SIZE.x,
			PORTAL_FRAME_SIZE.y
		)
		frames.add_frame("idle", atlas)

	animated_sprite.sprite_frames = frames
	animated_sprite.animation = "idle"
	add_child(animated_sprite)
	animated_sprite.play("idle")

	# Hide the fallback sprite
	if sprite:
		sprite.visible = false

	use_animated_sprite = true
	DebugHelper.log_info("Portal animated sprite loaded (%d frames)" % PORTAL_TOTAL_FRAMES)

func reset() -> void:
	max_hp = GameConfig.PORTAL_MAX_HEALTH
	current_hp = max_hp
	update_display()
	DebugHelper.log_debug("Portal reset: HP %d/%d" % [current_hp, max_hp])

func take_damage(damage: int) -> void:
	# Shield blocks all damage
	if shield_active:
		DebugHelper.log_debug("Portal shield blocked %d damage!" % damage)
		flash_shield()
		return

	current_hp = max(0, current_hp - damage)
	DebugHelper.log_debug("Portal took %d damage, HP: %d/%d" % [damage, current_hp, max_hp])

	SignalBus.portal_damaged.emit(damage, current_hp)
	update_display()

	# Flash effect
	flash_damage()

	# Visual effects
	if get_parent():
		EffectsManager.portal_hit_effect(global_position, get_parent())

	if current_hp <= 0:
		on_destroyed()

func flash_shield() -> void:
	if sprite == null:
		return

	# Blue flash for shield block
	var original_color = sprite.color
	sprite.color = Color(0.3, 0.5, 1.0)

	var tween = create_tween()
	tween.tween_property(sprite, "color", original_color, 0.3)

func _on_shield_activated(duration: float) -> void:
	shield_active = true
	DebugHelper.log_debug("Portal shield activated for %.1fs" % duration)

	# Visual indicator
	if sprite:
		sprite.modulate = Color(0.5, 0.7, 1.0, 1.0)

func _on_shield_deactivated() -> void:
	shield_active = false
	DebugHelper.log_debug("Portal shield deactivated")

	if sprite:
		sprite.modulate = Color.WHITE

func _on_portal_heal(amount: int) -> void:
	heal(amount)
	DebugHelper.log_info("Portal healed for %d HP" % amount)

func heal(amount: int) -> void:
	current_hp = min(max_hp, current_hp + amount)
	update_display()

func update_display() -> void:
	if hp_label:
		hp_label.text = "HP: %d/%d" % [current_hp, max_hp]

	var hp_ratio = float(current_hp) / float(max_hp)
	var color: Color

	if hp_ratio > HP_HEALTHY_THRESHOLD:
		color = GameConfig.COLORS.cyan
	elif hp_ratio > HP_DAMAGED_THRESHOLD:
		color = GameConfig.COLORS.amber
	else:
		color = GameConfig.COLORS.magenta

	# Apply color to appropriate sprite
	if use_animated_sprite and animated_sprite:
		animated_sprite.modulate = color
	elif sprite:
		sprite.color = color

func flash_damage() -> void:
	if use_animated_sprite and animated_sprite:
		var original_modulate = animated_sprite.modulate
		animated_sprite.modulate = Color.WHITE
		var tween = create_tween()
		tween.tween_property(animated_sprite, "modulate", original_modulate, 0.2)
	elif sprite:
		var original_color = sprite.color
		sprite.color = Color.WHITE
		var tween = create_tween()
		tween.tween_property(sprite, "color", original_color, 0.2)

func on_destroyed() -> void:
	DebugHelper.log_info("Portal destroyed!")
	SignalBus.portal_destroyed.emit()

	# Visual feedback
	if sprite:
		var tween = create_tween()
		tween.tween_property(sprite, "modulate:a", 0.0, 0.5)

func get_hp_ratio() -> float:
	return float(current_hp) / float(max_hp) if max_hp > 0 else 0.0
