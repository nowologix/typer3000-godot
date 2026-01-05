## enemy_word.gd
## Enemy entity that moves toward the portal with an attached word
extends CharacterBody2D
class_name EnemyWord

# Exported properties
@export var speed: float = 80.0
@export var damage: int = 1
@export var word: String = "TEST"

# Internal state
var target: Node2D = null
var alive: bool = true
var typed_progress: int = 0
var frozen: bool = false
var speed_multiplier: float = 1.0
var base_speed: float = 80.0

# Node references
@onready var word_label: Label = $WordLabel
@onready var sprite: ColorRect = $Sprite

func _ready() -> void:
	add_to_group("enemies")
	update_word_display()

func setup(new_word: String, portal_target: Node2D) -> void:
	word = new_word.to_upper()
	target = portal_target
	typed_progress = 0
	alive = true
	frozen = false
	speed_multiplier = 1.0
	base_speed = speed
	update_word_display()
	DebugHelper.log_debug("Enemy spawned with word: %s" % word)

func _physics_process(delta: float) -> void:
	if not alive or target == null or frozen:
		return

	# Move toward target with speed multiplier
	var direction = (target.global_position - global_position).normalized()
	var current_speed = base_speed * speed_multiplier
	velocity = direction * current_speed
	move_and_slide()

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

func apply_slow(amount: float, duration: float) -> void:
	speed_multiplier = amount
	# Create timer to restore speed
	var timer = get_tree().create_timer(duration)
	timer.timeout.connect(func(): speed_multiplier = 1.0)

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

	alive = false
	DebugHelper.log_debug("Enemy '%s' killed by typing" % word)

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

	if typed_progress > 0 and typed_progress < word.length():
		# Show typed portion in cyan, remaining in white
		var typed_part = word.substr(0, typed_progress)
		var remaining_part = word.substr(typed_progress)
		word_label.text = "[color=#00E5FF]%s[/color]%s" % [typed_part, remaining_part]
		# Enable BBCode if using RichTextLabel, otherwise just show plain
		# For simple Label, we'll use modulate instead
		word_label.text = word
		# Highlight the enemy when being typed
		if sprite:
			sprite.color = GameConfig.COLORS.cyan
	elif typed_progress >= word.length():
		word_label.text = word
		if sprite:
			sprite.color = GameConfig.COLORS.acid_green
	else:
		word_label.text = word
		if sprite:
			sprite.color = GameConfig.COLORS.magenta

func _on_tree_exiting() -> void:
	# Clean up any references
	target = null
