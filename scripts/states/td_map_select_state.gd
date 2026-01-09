## td_map_select_state.gd
## Tower Defence map selection with carousel
extends Control

const MAP_INFO := {
	"TOKYO": {"name": "TOKYO", "scene": "res://scenes/maps/td_map_tokyo.tscn", "preview": "res://assets/maps/typer3000map_tokyo_preview.jpg", "available": true},
	"FREUDENBERG": {"name": "FREUDENBERG", "scene": "res://scenes/maps/td_map_freudenberg.tscn", "preview": "res://assets/maps/typer3000map_freudenberg_preview.png", "available": true},
	"SILICON": {"name": "SILICON", "scene": "res://scenes/maps/td_map_silicon.tscn", "preview": "res://assets/maps/typer3000map_silicon_preview.jpg", "available": true}
}
const MAP_KEYS := ["TOKYO", "FREUDENBERG", "SILICON"]

const DIFFICULTY_INFO := {
	"EASY": {"name": "EASY", "value": 1, "stars": "★☆☆"},
	"MEDIUM": {"name": "MEDIUM", "value": 2, "stars": "★★☆"},
	"HARD": {"name": "HARD", "value": 3, "stars": "★★★"}
}
const DIFFICULTY_KEYS := ["EASY", "MEDIUM", "HARD"]

const CARD_WIDTH_SELECTED := 520.0
const CARD_HEIGHT_SELECTED := 309.0
const CARD_WIDTH_SIDE := 340.0
const CARD_HEIGHT_SIDE := 202.0
const CARD_SPACING := 40.0
const TRANSITION_TIME := 0.2

enum SelectState { MAP, DIFFICULTY }
var select_state: int = SelectState.MAP
var selected_index: int = 0
var difficulty_index: int = 1
var selected_map_key: String = ""
var typed_buffer: String = ""

@onready var title_label: Label = $VBoxContainer/Title
@onready var carousel_container: Control = $VBoxContainer/CarouselContainer
@onready var typed_display: Label = $VBoxContainer/TypedDisplay
@onready var hint_label: Label = $VBoxContainer/HintLabel
@onready var difficulty_container: HBoxContainer = $VBoxContainer/DifficultyContainer
@onready var difficulty_label: Label = $VBoxContainer/DifficultyContainer/DifficultyLabel

var card_nodes: Array = []
var blur_shader: Shader
var star_buttons: Array = []
var pulse_time: float = 0.0

const BLUR_SHADER_CODE := "shader_type canvas_item;
uniform float blur_amount : hint_range(0.0, 10.0) = 0.0;
uniform float desaturate : hint_range(0.0, 1.0) = 0.0;
uniform float darken : hint_range(0.0, 1.0) = 0.0;
uniform float corner_radius : hint_range(0.0, 20.0) = 0.0;
uniform vec2 rect_size = vec2(520.0, 290.0);
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
	create_star_buttons()
	update_carousel(false)
	update_display()

func _process(delta: float) -> void:
	# Pulse animation for stars in difficulty selection
	if select_state == SelectState.DIFFICULTY:
		pulse_time += delta * 4.0
		update_star_pulse()

func load_blur_shader() -> void:
	blur_shader = Shader.new()
	blur_shader.code = BLUR_SHADER_CODE

func create_star_buttons() -> void:
	# Stars are now created in create_card, so just hide the old difficulty container
	if difficulty_label:
		difficulty_label.visible = false
	if difficulty_container:
		difficulty_container.visible = false

func _on_star_button_pressed(index: int) -> void:
	if select_state != SelectState.DIFFICULTY:
		return
	difficulty_index = index
	update_display()
	SoundManager.play_word_complete()
	confirm_selection()

func _on_star_button_hover(index: int) -> void:
	if select_state != SelectState.DIFFICULTY:
		return
	if difficulty_index != index:
		difficulty_index = index
		pulse_time = 0.0  # Reset pulse for fresh animation
		SoundManager.play_menu_select()
		update_display()

func update_star_pulse() -> void:
	if selected_index < 0 or selected_index >= card_nodes.size():
		return
	var card = card_nodes[selected_index]
	if not is_instance_valid(card):
		return
	var star_container = card.get_node_or_null("StarContainer")
	if star_container == null:
		return
	
	var pulse = (sin(pulse_time) + 1.0) / 2.0  # 0 to 1
	
	for i in range(star_container.get_child_count()):
		var btn = star_container.get_child(i)
		if not is_instance_valid(btn):
			continue

		if i == difficulty_index:
			# Selected star pulses between gold and white
			var color = Color(1, 0.84, 0).lerp(Color(1, 1, 1), pulse * 0.5)
			btn.add_theme_color_override("font_color", color)
			# Also pulse scale slightly
			btn.scale = Vector2(1.0 + pulse * 0.1, 1.0 + pulse * 0.1)
		else:
			# Non-selected stars are dimmed
			btn.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
			btn.scale = Vector2.ONE

