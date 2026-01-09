## zen_progress_manager.gd
## Manages saving and loading progress for ZEN mode works
extends Node

const PROGRESS_DIR := "user://zen_progress/"
const SAVE_INTERVAL_CHARS := 200  # Save at least every 200 chars

# Progress data structure
var current_work_id: String = ""
var last_save_index: int = 0

func _ready() -> void:
	# Ensure progress directory exists
	DirAccess.make_dir_recursive_absolute(PROGRESS_DIR.replace("user://", OS.get_user_data_dir() + "/"))

func get_progress_path(work_id: String) -> String:
	return PROGRESS_DIR + work_id + ".json"

# Check if progress exists for a work
func has_progress(work_id: String) -> bool:
	return FileAccess.file_exists(get_progress_path(work_id))

# Get saved progress for a work
func get_progress(work_id: String) -> Dictionary:
	var path := get_progress_path(work_id)
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_text)
	if error != OK:
		return {}

	return json.data

# Save progress for a work
func save_progress(work_id: String, cursor_index: int, total_chars: int) -> void:
	var progress := {
		"cursor_index": cursor_index,
		"total_chars": total_chars,
		"percentage": float(cursor_index) / float(total_chars) * 100.0 if total_chars > 0 else 0.0,
		"timestamp": Time.get_unix_time_from_system()
	}

	var path := get_progress_path(work_id)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		DebugHelper.log_error("ZenProgressManager: Cannot save progress to %s" % path)
		return

	file.store_string(JSON.stringify(progress, "\t"))
	file.close()

	last_save_index = cursor_index
	DebugHelper.log_info("ZenProgressManager: Saved progress for %s at %d/%d (%.1f%%)" % [work_id, cursor_index, total_chars, progress.percentage])

# Clear progress for a work (restart)
func clear_progress(work_id: String) -> void:
	var path := get_progress_path(work_id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		DebugHelper.log_info("ZenProgressManager: Cleared progress for %s" % work_id)

# Start tracking a work
func start_tracking(work_id: String) -> void:
	current_work_id = work_id
	last_save_index = 0
	var progress := get_progress(work_id)
	if progress.has("cursor_index"):
		last_save_index = progress.cursor_index

# Check if we should save (called after typing)
func should_save(cursor_index: int, current_char: String) -> bool:
	# Save on period or newline
	if current_char in [".", "\n"]:
		return true

	# Save every SAVE_INTERVAL_CHARS characters
	if cursor_index - last_save_index >= SAVE_INTERVAL_CHARS:
		return true

	return false

# Format progress percentage for display
func get_progress_percentage(work_id: String) -> float:
	var progress := get_progress(work_id)
	return progress.get("percentage", 0.0)
