## magnet.gd
## Placeable magnet that deflects enemy movement
## Enemies are gently pulled toward magnet but not trapped
## Uses animated sprite that rotates faster with more enemies in range
extends Node2D

const MAGNET_RADIUS: float = 180.0  # Attraction range
const MAGNET_FORCE: float = 40.0  # Pull strength (gentle deflection)
const BEAM_SEGMENTS: int = 6  # Number of tractor beam lines

# Rotation speed constants
const BASE_ROTATION_SPEED: float = 0.3  # Radians per second when no enemies
const MAX_ROTATION_SPEED: float = 4.0  # Maximum rotation speed
const ROTATION_SPEED_PER_ENEMY: float = 0.5  # Additional speed per enemy in range

var duration: float = 60.0  # 1 minute lifetime
var time_remaining: float = 60.0
var is_active: bool = true

# Visual state
var pulse_phase: float = 0.0
var affected_enemies: Array = []  # Track enemies for beam effect
var current_rotation: float = 0.0

# Sprite
var sprite: AnimatedSprite2D = null

# Colors
const COLOR_MAGNET := Color(0.9, 0.2, 0.6, 1.0)  # Magenta/pink
const COLOR_BEAM := Color(0.9, 0.3, 0.7, 0.4)  # Semi-transparent beam
const COLOR_BEAM_BRIGHT := Color(1.0, 0.4, 0.8, 0.6)
const COLOR_RANGE := Color(0.9, 0.2, 0.6, 0.15)  # Very faint range indicator

func _ready() -> void:
	add_to_group("magnets")
	z_index = 5
	_setup_sprite()

func _setup_sprite() -> void:
	# Create SpriteFrames for the animation
	var frames = SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_loop("idle", true)
	frames.set_animation_speed("idle", 24.0)  # 24 FPS

	var frame_count = 0
	for i in range(111):
		var path = "res://assets/sprites/magnet/typer3000-freeze-turret-01_%03d.png" % i
		var tex = load(path)
		if tex:
			frames.add_frame("idle", tex)
			frame_count += 1

	if frame_count == 0:
		DebugHelper.log_warning("Magnet: No sprite frames loaded!")
		return

	# Create animated sprite
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.animation = "idle"
	sprite.centered = true
	sprite.scale = Vector2(0.4, 0.4)  # Scale down to fit
	sprite.z_index = 1
	add_child(sprite)
	sprite.play()

	DebugHelper.log_info("Magnet sprite loaded: %d frames" % frame_count)

func _process(delta: float) -> void:
	if not is_active:
		return

	# Update lifetime
	time_remaining -= delta
	if time_remaining <= 0:
		expire()
		return

	# Update visual pulse for beam effect
	pulse_phase += delta * 2.0
	if pulse_phase > TAU:
		pulse_phase -= TAU

	# Apply magnetic force to enemies
	apply_magnetic_force(delta)

	# Rotate sprite based on enemy count
	update_rotation(delta)

	# Redraw beams and effects
	queue_redraw()

func update_rotation(delta: float) -> void:
	if sprite == null:
		return

	# Calculate rotation speed based on affected enemies
	var enemy_count = affected_enemies.size()
	var rotation_speed = BASE_ROTATION_SPEED + (enemy_count * ROTATION_SPEED_PER_ENEMY)
	rotation_speed = min(rotation_speed, MAX_ROTATION_SPEED)

	# Rotate clockwise (positive direction in Godot)
	current_rotation += rotation_speed * delta
	if current_rotation > TAU:
		current_rotation -= TAU

	sprite.rotation = current_rotation

func apply_magnetic_force(delta: float) -> void:
	affected_enemies.clear()

	var enemies = get_tree().get_nodes_in_group("enemies")

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if not enemy.has_method("is_alive") or not enemy.is_alive():
			continue

		var distance = global_position.distance_to(enemy.global_position)

		# Only affect enemies within magnet radius
		if distance > MAGNET_RADIUS or distance < 10:
			continue

		# Track for visual effect
		affected_enemies.append(enemy)

		# Calculate pull direction (toward magnet)
		var direction = (global_position - enemy.global_position).normalized()

		# Force falls off with distance (inverse relationship, not too strong)
		# Closer = stronger pull, but capped to prevent orbiting
		var distance_factor = 1.0 - (distance / MAGNET_RADIUS)
		var force_strength = MAGNET_FORCE * distance_factor * distance_factor

		# Apply as velocity modification (not direct position change)
		# This creates a gentle deflection rather than snapping
		if enemy.has_method("apply_external_force"):
			enemy.apply_external_force(direction * force_strength)
		else:
			# Fallback: direct position adjustment (gentler)
			enemy.global_position += direction * force_strength * delta * 0.5

func expire() -> void:
	is_active = false

	# Fade out animation
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(queue_free)

func _draw() -> void:
	if not is_active:
		return

	# Draw range indicator (faint circle)
	draw_arc(Vector2.ZERO, MAGNET_RADIUS, 0, TAU, 64, COLOR_RANGE, 2.0)

	# Draw tractor beams to affected enemies
	for enemy in affected_enemies:
		if is_instance_valid(enemy):
			draw_tractor_beam(enemy.global_position - global_position)

	# Draw remaining time indicator ring
	draw_timer_ring()

func draw_tractor_beam(target_offset: Vector2) -> void:
	var distance = target_offset.length()
	if distance < 30:  # Don't draw beam if too close
		return

	var direction = target_offset.normalized()

	# Draw multiple wavy beam lines
	for i in range(BEAM_SEGMENTS):
		var phase_offset = float(i) / BEAM_SEGMENTS * TAU
		var wave_amplitude = 6.0 + sin(pulse_phase * 3 + phase_offset) * 3.0

		# Create wavy line from magnet to enemy
		var points: PackedVector2Array = []
		var segments = 10

		for j in range(segments + 1):
			var t = float(j) / segments
			# Start beam from edge of sprite (about 30px out)
			var start_offset = 30.0
			var beam_distance = distance - start_offset
			var base_pos = direction * (start_offset + beam_distance * t)

			# Add perpendicular wave
			var perp = Vector2(-direction.y, direction.x)
			var wave = sin(t * PI * 3 + pulse_phase * 2 + phase_offset) * wave_amplitude * (1.0 - t * 0.5)

			points.append(base_pos + perp * wave)

		# Draw with varying alpha based on phase
		var alpha = 0.25 + sin(pulse_phase + phase_offset) * 0.1
		var beam_color = Color(COLOR_BEAM.r, COLOR_BEAM.g, COLOR_BEAM.b, alpha)

		if points.size() > 1:
			draw_polyline(points, beam_color, 2.0, true)

func draw_timer_ring() -> void:
	# Draw remaining time as arc around magnet
	var progress = time_remaining / duration
	var arc_radius = 45.0  # Slightly outside sprite

	# Background ring (dark)
	draw_arc(Vector2.ZERO, arc_radius, 0, TAU, 32, Color(0.2, 0.1, 0.15, 0.4), 3.0)

	# Progress ring (starts at top, goes clockwise)
	if progress > 0:
		var start_angle = -PI / 2
		var end_angle = start_angle + TAU * progress
		var segments = max(int(32 * progress), 2)
		draw_arc(Vector2.ZERO, arc_radius, start_angle, end_angle, segments, COLOR_BEAM_BRIGHT, 3.0)

func get_remaining_time() -> float:
	return time_remaining

func get_affected_count() -> int:
	return affected_enemies.size()
