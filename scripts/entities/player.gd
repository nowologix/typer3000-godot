## player.gd
## The player character that can move around the screen
extends CharacterBody2D

@export var max_hp: int = 5
@export var speed: float = 200.0
@export var radius: float = 15.0

var current_hp: int = 5
var invincibility_frames: int = 0

@onready var sprite: ColorRect = $Sprite
@onready var hp_bar: ColorRect = $HPBar
@onready var hp_bar_fill: ColorRect = $HPBar/Fill
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("player")
	reset()

func reset() -> void:
	current_hp = max_hp
	invincibility_frames = 0
	update_display()

func _physics_process(delta: float) -> void:
	# Handle movement input (arrow keys only)
	var input_dir = Vector2.ZERO

	if Input.is_key_pressed(KEY_UP):
		input_dir.y -= 1
	if Input.is_key_pressed(KEY_DOWN):
		input_dir.y += 1
	if Input.is_key_pressed(KEY_LEFT):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_RIGHT):
		input_dir.x += 1

	# Normalize diagonal movement
	if input_dir.length() > 0:
		input_dir = input_dir.normalized()

	velocity = input_dir * speed
	move_and_slide()

	# Keep player in bounds
	position.x = clamp(position.x, radius, GameConfig.SCREEN_WIDTH - radius)
	position.y = clamp(position.y, radius, GameConfig.SCREEN_HEIGHT - radius)

	# Handle invincibility frames
	if invincibility_frames > 0:
		invincibility_frames -= 1
		# Blink effect
		if sprite:
			sprite.visible = (invincibility_frames / 5) % 2 == 0
	elif sprite and not sprite.visible:
		sprite.visible = true

func take_damage(damage: int) -> void:
	if invincibility_frames > 0:
		return

	current_hp = max(0, current_hp - damage)
	invincibility_frames = 60  # 1 second at 60 FPS

	DebugHelper.log_debug("Player took %d damage, HP: %d/%d" % [damage, current_hp, max_hp])
	SignalBus.player_damaged.emit(damage, current_hp)

	update_display()
	flash_damage()

	if current_hp <= 0:
		on_death()

func heal(amount: int) -> void:
	current_hp = min(max_hp, current_hp + amount)
	update_display()

func update_display() -> void:
	if hp_bar_fill:
		var ratio = float(current_hp) / float(max_hp)
		hp_bar_fill.size.x = 30 * ratio

		# Color based on health
		if ratio > 0.5:
			hp_bar_fill.color = GameConfig.COLORS.acid_green
		elif ratio > 0.25:
			hp_bar_fill.color = GameConfig.COLORS.amber
		else:
			hp_bar_fill.color = GameConfig.COLORS.magenta

func flash_damage() -> void:
	if sprite == null:
		return

	var original_color = sprite.color
	sprite.color = Color.WHITE

	var tween = create_tween()
	tween.tween_property(sprite, "color", original_color, 0.2)

func on_death() -> void:
	DebugHelper.log_info("Player died!")
	SignalBus.player_died.emit()

func get_hp_ratio() -> float:
	return float(current_hp) / float(max_hp) if max_hp > 0 else 0.0
