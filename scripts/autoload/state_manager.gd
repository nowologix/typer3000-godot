## state_manager.gd
## Manages game state transitions via scene switching
## Autoload singleton: StateManager
extends Node

# State scene paths
const STATE_SCENES := {
	"menu": "res://scenes/states/menu_state.tscn",
	"game": "res://scenes/states/game_state.tscn",
	"pause": "res://scenes/states/pause_state.tscn",
	"game_over": "res://scenes/states/game_over_state.tscn",
	"settings": "res://scenes/states/settings_state.tscn",
	"statistics": "res://scenes/states/statistics_state.tscn",
	"mode_select": "res://scenes/states/mode_select_state.tscn",
	"lobby": "res://scenes/states/lobby_state.tscn",
	"wordwar": "res://scenes/states/wordwar_state.tscn",
	"vs_battle": "res://scenes/states/vs_battle_state.tscn",
	"coop_game": "res://scenes/states/coop_game_state.tscn",
}

var current_state: Node = null
var current_state_name: String = ""
var state_container: Node = null
var state_params: Dictionary = {}

# History for back navigation
var state_history: Array[String] = []
const MAX_HISTORY: int = 10

func _ready() -> void:
	# We'll get the container after main scene loads
	call_deferred("_find_state_container")

func _find_state_container() -> void:
	# Wait for main scene to be ready
	await get_tree().process_frame
	state_container = get_tree().root.get_node_or_null("Main/StateContainer")
	if state_container == null:
		push_error("StateManager: Could not find Main/StateContainer node!")
	else:
		DebugHelper.log_info("StateManager initialized, container found")

func change_state(state_name: String, params: Dictionary = {}) -> void:
	if not STATE_SCENES.has(state_name):
		push_error("StateManager: Unknown state '%s'" % state_name)
		return

	if state_container == null:
		push_error("StateManager: No state container available")
		return

	DebugHelper.log_info("StateManager: Changing to state '%s'" % state_name)

	# Store params for the new state
	state_params = params

	# Add current state to history
	if current_state_name != "" and current_state_name != state_name:
		state_history.push_back(current_state_name)
		if state_history.size() > MAX_HISTORY:
			state_history.pop_front()

	# Exit current state
	if current_state != null:
		if current_state.has_method("on_exit"):
			current_state.on_exit()
		current_state.queue_free()
		await current_state.tree_exited

	# Load and instantiate new state
	var scene_path = STATE_SCENES[state_name]
	var scene = load(scene_path)
	if scene == null:
		push_error("StateManager: Failed to load scene '%s'" % scene_path)
		return

	current_state = scene.instantiate()
	current_state_name = state_name
	state_container.add_child(current_state)

	# Enter new state
	if current_state.has_method("on_enter"):
		current_state.on_enter(params)

	DebugHelper.log_info("StateManager: Now in state '%s'" % state_name)

func go_back() -> void:
	if state_history.size() > 0:
		var prev_state = state_history.pop_back()
		change_state(prev_state)
	else:
		DebugHelper.log_warning("StateManager: No history to go back to")

func get_param(key: String, default = null):
	return state_params.get(key, default)

func is_state(state_name: String) -> bool:
	return current_state_name == state_name
