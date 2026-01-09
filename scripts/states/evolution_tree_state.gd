## evolution_tree_state.gd
## Visual tree UI for unlocking and toggling meta-progression abilities
extends Node2D

# Layout constants
const MARGIN: float = 40.0
const HEADER_HEIGHT: float = 80.0
const NODE_SIZE := Vector2(220, 100)
const NODE_SPACING := Vector2(260, 130)
const CONNECTION_COLOR := Color(0.3, 0.35, 0.4)
const CONNECTION_ACTIVE_COLOR := Color(0.4, 0.8, 1.0)

# Tree centering - calculate based on 3 columns
const TREE_COLUMNS: int = 3
var tree_offset_x: float = 0.0  # Calculated at runtime

# Colors
const BG_DARK := Color(0.05, 0.06, 0.09)
const BG_CARD := Color(0.1, 0.11, 0.15)
const BG_CARD_HOVER := Color(0.14, 0.15, 0.2)
const ACCENT_PRIMARY := Color(0.4, 0.8, 1.0)      # Cyan - owned
const ACCENT_SECONDARY := Color(0.98, 0.7, 0.2)   # Gold - can buy
const ACCENT_SUCCESS := Color(0.3, 0.9, 0.4)      # Green - active
const ACCENT_LOCKED := Color(0.35, 0.37, 0.42)    # Gray - locked
const TEXT_PRIMARY := Color(1.0, 1.0, 1.0)
const TEXT_SECONDARY := Color(0.6, 0.63, 0.7)
const TEXT_MUTED := Color(0.4, 0.42, 0.48)
const BORDER_COLOR := Color(0.2, 0.22, 0.28)

# Tree layout - defines grid positions for each unlockable
const TREE_LAYOUT := {
	"portal_hp_1": Vector2(0, 0),
	"auto_shield_20": Vector2(1, 0),
	"td_resources_1": Vector2(2, 0),
	"portal_hp_2": Vector2(0, 1),
	"auto_shield_15": Vector2(1, 1),
	"td_resources_2": Vector2(2, 1),
	"portal_hp_3": Vector2(0, 2),
	"auto_shield_10": Vector2(1, 2),
	"td_resources_3": Vector2(2, 2),
	"burst_mode": Vector2(0.5, 3),
	"vampire": Vector2(1.5, 3),
}

const COLUMN_TITLES := ["PORTAL HP", "AUTO-SHIELD", "TD RESOURCES"]
const COLUMN_TITLES_DE := ["PORTAL HP", "AUTO-SCHILD", "TD RESSOURCEN"]

var selected_index: int = 0
var node_list: Array = []
var scroll_offset: float = 0.0
var target_scroll: float = 0.0
var bold_font: Font = null
var sparkle_time: float = 0.0
var confirming_purchase: bool = false
var hovered_index: int = -1

func _ready() -> void:
	build_node_list()
	calculate_tree_centering()
	bold_font = load("res://assets/fonts/EurostileBold.tres")
	DebugHelper.log_info("EvolutionTreeState ready")

func calculate_tree_centering() -> void:
	var total_width: float = (TREE_COLUMNS - 1) * NODE_SPACING.x + NODE_SIZE.x
	tree_offset_x = (GameConfig.SCREEN_WIDTH - total_width) / 2.0

func on_enter(_params: Dictionary) -> void:
	DebugHelper.log_info("EvolutionTreeState entered")
	MenuBackground.show_background()
	selected_index = 0
	scroll_offset = 0.0
	confirming_purchase = false
	calculate_tree_centering()
	queue_redraw()

func on_exit() -> void:
	DebugHelper.log_info("EvolutionTreeState exiting")

func build_node_list() -> void:
	node_list.clear()
	var sorted_nodes: Array = []
	for id in TREE_LAYOUT:
		var pos: Vector2 = TREE_LAYOUT[id]
		sorted_nodes.append({"id": id, "pos": pos})
	sorted_nodes.sort_custom(func(a, b):
		if a.pos.y != b.pos.y:
			return a.pos.y < b.pos.y
		return a.pos.x < b.pos.x
	)
	for node in sorted_nodes:
		node_list.append(node.id)

