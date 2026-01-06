## blue_hit_effect.gd
## Visual effect for GUN turret hits on enemies
## Plays a random blue hit splash animation then self-destructs
extends AnimatedSprite2D

const ANIMATION_FPS := 30.0  # Animation playback speed
const SCALE_FACTOR := 0.5  # Scale down from 256x256 to fit enemies

# Animation data: name -> frame count
const ANIMATIONS := {
	"splash_1": 40,
	"splash_2": 52,
	"splash_3": 49,
	"splash_4": 62,
	"splash_5": 57,
}

static var _sprite_frames: SpriteFrames = null
static var _frames_loaded: bool = false

func _ready() -> void:
	# Load sprite frames if not already loaded
	if not _frames_loaded:
		_load_sprite_frames()

	if _sprite_frames:
		sprite_frames = _sprite_frames

	# Random animation
	var anim_names = ANIMATIONS.keys()
	var random_anim = anim_names[randi() % anim_names.size()]

	# Connect to animation finished
	animation_finished.connect(_on_animation_finished)

	# Apply scale
	scale = Vector2(SCALE_FACTOR, SCALE_FACTOR)

	# Slight random rotation for variety
	rotation = randf_range(-0.3, 0.3)

	# Start playing
	play(random_anim)

func _on_animation_finished() -> void:
	queue_free()

static func _load_sprite_frames() -> void:
	if _frames_loaded:
		return

	_sprite_frames = SpriteFrames.new()

	var base_path := "res://assets/sprites/effects/blue_hits/"

	for anim_name in ANIMATIONS:
		var frame_count: int = ANIMATIONS[anim_name]
		var file_prefix: String

		# Map animation name to file prefix
		match anim_name:
			"splash_1": file_prefix = "blue-hit-splash-1_"
			"splash_2": file_prefix = "blue-hit-splash-2_"
			"splash_3": file_prefix = "blue-hit-splash-3_"
			"splash_4": file_prefix = "blue-hit-splash-4_"
			"splash_5": file_prefix = "blue-hit-splash-5_"

		# Add animation
		_sprite_frames.add_animation(anim_name)
		_sprite_frames.set_animation_speed(anim_name, ANIMATION_FPS)
		_sprite_frames.set_animation_loop(anim_name, false)

		# Load frames directly from file (bypasses import system)
		var frames_loaded_count := 0
		for i in range(frame_count):
			var frame_path := "%s%s%02d.png" % [base_path, file_prefix, i]
			var texture := _load_texture_direct(frame_path)

			if texture:
				_sprite_frames.add_frame(anim_name, texture)
				frames_loaded_count += 1

		if frames_loaded_count == 0:
			push_warning("BlueHitEffect: No frames loaded for %s" % anim_name)

	# Remove default animation if it exists
	if _sprite_frames.has_animation("default"):
		_sprite_frames.remove_animation("default")

	_frames_loaded = true
	DebugHelper.log_info("BlueHitEffect: Loaded %d animations" % ANIMATIONS.size())

# Load texture directly from file without requiring Godot import
static func _load_texture_direct(res_path: String) -> ImageTexture:
	# Convert res:// to absolute path for direct file loading
	var absolute_path := ProjectSettings.globalize_path(res_path)

	if not FileAccess.file_exists(absolute_path):
		return null

	# Load image directly from file
	var image := Image.new()
	var err := image.load(absolute_path)
	if err != OK:
		return null

	# Create texture from image
	return ImageTexture.create_from_image(image)

# Factory method to spawn a hit effect at position
static func spawn_at(parent: Node, position: Vector2) -> void:
	var effect := preload("res://scenes/effects/blue_hit_effect.tscn").instantiate()
	effect.global_position = position
	parent.add_child(effect)
