## effects_manager.gd
## Handles visual effects like particles, screen shake, hit effects, etc.
extends Node

# Screen shake parameters
var shake_intensity: float = 0.0
var shake_decay: float = 5.0
var shake_offset: Vector2 = Vector2.ZERO

# Camera reference (set after game state loads)
var camera: Camera2D = null

# Hit effect textures (loaded on ready)
var hit_textures: Array[Texture2D] = []
var hit_index: int = 0

# Hit effect configuration
const HIT_FRAME_SIZE := Vector2(256, 256)
const HIT_COLUMNS := 10
const HIT_TOTAL_FRAMES := 19
const HIT_FPS := 45.0
const HIT_SCALE := 0.5  # Scale down for display

# Tower placement effect configuration
const TOWER_PLACE_FRAME_SIZE := Vector2(256, 256)
const TOWER_PLACE_COLUMNS := 10
const TOWER_PLACE_TOTAL_FRAMES := 74
const TOWER_PLACE_FPS := 30.0
const TOWER_PLACE_SCALE := 0.5  # Scale for tower placement effect
var tower_place_texture: Texture2D = null

func _ready() -> void:
	_load_hit_textures()
	_load_tower_place_texture()
	if hit_textures.size() > 0:
		DebugHelper.log_info("EffectsManager loaded %d hit effects" % hit_textures.size())

func _load_hit_textures() -> void:
	for i in range(1, 9):
		var path = "res://assets/sprites/effects/hit_%d.png" % i
		if ResourceLoader.exists(path):
			hit_textures.append(load(path))
		else:
			DebugHelper.log_debug("Hit effect not found: %s" % path)

func _load_tower_place_texture() -> void:
	var path = "res://assets/sprites/effects/tower_place_effect_sheet.png"
	tower_place_texture = _load_image_direct(path)
	if tower_place_texture:
		DebugHelper.log_info("EffectsManager: Tower placement effect loaded")
	else:
		DebugHelper.log_warning("EffectsManager: Failed to load tower placement effect")

func _load_image_direct(res_path: String) -> ImageTexture:
	# Load PNG directly at runtime (bypasses import system)
	var abs_path = ProjectSettings.globalize_path(res_path)
	var image = Image.new()
	var err = image.load(abs_path)
	if err == OK:
		return ImageTexture.create_from_image(image)
	# Fallback: Try resource loader
	if ResourceLoader.exists(res_path):
		var tex = load(res_path)
		if tex:
			return tex
	return null

func _process(delta: float) -> void:
	# Apply screen shake decay
	if shake_intensity > 0:
		shake_intensity = max(0, shake_intensity - shake_decay * delta)
		shake_offset = Vector2(
			randf_range(-shake_intensity, shake_intensity),
			randf_range(-shake_intensity, shake_intensity)
		)
		if camera:
			camera.offset = shake_offset
	elif shake_offset != Vector2.ZERO:
		shake_offset = Vector2.ZERO
		if camera:
			camera.offset = Vector2.ZERO

func screen_shake(intensity: float, duration: float = 0.3) -> void:
	shake_intensity = max(shake_intensity, intensity)
	shake_decay = intensity / duration

func spawn_text_popup(position: Vector2, text: String, color: Color, parent: Node) -> void:
	# Create floating text that rises and fades
	var label = Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.z_index = 100
	parent.add_child(label)

	# Animate
	var tween = label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", position.y - 50, 0.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.chain().tween_callback(label.queue_free)

func spawn_score_popup(position: Vector2, score: int, parent: Node) -> void:
	var color = GameConfig.COLORS.acid_green if score > 0 else GameConfig.COLORS.magenta
	var text = "+%d" % score if score > 0 else str(score)
	spawn_text_popup(position, text, color, parent)

func spawn_combo_popup(position: Vector2, combo: int, parent: Node) -> void:
	if combo >= 5:
		var text = "%dx COMBO!" % combo
		var color = GameConfig.COLORS.amber if combo < 10 else GameConfig.COLORS.cyan
		spawn_text_popup(position, text, color, parent)

func spawn_particles_burst(position: Vector2, color: Color, count: int, parent: Node) -> void:
	# Simple particle burst using labels as "particles"
	# ASSUMPTION: CPUParticles2D would be better but requires more setup
	for i in range(count):
		var particle = ColorRect.new()
		particle.size = Vector2(4, 4)
		particle.color = color
		particle.position = position - Vector2(2, 2)
		particle.z_index = 50
		parent.add_child(particle)

		# Random direction
		var angle = randf() * TAU
		var speed = randf_range(100, 200)
		var velocity = Vector2(cos(angle), sin(angle)) * speed
		var end_pos = position + velocity * 0.5

		var tween = particle.create_tween()
		tween.set_parallel(true)
		tween.tween_property(particle, "position", end_pos, 0.5)
		tween.tween_property(particle, "modulate:a", 0.0, 0.5)
		tween.chain().tween_callback(particle.queue_free)