func _process(delta: float) -> void:
	sparkle_time += delta
	if abs(scroll_offset - target_scroll) > 0.5:
		scroll_offset = lerp(scroll_offset, target_scroll, delta * 12.0)
	queue_redraw()

func _input(event: InputEvent) -> void:
	if confirming_purchase:
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				confirm_purchase()
			elif event.keycode == KEY_ESCAPE:
				confirming_purchase = false
				SoundManager.play_menu_back()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			handle_confirmation_click(event.position)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and event.pressed and not event.is_echo():
		match event.keycode:
			KEY_ESCAPE:
				StateManager.change_state("menu")
				SoundManager.play_menu_back()
				get_viewport().set_input_as_handled()
			KEY_LEFT, KEY_A:
				navigate(-1, 0)
			KEY_RIGHT, KEY_D:
				navigate(1, 0)
			KEY_UP, KEY_W:
				navigate(0, -1)
			KEY_DOWN, KEY_S:
				navigate(0, 1)
			KEY_ENTER, KEY_KP_ENTER:
				activate_selected()
			KEY_SPACE:
				toggle_selected()

	if event is InputEventMouseMotion:
		var new_hover := get_node_at_position(event.position)
		if new_hover != hovered_index:
			hovered_index = new_hover
			if hovered_index != -1 and hovered_index != selected_index:
				selected_index = hovered_index
				SoundManager.play_menu_select()
			queue_redraw()

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				var clicked := get_node_at_position(event.position)
				if clicked != -1:
					selected_index = clicked
					activate_selected()
			MOUSE_BUTTON_WHEEL_UP:
				target_scroll = maxf(0, target_scroll - 50)
			MOUSE_BUTTON_WHEEL_DOWN:
				target_scroll = minf(200, target_scroll + 50)
			MOUSE_BUTTON_XBUTTON1:
				StateManager.change_state("menu")
				SoundManager.play_menu_back()

func get_node_at_position(pos: Vector2) -> int:
	for i in range(node_list.size()):
		var id: String = node_list[i]
		var node_pos := get_node_screen_position(id)
		var rect := Rect2(node_pos, NODE_SIZE)
		if rect.has_point(pos):
			return i
	return -1

func navigate(dx: int, dy: int) -> void:
	if node_list.is_empty():
		return
	var current_id: String = node_list[selected_index]
	var current_pos: Vector2 = TREE_LAYOUT[current_id]
	var target_pos := current_pos + Vector2(dx, dy)
	var best_index := selected_index
	var best_dist := 999.0
	for i in range(node_list.size()):
		var pos: Vector2 = TREE_LAYOUT[node_list[i]]
		if dy != 0 and sign(pos.y - current_pos.y) != sign(dy):
			continue
		if dx != 0 and sign(pos.x - current_pos.x) != sign(dx):
			continue
		var dist := pos.distance_to(target_pos)
		if dist < best_dist and i != selected_index:
			best_dist = dist
			best_index = i
	if best_index != selected_index:
		selected_index = best_index
		SoundManager.play_menu_select()
		queue_redraw()

func activate_selected() -> void:
	if node_list.is_empty() or not ProgressionManager:
		return
	var id: String = node_list[selected_index]
	if ProgressionManager.is_unlocked(id):
		toggle_selected()
	else:
		var check := ProgressionManager.can_unlock(id)
		if check.can_unlock:
			confirming_purchase = true
			SoundManager.play_menu_select()
			queue_redraw()
		else:
			SoundManager.play_type_error()

func confirm_purchase() -> void:
	if node_list.is_empty() or not ProgressionManager:
		return
	var id: String = node_list[selected_index]
	if ProgressionManager.purchase_unlock(id):
		SoundManager.play_word_complete()
	confirming_purchase = false
	queue_redraw()

