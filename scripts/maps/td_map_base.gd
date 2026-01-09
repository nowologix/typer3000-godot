## td_map_base.gd
## Base class for Tower Defence maps
## Handles coordinate system for ultrawide support
extends Node2D

# Map image dimensions (21:9 ultrawide at 1440p)
const MAP_WIDTH: float = 3440.0
const MAP_HEIGHT: float = 1440.0

# Core area dimensions (16:9 centered within the map)
const CORE_WIDTH: float = 2560.0   # 1440 * (16/9)
const CORE_HEIGHT: float = 1440.0

# Core area offset within the map image
const CORE_OFFSET_X: float = 440.0  # (3440 - 2560) / 2

# Map elements (set in scene)
@onready var background: Sprite2D = $Background
@onready var overlay: Sprite2D = $Overlay  # Tree canopies, bridges - rendered on top
@onready var enemy_path: Path2D = $EnemyPath
@onready var spawn_point: Marker2D = $SpawnPoint
@onready var portal_point: Marker2D = $PortalPoint
@onready var build_zones: Node2D = $BuildZones

# Z-index layers
const Z_BACKGROUND: int = 0
const Z_PATH_VISUAL: int = -50
const Z_GAME_OBJECTS: int = 0  # Enemies, towers, portal
const Z_OVERLAY: int = 100     # Tree canopies, foreground elements

# Calculated at runtime
var screen_width: float = 1280.0
var screen_height: float = 720.0
var core_offset_x: float = 0.0  # Offset to center the core area

func _ready() -> void:
	update_layout()
	get_viewport().size_changed.connect(_on_viewport_size_changed)

func _on_viewport_size_changed() -> void:
	update_layout()

func update_layout() -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	screen_width = viewport_size.x
	screen_height = viewport_size.y

	# Calculate where the 16:9 core starts (centered)
	core_offset_x = (screen_width - CORE_WIDTH) / 2.0

	# Only set z-indices - positioning handled by tower_defence_state.gd
	if background:
		background.z_index = Z_BACKGROUND
	if overlay:
		overlay.z_index = Z_OVERLAY

	DebugHelper.log_info("TD Map layout updated: screen=%.0fx%.0f, core_offset=%.0f" % [screen_width, screen_height, core_offset_x])

# Convert core-relative position to screen position
# Use this for path points, spawn, portal
func core_to_screen(core_pos: Vector2) -> Vector2:
	return Vector2(core_pos.x + core_offset_x, core_pos.y)

# Convert screen position to core-relative position
func screen_to_core(screen_pos: Vector2) -> Vector2:
	return Vector2(screen_pos.x - core_offset_x, screen_pos.y)

# Check if a screen position is within the core area
func is_in_core(screen_pos: Vector2) -> bool:
	var core_pos = screen_to_core(screen_pos)
	return core_pos.x >= 0 and core_pos.x <= CORE_WIDTH and core_pos.y >= 0 and core_pos.y <= CORE_HEIGHT

# Get the path for enemies to follow
func get_enemy_path() -> Path2D:
	return enemy_path

# Get spawn position (screen coordinates)
func get_spawn_position() -> Vector2:
	if spawn_point:
		return spawn_point.global_position
	return core_to_screen(Vector2(-50, CORE_HEIGHT / 2))

# Get portal/goal position (screen coordinates)
func get_portal_position() -> Vector2:
	if portal_point:
		return portal_point.global_position
	return core_to_screen(Vector2(CORE_WIDTH + 50, CORE_HEIGHT / 2))

# Check if a position is valid for building
func can_build_at(screen_pos: Vector2) -> bool:
	if not build_zones:
		return false

	for zone in build_zones.get_children():
		if zone is Area2D:
			# Check if point is inside the area
			var space_state = get_world_2d().direct_space_state
			var query = PhysicsPointQueryParameters2D.new()
			query.position = screen_pos
			query.collide_with_areas = true
			query.collision_mask = zone.collision_mask
			var result = space_state.intersect_point(query, 1)
			if result.size() > 0:
				return true
	return false

# Get all build zone polygons (for visual highlighting)
func get_build_zone_polygons() -> Array:
	var polygons = []
	if build_zones:
		for zone in build_zones.get_children():
			if zone is Polygon2D:
				polygons.append(zone)
			elif zone.has_node("Polygon"):
				polygons.append(zone.get_node("Polygon"))
	return polygons
