## typing_manager.gd
## Handles all typing input, word matching, and combo tracking
## Autoload singleton: TypingManager
extends Node

# Current typing state
var active_enemy: Node = null
var active_powerup: Node = null  # Can also target powerups
var typed_index: int = 0
var combo: int = 0
var max_combo: int = 0
var errors: int = 0
var total_chars_typed: int = 0
var correct_chars_typed: int = 0

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
		# A-Z (uppercase)
		if char_code >= 65 and char_code <= 90:
			process_char(char(char_code))
		# a-z (lowercase) -> convert to uppercase
		elif char_code >= 97 and char_code <= 122:
			process_char(char(char_code).to_upper())
		# 0-9 (numbers) - only in build mode for position selection
		elif char_code >= 48 and char_code <= 57 and BuildManager.is_building():
			process_char(char(char_code))

func process_char(typed_char: String) -> void:
	total_chars_typed += 1

	# If in build mode, forward to BuildManager
	if BuildManager.is_building():
		var result = BuildManager.process_char(typed_char)
		handle_build_result(result)
		build_buffer = ""
		return

	# Always track BUILD buffer in parallel
	var new_build_buffer = build_buffer + typed_char
	var build_still_matches = BUILD_TRIGGER.begins_with(new_build_buffer)

	# Check if we have an active target
	var has_active_target = (active_enemy != null and is_instance_valid(active_enemy)) or 							(active_powerup != null and is_instance_valid(active_powerup))

	if has_active_target:
		# Already have a target - process normally, but keep tracking BUILD
		if build_still_matches:
			build_buffer = new_build_buffer
			if build_buffer == BUILD_TRIGGER:
				# BUILD complete while typing enemy - enter build mode
				BuildManager.enter_build_mode()
				build_buffer = ""
				# Reset enemy target
				if active_enemy != null and active_enemy.has_method("update_typed_progress"):
					active_enemy.update_typed_progress(0)
				active_enemy = null
				active_powerup = null
				typed_index = 0
				SoundManager.play_menu_select()
				return
		else:
			build_buffer = ""

		# Continue processing active target
		if active_powerup != null and is_instance_valid(active_powerup):
			process_powerup_char(typed_char)
			return

		if active_enemy != null and is_instance_valid(active_enemy):
			var word = active_enemy.word
			if typed_index < word.length():
				var expected_char = word[typed_index].to_upper()
				if typed_char == expected_char:
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
					# Enemy word failed - check if BUILD still matches
					if build_still_matches:
						# Switch to BUILD-only mode - reset enemy target silently
						if active_enemy.has_method("update_typed_progress"):
							active_enemy.update_typed_progress(0)
						active_enemy = null
						active_powerup = null
						typed_index = 0
						# Check if BUILD is complete
						if build_buffer == BUILD_TRIGGER:
							BuildManager.enter_build_mode()
							build_buffer = ""
							SoundManager.play_menu_select()
						# BUILD still in progress - no error sound
					else:
						on_typing_error()
						SignalBus.char_typed.emit(typed_char, false)
		return

	# No active target - look for matches
	# Update build buffer
	if build_still_matches:
		build_buffer = new_build_buffer
	else:
		build_buffer = ""

	# Try to find enemy/powerup starting with this character
	active_powerup = find_powerup_starting_with(typed_char)
	if active_powerup != null:
		active_enemy = null
		typed_index = 1  # First char already matched
		correct_chars_typed += 1
		combo += 1
		if combo > max_combo:
			max_combo = combo
		SoundManager.play_type_correct()
		SignalBus.char_typed.emit(typed_char, true)
		SignalBus.combo_updated.emit(combo)
		if active_powerup.has_method("update_typed_progress"):
			active_powerup.update_typed_progress(typed_index)
		DebugHelper.log_debug("Locked onto powerup: %s" % active_powerup.word)
		# Check if single-char powerup
		if typed_index >= active_powerup.word.length():
			complete_powerup()
		return

	active_enemy = find_enemy_starting_with(typed_char)
	if active_enemy != null:
		typed_index = 1  # First char already matched
		correct_chars_typed += 1
		combo += 1
		if combo > max_combo:
			max_combo = combo
		SoundManager.play_type_correct()
		if enemy_container:
			EffectsManager.spawn_hit_effect(active_enemy.global_position, enemy_container)
		SignalBus.char_typed.emit(typed_char, true)
		SignalBus.combo_updated.emit(combo)
		if active_enemy.has_method("update_typed_progress"):
			active_enemy.update_typed_progress(typed_index)
		DebugHelper.log_debug("Locked onto enemy: %s" % active_enemy.word)
		SignalBus.word_started.emit(active_enemy)
		# Check if single-char enemy
		if typed_index >= active_enemy.word.length():
			complete_word()
		return

	# No enemy/powerup found
	if build_still_matches:
		# Only BUILD matches - check if complete
		if build_buffer == BUILD_TRIGGER:
			BuildManager.enter_build_mode()
			build_buffer = ""
			SoundManager.play_menu_select()
			return
		# Still typing BUILD, no sound needed
		return
	else:
		# Nothing matches
		on_typing_error()
		SignalBus.char_typed.emit(typed_char, false)


