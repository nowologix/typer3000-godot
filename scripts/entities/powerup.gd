## powerup.gd
## Collectible powerup that player types to activate
extends Node2D
class_name PowerUp

@export var word: String = "POWER"
@export var powerup_type: int = 0
@export var lifetime: float = 15.0  # Despawn after this time
@export var pulse_speed: float = 2.0

var typed_progress: int = 0
var alive: bool = true
var time_alive: float = 0.0
var base_scale: Vector2 = Vector2.ONE

@onready var word_label: Label = $WordLabel
@onready var sprite: ColorRect = $Sprite

func _ready() -> void:
	add_to_group("powerups")
	base_scale = scale

	# Initialize from meta if set dynamically
	if has_meta("powerup_type"):
		powerup_type = get_meta("powerup_type")
	if has_meta("powerup_word"):
		word = get_meta("powerup_word")
	if has_meta("powerup_color") and sprite:
		sprite.color = get_meta("powerup_color")

	update_display()

func _process(delta: float) -> void:
	if not alive:
		return

	time_alive += delta

	# Pulse animation
	var pulse = 1.0 + 0.1 * sin(time_alive * pulse_speed * TAU)
	scale = base_scale * pulse

	# Lifetime check
	if time_alive >= lifetime:
		despawn()

	# Flash warning when about to despawn
	if lifetime - time_alive < 3.0:
		var flash = 0.5 + 0.5 * sin(time_alive * 10.0)
		modulate.a = flash

func setup(new_word: String, type: int, color: Color) -> void:
	word = new_word
	powerup_type = type
	typed_progress = 0
	alive = true
	time_alive = 0.0

	if sprite:
		sprite.color = color

	update_display()

func get_word() -> String:
	return word

func is_alive() -> bool:
	return alive

func update_typed_progress(progress: int) -> void:
	typed_progress = progress
	update_display()

func update_display() -> void:
	if word_label:
		word_label.text = word

		# Highlight typed portion
		if typed_progress > 0 and typed_progress < word.length():
			# Show progress with color
			if sprite:
				sprite.modulate = Color(1.5, 1.5, 1.5)  # Brighten
		else:
			if sprite:
				sprite.modulate = Color.WHITE

func collect() -> void:
	if not alive:
		return

	alive = false
	DebugHelper.log_debug("PowerUp collected: %s" % word)

	# Visual feedback
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", base_scale * 1.5, 0.2)
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.chain().tween_callback(queue_free)

	# Notify powerup manager
	PowerUpManager.collect_powerup(powerup_type)

func despawn() -> void:
	if not alive:
		return

	alive = false
	DebugHelper.log_debug("PowerUp despawned: %s" % word)

	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)