func handle_confirmation_click(pos: Vector2) -> void:
	var dialog_rect := get_confirmation_dialog_rect()
	var confirm_btn := Rect2(dialog_rect.position.x + 20, dialog_rect.position.y + dialog_rect.size.y - 50, 100, 35)
	var cancel_btn := Rect2(dialog_rect.position.x + dialog_rect.size.x - 120, dialog_rect.position.y + dialog_rect.size.y - 50, 100, 35)
	if confirm_btn.has_point(pos):
		confirm_purchase()
	elif cancel_btn.has_point(pos) or not dialog_rect.has_point(pos):
		confirming_purchase = false
		SoundManager.play_menu_back()

func get_confirmation_dialog_rect() -> Rect2:
	var dialog_size := Vector2(320, 180)
	var dialog_pos := Vector2((GameConfig.SCREEN_WIDTH - dialog_size.x) / 2, (GameConfig.SCREEN_HEIGHT - dialog_size.y) / 2)
	return Rect2(dialog_pos, dialog_size)

func toggle_selected() -> void:
	if node_list.is_empty() or not ProgressionManager:
		return
	var id: String = node_list[selected_index]
	if not ProgressionManager.is_unlocked(id):
		return
	var data: Dictionary = ProgressionManager.UNLOCKABLES.get(id, {})
	if data.category == ProgressionManager.UnlockCategory.EVOLUTION:
		ProgressionManager.toggle_evolution(id)
		SoundManager.play_menu_select()
	elif data.category == ProgressionManager.UnlockCategory.START_BONUS:
		ProgressionManager.toggle_bonus(id)
		SoundManager.play_menu_select()
	queue_redraw()

func _draw() -> void:
	var width := GameConfig.SCREEN_WIDTH
	var height := GameConfig.SCREEN_HEIGHT
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(0, 0, width, height), BG_DARK)
	draw_header(font, width)
	draw_column_titles(font)
	draw_connections()
	draw_tree_nodes(font)
	draw_evolution_title(font)
	draw_footer(font, width, height)
	draw_confirmation_dialog(font)

func draw_header(font: Font, width: float) -> void:
	var currency := ProgressionManager.get_currency() if ProgressionManager else 0
	var lang = SaveManager.get_setting("language") if SaveManager else "EN"
	var title = "EVOLUTION TREE" if lang != "DE" else "EVOLUTIONSBAUM"
	var title_font: Font = bold_font if bold_font else font
	draw_string(title_font, Vector2(MARGIN, 50), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, TEXT_PRIMARY)
	draw_cost_chip(font, Vector2(width - MARGIN - 90, 32), currency, true)

func draw_column_titles(font: Font) -> void:
	var lang = SaveManager.get_setting("language") if SaveManager else "EN"
	var titles = COLUMN_TITLES_DE if lang == "DE" else COLUMN_TITLES
	var title_font: Font = bold_font if bold_font else font
	for i in range(3):
		var x := get_column_x(i) + NODE_SIZE.x / 2
		var y := HEADER_HEIGHT + 20 - scroll_offset
		draw_string(title_font, Vector2(x - 80, y), titles[i], HORIZONTAL_ALIGNMENT_CENTER, 160, 14, TEXT_SECONDARY)

func draw_evolution_title(font: Font) -> void:
	var lang = SaveManager.get_setting("language") if SaveManager else "EN"
	var title = "EVOLUTIONS" if lang != "DE" else "EVOLUTIONEN"
	var y := HEADER_HEIGHT + 50 + 2.9 * NODE_SPACING.y - scroll_offset
	var title_font: Font = bold_font if bold_font else font
	draw_line(Vector2(MARGIN, y), Vector2(GameConfig.SCREEN_WIDTH - MARGIN, y), BORDER_COLOR, 1)
	draw_string(title_font, Vector2(GameConfig.SCREEN_WIDTH / 2 - 70, y + 22), title, HORIZONTAL_ALIGNMENT_CENTER, 140, 16, TEXT_SECONDARY)

