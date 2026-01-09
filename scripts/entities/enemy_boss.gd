## enemy_boss.gd
## Boss enemy entity that appears every 10 waves
## Uses aphorisms (sentences) instead of single words
## Has multiple HP and special visuals
extends CharacterBody2D
class_name EnemyBoss

# Exported properties
@export var speed: float = 30.0  # Slower than normal enemies
@export var damage: int = 5     # More damage to portal
@export var max_hp: int = 3     # Number of aphorisms to defeat boss

# Word property for TypingManager compatibility
var word: String:
	get:
		return current_aphorism
	set(value):
		current_aphorism = value

# Current aphorism
var current_aphorism: String = ""  # Clean text for typing (no spaces/punctuation)
var display_aphorism: String = ""   # Original text for display (with spaces)
var aphorism_author: String = ""
var typed_progress: int = 0

# Boss state
var target: Node2D = null
var alive: bool = true
var current_hp: int = 3
var boss_level: int = 1  # 1-4, determines aphorism difficulty
var frozen: bool = false
var speed_multiplier: float = 1.0
var base_speed: float = 30.0

# Visual state
var pulse_time: float = 0.0
var is_typing_active: bool = false

# Node references
@onready var word_label: RichTextLabel = $WordLabel
@onready var sprite: Sprite2D = $Sprite
@onready var hp_bar: ColorRect = $HPBar
@onready var hp_bar_bg: ColorRect = $HPBarBG
@onready var author_label: Label = $AuthorLabel
@onready var glow_effect: ColorRect = $GlowEffect

# Boss textures (different variants)
const BOSS_TEXTURES := [
	preload("res://assets/sprites/enemies/enemy_boss_01.png"),
	preload("res://assets/sprites/enemies/enemy_boss_02.png"),
	preload("res://assets/sprites/enemies/enemy_boss_03.png"),
	preload("res://assets/sprites/enemies/enemy_boss_04.png"),
	preload("res://assets/sprites/enemies/enemy_boss_05.png"),
]

# Signals
signal boss_phase_complete(boss: EnemyBoss, remaining_hp: int)
signal boss_defeated(boss: EnemyBoss)

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("bosses")
	_setup_visuals()
	load_next_aphorism()

func setup(portal_target: Node2D, level: int = 1) -> void:
	target = portal_target
	boss_level = clampi(level, 1, 4)
	current_hp = max_hp
	alive = true
	frozen = false
	speed_multiplier = 1.0
	base_speed = speed

	# Boss level affects HP
	match boss_level:
		1: max_hp = 2
		2: max_hp = 3
		3: max_hp = 4
		4: max_hp = 5
	current_hp = max_hp

	# Select random boss texture
	if sprite and BOSS_TEXTURES.size() > 0:
		var tex_index = randi() % BOSS_TEXTURES.size()
		sprite.texture = BOSS_TEXTURES[tex_index]
		sprite.modulate = Color.WHITE

	load_next_aphorism()
	update_hp_bar()
	DebugHelper.log_info("Boss spawned - Level %d, HP: %d" % [boss_level, max_hp])

func _setup_visuals() -> void:
	# Initial visual setup happens in _ready
	if glow_effect:
		glow_effect.modulate.a = 0.3

func load_next_aphorism() -> void:
	var aph = AphorismLoader.get_boss_aphorism(boss_level)

	# Keep full text with spaces and punctuation, just uppercase
	current_aphorism = aph.text.to_upper().strip_edges()
	display_aphorism = current_aphorism
	aphorism_author = aph.author
	typed_progress = 0
	update_word_display()
	update_author_display()
	DebugHelper.log_info("Boss aphorism: %s (%d chars)" % [current_aphorism, current_aphorism.length()])

func _physics_process(delta: float) -> void:
	if not alive or target == null or frozen:
		return

	# Move toward target with speed multiplier
	var direction = (target.global_position - global_position).normalized()
	var current_speed = base_speed * speed_multiplier
	velocity = direction * current_speed
	move_and_slide()

	# Rotate sprite toward movement direction (0° = up in sprite)
	if sprite and direction.length() > 0.1:
		var target_angle = direction.angle() + PI / 2
		sprite.rotation = target_angle

	# Check if reached portal
	var distance_to_target = global_position.distance_to(target.global_position)
	if distance_to_target < 60:  # Larger collision radius for boss
		reach_portal()

func _process(delta: float) -> void:
	# Pulsing glow effect
	pulse_time += delta
	if glow_effect:
		var pulse = (sin(pulse_time * 2.0) + 1.0) / 2.0
		glow_effect.modulate.a = 0.2 + pulse * 0.3

		# Color based on HP
		var hp_ratio = float(current_hp) / float(max_hp)
		if hp_ratio > 0.6:
			glow_effect.color = Color(1.0, 0.8, 0.0)  # Gold
		elif hp_ratio > 0.3:
			glow_effect.color = Color(1.0, 0.4, 0.0)  # Orange
		else:
			glow_effect.color = Color(1.0, 0.1, 0.1)  # Red