func on_enter(_params: Dictionary) -> void:
	DebugHelper.log_info("TDMapSelectState entered")
	MenuBackground.show_background()
	typed_buffer = ""
	selected_index = 0
	difficulty_index = 1
	select_state = SelectState.MAP
	selected_map_key = ""
	update_carousel(false)
	update_display()

func on_exit() -> void:
	DebugHelper.log_info("TDMapSelectState exiting")

func create_carousel_cards() -> void:
	for card in card_nodes:
		if is_instance_valid(card):
			card.queue_free()
	card_nodes.clear()
	for i in range(MAP_KEYS.size()):
		var map_key = MAP_KEYS[i]
		var map_data = MAP_INFO[map_key]
		var card = create_card(map_data)
		carousel_container.add_child(card)
		card_nodes.append(card)

func create_card(map_data: Dictionary) -> Control:
	var card = Control.new()
	card.name = "Card_" + map_data.name
	var panel = PanelContainer.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1)
	style.border_color = Color(0.3, 0.3, 0.35)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", style)
	card.add_child(panel)
	# Container with clip_contents to properly clip image to panel bounds
	var preview_container = Control.new()
	preview_container.name = "PreviewContainer"
	preview_container.mouse_filter = Control.MOUSE_FILTER_PASS
	preview_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_container.clip_contents = true
	panel.add_child(preview_container)
	var preview = TextureRect.new()
	preview.name = "Preview"
	preview.mouse_filter = Control.MOUSE_FILTER_PASS
	preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var tex = load(map_data.preview)
	if tex:
		preview.texture = tex
	var mat = ShaderMaterial.new()
	mat.shader = blur_shader
	mat.set_shader_parameter("blur_amount", 0.0)
	mat.set_shader_parameter("desaturate", 0.0)
	mat.set_shader_parameter("darken", 0.0)
	mat.set_shader_parameter("corner_radius", 10.0)
	mat.set_shader_parameter("rect_size", Vector2(CARD_WIDTH_SELECTED, CARD_HEIGHT_SELECTED))
	preview.material = mat
	preview_container.add_child(preview)
	var name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	name_label.text = map_data.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_label.offset_bottom = -20
	name_label.add_theme_color_override("font_color", Color(1, 1, 1))
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
	name_label.add_theme_constant_override("shadow_offset_x", 3)
	name_label.add_theme_constant_override("shadow_offset_y", 3)
	name_label.add_theme_font_size_override("font_size", 32)
	var font = load("res://assets/fonts/EurostileBold.tres")
	if font:
		name_label.add_theme_font_override("font", font)
	card.add_child(name_label)
	
	# Star container for difficulty selection (centered on card)
	var star_container = HBoxContainer.new()
	star_container.name = "StarContainer"
	star_container.visible = false
	star_container.set_anchors_preset(Control.PRESET_CENTER)
	star_container.offset_left = -180
	star_container.offset_right = 180
	star_container.offset_top = -30
	star_container.offset_bottom = 30
	star_container.alignment = BoxContainer.ALIGNMENT_CENTER
	star_container.add_theme_constant_override("separation", 30)
	card.add_child(star_container)
	
	# Create star buttons inside card
	var btn_font = load("res://assets/fonts/EurostileBold.tres")
	for i in range(DIFFICULTY_KEYS.size()):
		var diff_key = DIFFICULTY_KEYS[i]
		var diff_data = DIFFICULTY_INFO[diff_key]
		var btn = Button.new()
		btn.name = "StarBtn_" + diff_key
		btn.text = diff_data.stars
		btn.flat = true
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.custom_minimum_size = Vector2(100, 50)
		btn.pivot_offset = Vector2(50, 25)
		if btn_font:
			btn.add_theme_font_override("font", btn_font)
		btn.add_theme_font_size_override("font_size", 32)
		btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		btn.add_theme_color_override("font_hover_color", Color(1, 0.84, 0))
		btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
		btn.pressed.connect(_on_star_button_pressed.bind(i))
		btn.mouse_entered.connect(_on_star_button_hover.bind(i))
		star_container.add_child(btn)
	
	# Add mouse support (click only, no hover scrolling)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_card_gui_input.bind(card))

	return card