func draw_connections() -> void:
	if not ProgressionManager:
		return
	for id in ProgressionManager.UNLOCKABLES:
		var data: Dictionary = ProgressionManager.UNLOCKABLES[id]
		if data.requires == null:
			continue
		var from_id: String = data.requires
		if not TREE_LAYOUT.has(from_id) or not TREE_LAYOUT.has(id):
			continue
		var from_screen := get_node_screen_position(from_id) + Vector2(NODE_SIZE.x / 2, NODE_SIZE.y)
		var to_screen := get_node_screen_position(id) + Vector2(NODE_SIZE.x / 2, 0)
		var color := CONNECTION_ACTIVE_COLOR if ProgressionManager.is_unlocked(from_id) else CONNECTION_COLOR
		draw_line(from_screen, to_screen, color, 2.0)

func draw_tree_nodes(font: Font) -> void:
	for i in range(node_list.size()):
		var id: String = node_list[i]
		var is_selected := (i == selected_index)
		draw_node(font, id, is_selected)

func draw_node(font: Font, id: String, selected: bool) -> void:
	if not ProgressionManager:
		return
	var data: Dictionary = ProgressionManager.UNLOCKABLES.get(id, {})
	var pos := get_node_screen_position(id)
	var rect := Rect2(pos, NODE_SIZE)
	var is_unlocked := ProgressionManager.is_unlocked(id)
	var is_active := ProgressionManager.is_bonus_active(id) or ProgressionManager.is_evolution_active(id)
	var can_unlock_result := ProgressionManager.can_unlock(id)
	var can_unlock: bool = can_unlock_result.can_unlock
	var bg_color := BG_CARD_HOVER if selected else BG_CARD
	draw_rect(rect, bg_color)
	var border_color := BORDER_COLOR
	if is_active:
		border_color = ACCENT_SUCCESS
	elif is_unlocked:
		border_color = ACCENT_PRIMARY
	elif can_unlock:
		border_color = ACCENT_SECONDARY
	if selected:
		border_color = border_color.lightened(0.3)
	draw_rect(Rect2(pos.x, pos.y, NODE_SIZE.x, 2), border_color)
	draw_rect(Rect2(pos.x, pos.y + NODE_SIZE.y - 2, NODE_SIZE.x, 2), border_color)
	draw_rect(Rect2(pos.x, pos.y, 2, NODE_SIZE.y), border_color)
	draw_rect(Rect2(pos.x + NODE_SIZE.x - 2, pos.y, 2, NODE_SIZE.y), border_color)
	var lang = SaveManager.get_setting("language") if SaveManager else "EN"
	var status_color := ACCENT_LOCKED
	var status_text := "LOCKED" if lang != "DE" else "GESPERRT"
	if is_active:
		status_color = ACCENT_SUCCESS
		status_text = "ON" if lang != "DE" else "AN"
	elif is_unlocked:
		status_color = ACCENT_PRIMARY
		status_text = "OFF" if lang != "DE" else "AUS"
	elif can_unlock:
		status_color = ACCENT_SECONDARY
		status_text = ""
		draw_sparkles(pos, NODE_SIZE)
	draw_rect(Rect2(pos.x + 10, pos.y + 10, 10, 10), status_color)
	var name_text := ProgressionManager.get_localized_name(data)
	var name_color := TEXT_PRIMARY if is_unlocked else TEXT_SECONDARY
	var name_font: Font = bold_font if bold_font else font
	draw_string(name_font, Vector2(pos.x + 28, pos.y + 30), name_text, HORIZONTAL_ALIGNMENT_LEFT, NODE_SIZE.x - 36, 16, name_color)
	var desc_text := ProgressionManager.get_localized_description(data)
	var desc_color := TEXT_SECONDARY if is_unlocked else TEXT_MUTED
	draw_string(font, Vector2(pos.x + 10, pos.y + 55), desc_text, HORIZONTAL_ALIGNMENT_LEFT, NODE_SIZE.x - 20, 12, desc_color)
	if can_unlock and not is_unlocked:
		draw_cost_chip(font, Vector2(pos.x + NODE_SIZE.x - 85, pos.y + NODE_SIZE.y - 32), data.cost, false)
	else:
		draw_string(font, Vector2(pos.x + NODE_SIZE.x - 70, pos.y + NODE_SIZE.y - 16), status_text, HORIZONTAL_ALIGNMENT_RIGHT, 60, 13, status_color)

