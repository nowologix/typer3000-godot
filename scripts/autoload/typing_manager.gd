## typing_manager.gd
## Handles all typing input, word matching, and combo tracking
## Supports parallel tracking of enemies, powerups, and BUILD command
## Autoload singleton: TypingManager
extends Node

# Current typing state
var active_enemy: Node = null
var active_powerup: Node = null
var typed_index: int = 0
var combo: int = 0
var max_combo: int = 0
var errors: int = 0
var total_chars_typed: int = 0
var correct_chars_typed: int = 0

# Parallel tracking - track multiple potential targets
var potential_enemies: Array = []
var potential_powerups: Array = []
var typed_buffer: String = ""  # What user has typed so far

# Typing enabled flag
var typing_enabled: bool = false

# Powerup effects
var combo_keeper_active: bool = false

# BUILD command detection
const BUILD_TRIGGER := "BUILD"
var build_buffer: String = ""

# Reference to enemy container (set by game state)
var enemy_container: Node = null

func _ready() -> void:
	DebugHelper.log_info("TypingManager initialized")

func _input(event: InputEvent) -> void:
	if not typing_enabled:
		return

	if event is InputEventKey and event.pressed and not event.is_echo():
		var char_code = event.unicode
		if char_code >= 65 and char_code <= 90:
			process_char(char(char_code))
		elif char_code >= 97 and char_code <= 122:
			process_char(char(char_code).to_upper())
		elif char_code >= 48 and char_code <= 57 and BuildManager.is_building():
			process_char(char(char_code))

func process_char(typed_char: String) -> void:
	total_chars_typed += 1

	# If in build mode, forward to BuildManager
	if BuildManager.is_building():
		var result = BuildManager.process_char(typed_char)
		handle_build_result(result)
		build_buffer = ""
		typed_buffer = ""
		return

	# Track BUILD in parallel
	var new_build_buffer = build_buffer + typed_char
	var build_matches = BUILD_TRIGGER.begins_with(new_build_buffer)

	# Check if we have a locked target
	if active_enemy != null and is_instance_valid(active_enemy):
		process_active_enemy(typed_char, build_matches, new_build_buffer)
		return

	if active_powerup != null and is_instance_valid(active_powerup):
		process_active_powerup(typed_char, build_matches, new_build_buffer)
		return

	# No locked target - use parallel tracking
	var new_typed_buffer = typed_buffer + typed_char

	# Update BUILD buffer
	if build_matches:
		build_buffer = new_build_buffer
	else:
		build_buffer = ""

	# Find all matching targets
	var matching_enemies = find_enemies_matching(new_typed_buffer)
	var matching_powerups = find_powerups_matching(new_typed_buffer)

	var total_matches = matching_enemies.size() + matching_powerups.size()
	if build_matches:
		total_matches += 1

	if total_matches == 0:
		# Nothing matches - error
		on_typing_error()
		SignalBus.char_typed.emit(typed_char, false)
		typed_buffer = ""
		return

	# Something matches
	typed_buffer = new_typed_buffer
	correct_chars_typed += 1
	combo += 1
	if combo > max_combo:
		max_combo = combo
	SoundManager.play_type_correct()
	SignalBus.char_typed.emit(typed_char, true)
	SignalBus.combo_updated.emit(combo)

	# Check if BUILD is complete
	if build_matches and build_buffer == BUILD_TRIGGER:
		BuildManager.enter_build_mode()
		build_buffer = ""
		typed_buffer = ""
		clear_potential_targets()
		SoundManager.play_menu_select()
		return

	# Check if exactly one target matches - lock onto it
	if matching_enemies.size() == 1 and matching_powerups.size() == 0 and not build_matches:
		lock_onto_enemy(matching_enemies[0], new_typed_buffer.length())
		typed_buffer = ""
		return

	if matching_powerups.size() == 1 and matching_enemies.size() == 0 and not build_matches:
		lock_onto_powerup(matching_powerups[0], new_typed_buffer.length())
		typed_buffer = ""
		return

	# Check for exact word match
	for enemy in matching_enemies:
		if enemy.word.to_upper() == new_typed_buffer:
			lock_onto_enemy(enemy, new_typed_buffer.length())
			complete_word()
			typed_buffer = ""
			return

	for powerup in matching_powerups:
		if powerup.word.to_upper() == new_typed_buffer:
			lock_onto_powerup(powerup, new_typed_buffer.length())
			complete_powerup()
			typed_buffer = ""
			return

	# Multiple matches - update visual feedback on all
	update_potential_targets(matching_enemies, matching_powerups, new_typed_buffer.length())

