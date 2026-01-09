## mode_select_state.gd
## Multiplayer mode selection with carousel - VS, COOP, WORD-WAR
extends Control

const MODE_INFO := {
	"VS": {
		"name": "VS",
		"title_key": "VS",
		"desc": "Race against your opponent!\nBoth play solo - first to lose, loses.",
		"color": Color(1.0, 0.3, 0.4),
		"video": "res://assets/videos/vs_preview.ogv"
	},
	"COOP": {
		"name": "COOP",
		"title_key": "COOP",
		"desc": "Team up on the same battlefield!\nOne builds, one types - or mix it up!",
		"color": Color(0.3, 0.9, 0.4),
		"video": "res://assets/videos/coop_preview.ogv"
	},
	"WORDWAR": {
		"name": "WORD-WAR",
		"title_key": "WORDWAR",
		"desc": "Type words to attack!\nSend words flying at your opponent.",
		"color": Color(0.4, 0.7, 1.0),
		"video": "res://assets/videos/wordwar_preview.ogv"
	}
}

const MODE_KEYS := ["VS", "COOP", "WORDWAR"]

const CARD_WIDTH_SELECTED := 520.0
const CARD_HEIGHT_SELECTED := 320.0
const CARD_WIDTH_SIDE := 360.0
const CARD_HEIGHT_SIDE := 220.0
const CARD_SPACING := 50.0
const TRANSITION_TIME := 0.2

var selected_index: int = 0
var typed_buffer: String = ""

@onready var title_label: Label = $VBoxContainer/Title
@onready var carousel_container: Control = $VBoxContainer/CarouselContainer
@onready var typed_display: Label = $VBoxContainer/TypedDisplay
@onready var hint_label: Label = $VBoxContainer/HintLabel

var card_nodes: Array = []
var blur_shader: Shader

const BLUR_SHADER_CODE := "shader_type canvas_item;
uniform float blur_amount : hint_range(0.0, 10.0) = 0.0;
uniform float desaturate : hint_range(0.0, 1.0) = 0.0;
uniform float darken : hint_range(0.0, 1.0) = 0.0;
uniform float corner_radius : hint_range(0.0, 20.0) = 0.0;
uniform vec2 rect_size = vec2(520.0, 320.0);
void fragment() {
	vec2 ps = TEXTURE_PIXEL_SIZE * blur_amount;
	vec4 col = vec4(0.0);
	if (blur_amount > 0.5) {
		col += texture(TEXTURE, UV + vec2(-ps.x, -ps.y)) * 0.0625;
		col += texture(TEXTURE, UV + vec2(0.0, -ps.y)) * 0.125;
		col += texture(TEXTURE, UV + vec2(ps.x, -ps.y)) * 0.0625;
		col += texture(TEXTURE, UV + vec2(-ps.x, 0.0)) * 0.125;
		col += texture(TEXTURE, UV) * 0.25;
		col += texture(TEXTURE, UV + vec2(ps.x, 0.0)) * 0.125;
		col += texture(TEXTURE, UV + vec2(-ps.x, ps.y)) * 0.0625;
		col += texture(TEXTURE, UV + vec2(0.0, ps.y)) * 0.125;
		col += texture(TEXTURE, UV + vec2(ps.x, ps.y)) * 0.0625;
	} else {
		col = texture(TEXTURE, UV);
	}
	float gray = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	col.rgb = mix(col.rgb, vec3(gray), desaturate);
	col.rgb *= (1.0 - darken);
	if (corner_radius > 0.0) {
		vec2 pixel_pos = UV * rect_size;
		vec2 from_corner = min(pixel_pos, rect_size - pixel_pos);
		if (from_corner.x < corner_radius && from_corner.y < corner_radius) {
			float dist = corner_radius - length(vec2(corner_radius) - from_corner);
			col.a *= smoothstep(0.0, 1.5, dist);
		}
	}
	COLOR = col;
}
"

func _ready() -> void:
	typed_buffer = ""
	load_blur_shader()
	await get_tree().process_frame
	create_carousel_cards()
	update_carousel(false)
	update_display()
	if SignalBus.has_signal("language_changed"):
		SignalBus.language_changed.connect(_on_language_changed)

