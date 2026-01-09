## wordwar_state.gd
## WordWar VS mode - 1v1 competitive typing battle
extends Control

# Game configuration
const GAME_DURATION: float = 120.0  # 2 minutes
const WORDS_PER_ROUND: int = 10
const SEND_WORD_THRESHOLD: int = 3  # Words to complete before sending to opponent

# Game state
var game_active: bool = false
var time_remaining: float = GAME_DURATION
var my_score: int = 0
var opponent_score: int = 0
var words_completed: int = 0
var words_to_send: int = 0

# Current word
var current_word: String = ""
var typed_index: int = 0

# Word lists
var word_pool: Array[String] = []
var pending_words: Array[String] = []  # Words sent by opponent

# Multiplayer
var is_multiplayer: bool = false
var game_seed: int = 0

# Node references
@onready var my_word_label: Label = $GameContainer/LeftPanel/MyWordLabel
@onready var my_score_label: Label = $GameContainer/LeftPanel/MyScoreLabel
@onready var opponent_word_label: Label = $GameContainer/RightPanel/OpponentWordLabel
@onready var opponent_score_label: Label = $GameContainer/RightPanel/OpponentScoreLabel
@onready var timer_label: Label = $TopBar/TimerLabel
@onready var typed_display: Label = $GameContainer/LeftPanel/TypedDisplay
@onready var pending_label: Label = $GameContainer/LeftPanel/PendingLabel

func _ready() -> void:
	load_words()

func load_words() -> void:
	# Load words from JSON
	word_pool = [
		"SWIFT", "BLAZE", "STORM", "QUICK", "FLASH", "SPARK", "POWER", "SPEED",
		"BRAVE", "FORCE", "SHARP", "LIGHT", "STEEL", "FLAME", "FROST", "THUNDER",
		"RAPID", "STRIKE", "CLASH", "BURST", "SURGE", "BLAST", "CRASH", "SMASH",
		"DODGE", "BLOCK", "GUARD", "ATTACK", "DEFEND", "CHARGE", "COUNTER", "COMBO"
	]

func on_enter(params: Dictionary) -> void:
	DebugHelper.log_info("WordWarState entered")
	MenuBackground.hide_background()

	is_multiplayer = params.get("multiplayer", false)
	game_seed = params.get("seed", randi())

	# Use seed for consistent word order in multiplayer
	seed(game_seed)

	# Connect network signals if multiplayer
	if is_multiplayer:
		SignalBus.network_score_update.connect(_on_opponent_score)
		SignalBus.network_word_completed.connect(_on_opponent_word)
		SignalBus.network_game_over.connect(_on_network_game_over)

	start_game()

func on_exit() -> void:
	DebugHelper.log_info("WordWarState exiting")
	game_active = false

	if is_multiplayer:
		if SignalBus.network_score_update.is_connected(_on_opponent_score):
			SignalBus.network_score_update.disconnect(_on_opponent_score)
		if SignalBus.network_word_completed.is_connected(_on_opponent_word):
			SignalBus.network_word_completed.disconnect(_on_opponent_word)
		if SignalBus.network_game_over.is_connected(_on_network_game_over):
			SignalBus.network_game_over.disconnect(_on_network_game_over)

func start_game() -> void:
	game_active = true
	time_remaining = GAME_DURATION
	my_score = 0
	opponent_score = 0
	words_completed = 0
	words_to_send = 0
	pending_words.clear()

	SoundManager.play_game_start()
	get_next_word()
	update_display()

func _process(delta: float) -> void:
	if not game_active:
		return

	# Update timer
	time_remaining -= delta
	if time_remaining <= 0:
		time_remaining = 0
		end_game()

	update_timer_display()

func _input(event: InputEvent) -> void:
	if not game_active:
		# Check for restart/exit commands
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ESCAPE:
				exit_to_menu()
			elif event.keycode == KEY_ENTER:
				start_game()
		return

	if event is InputEventKey and event.pressed and not event.is_echo():
		var char_code = event.unicode

		if event.keycode == KEY_ESCAPE:
			exit_to_menu()
			return

		# A-Z
		if (char_code >= 65 and char_code <= 90) or (char_code >= 97 and char_code <= 122):
			process_char(char(char_code).to_upper())

func process_char(typed_char: String) -> void:
	if current_word.length() == 0:
		return

	var expected_char = current_word[typed_index].to_upper()

	if typed_char == expected_char:
		# Correct!
		typed_index += 1
		SoundManager.play_type_correct()

		if typed_index >= current_word.length():
			complete_word()
	else:
		# Wrong!
		typed_index = 0
		SoundManager.play_type_error()

	update_display()