func spawn_hit_effect(position: Vector2, parent: Node) -> void:
	if hit_textures.is_empty():
		# Fallback to particles if no hit textures
		spawn_particles_burst(position, GameConfig.COLORS.acid_green, 8, parent)
		return

	# Get next hit texture (cycle through all 8)
	var texture = hit_textures[hit_index]
	hit_index = (hit_index + 1) % hit_textures.size()

	# Create animated sprite
	var effect = AnimatedSprite2D.new()
	effect.position = position
	effect.z_index = 100  # Above most things
	effect.scale = Vector2(HIT_SCALE, HIT_SCALE)

	# Create sprite frames from the texture
	var frames = SpriteFrames.new()
	frames.add_animation("hit")
	frames.set_animation_speed("hit", HIT_FPS)
	frames.set_animation_loop("hit", false)

	# Extract frames from spritesheet
	for frame_idx in range(HIT_TOTAL_FRAMES):
		var atlas = AtlasTexture.new()
		atlas.atlas = texture
		var col = frame_idx % HIT_COLUMNS
		var row = frame_idx / HIT_COLUMNS
		atlas.region = Rect2(
			col * HIT_FRAME_SIZE.x,
			row * HIT_FRAME_SIZE.y,
			HIT_FRAME_SIZE.x,
			HIT_FRAME_SIZE.y
		)
		frames.add_frame("hit", atlas)

	effect.sprite_frames = frames
	effect.animation = "hit"

	# Use additive blending for glow effect
	effect.material = CanvasItemMaterial.new()
	effect.material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	# Add to scene
	parent.add_child(effect)

	# Play and auto-remove
	effect.play("hit")
	effect.animation_finished.connect(func(): effect.queue_free())

func enemy_death_effect(enemy_position: Vector2, parent: Node) -> void:
	# Spawn hit animation effect
	spawn_hit_effect(enemy_position, parent)
	# Also spawn some particles
	spawn_particles_burst(enemy_position, GameConfig.COLORS.acid_green, 4, parent)

func portal_hit_effect(portal_position: Vector2, parent: Node) -> void:
	spawn_particles_burst(portal_position, GameConfig.COLORS.magenta, 12, parent)
	screen_shake(5.0, 0.2)

func word_complete_effect(position: Vector2, word: String, combo: int, parent: Node) -> void:
	# Particles
	spawn_particles_burst(position, GameConfig.COLORS.cyan, 6, parent)

	# Score popup
	var score = word.length() * 10 + combo * 5
	spawn_score_popup(position + Vector2(0, -20), score, parent)

	# Combo popup (only for significant combos)
	if combo >= 5 and combo % 5 == 0:
		spawn_combo_popup(position + Vector2(0, -50), combo, parent)

func spawn_tower_place_effect(position: Vector2, parent: Node) -> void:
	if tower_place_texture == null:
		# Fallback to particles if no texture
		spawn_particles_burst(position, GameConfig.COLORS.cyan, 12, parent)
		return

	# Create animated sprite
	var effect = AnimatedSprite2D.new()
	effect.position = position
	effect.z_index = 50  # Below UI but above game elements
	effect.scale = Vector2(TOWER_PLACE_SCALE, TOWER_PLACE_SCALE)

	# Create sprite frames from the texture
	var frames = SpriteFrames.new()
	frames.add_animation("place")
	frames.set_animation_speed("place", TOWER_PLACE_FPS)
	frames.set_animation_loop("place", false)

	# Extract frames from spritesheet
	for frame_idx in range(TOWER_PLACE_TOTAL_FRAMES):
		var atlas = AtlasTexture.new()
		atlas.atlas = tower_place_texture
		var col = frame_idx % TOWER_PLACE_COLUMNS
		var row = frame_idx / TOWER_PLACE_COLUMNS
		atlas.region = Rect2(
			col * TOWER_PLACE_FRAME_SIZE.x,
			row * TOWER_PLACE_FRAME_SIZE.y,
			TOWER_PLACE_FRAME_SIZE.x,
			TOWER_PLACE_FRAME_SIZE.y
		)
		frames.add_frame("place", atlas)

	effect.sprite_frames = frames
	effect.animation = "place"

	# Use additive blending for glow effect
	effect.material = CanvasItemMaterial.new()
	effect.material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	# Add to scene
	parent.add_child(effect)

	# Play and auto-remove
	effect.play("place")
	effect.animation_finished.connect(func(): effect.queue_free())
