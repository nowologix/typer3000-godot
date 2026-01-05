## debug_helper.gd
## Centralized logging and debug utilities
## Autoload singleton: DebugHelper
extends Node

enum LogLevel {
	DEBUG,
	INFO,
	WARNING,
	ERROR
}

var current_log_level: LogLevel = LogLevel.DEBUG
var log_to_file: bool = false
var log_file: FileAccess = null

# Color codes for console (doesn't affect Godot output, but useful for reference)
const LOG_PREFIXES := {
	LogLevel.DEBUG: "[DEBUG]",
	LogLevel.INFO: "[INFO]",
	LogLevel.WARNING: "[WARN]",
	LogLevel.ERROR: "[ERROR]"
}

func _ready() -> void:
	# We can't log to DebugHelper from DebugHelper._ready, so just print directly
	print("[INFO] DebugHelper initialized")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if log_file != null:
			log_file.close()

func set_log_level(level: LogLevel) -> void:
	current_log_level = level

func log_debug(message: String) -> void:
	if current_log_level <= LogLevel.DEBUG:
		_log(LogLevel.DEBUG, message)

func log_info(message: String) -> void:
	if current_log_level <= LogLevel.INFO:
		_log(LogLevel.INFO, message)

func log_warning(message: String) -> void:
	if current_log_level <= LogLevel.WARNING:
		_log(LogLevel.WARNING, message)
		push_warning(message)

func log_error(message: String) -> void:
	_log(LogLevel.ERROR, message)
	push_error(message)

func _log(level: LogLevel, message: String) -> void:
	var timestamp = Time.get_datetime_string_from_system()
	var prefix = LOG_PREFIXES[level]
	var full_message = "%s %s %s" % [timestamp, prefix, message]

	print(full_message)

	if log_to_file and log_file != null:
		log_file.store_line(full_message)

func enable_file_logging(path: String = "user://debug.log") -> void:
	log_file = FileAccess.open(path, FileAccess.WRITE)
	if log_file != null:
		log_to_file = true
		log_info("File logging enabled: %s" % path)
	else:
		push_error("Failed to open log file: %s" % path)

# Debug visualization helpers
func draw_debug_point(canvas: CanvasItem, pos: Vector2, color: Color = Color.RED, radius: float = 5.0) -> void:
	canvas.draw_circle(pos, radius, color)

func draw_debug_line(canvas: CanvasItem, from: Vector2, to: Vector2, color: Color = Color.GREEN, width: float = 2.0) -> void:
	canvas.draw_line(from, to, color, width)

func draw_debug_rect(canvas: CanvasItem, rect: Rect2, color: Color = Color.YELLOW, filled: bool = false, width: float = 2.0) -> void:
	if filled:
		canvas.draw_rect(rect, color)
	else:
		canvas.draw_rect(rect, color, false, width)

# Performance monitoring
var frame_times: Array[float] = []
const FRAME_TIME_SAMPLES: int = 60

func _process(delta: float) -> void:
	frame_times.append(delta)
	if frame_times.size() > FRAME_TIME_SAMPLES:
		frame_times.pop_front()

func get_average_fps() -> float:
	if frame_times.size() == 0:
		return 0.0
	var avg_delta = 0.0
	for dt in frame_times:
		avg_delta += dt
	avg_delta /= frame_times.size()
	return 1.0 / avg_delta if avg_delta > 0 else 0.0

func get_fps_string() -> String:
	return "FPS: %.1f" % get_average_fps()