func complete_word() -> void:
	words_completed += 1
	words_to_send += 1

	# Score based on word length
	var word_score = current_word.length() * 10
	my_score += word_score

	SoundManager.play_word_complete()
	DebugHelper.log_debug("Word completed: %s (+%d)" % [current_word, word_score])

	# Send word to opponent
	if words_to_send >= SEND_WORD_THRESHOLD:
		send_word_to_opponent()
		words_to_send = 0

	# Network sync
	if is_multiplayer:
		NetworkManager.send_score_update(my_score)
		NetworkManager.send_word_completed(current_word)

	get_next_word()

func get_next_word() -> void:
	# Check pending words from opponent first
	if pending_words.size() > 0:
		current_word = pending_words.pop_front()
		DebugHelper.log_debug("Taking pending word: %s" % current_word)
	else:
		# Get random word from pool
		current_word = word_pool[randi() % word_pool.size()]

	typed_index = 0
	update_display()

func send_word_to_opponent() -> void:
	# In multiplayer, this would send via network
	# In single player, add to AI opponent's queue
	if not is_multiplayer:
		# AI opponent gets the word
		process_ai_word()

	DebugHelper.log_debug("Sent word to opponent")

func process_ai_word() -> void:
	# Simple AI: complete word after random delay
	var ai_delay = randf_range(0.5, 2.0)
	var timer = get_tree().create_timer(ai_delay)
	timer.timeout.connect(func():
		if game_active:
			opponent_score += 30
			update_display()
	)

func _on_opponent_score(player_id: int, score: int) -> void:
	if player_id != NetworkManager.player_id:
		opponent_score = score
		update_display()

func _on_opponent_word(player_id: int, word: String) -> void:
	if player_id != NetworkManager.player_id:
		# Opponent completed a word, add to our pending
		pending_words.append(word.to_upper())
		update_display()
		SoundManager.play_word_incoming()
		DebugHelper.log_debug("Received word from opponent: %s" % word)

func _on_network_game_over(winner_id: int, final_scores: Dictionary) -> void:
	end_game()

func end_game() -> void:
	game_active = false

	var won = my_score > opponent_score
	DebugHelper.log_info("WordWar ended! Score: %d vs %d - %s" % [my_score, opponent_score, "WIN" if won else "LOSE"])

	# Send game over to network
	if is_multiplayer:
		NetworkManager.send_game_over(won, my_score)

	# Show results
	show_results(won)

func show_results(won: bool) -> void:
	if my_word_label:
		if won:
			my_word_label.text = "VICTORY!"
			my_word_label.add_theme_color_override("font_color", GameConfig.COLORS.acid_green)
			SoundManager.play_victory()
		elif my_score == opponent_score:
			my_word_label.text = "DRAW!"
			my_word_label.add_theme_color_override("font_color", GameConfig.COLORS.amber)
		else:
			my_word_label.text = "DEFEAT"
			my_word_label.add_theme_color_override("font_color", GameConfig.COLORS.magenta)
			SoundManager.play_defeat()

	if typed_display:
		typed_display.text = "Press ENTER to play again | ESC to exit"

func exit_to_menu() -> void:
	if is_multiplayer:
		NetworkManager.leave_lobby()
	StateManager.change_state("menu")

func update_display() -> void:
	if my_word_label and game_active:
		# Show word with typed progress
		if typed_index > 0:
			var typed = current_word.substr(0, typed_index)
			var remaining = current_word.substr(typed_index)
			my_word_label.text = "[%s]%s" % [typed, remaining]
		else:
			my_word_label.text = current_word

	if my_score_label:
		my_score_label.text = "Score: %d" % my_score

	if opponent_score_label:
		opponent_score_label.text = "Opponent: %d" % opponent_score

	if typed_display:
		if typed_index > 0:
			typed_display.text = current_word.substr(0, typed_index)
		else:
			typed_display.text = ""

	if pending_label:
		if pending_words.size() > 0:
			pending_label.text = "Incoming: %d words!" % pending_words.size()
			pending_label.add_theme_color_override("font_color", GameConfig.COLORS.magenta)
		else:
			pending_label.text = ""

func update_timer_display() -> void:
	if timer_label:
		var minutes = int(time_remaining) / 60
		var seconds = int(time_remaining) % 60
		timer_label.text = "%d:%02d" % [minutes, seconds]

		# Color based on time
		if time_remaining < 10:
			timer_label.add_theme_color_override("font_color", GameConfig.COLORS.magenta)
		elif time_remaining < 30:
			timer_label.add_theme_color_override("font_color", GameConfig.COLORS.amber)
		else:
			timer_label.add_theme_color_override("font_color", GameConfig.COLORS.cyan)