func process_active_enemy(typed_char: String, build_matches: bool, new_build_buffer: String) -> void:
	var word = active_enemy.word
	if typed_index >= word.length():
		return

	var expected_char = word[typed_index].to_upper()
	if typed_char == expected_char:
		# Correct character
		if build_matches:
			build_buffer = new_build_buffer
		else:
			build_buffer = ""

		typed_index += 1
		combo += 1
		correct_chars_typed += 1
		if combo > max_combo:
			max_combo = combo
		SoundManager.play_type_correct()
		if is_instance_valid(active_enemy) and enemy_container:
			EffectsManager.spawn_hit_effect(active_enemy.global_position, enemy_container)
		if combo == 5 or combo == 10 or combo == 25:
			SoundManager.play_combo_milestone(combo)
		SignalBus.char_typed.emit(typed_char, true)
		SignalBus.combo_updated.emit(combo)
		if active_enemy.has_method("update_typed_progress"):
			active_enemy.update_typed_progress(typed_index)
		if typed_index >= word.length():
			complete_word()
	else:
		# Wrong character - check alternatives
		if build_matches:
			build_buffer = new_build_buffer
			# Release enemy, continue BUILD
			if active_enemy.has_method("update_typed_progress"):
				active_enemy.update_typed_progress(0)
			active_enemy = null
			typed_index = 0
			if build_buffer == BUILD_TRIGGER:
				BuildManager.enter_build_mode()
				build_buffer = ""
				SoundManager.play_menu_select()
		else:
			on_typing_error()
			SignalBus.char_typed.emit(typed_char, false)

func process_active_powerup(typed_char: String, build_matches: bool, new_build_buffer: String) -> void:
	var word = active_powerup.word
	if typed_index >= word.length():
		return

	var expected_char = word[typed_index].to_upper()
	if typed_char == expected_char:
		if build_matches:
			build_buffer = new_build_buffer
		else:
			build_buffer = ""

		typed_index += 1
		combo += 1
		correct_chars_typed += 1
		if combo > max_combo:
			max_combo = combo
		SoundManager.play_type_correct()
		if is_instance_valid(active_powerup) and enemy_container:
			EffectsManager.spawn_hit_effect(active_powerup.global_position, enemy_container)
		SignalBus.char_typed.emit(typed_char, true)
		SignalBus.combo_updated.emit(combo)
		if active_powerup.has_method("update_typed_progress"):
			active_powerup.update_typed_progress(typed_index)
		if typed_index >= word.length():
			complete_powerup()
	else:
		# Wrong character - check if enemy matches instead
		var matching_enemies = find_enemies_matching(typed_buffer + typed_char) if typed_buffer.length() > 0 else []

		if build_matches:
			build_buffer = new_build_buffer
			if active_powerup.has_method("update_typed_progress"):
				active_powerup.update_typed_progress(0)
			active_powerup = null
			typed_index = 0
			if build_buffer == BUILD_TRIGGER:
				BuildManager.enter_build_mode()
				build_buffer = ""
				SoundManager.play_menu_select()
		elif matching_enemies.size() > 0:
			# Switch to enemy
			if active_powerup.has_method("update_typed_progress"):
				active_powerup.update_typed_progress(0)
			active_powerup = null
			lock_onto_enemy(matching_enemies[0], typed_buffer.length() + 1)
			typed_buffer = ""
			combo += 1
			correct_chars_typed += 1
			SoundManager.play_type_correct()
			SignalBus.char_typed.emit(typed_char, true)
		else:
			on_typing_error()
			SignalBus.char_typed.emit(typed_char, false)

func find_enemies_matching(prefix: String) -> Array:
	var matches: Array = []
	if enemy_container == null:
		return matches

	for enemy in enemy_container.get_children():
		if enemy.has_method("get_word") and enemy.has_method("is_alive") and enemy.is_alive():
			var word = enemy.get_word().to_upper()
			if word.begins_with(prefix):
				matches.append(enemy)

	# Sort by distance to portal (closest first)
	matches.sort_custom(func(a, b):
		var dist_a = GameConfig.SCREEN_HEIGHT - a.position.y
		var dist_b = GameConfig.SCREEN_HEIGHT - b.position.y
		return dist_a < dist_b
	)

	return matches

func find_powerups_matching(prefix: String) -> Array:
	var matches: Array = []
	var powerups = get_tree().get_nodes_in_group("powerups")

	for powerup in powerups:
		if powerup.has_method("get_word") and powerup.has_method("is_alive") and powerup.is_alive():
			var word = powerup.get_word().to_upper()
			if word.begins_with(prefix):
				matches.append(powerup)

	return matches

