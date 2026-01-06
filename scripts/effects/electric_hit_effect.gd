## electric_hit_effect.gd
## Visual effect for Tesla Tower on enemies in range
## Shows electric zap animation on affected enemies
extends AnimatedSprite2D

const ANIMATION_FPS := 24.0
const SCALE_FACTOR := 0.6
const FRAME_WIDTH := 256
const FRAME_HEIGHT := 144
const TOTAL_FRAMES := 38
const SHEET_COLUMNS := 10

static var _sprite_frames: SpriteFrames = null
static var _frames_loaded: bool = false

func _ready() -> void:
	if not _frames_loaded:
		_load_sprite_frames()

	if _sprite_frames:
		sprite_frames = _sprite_frames

	animation_finished.connect(_on_animation_finished)

	scale = Vector2(SCALE_FACTOR, SCALE_FACTOR)
	rotation = randf_range(-PI, PI)

	if sprite_frames and sprite_frames.has_animation("zap"):
		play("zap")

func _on_animation_finished() -> void:
	queue_free()

static func _load_sprite_frames() -> void:
	if _frames_loaded:
		return

	_sprite_frames = SpriteFrames.new()

	var sheet_path := "res://assets/sprites/effects/electric-hit_sheet.png"
	var sheet_texture := load(sheet_path) as Texture2D

	if not sheet_texture:
		DebugHelper.log_error("ElectricHitEffect: Could not load spritesheet")
		return

	# Create atlas textures for each frame
	_sprite_frames.add_animation("zap")
	_sprite_frames.set_animation_speed("zap", ANIMATION_FPS)
	_sprite_frames.set_animation_loop("zap", false)

	for i in range(TOTAL_FRAMES):
		var col := i % SHEET_COLUMNS
		var row := i / SHEET_COLUMNS

		var atlas := AtlasTexture.new()
		atlas.atlas = sheet_texture
		atlas.region = Rect2(col * FRAME_WIDTH, row * FRAME_HEIGHT, FRAME_WIDTH, FRAME_HEIGHT)

		_sprite_frames.add_frame("zap", atlas)

	if _sprite_frames.has_animation("default"):
		_sprite_frames.remove_animation("default")

	_frames_loaded = true
	DebugHelper.log_info("ElectricHitEffect: Loaded %d frames" % TOTAL_FRAMES)

static func spawn_at(parent: Node, position: Vector2) -> void:
	var effect := preload("res://scenes/effects/electric_hit_effect.tscn").instantiate()
	effect.global_position = position
	parent.add_child(effect)