func _on_card_gui_input(event: InputEvent, card: Control) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var idx = card_nodes.find(card)
		if idx != -1:
			if select_state == SelectState.MAP:
				selected_index = idx
				SoundManager.play_word_complete()
				update_carousel()
				confirm_selection()
			elif select_state == SelectState.DIFFICULTY and idx == selected_index:
				# Click on selected card confirms difficulty
				SoundManager.play_word_complete()
				confirm_selection()

func _on_card_mouse_entered(card: Control) -> void:
	if InputMode.is_keyboard_mode():
		return
	if select_state != SelectState.MAP:
		return
	var idx = card_nodes.find(card)
	if idx != -1 and idx != selected_index:
		selected_index = idx
		SoundManager.play_menu_select()
		update_carousel()

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
			# Darken and blur in difficulty mode so stars are visible
			if select_state == SelectState.DIFFICULTY:
				blur = 2.5
				desat = 0.2
				darken_val = 0.3
			else:
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
			var new_style = StyleBoxFlat.new()
			new_style.bg_color = Color(0.08, 0.08, 0.1)
			new_style.set_corner_radius_all(12)
			if offset == 0:
				new_style.border_color = Color(1, 0.84, 0)
				new_style.set_border_width_all(4)
			else:
				new_style.border_color = Color(0.25, 0.25, 0.3)
				new_style.set_border_width_all(2)
			panel.add_theme_stylebox_override("panel", new_style)
			var preview_container = panel.get_node_or_null("PreviewContainer")
			var preview_node = preview_container.get_node_or_null("Preview") if preview_container else null
			if preview_node and preview_node.material:
				var pmat = preview_node.material as ShaderMaterial
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
			var target_font_size = 36 if offset == 0 else 24
			name_label.add_theme_font_size_override("font_size", target_font_size)
		# Show/hide star container based on select state
		var star_container = card.get_node_or_null("StarContainer")
		if star_container:
			star_container.visible = (offset == 0 and select_state == SelectState.DIFFICULTY)
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
		if select_state == SelectState.DIFFICULTY:
			title_label.text = MAP_INFO[selected_map_key].name + " - SELECT DIFFICULTY"
		else:
			title_label.text = "SELECT MAP"
	if difficulty_container:
		difficulty_container.visible = (select_state == SelectState.DIFFICULTY)
	if hint_label:
		if select_state == SelectState.DIFFICULTY:
			hint_label.text = "< > or CLICK stars to select, ENTER or CLICK card to start, ESC to go back"
		else:
			hint_label.text = "< > to select map, ENTER or CLICK to confirm, ESC to go back"

func is_back_button_area(pos: Vector2) -> bool:
	# Back button area in bottom-left corner
	return pos.x < 120 and pos.y > GameConfig.SCREEN_HEIGHT - 60

func _input(event: InputEvent) -> void:
	# Mouse wheel scrolling
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if select_state == SelectState.MAP:
				selected_index = (selected_index - 1 + MAP_KEYS.size()) % MAP_KEYS.size()
				update_carousel()
			else:
				difficulty_index = (difficulty_index - 1 + DIFFICULTY_KEYS.size()) % DIFFICULTY_KEYS.size()
				pulse_time = 0.0  # Reset pulse for fresh animation
				update_display()
			SoundManager.play_menu_select()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if select_state == SelectState.MAP:
				selected_index = (selected_index + 1) % MAP_KEYS.size()
				update_carousel()
			else:
				difficulty_index = (difficulty_index + 1) % DIFFICULTY_KEYS.size()
				pulse_time = 0.0  # Reset pulse for fresh animation
				update_display()
			SoundManager.play_menu_select()
			return

		if event.button_index == MOUSE_BUTTON_XBUTTON1:
			SoundManager.play_menu_back()
			StateManager.change_state("solo_mode_select")
			return

	if event is InputEventKey and event.pressed and not event.is_echo():
		var char_code = event.unicode
		if event.keycode == KEY_ESCAPE:
			SoundManager.play_menu_back()
			if select_state == SelectState.DIFFICULTY:
				select_state = SelectState.MAP
				typed_buffer = ""
				update_carousel()
				update_display()
			else:
				StateManager.change_state("solo_mode_select")
			return
		if event.keycode == KEY_LEFT:
			if select_state == SelectState.MAP:
				selected_index = (selected_index - 1 + MAP_KEYS.size()) % MAP_KEYS.size()
				update_carousel()
			else:
				difficulty_index = (difficulty_index - 1 + DIFFICULTY_KEYS.size()) % DIFFICULTY_KEYS.size()
				pulse_time = 0.0  # Reset pulse for fresh animation
				update_display()
			SoundManager.play_menu_select()
			return
		if event.keycode == KEY_RIGHT:
			if select_state == SelectState.MAP:
				selected_index = (selected_index + 1) % MAP_KEYS.size()
				update_carousel()
			else:
				difficulty_index = (difficulty_index + 1) % DIFFICULTY_KEYS.size()
				pulse_time = 0.0  # Reset pulse for fresh animation
				update_display()
			SoundManager.play_menu_select()
			return
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			# Autofill if typing partial match
			if typed_buffer.length() > 0:
				if select_state == SelectState.MAP:
					for i in range(MAP_KEYS.size()):
						var key = MAP_KEYS[i]
						if MAP_INFO[key].name.begins_with(typed_buffer):
							selected_index = i
							typed_buffer = MAP_INFO[key].name
							update_display()
							update_carousel()
							break
				else:
					for i in range(DIFFICULTY_KEYS.size()):
						var key = DIFFICULTY_KEYS[i]
						if DIFFICULTY_INFO[key].name.begins_with(typed_buffer):
							difficulty_index = i
							typed_buffer = DIFFICULTY_INFO[key].name
							update_display()
							break
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