func set_frozen(freeze: bool) -> void:
	frozen = freeze
	if sprite:
		if frozen:
			sprite.modulate = Color(0.5, 0.8, 1.0)
		else:
			sprite.modulate = Color.WHITE

func set_speed_multiplier(multiplier: float) -> void:
	speed_multiplier = multiplier

func is_slowed() -> bool:
	return speed_multiplier < 1.0

func apply_slow(amount: float, duration: float) -> bool:
	if speed_multiplier < 1.0:
		return false

	speed_multiplier = amount
	var timer = get_tree().create_timer(duration)
	timer.timeout.connect(func(): speed_multiplier = 1.0)
	return true

func take_tower_damage(damage_amount: int) -> void:
	# Towers deal reduced damage to bosses (remove characters)
	if damage_amount > 0 and current_aphorism.length() > typed_progress:
		var chars_to_remove = min(damage_amount, current_aphorism.length() - typed_progress)
		typed_progress += chars_to_remove
		update_word_display()

		if typed_progress >= current_aphorism.length():
			complete_phase()

func complete_phase() -> void:
	# One aphorism defeated
	current_hp -= 1
	update_hp_bar()

	# Visual feedback
	_flash_boss()
	SoundManager.play_sfx("enemy_hit")

	boss_phase_complete.emit(self, current_hp)
	SignalBus.boss_phase_complete.emit(self, current_hp)
	DebugHelper.log_info("Boss phase complete! HP: %d/%d" % [current_hp, max_hp])

	if current_hp <= 0:
		die()
	else:
		# Load next aphorism
		load_next_aphorism()

func _flash_boss() -> void:
	if sprite:
		var original_modulate = sprite.modulate
		sprite.modulate = Color.WHITE
		await get_tree().create_timer(0.1).timeout
		if is_instance_valid(self) and sprite:
			sprite.modulate = original_modulate

func reach_portal() -> void:
	if not alive:
		return

	alive = false
	DebugHelper.log_info("Boss reached portal!")

	if target and target.has_method("take_damage"):
		target.take_damage(damage)

	SignalBus.enemy_reached_portal.emit(self)
	queue_free()

func die() -> void:
	if not alive:
		return

	alive = false
	DebugHelper.log_info("Boss defeated!")

	# Big effects for boss death
	if get_parent():
		EffectsManager.spawn_particles_burst(global_position, GameConfig.COLORS.amber, 20, get_parent())
		EffectsManager.screen_shake(10.0, 0.5)

	SoundManager.play_sfx("nuke_explosion")

	boss_defeated.emit(self)
	SignalBus.boss_defeated.emit(self)
	SignalBus.enemy_killed.emit(self, true)

	# Epic death animation
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.2)
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(queue_free)

func is_alive() -> bool:
	return alive

func get_word() -> String:
	return current_aphorism

func update_typed_progress(progress: int) -> void:
	typed_progress = progress
	update_word_display()

	# Check if current aphorism complete
	if typed_progress >= current_aphorism.length():
		complete_phase()

func update_word_display() -> void:
	if word_label == null:
		return

	is_typing_active = typed_progress > 0

	if typed_progress > 0 and typed_progress < current_aphorism.length():
		var typed_part = current_aphorism.substr(0, typed_progress)
		var remaining_part = current_aphorism.substr(typed_progress)
		word_label.text = "[center][color=#00E5FF]%s[/color]%s[/center]" % [typed_part, remaining_part]
		if sprite:
			# Subtle cyan tint when being typed
			sprite.modulate = Color(0.8, 1.0, 1.0)
	elif typed_progress >= current_aphorism.length():
		word_label.text = "[center][color=#00FF00]%s[/color][/center]" % current_aphorism
		if sprite:
			# Subtle green tint when complete
			sprite.modulate = Color(0.8, 1.0, 0.8)
	else:
		word_label.text = "[center]%s[/center]" % current_aphorism
		if sprite:
			sprite.modulate = Color.WHITE  # Normal boss appearance

func update_author_display() -> void:
	if author_label == null:
		return

	if aphorism_author.is_empty():
		author_label.visible = false
	else:
		author_label.visible = true
		author_label.text = "- %s" % aphorism_author

func update_hp_bar() -> void:
	if hp_bar == null or hp_bar_bg == null:
		return

	var hp_ratio = float(current_hp) / float(max_hp)
	hp_bar.size.x = hp_bar_bg.size.x * hp_ratio

	# Color based on HP
	if hp_ratio > 0.6:
		hp_bar.color = GameConfig.COLORS.acid_green
	elif hp_ratio > 0.3:
		hp_bar.color = GameConfig.COLORS.amber
	else:
		hp_bar.color = GameConfig.COLORS.magenta

func _on_tree_exiting() -> void:
	target = null