func lock_onto_enemy(enemy: Node, progress: int) -> void:
	active_enemy = enemy
	active_powerup = null
	typed_index = progress
	if active_enemy.has_method("update_typed_progress"):
		active_enemy.update_typed_progress(typed_index)
	SignalBus.word_started.emit(active_enemy)
	DebugHelper.log_debug("Locked onto enemy: %s (progress: %d)" % [active_enemy.word, progress])

func lock_onto_powerup(powerup: Node, progress: int) -> void:
	active_powerup = powerup
	active_enemy = null
	typed_index = progress
	if active_powerup.has_method("update_typed_progress"):
		active_powerup.update_typed_progress(typed_index)
	DebugHelper.log_debug("Locked onto powerup: %s (progress: %d)" % [active_powerup.word, progress])

func update_potential_targets(enemies: Array, powerups: Array, progress: int) -> void:
	# Update visual progress on all potential targets
	for enemy in enemies:
		if enemy.has_method("update_typed_progress"):
			enemy.update_typed_progress(progress)

	for powerup in powerups:
		if powerup.has_method("update_typed_progress"):
			powerup.update_typed_progress(progress)

	potential_enemies = enemies
	potential_powerups = powerups

func clear_potential_targets() -> void:
	for enemy in potential_enemies:
		if is_instance_valid(enemy) and enemy.has_method("update_typed_progress"):
			enemy.update_typed_progress(0)

	for powerup in potential_powerups:
		if is_instance_valid(powerup) and powerup.has_method("update_typed_progress"):
			powerup.update_typed_progress(0)

	potential_enemies = []
	potential_powerups = []

func complete_word() -> void:
	if active_enemy != null and is_instance_valid(active_enemy):
		DebugHelper.log_debug("Word completed: %s (combo: %d)" % [active_enemy.word, combo])
		SignalBus.word_completed.emit(active_enemy, combo)
		SignalBus.enemy_killed.emit(active_enemy, true)

		if active_enemy.has_method("die"):
			active_enemy.die()

	active_enemy = null
	typed_index = 0
	clear_potential_targets()

func complete_powerup() -> void:
	if active_powerup != null and is_instance_valid(active_powerup):
		DebugHelper.log_debug("PowerUp completed: %s" % active_powerup.word)
		if active_powerup.has_method("collect"):
			active_powerup.collect()

	active_powerup = null
	typed_index = 0
	clear_potential_targets()

func on_typing_error() -> void:
	errors += 1
	SoundManager.play_type_error()

	if not combo_keeper_active:
		if combo >= 5:
			SoundManager.play_combo_break()
		combo = 0
		SignalBus.combo_reset.emit()

	if active_enemy != null and is_instance_valid(active_enemy):
		if active_enemy.has_method("update_typed_progress"):
			active_enemy.update_typed_progress(0)
		SignalBus.word_failed.emit(active_enemy)

	if active_powerup != null and is_instance_valid(active_powerup):
		if active_powerup.has_method("update_typed_progress"):
			active_powerup.update_typed_progress(0)

	active_enemy = null
	active_powerup = null
	typed_index = 0
	typed_buffer = ""
	build_buffer = ""
	clear_potential_targets()

func handle_build_result(result: Dictionary) -> void:
	match result["action"]:
		"tower_placed":
			SoundManager.play_tower_build()
			DebugHelper.log_info("Tower placed!")
		"tower_selected":
			SoundManager.play_menu_select()
		"cancel":
			SoundManager.play_menu_back()
		"invalid", "position_occupied", "insufficient_points", "wave_limit":
			SoundManager.play_type_error()
		"typing":
			SoundManager.play_menu_select()

func enable_typing() -> void:
	typing_enabled = true
	build_buffer = ""
	typed_buffer = ""
	DebugHelper.log_debug("Typing enabled")

func disable_typing() -> void:
	typing_enabled = false
	active_enemy = null
	active_powerup = null
	typed_index = 0
	typed_buffer = ""
	DebugHelper.log_debug("Typing disabled")

func set_enemy_container(container: Node) -> void:
	enemy_container = container
	DebugHelper.log_debug("Enemy container set: %s" % container.name)

func reset_stats() -> void:
	combo = 0
	max_combo = 0
	errors = 0
	total_chars_typed = 0
	correct_chars_typed = 0
	active_enemy = null
	active_powerup = null
	typed_index = 0
	build_buffer = ""
	typed_buffer = ""
	clear_potential_targets()

func get_stats() -> Dictionary:
	var accuracy = 0.0
	if total_chars_typed > 0:
		accuracy = (float(correct_chars_typed) / float(total_chars_typed)) * 100.0

	return {
		"combo": combo,
		"max_combo": max_combo,
		"errors": errors,
		"total_chars": total_chars_typed,
		"correct_chars": correct_chars_typed,
		"accuracy": accuracy
	}