func update_display() -> void:
	if difficulty_label and select_state == SelectState.DIFFICULTY:
		var diff_key = DIFFICULTY_KEYS[difficulty_index]
		var diff_data = DIFFICULTY_INFO[diff_key]
		difficulty_label.text = diff_data.stars + "  " + diff_key
	if typed_display:
		if select_state == SelectState.DIFFICULTY:
			typed_display.text = ""
			return
		typed_display.text = typed_buffer
		var matches = false
		for key in MAP_KEYS:
			if MAP_INFO[key].name.begins_with(typed_buffer) and typed_buffer.length() > 0:
				matches = true
				break
		if matches:
			typed_display.add_theme_color_override("font_color", Color(0.486, 1, 0))
		elif typed_buffer.length() > 0:
			typed_display.add_theme_color_override("font_color", Color(1, 0, 0.5))
		else:
			typed_display.add_theme_color_override("font_color", Color(0, 1, 1))

func check_typed_command() -> void:
	if select_state == SelectState.MAP:
		for i in range(MAP_KEYS.size()):
			var key = MAP_KEYS[i]
			if typed_buffer == MAP_INFO[key].name:
				selected_index = i
				update_carousel()
				confirm_selection()
				return
		var could_match = false
		for key in MAP_KEYS:
			if MAP_INFO[key].name.begins_with(typed_buffer):
				could_match = true
				break
		if not could_match and typed_buffer.length() > 0:
			SoundManager.play_type_error()
			typed_buffer = ""
			update_display()
	else:
		for i in range(DIFFICULTY_KEYS.size()):
			var key = DIFFICULTY_KEYS[i]
			if typed_buffer == DIFFICULTY_INFO[key].name:
				difficulty_index = i
				update_display()
				confirm_selection()
				return
		var could_match = false
		for key in DIFFICULTY_KEYS:
			if DIFFICULTY_INFO[key].name.begins_with(typed_buffer):
				could_match = true
				break
		if not could_match and typed_buffer.length() > 0:
			SoundManager.play_type_error()
			typed_buffer = ""
			update_display()

func confirm_selection() -> void:
	if select_state == SelectState.MAP:
		var map_key = MAP_KEYS[selected_index]
		var map_data = MAP_INFO[map_key]
		if not map_data.available:
			show_not_available()
			return
		selected_map_key = map_key
		select_state = SelectState.DIFFICULTY
		difficulty_index = 1
		pulse_time = 0.0  # Start fresh pulse animation
		typed_buffer = ""
		SoundManager.play_menu_select()
		update_carousel()
		update_display()
		DebugHelper.log_info("Selected map: %s, now selecting difficulty" % map_data.name)
	else:
		var diff_key = DIFFICULTY_KEYS[difficulty_index]
		var diff_data = DIFFICULTY_INFO[diff_key]
		var map_data = MAP_INFO[selected_map_key]
		DebugHelper.log_info("Starting TD: Map=%s, Difficulty=%s" % [selected_map_key, diff_key])
		SoundManager.play_word_complete()
		StateManager.change_state("tower_defence", {"map": selected_map_key.to_lower(), "map_scene": map_data.scene, "difficulty": diff_data.value})

func show_not_available() -> void:
	if typed_display:
		typed_display.text = "COMING SOON"
		typed_display.add_theme_color_override("font_color", Color(1, 0.8, 0))
	SoundManager.play_type_error()
	var timer = get_tree().create_timer(1.5)
	timer.timeout.connect(func():
		typed_buffer = ""
		update_display()
	)