func process_powerup_char(typed_char: String) -> void:
	if active_powerup == null or not is_instance_valid(active_powerup):
		return

	var word = active_powerup.word
	if typed_index < word.length():
		var expected_char = word[typed_index].to_upper()
		if typed_char == expected_char:
			typed_index += 1
			combo += 1
			correct_chars_typed += 1
			if combo > max_combo:
				max_combo = combo

			# Play type sound and spawn hit effect
			SoundManager.play_type_correct()
			if is_instance_valid(active_powerup) and enemy_container:
				EffectsManager.spawn_hit_effect(active_powerup.global_position, enemy_container)

			SignalBus.char_typed.emit(typed_char, true)
			SignalBus.combo_updated.emit(combo)

			if active_powerup.has_method("update_typed_progress"):
				active_powerup.update_typed_progress(typed_index)

			# Check if powerup word is complete
			if typed_index >= word.length():
				complete_powerup()
		else:
			on_typing_error()
			SignalBus.char_typed.emit(typed_char, false)

func complete_powerup() -> void:
	if active_powerup != null and is_instance_valid(active_powerup):
		DebugHelper.log_debug("PowerUp word completed: %s" % active_powerup.word)
		if active_powerup.has_method("collect"):
			active_powerup.collect()

	active_powerup = null
	typed_index = 0

func find_powerup_starting_with(char: String) -> Node:
	var powerups = get_tree().get_nodes_in_group("powerups")
	for powerup in powerups:
		if powerup.has_method("get_word") and powerup.is_alive():
			var word = powerup.get_word()
			if word.length() > 0 and word[0].to_upper() == char:
				return powerup
	return null

func find_enemy_starting_with(char: String) -> Node:
	if enemy_container == null:
		DebugHelper.log_warning("TypingManager: No enemy container set")
		return null

	var best_enemy: Node = null
	var best_distance: float = INF

	for enemy in enemy_container.get_children():
		if enemy.has_method("get_word") and enemy.is_alive():
			var word = enemy.get_word()
			if word.length() > 0 and word[0].to_upper() == char:
				# Prefer enemies closer to the portal (lower y = further from portal)
				# ASSUMPTION: Enemies move downward toward portal at bottom
				var distance_to_portal = GameConfig.SCREEN_HEIGHT - enemy.position.y
				if distance_to_portal < best_distance:
					best_distance = distance_to_portal
					best_enemy = enemy

	return best_enemy

func complete_word() -> void:
	if active_enemy != null and is_instance_valid(active_enemy):
		DebugHelper.log_debug("Word completed: %s (combo: %d)" % [active_enemy.word, combo])
		SignalBus.word_completed.emit(active_enemy, combo)
		SignalBus.enemy_killed.emit(active_enemy, true)

		# Kill the enemy
		if active_enemy.has_method("die"):
			active_enemy.die()

	# Reset for next word
	active_enemy = null
	typed_index = 0

func on_typing_error() -> void:
	errors += 1
	SoundManager.play_type_error()

	# Combo keeper powerup prevents combo reset
	if not combo_keeper_active:
		if combo >= 5:
			SoundManager.play_combo_break()
		combo = 0
		SignalBus.combo_reset.emit()

	# Lose lock on current target
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

	if combo_keeper_active:
		DebugHelper.log_debug("Typing error! (Combo kept)")
	else:
		DebugHelper.log_debug("Typing error! Combo reset.")

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

func clear_build_buffer() -> void:
	build_buffer = ""

func enable_typing() -> void:
	typing_enabled = true
	build_buffer = ""
	DebugHelper.log_debug("Typing enabled")

func disable_typing() -> void:
	typing_enabled = false
	active_enemy = null
	typed_index = 0
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
	typed_index = 0
	build_buffer = ""

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
