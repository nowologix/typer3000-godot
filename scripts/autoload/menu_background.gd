## menu_background.gd
## Persistent animated background for all menu screens
## Runs as autoload so it persists across scene changes
extends CanvasLayer

var container: Control
var video_player: VideoStreamPlayer
var overlay: ColorRect
var background: ColorRect
var is_visible: bool = false

func _ready() -> void:
	# Put this layer behind everything
	layer = -100

	# Create a full-screen container
	container = Control.new()
	container.anchor_right = 1.0
	container.anchor_bottom = 1.0
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	# Create background color
	background = ColorRect.new()
	background.anchor_right = 1.0
	background.anchor_bottom = 1.0
	background.color = Color(0.02, 0.02, 0.05, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(background)

	# Create video player
	video_player = VideoStreamPlayer.new()
	video_player.anchor_right = 1.0
	video_player.anchor_bottom = 1.0
	video_player.expand = true
	video_player.finished.connect(_on_video_finished)
	video_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(video_player)

	# Load video
	var video_path = "res://assets/video/menu_background.ogv"
	if ResourceLoader.exists(video_path):
		video_player.stream = load(video_path)
		DebugHelper.log_info("MenuBackground: Video loaded")
	else:
		DebugHelper.log_info("MenuBackground: Video not found at %s" % video_path)

	# Create darkening overlay
	overlay = ColorRect.new()
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.color = Color(0.02, 0.02, 0.05, 0.4)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(overlay)

	# Start visible for main menu
	show_background()

func show_background() -> void:
	is_visible = true
	visible = true
	if video_player and video_player.stream:
		video_player.play()

func hide_background() -> void:
	is_visible = false
	visible = false
	if video_player:
		video_player.stop()

func _on_video_finished() -> void:
	if is_visible and video_player:
		video_player.play()