func get_column_x(col: int) -> float:
	return tree_offset_x + col * NODE_SPACING.x

func get_node_screen_position(id: String) -> Vector2:
	if not TREE_LAYOUT.has(id):
		return Vector2.ZERO
	var grid_pos: Vector2 = TREE_LAYOUT[id]
	var base_y := HEADER_HEIGHT + 50 - scroll_offset
	var extra_y := 40.0 if grid_pos.y >= 3 else 0.0
	return Vector2(tree_offset_x + grid_pos.x * NODE_SPACING.x, base_y + grid_pos.y * NODE_SPACING.y + extra_y)

func draw_sparkles(pos: Vector2, size: Vector2) -> void:
	var num_sparkles := 6
	for i in range(num_sparkles):
		var angle := (TAU / num_sparkles) * i + sparkle_time * 1.5
		var sparkle_pos := Vector2(pos.x + size.x * 0.5 + cos(angle) * (size.x * 0.55), pos.y + size.y * 0.5 + sin(angle) * (size.y * 0.55))
		var alpha := (sin(sparkle_time * 4.0 + i * 1.2) + 1.0) * 0.4
		var sparkle_color := Color(ACCENT_SECONDARY.r, ACCENT_SECONDARY.g, ACCENT_SECONDARY.b, alpha)
		var sparkle_size := 2.0 + sin(sparkle_time * 5.0 + i) * 1.0
		draw_circle(sparkle_pos, sparkle_size, sparkle_color)

func draw_cost_chip(font: Font, pos: Vector2, cost: int, large: bool) -> void:
	var chip_width := 80.0 if large else 75.0
	var chip_height := 28.0 if large else 26.0
	var chip_rect := Rect2(pos.x, pos.y, chip_width, chip_height)
	draw_rect(chip_rect, Color(0.18, 0.14, 0.05))
	draw_rect(Rect2(pos.x, pos.y, chip_width, 2), ACCENT_SECONDARY)
	draw_rect(Rect2(pos.x, pos.y + chip_height - 2, chip_width, 2), ACCENT_SECONDARY.darkened(0.3))
	draw_rect(Rect2(pos.x, pos.y, 2, chip_height), ACCENT_SECONDARY.darkened(0.2))
	draw_rect(Rect2(pos.x + chip_width - 2, pos.y, 2, chip_height), ACCENT_SECONDARY.darkened(0.2))
	var coin_x := pos.x + 15
	var coin_y := pos.y + chip_height / 2
	var coin_r := 8.0 if large else 7.0
	draw_circle(Vector2(coin_x, coin_y), coin_r, ACCENT_SECONDARY)
	draw_circle(Vector2(coin_x, coin_y), coin_r * 0.45, Color(0.18, 0.14, 0.05))
	var title_font: Font = bold_font if bold_font else font
	var font_size := 18 if large else 16
	draw_string(title_font, Vector2(pos.x + 28, pos.y + chip_height - 7), str(cost), HORIZONTAL_ALIGNMENT_LEFT, 45, font_size, ACCENT_SECONDARY)

