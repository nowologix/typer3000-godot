## player.gd
## The player character that can move around the screen
extends CharacterBody2D

@export var max_hp: int = 20
@export var speed: float = 200.0
@export var radius: float = 15.0

var current_hp: int = 20
var invincibility_frames: int = 0
var movement_enabled: bool = true  # For COOP: only P2 can move
var is_tower_defence_mode: bool = false  # TD mode: invisible cursor only

@onready var sprite: Sprite2D = $Sprite
@onready var hp_bar: ColorRect = $HPBar
@onready var hp_bar_fill: ColorRect = $HPBar/Fill
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var shadow: Sprite2D = $Shadow

func _ready() -> void:
	add_to_group("player")
	SignalBus.player_healed.connect(_on_player_healed)
	reset()

func _on_player_healed(amount: int) -> void:
	heal(amount)

func setup_tower_defence_mode() -> void:
	is_tower_defence_mode = true
	# Hide visual elements - player becomes invisible cursor
	if sprite:
		sprite.visible = false
	if shadow:
		shadow.visible = false
	if hp_bar:
		hp_bar.visible = false
	# Disable collision - player can't be hit
	if collision_shape:
		collision_shape.disabled = true

func reset() -> void:
	current_hp = max_hp
	invincibility_frames = 0
	is_tower_defence_mode = false
	# Reset visibility (in case coming from TD mode)
	if sprite:
		sprite.visible = true
	if shadow:
		shadow.visible = true
	if hp_bar:
		hp_bar.visible = true
	if collision_shape:
		collision_shape.disabled = false
	update_display()

func _physics_process(delta: float) -> void:
	# Handle movement input (arrow keys only) - only if movement is enabled
	var input_dir = Vector2.ZERO

	if movement_enabled:
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

	# Handle invincibility frames (skip in TD mode - no visual player)
	if is_tower_defence_mode:
		return

	if invincibility_frames > 0:
		invincibility_frames -= 1
		# Blink effect
		if sprite:
			sprite.visible = (invincibility_frames / 5) % 2 == 0
	elif sprite and not sprite.visible:
		sprite.visible = true

func take_damage(damage: int) -> void:
	# No damage in Tower Defence mode
	if is_tower_defence_mode:
		return

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

	var original_modulate = sprite.modulate
	sprite.modulate = Color.WHITE

	var tween = create_tween()
	tween.tween_property(sprite, "modulate", original_modulate, 0.2)

func on_death() -> void:
	DebugHelper.log_info("Player died!")
	SignalBus.player_died.emit()

func get_hp_ratio() -> float:
	return float(current_hp) / float(max_hp) if max_hp > 0 else 0.0