func load_blur_shader() -> void:
	blur_shader = Shader.new()
	blur_shader.code = BLUR_SHADER_CODE

func on_enter(_params: Dictionary) -> void:
	DebugHelper.log_info("ModeSelectState entered")
	MenuBackground.show_background()
	typed_buffer = ""
	selected_index = 0
	update_carousel(false)
	update_display()

func on_exit() -> void:
	DebugHelper.log_info("ModeSelectState exiting")
	if SignalBus.has_signal("language_changed") and SignalBus.language_changed.is_connected(_on_language_changed):
		SignalBus.language_changed.disconnect(_on_language_changed)

func _on_language_changed() -> void:
	update_ui_labels()

func create_carousel_cards() -> void:
	for card in card_nodes:
		if is_instance_valid(card):
			card.queue_free()
	card_nodes.clear()
	for i in range(MODE_KEYS.size()):
		var mode_key = MODE_KEYS[i]
		var mode_data = MODE_INFO[mode_key]
		var card = create_card(mode_data)
		carousel_container.add_child(card)
		card_nodes.append(card)

func create_card(mode_data: Dictionary) -> Control:
	var card = Control.new()
	card.name = "Card_" + mode_data.name

	# Enable mouse input (click only, no hover scrolling)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_card_gui_input.bind(card))

	var panel = PanelContainer.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1)
	style.border_color = Color(0.3, 0.3, 0.35)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)
	card.add_child(panel)
	var video_container = Control.new()
	video_container.name = "VideoContainer"
	video_container.mouse_filter = Control.MOUSE_FILTER_PASS
	video_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	video_container.clip_contents = true
	panel.add_child(video_container)
	var video = VideoStreamPlayer.new()
	video.name = "Video"
	video.mouse_filter = Control.MOUSE_FILTER_PASS
	video.set_anchors_preset(Control.PRESET_FULL_RECT)
	video.expand = true
	video.autoplay = true
	video.loop = true
	var stream = load(mode_data.video)
	if stream:
		video.stream = stream
	var mat = ShaderMaterial.new()
	mat.shader = blur_shader
	mat.set_shader_parameter("blur_amount", 0.0)
	mat.set_shader_parameter("desaturate", 0.0)
	mat.set_shader_parameter("darken", 0.0)
	mat.set_shader_parameter("corner_radius", 10.0)
	mat.set_shader_parameter("rect_size", Vector2(CARD_WIDTH_SELECTED, CARD_HEIGHT_SELECTED))
	video.material = mat
	video_container.add_child(video)
	var name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	name_label.text = mode_data.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	name_label.offset_top = 20
	name_label.offset_bottom = 70
	name_label.offset_left = -200
	name_label.offset_right = 200
	name_label.add_theme_color_override("font_color", mode_data.color)
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
	name_label.add_theme_constant_override("shadow_offset_x", 3)
	name_label.add_theme_constant_override("shadow_offset_y", 3)
	name_label.add_theme_font_size_override("font_size", 42)
	var font = load("res://assets/fonts/EurostileBold.tres")
	if font:
		name_label.add_theme_font_override("font", font)
	card.add_child(name_label)
	var desc_label = Label.new()
	desc_label.name = "DescLabel"
	desc_label.mouse_filter = Control.MOUSE_FILTER_PASS
	desc_label.text = mode_data.desc
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	desc_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	desc_label.offset_bottom = -25
	desc_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	desc_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
	desc_label.add_theme_constant_override("shadow_offset_x", 2)
	desc_label.add_theme_constant_override("shadow_offset_y", 2)
	desc_label.add_theme_font_size_override("font_size", 18)
	if font:
		desc_label.add_theme_font_override("font", font)
	card.add_child(desc_label)
	return card

