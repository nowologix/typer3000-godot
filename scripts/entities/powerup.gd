## powerup.gd
## Collectible powerup that player types to activate
extends Node2D
class_name PowerUp

@export var word: String = "POWER"
@export var powerup_type: int = 0
@export var lifetime: float = 15.0  # Despawn after this time
@export var pulse_speed: float = 0.5

var typed_progress: int = 0
var alive: bool = true
var time_alive: float = 0.0
var base_scale: Vector2 = Vector2.ONE

# Animation properties
var sprite_sheet: Texture2D = null
var frame_width: int = 256
var frame_height: int = 256
var total_frames: int = 1
var columns: int = 1
var current_frame: int = 0
var frame_timer: float = 0.0
var fps: float = 24.0
var has_animated_sprite: bool = false

# Sprite sheet configurations
const SPRITE_SHEETS := {
	0: {"path": "res://assets/sprites/powerups/powerup_freeze_sheet.png", "frames": 42, "columns": 7, "fps": 24, "scale": 0.30},  # FREEZE (20% bigger)
	1: {"path": "res://assets/sprites/powerups/powerup_shield_sheet.png", "frames": 84, "columns": 10, "fps": 24, "scale": 0.25},  # SHIELD
	2: {"path": "res://assets/sprites/powerups/powerup_double_sheet.png", "frames": 60, "columns": 10, "fps": 24, "scale": 0.25},  # DOUBLE_SCORE
	3: {"path": "res://assets/sprites/powerups/powerup_heal_sheet.png", "frames": 72, "columns": 9, "fps": 24, "scale": 0.25},   # HEAL
	4: {"path": "res://assets/sprites/powerups/powerup_nuke_sheet.png", "frames": 120, "columns": 12, "fps": 24, "scale": 0.25},  # NUKE
	5: {"path": "res://assets/sprites/powerups/powerup_slow_sheet.png", "frames": 109, "columns": 11, "fps": 24, "scale": 0.25},  # SLOW_MO
	6: {"path": "res://assets/sprites/powerups/typer3000-magnet-icon.png", "frames": 1, "columns": 1, "fps": 1, "scale": 0.25}  # MAGNET
}

@onready var word_label: RichTextLabel = $WordLabel
@onready var sprite: Sprite2D = $Sprite
@onready var fallback_sprite: ColorRect = $FallbackSprite

func _ready() -> void:
	add_to_group("powerups")
	base_scale = scale

	# Initialize from meta if set dynamically
	if has_meta("powerup_type"):
		powerup_type = get_meta("powerup_type")
	if has_meta("powerup_word"):
		word = get_meta("powerup_word")

	# Load animated sprite sheet if available for this type
	_load_sprite_sheet()

	# Set fallback color if no sprite sheet
	if has_meta("powerup_color") and fallback_sprite and not has_animated_sprite:
		fallback_sprite.color = get_meta("powerup_color")
		fallback_sprite.visible = true
		if sprite:
			sprite.visible = false

	update_display()

func _load_sprite_sheet() -> void:
	if not SPRITE_SHEETS.has(powerup_type):
		has_animated_sprite = false
		return

	var config = SPRITE_SHEETS[powerup_type]
	sprite_sheet = _load_texture(config.path)

	if sprite_sheet and sprite:
		has_animated_sprite = true
		total_frames = config.frames
		columns = config.columns
		fps = config.fps

		# Setup sprite
		sprite.texture = sprite_sheet
		sprite.hframes = columns
		sprite.vframes = (total_frames + columns - 1) / columns
		sprite.frame = 0
		sprite.scale = Vector2(config.scale, config.scale)
		sprite.visible = true

		if fallback_sprite:
			fallback_sprite.visible = false

		DebugHelper.log_debug("PowerUp %s: Loaded sprite sheet with %d frames (scale: %.2f)" % [word, total_frames, config.scale])
	else:
		has_animated_sprite = false
		if fallback_sprite:
			fallback_sprite.visible = true
		if sprite:
			sprite.visible = false

func _load_texture(res_path: String) -> Texture2D:
	# Load PNG directly at runtime (bypasses import system to avoid errors)
	var abs_path = ProjectSettings.globalize_path(res_path)
	var image = Image.new()
	var err = image.load(abs_path)
	if err == OK:
		return ImageTexture.create_from_image(image)

	# Fallback: Try resource loader (for imported resources)
	if ResourceLoader.exists(res_path):
		var tex = load(res_path)
		if tex:
			return tex

	DebugHelper.log_warning("PowerUp: Failed to load texture: %s" % res_path)
	return null

func _process(delta: float) -> void:
	if not alive:
		return

	time_alive += delta

	# Animate sprite sheet
	if has_animated_sprite and sprite:
		frame_timer += delta
		if frame_timer >= 1.0 / fps:
			frame_timer = 0.0
			current_frame = (current_frame + 1) % total_frames
			sprite.frame = current_frame

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

	# Reload sprite sheet for new type
	_load_sprite_sheet()

	if fallback_sprite and not has_animated_sprite:
		fallback_sprite.color = color
		fallback_sprite.visible = true
		if sprite:
			sprite.visible = false

	update_display()

func get_word() -> String:
	return word

func is_alive() -> bool:
	return alive

func update_typed_progress(progress: int) -> void:
	typed_progress = progress
	update_display()

func update_display() -> void:
	if word_label == null:
		return

	# Show typed progress with color coding (like enemies)
	if typed_progress > 0 and typed_progress < word.length():
		var typed_part = word.substr(0, typed_progress)
		var remaining_part = word.substr(typed_progress)
		word_label.text = "[center][color=#00E5FF]%s[/color]%s[/center]" % [typed_part, remaining_part]
		# Brighten sprite when typing
		if has_animated_sprite and sprite:
			sprite.modulate = Color(1.5, 1.5, 1.5)
		elif fallback_sprite:
			fallback_sprite.modulate = Color(1.5, 1.5, 1.5)
	elif typed_progress >= word.length():
		word_label.text = "[center][color=#7CFF00]%s[/color][/center]" % word
		if has_animated_sprite and sprite:
			sprite.modulate = Color(1.5, 1.5, 1.5)
		elif fallback_sprite:
			fallback_sprite.modulate = Color(1.5, 1.5, 1.5)
	else:
		word_label.text = "[center]%s[/center]" % word
		if has_animated_sprite and sprite:
			sprite.modulate = Color.WHITE
		elif fallback_sprite:
			fallback_sprite.modulate = Color.WHITE

func collect() -> void:
	if not alive:
		DebugHelper.log_warning("PowerUp collect called but not alive!")
		return

	alive = false
	DebugHelper.log_info("PowerUp COLLECTED: word=%s, type=%d" % [word, powerup_type])

	# Visual feedback
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", base_scale * 1.5, 0.2)
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.chain().tween_callback(queue_free)

	# Notify powerup manager - this activates the effect!
	PowerUpManager.collect_powerup(powerup_type)

func despawn() -> void:
	if not alive:
		return

	alive = false
	DebugHelper.log_debug("PowerUp despawned: %s" % word)

	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)
