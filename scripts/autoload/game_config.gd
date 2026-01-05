## game_config.gd
## Global game configuration and constants
## Autoload singleton: GameConfig
extends Node

# Screen dimensions (base resolution)
const SCREEN_WIDTH: int = 1280
const SCREEN_HEIGHT: int = 720
const BASE_FONT_SIZE: int = 16

# Game states
enum GameStates {
	MENU,
	GAME,
	PAUSE,
	GAME_OVER,
	SETTINGS,
	LOBBY,
	WORDWAR
}

# Portal settings
const PORTAL_MAX_HEALTH: int = 20
const PORTAL_POSITION := Vector2(SCREEN_WIDTH / 2, SCREEN_HEIGHT - 80)

# Enemy settings
const ENEMY_BASE_SPEED: float = 80.0
const ENEMY_SPAWN_MARGIN: int = 50
const ENEMY_SPAWN_Y_MIN: int = 50
const ENEMY_SPAWN_Y_MAX: int = 200

# Typing settings
const WORD_LOCK_TIMEOUT: float = 5.0

# Wave settings
const WAVE_SPAWN_INTERVAL: float = 2.0
const ENEMIES_PER_WAVE: int = 5
const WAVE_DELAY: float = 3.0

# Colors (Gritty Cyber / Neon Industrial)
const COLORS := {
	"bg_darkest": Color("#05070D"),
	"bg_dark": Color("#0A0E1A"),
	"bg_mid": Color("#0F1420"),
	"bg_light": Color("#1A1F2E"),
	"cyan": Color("#00E5FF"),
	"cyan_dim": Color("#007A99"),
	"magenta": Color("#FF2A8A"),
	"magenta_dim": Color("#991A54"),
	"acid_green": Color("#7CFF00"),
	"amber": Color("#FFB000"),
	"white": Color("#FFFFFF"),
	"text_primary": Color("#E8E8E8"),
	"text_secondary": Color("#888899"),
	"text_dim": Color("#555566"),
}

# Debug mode
var debug_mode: bool = true

# Fonts
var font_normal: FontFile = null
var font_bold: FontFile = null
var font_black: FontFile = null
var global_theme: Theme = null

# Current scale factor
var ui_scale: float = 1.0

func _ready() -> void:
	load_fonts()
	apply_global_theme()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	DebugHelper.log_info("GameConfig initialized")

func load_fonts() -> void:
	# Load Eurostile fonts programmatically (without editor import)
	font_normal = load_font_from_file("res://assets/fonts/EuroStyleNormal.ttf")
	font_bold = load_font_from_file("res://assets/fonts/EurostileBold.ttf")
	font_black = load_font_from_file("res://assets/fonts/EurostileExtendedBlack.ttf")
	
	if font_normal:
		DebugHelper.log_info("Eurostile fonts loaded successfully")
	else:
		push_warning("Could not load Eurostile fonts")

func apply_global_theme() -> void:
	if not font_normal:
		return
	
	# Calculate scale based on viewport size
	update_ui_scale()
	
	# Create a global theme with Eurostile font
	global_theme = Theme.new()
	global_theme.default_font = font_normal
	global_theme.default_font_size = get_scaled_font_size(BASE_FONT_SIZE)
	
	# Set as the project's default theme
	ThemeDB.fallback_font = font_normal
	ThemeDB.fallback_font_size = get_scaled_font_size(BASE_FONT_SIZE)
	
	# Apply theme to root viewport when tree is ready
	get_tree().root.theme = global_theme
	
	DebugHelper.log_info("Global Eurostile theme applied (scale: %.2f)" % ui_scale)

func update_ui_scale() -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	ui_scale = viewport_size.y / float(SCREEN_HEIGHT)
	
	# Clamp scale to reasonable bounds
	ui_scale = clamp(ui_scale, 0.5, 3.0)

func get_scaled_font_size(base_size: int) -> int:
	return int(base_size * ui_scale)

func _on_viewport_size_changed() -> void:
	update_ui_scale()
	
	if global_theme:
		global_theme.default_font_size = get_scaled_font_size(BASE_FONT_SIZE)
		ThemeDB.fallback_font_size = get_scaled_font_size(BASE_FONT_SIZE)
	
	DebugHelper.log_info("Viewport resized, new scale: %.2f" % ui_scale)

func load_font_from_file(path: String) -> FontFile:
	# Load font by reading raw TTF data directly
	var abs_path = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path):
		var font_file = FontFile.new()
		var file = FileAccess.open(abs_path, FileAccess.READ)
		if file:
			var data = file.get_buffer(file.get_length())
			file.close()
			font_file.data = data
			return font_file
	
	push_warning("Failed to load font: " + path)
	return null

# Helper to get scaled value for UI positioning
func scale_value(value: float) -> float:
	return value * ui_scale

func scale_vector(vec: Vector2) -> Vector2:
	return vec * ui_scale