func update_carousel(animate: bool = true) -> void:
	if card_nodes.is_empty() or not is_instance_valid(carousel_container):
		return
	var container_size = carousel_container.size
	var center_x = container_size.x / 2.0
	var center_y = container_size.y / 2.0
	for i in range(card_nodes.size()):
		var card = card_nodes[i]
		if not is_instance_valid(card):
			continue
		var offset = i - selected_index
		var target_width: float
		var target_height: float
		var target_x: float
		var target_y: float
		var blur: float
		var desat: float
		var darken_val: float
		var z_idx: int
		if offset == 0:
			target_width = CARD_WIDTH_SELECTED
			target_height = CARD_HEIGHT_SELECTED
			target_x = center_x - target_width / 2.0
			target_y = center_y - target_height / 2.0
			blur = 0.0
			desat = 0.0
			darken_val = 0.0
			z_idx = 10
		else:
			target_width = CARD_WIDTH_SIDE
			target_height = CARD_HEIGHT_SIDE
			target_y = center_y - target_height / 2.0
			if offset < 0:
				target_x = center_x - CARD_WIDTH_SELECTED / 2.0 - CARD_SPACING - target_width
				if offset < -1:
					target_x += (offset + 1) * (target_width + 20)
			else:
				target_x = center_x + CARD_WIDTH_SELECTED / 2.0 + CARD_SPACING
				if offset > 1:
					target_x += (offset - 1) * (target_width + 20)
			blur = 2.5
			desat = 0.5
			darken_val = 0.35
			z_idx = 5 - abs(offset)
		var panel = card.get_node_or_null("Panel")
		if panel:
			var mode_key = MODE_KEYS[i]
			var mode_color = MODE_INFO[mode_key].color
			var new_style = StyleBoxFlat.new()
			new_style.bg_color = Color(0.08, 0.08, 0.1)
			new_style.set_corner_radius_all(12)
			if offset == 0:
				new_style.border_color = mode_color
				new_style.set_border_width_all(4)
			else:
				new_style.border_color = Color(0.25, 0.25, 0.3)
				new_style.set_border_width_all(2)
			panel.add_theme_stylebox_override("panel", new_style)
			var video_container = panel.get_node_or_null("VideoContainer")
			if video_container:
				var video_node = video_container.get_node_or_null("Video")
				if video_node and video_node.material:
					var pmat = video_node.material as ShaderMaterial
					pmat.set_shader_parameter("rect_size", Vector2(target_width, target_height))
					if animate:
						var shader_tween = create_tween()
						shader_tween.set_parallel(true)
						shader_tween.tween_property(pmat, "shader_parameter/blur_amount", blur, TRANSITION_TIME)
						shader_tween.tween_property(pmat, "shader_parameter/desaturate", desat, TRANSITION_TIME)
						shader_tween.tween_property(pmat, "shader_parameter/darken", darken_val, TRANSITION_TIME)
					else:
						pmat.set_shader_parameter("blur_amount", blur)
						pmat.set_shader_parameter("desaturate", desat)
						pmat.set_shader_parameter("darken", darken_val)
		var name_label = card.get_node_or_null("NameLabel")
		if name_label:
			var target_font_size = 42 if offset == 0 else 28
			name_label.add_theme_font_size_override("font_size", target_font_size)
			name_label.modulate.a = 1.0 if offset == 0 else 0.6
		var desc_label = card.get_node_or_null("DescLabel")
		if desc_label:
			var target_desc_size = 18 if offset == 0 else 14
			desc_label.add_theme_font_size_override("font_size", target_desc_size)
			desc_label.modulate.a = 1.0 if offset == 0 else 0.4
		card.z_index = z_idx
		if animate:
			var pos_tween = create_tween()
			pos_tween.set_parallel(true)
			pos_tween.set_ease(Tween.EASE_OUT)
			pos_tween.set_trans(Tween.TRANS_CUBIC)
			pos_tween.tween_property(card, "position", Vector2(target_x, target_y), TRANSITION_TIME)
			pos_tween.tween_property(card, "size", Vector2(target_width, target_height), TRANSITION_TIME)
		else:
			card.position = Vector2(target_x, target_y)
			card.size = Vector2(target_width, target_height)
	update_ui_labels()

func update_ui_labels() -> void:
	if title_label:
		title_label.text = Tr.t("SELECT_MODE", "SELECT MODE")
	if hint_label:
		hint_label.text = "[< BACK]  < > to select, ENTER to confirm"

func is_back_button_area(pos: Vector2) -> bool:
	return pos.x < 120 and pos.y > GameConfig.SCREEN_HEIGHT - 60

