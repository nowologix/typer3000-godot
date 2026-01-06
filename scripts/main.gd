## main.gd
## Main scene controller - entry point for the game
extends Control

@onready var fps_label: Label = $DebugOverlay/FPSLabel
@onready var debug_label: Label = $DebugOverlay/DebugLabel

var show_debug_overlay: bool = true

func _ready() -> void:
	DebugHelper.log_info("Main scene loaded")

	# Wait for StateManager to find the container, then change to menu
	_init_state_manager()

func _init_state_manager() -> void:
	# Wait a couple frames for StateManager to initialize
	await get_tree().process_frame
	await get_tree().process_frame

	# Set the container directly if not found
	if StateManager.state_container == null:
		StateManager.state_container = $StateContainer
		DebugHelper.log_info("StateManager container set from Main")

	# Now change to menu
	StateManager.change_state("menu")

	# Play welcome voice
	SoundManager.play_voice_welcome()

func _process(_delta: float) -> void:
	# Update FPS display
	if show_debug_overlay and fps_label:
		fps_label.text = DebugHelper.get_fps_string()

func _input(event: InputEvent) -> void:
	# Toggle debug overlay with F3
	if event.is_action_pressed("debug_toggle"):
		show_debug_overlay = not show_debug_overlay
		$DebugOverlay.visible = show_debug_overlay
		DebugHelper.log_debug("Debug overlay: %s" % ("ON" if show_debug_overlay else "OFF"))