func draw_confirmation_dialog(font: Font) -> void:
	if not confirming_purchase:
		return
	var id: String = node_list[selected_index]
	var data: Dictionary = ProgressionManager.UNLOCKABLES.get(id, {})
	var lang = SaveManager.get_setting("language") if SaveManager else "EN"
	draw_rect(Rect2(0, 0, GameConfig.SCREEN_WIDTH, GameConfig.SCREEN_HEIGHT), Color(0, 0, 0, 0.7))
	var dialog_rect := get_confirmation_dialog_rect()
	draw_rect(dialog_rect, BG_CARD)
	draw_rect(Rect2(dialog_rect.position.x, dialog_rect.position.y, dialog_rect.size.x, 3), ACCENT_SECONDARY)
	draw_rect(Rect2(dialog_rect.position.x, dialog_rect.position.y + dialog_rect.size.y - 2, dialog_rect.size.x, 2), BORDER_COLOR)
	draw_rect(Rect2(dialog_rect.position.x, dialog_rect.position.y, 2, dialog_rect.size.y), BORDER_COLOR)
	draw_rect(Rect2(dialog_rect.position.x + dialog_rect.size.x - 2, dialog_rect.position.y, 2, dialog_rect.size.y), BORDER_COLOR)
	var title_font: Font = bold_font if bold_font else font
	var title_text = "ACQUIRE?" if lang != "DE" else "ERWERBEN?"
	draw_string(title_font, Vector2(dialog_rect.position.x + dialog_rect.size.x / 2 - 60, dialog_rect.position.y + 38), title_text, HORIZONTAL_ALIGNMENT_CENTER, 120, 24, TEXT_PRIMARY)
	var name_text := ProgressionManager.get_localized_name(data)
	draw_string(title_font, Vector2(dialog_rect.position.x + 20, dialog_rect.position.y + 75), name_text, HORIZONTAL_ALIGNMENT_LEFT, dialog_rect.size.x - 40, 18, ACCENT_PRIMARY)
	draw_cost_chip(font, Vector2(dialog_rect.position.x + dialog_rect.size.x / 2 - 40, dialog_rect.position.y + 90), data.cost, true)
	var btn_y := dialog_rect.position.y + dialog_rect.size.y - 50
	var confirm_text = "YES" if lang != "DE" else "JA"
	var cancel_text = "NO" if lang != "DE" else "NEIN"
	draw_rect(Rect2(dialog_rect.position.x + 20, btn_y, 100, 35), ACCENT_SUCCESS.darkened(0.6))
	draw_rect(Rect2(dialog_rect.position.x + 20, btn_y, 100, 2), ACCENT_SUCCESS)
	draw_string(title_font, Vector2(dialog_rect.position.x + 45, btn_y + 24), confirm_text, HORIZONTAL_ALIGNMENT_CENTER, 50, 16, ACCENT_SUCCESS)
	draw_rect(Rect2(dialog_rect.position.x + dialog_rect.size.x - 120, btn_y, 100, 35), Color(0.35, 0.15, 0.15))
	draw_rect(Rect2(dialog_rect.position.x + dialog_rect.size.x - 120, btn_y, 100, 2), Color(1, 0.4, 0.4))
	draw_string(title_font, Vector2(dialog_rect.position.x + dialog_rect.size.x - 95, btn_y + 24), cancel_text, HORIZONTAL_ALIGNMENT_CENTER, 50, 16, Color(1, 0.5, 0.5))

func draw_footer(font: Font, width: float, height: float) -> void:
	var footer_y := height - 50
	draw_rect(Rect2(0, footer_y, width, 50), Color(0.04, 0.05, 0.08))
	draw_line(Vector2(0, footer_y), Vector2(width, footer_y), BORDER_COLOR, 1)
	
	# Back button
	var back_rect := get_back_button_rect()
	draw_rect(back_rect, Color(0.15, 0.15, 0.2))
	draw_rect(Rect2(back_rect.position.x, back_rect.position.y, back_rect.size.x, 2), ACCENT_PRIMARY.darkened(0.3))
	var title_font: Font = bold_font if bold_font else font
	var lang = SaveManager.get_setting("language") if SaveManager else "EN"
	var back_text = "< BACK" if lang != "DE" else "< ZURUECK"
	draw_string(title_font, Vector2(back_rect.position.x + 15, back_rect.position.y + 24), back_text, HORIZONTAL_ALIGNMENT_LEFT, 80, 14, ACCENT_PRIMARY)
	
	var hints := "ARROWS/MOUSE Navigate  |  ENTER/CLICK Buy/Toggle"
	if lang == "DE":
		hints = "PFEILE/MAUS Navigieren  |  ENTER/KLICK Kaufen"
	draw_string(font, Vector2(width / 2 - 150, footer_y + 30), hints, HORIZONTAL_ALIGNMENT_LEFT, 300, 13, TEXT_MUTED)

func get_back_button_rect() -> Rect2:
	return Rect2(MARGIN, GameConfig.SCREEN_HEIGHT - 42, 100, 34)

func is_back_button_clicked(pos: Vector2) -> bool:
	return get_back_button_rect().has_point(pos)