func _on_card_gui_input(event: InputEvent, card: Control) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var idx = card_nodes.find(card)
		if idx != -1:
			selected_index = idx
			SoundManager.play_word_complete()
			update_carousel()
			confirm_selection()

func _on_card_mouse_entered(_card: Control) -> void:
	# Disabled: Mouse hover no longer scrolls carousel
	# Use click to select instead
	pass

func _get_best_match() -> int:
	if typed_buffer.length() == 0:
		return selected_index
	for i in range(MODE_KEYS.size()):
		var key = MODE_KEYS[i]
		if MODE_INFO[key].name.begins_with(typed_buffer):
			return i
	return -1

func _input(event: InputEvent) -> void:
	# Mouse wheel scrolling
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			selected_index = (selected_index - 1 + MODE_KEYS.size()) % MODE_KEYS.size()
			SoundManager.play_menu_select()
			update_carousel()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			selected_index = (selected_index + 1) % MODE_KEYS.size()
			SoundManager.play_menu_select()
			update_carousel()
			return

		if event.button_index == MOUSE_BUTTON_XBUTTON1:
			SoundManager.play_menu_back()
			StateManager.change_state("lobby")
			return

		if event.button_index == MOUSE_BUTTON_LEFT:
			if is_back_button_area(event.position):
				SoundManager.play_menu_back()
				StateManager.change_state("lobby")
				return

	if event is InputEventKey and event.pressed and not event.is_echo():
		var char_code = event.unicode
		if event.keycode == KEY_ESCAPE:
			SoundManager.play_menu_back()
			StateManager.change_state("lobby")
			return
		if event.keycode == KEY_LEFT:
			selected_index = (selected_index - 1 + MODE_KEYS.size()) % MODE_KEYS.size()
			SoundManager.play_menu_select()
			update_carousel()
			return
		if event.keycode == KEY_RIGHT:
			selected_index = (selected_index + 1) % MODE_KEYS.size()
			SoundManager.play_menu_select()
			update_carousel()
			return
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			var best_idx = _get_best_match()
			if best_idx >= 0:
				selected_index = best_idx
				update_carousel()
			confirm_selection()
			return
		if event.keycode == KEY_BACKSPACE:
			if typed_buffer.length() > 0:
				typed_buffer = typed_buffer.substr(0, typed_buffer.length() - 1)
				SoundManager.play_menu_select()
				update_display()
			return
		if (char_code >= 65 and char_code <= 90) or (char_code >= 97 and char_code <= 122):
			typed_buffer += char(char_code).to_upper()
			SoundManager.play_menu_select()
			update_display()
			check_typed_command()
		if char_code == 45:
			typed_buffer += "-"
			update_display()
			check_typed_command()

func update_display() -> void:
	if typed_display:
		typed_display.text = typed_buffer
		var matches = false
		for key in MODE_KEYS:
			var mode_name = MODE_INFO[key].name
			if mode_name.begins_with(typed_buffer) and typed_buffer.length() > 0:
				matches = true
				break
		if matches:
			typed_display.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
		elif typed_buffer.length() > 0:
			typed_display.add_theme_color_override("font_color", GameConfig.COLORS.magenta)
		else:
			typed_display.add_theme_color_override("font_color", GameConfig.COLORS.cyan)

func check_typed_command() -> void:
	for i in range(MODE_KEYS.size()):
		var key = MODE_KEYS[i]
		if typed_buffer == MODE_INFO[key].name:
			selected_index = i
			update_carousel()
			confirm_selection()
			return
	var could_match = false
	for key in MODE_KEYS:
		if MODE_INFO[key].name.begins_with(typed_buffer):
			could_match = true
			break
	if not could_match and typed_buffer.length() > 0:
		SoundManager.play_type_error()
		typed_buffer = ""
		update_display()

func confirm_selection() -> void:
	var mode_key = MODE_KEYS[selected_index]
	var mode_data = MODE_INFO[mode_key]
	DebugHelper.log_info("Selected mode: %s" % mode_data.name)
	SoundManager.play_word_complete()
	SoundManager.play_voice_lobby_initiated()
	StateManager.change_state("lobby", {
		"mode": mode_key,
		"mode_name": mode_data.name,
		"mode_title": Tr.t(mode_data.title_key, mode_data.name),
		"action": "host"
	})
