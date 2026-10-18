extends Node2D

const SQUARE := 88.0
const BOARD_ORIGIN := Vector2(40, 40)

const COLOR_LIGHT := Color(0.93, 0.86, 0.72)
const COLOR_DARK := Color(0.55, 0.38, 0.26)
const COLOR_SELECT := Color(0.95, 0.85, 0.25, 0.55)
const COLOR_MOVE := Color(0.15, 0.55, 0.2, 0.55)
const COLOR_CAPTURE := Color(0.8, 0.15, 0.15, 0.55)
const COLOR_HINT := Color(0.25, 0.65, 0.95, 0.55)
const COLOR_CHECK := Color(0.85, 0.1, 0.1, 0.55)

@onready var board_draw: Node2D = $BoardDraw
@onready var prev_button: Button = $UI/SidePanel/Content/NavRow/PrevButton
@onready var title_label: Label = $UI/SidePanel/Content/TitleLabel
@onready var status_label: Label = $UI/SidePanel/Content/StatusLabel
@onready var feedback_label: Label = $UI/SidePanel/Content/FeedbackLabel

var puzzles: Array = []
var current_index := 0
var engine: ChessEngine
var move_progress := 0 # index into the full W,B,W,B,... move sequence
var solved := false
var attempt_clean := true # no wrong tries and no hints on the current puzzle
var deviated := false # mate mode: player left the stored line (still forcing mate)
var hint_square = null

var mode := "mate" # "mate" (static curated bank), "fork", "pin" or "backrank" (all generated fresh every time)

# Pathway Этап 3 — "Микс": mode "mix3" serves mate/fork/pin puzzles at
# random without labelling which trick applies (the player must recognise
# it themselves). mix_underlying tracks the real theme for solving logic
# and is only revealed in the feedback text after the puzzle is solved.
# "Овраг зевков" ("Дорога домой"): positions from the player's OWN games
# where they blundered (Profile.recent_blunders keeps fen + played move).
# The task: find any move clearly stronger than the one played back then —
# verified live by the engine. Fixing your own mistake beats any textbook.
const ALT_MOVE_MAX_LOSS := 20.0 # сп: насколько хуже лучшего может быть засчитанный альтернативный ход
var blunder_ai := ChessAI.new(ChessAI.ANALYSIS_LEVEL) # solver only, never an opponent
var current_blunder: Dictionary = {}
var blunder_idx := 0
var blunder_checking := false

const MIX_THEMES := ["mate", "fork", "pin"]
const MIX_STATUS_TEXT := "Найдите способ выиграть материал — приём не подсказываем!"
var current_mix_puzzle: Dictionary = {}
var mix_underlying := ""
var mix_rng := RandomNumberGenerator.new()
var current_fork_puzzle: Dictionary = {}
var fork_rng := RandomNumberGenerator.new()
var current_pin_puzzle: Dictionary = {}
var pin_rng := RandomNumberGenerator.new()
var current_backrank_puzzle: Dictionary = {}
var backrank_rng := RandomNumberGenerator.new()
var current_defense_puzzle: Dictionary = {}
var defense_rng := RandomNumberGenerator.new()
var current_deflection_puzzle: Dictionary = {}
var deflection_rng := RandomNumberGenerator.new()

# "Свободная практика" (Этап 5 Pathway) — mixes all generated themes
# together at random, plus the static mate bank, for open-ended review.
const PRACTICE_THEMES := ["mate", "fork", "pin", "backrank", "defense", "deflection"]
var in_practice := false
var practice_rng := RandomNumberGenerator.new()

var selected_square = null
var legal_targets: Array = []
var dragging := false
var drag_from = null
var drag_pos := Vector2.ZERO

func _ready() -> void:
	puzzles = PuzzleData.all()
	fork_rng.randomize()
	pin_rng.randomize()
	backrank_rng.randomize()
	defense_rng.randomize()
	deflection_rng.randomize()
	practice_rng.randomize()
	mix_rng.randomize()
	board_draw.draw.connect(_on_board_draw)
	# jump straight into a theme when arriving from a map task node
	if Global.puzzle_theme != "":
		var t = Global.puzzle_theme
		Global.puzzle_theme = ""
		match t:
			"fork": _load_new_fork_puzzle()
			"pin": _load_new_pin_puzzle()
			"backrank": _load_new_backrank_puzzle()
			"defense": _load_new_defense_puzzle()
			"deflection": _load_new_deflection_puzzle()
			"mix": _load_new_mix3_puzzle()
			"blunders": _load_next_blunder_puzzle()
			"practice": _load_new_practice_puzzle()
			_: _load_puzzle(0)
		# a failed generator leaves no position loaded — fall back to the
		# static bank so the scene never draws with a null engine
		if engine == null:
			_load_puzzle(0)
		return
	# explicit pick from the puzzle hub beats auto-resume
	if Global.puzzle_jump >= 0:
		current_index = clampi(Global.puzzle_jump, 0, puzzles.size() - 1)
		Global.puzzle_jump = -1
		_load_puzzle(current_index)
		return
	var saved = Profile.puzzle_state
	if saved.is_empty() or not _try_resume_puzzle(saved):
		current_index = clampi(Global.puzzle_start_index, 0, puzzles.size() - 1)
		_load_puzzle(current_index)

# Restores whichever puzzle (static mate bank, a generated theme, or free
# practice) the player was on last time, replaying its moves so far. Returns
# false if the save turns out to be unusable, so _ready() falls back fresh.
func _try_resume_puzzle(saved: Dictionary) -> bool:
	var saved_mode: String = saved.get("mode", "")
	var mp: int = saved.get("move_progress", 0)
	if saved_mode == "mate":
		var idx: int = saved.get("index", -1)
		if idx < 0 or idx >= puzzles.size():
			return false
		mode = "mate"
		current_index = idx
		_load_from_dict(puzzles[idx], mp)
		title_label.text = "Задача %d / %d" % [idx + 1, puzzles.size()]
		status_label.text = _mate_in_label(puzzles[idx].mate_in) + " (белые начинают и ставят мат)"
	elif saved_mode in ["fork", "pin", "backrank", "defense", "deflection"]:
		var p: Dictionary = saved.get("puzzle", {})
		if p.is_empty():
			return false
		mode = saved_mode
		match saved_mode:
			"fork": current_fork_puzzle = p
			"pin": current_pin_puzzle = p
			"backrank": current_backrank_puzzle = p
			"defense": current_defense_puzzle = p
			"deflection": current_deflection_puzzle = p
		_load_from_dict(p, mp)
		title_label.text = _mode_title(saved_mode)
		status_label.text = _mode_status(saved_mode)
	elif saved_mode == "mix3":
		var p: Dictionary = saved.get("puzzle", {})
		if p.is_empty():
			return false
		mode = "mix3"
		mix_underlying = saved.get("mix_underlying", "fork")
		current_mix_puzzle = p
		_load_from_dict(p, mp)
		title_label.text = "Микс: три приёма"
		status_label.text = MIX_STATUS_TEXT
	else:
		return false
	if saved.get("practice", false):
		in_practice = true
		title_label.text = "Свободная практика — " + title_label.text
	_update_nav_buttons() # in_practice above must win over _load_from_dict's earlier check
	_update_status()
	return true

func _mode_title(mode_: String) -> String:
	match mode_:
		"fork": return "Вилка (новая задача каждый раз)"
		"pin": return "Связка (новая задача каждый раз)"
		"backrank": return "Мат на последней горизонтали (новая задача каждый раз)"
		"defense": return "Уничтожение защиты (новая задача каждый раз)"
		"deflection": return "Отвлечение (новая задача каждый раз)"
	return ""

func _mode_status(mode_: String) -> String:
	match mode_:
		"fork":
			var p = _current_puzzle()
			return "Найдите ход, который атакует короля и фигуру (%s) одновременно" % ("ферзя" if p.piece_lost == "Q" else "ладью")
		"pin": return "Свяжите коня противника с королём, чтобы забрать его следующим ходом"
		"backrank": return "Король чёрных заперт своими пешками — найдите мат в 1 ход по горизонтали"
		"defense": return "Заберите защитника — ладья чёрных останется без защиты"
		"deflection": return "Объявите шах, чтобы увести короля от ладьи, которую он защищает"
	return ""

# Persists exactly enough to resume: which puzzle (or index into the static
# bank) and how far into its move sequence the player has gotten.
func _autosave_puzzle() -> void:
	if mode == "blunder":
		return # blunder quests are one-shot, no resume needed
	var state = {"mode": mode, "move_progress": move_progress, "practice": in_practice}
	if mode == "mate":
		state["index"] = current_index
	else:
		state["puzzle"] = _current_puzzle()
		if mode == "mix3":
			state["mix_underlying"] = mix_underlying
	Profile.save_puzzle_state(state)

func _mate_in_label(n: int) -> String:
	return "Мат в %d ход%s" % [n, ("" if n == 1 else ("а" if n < 5 else "ов"))]

func _current_puzzle() -> Dictionary:
	if mode == "mix3":
		return current_mix_puzzle
	if mode == "fork":
		return current_fork_puzzle
	if mode == "pin":
		return current_pin_puzzle
	if mode == "backrank":
		return current_backrank_puzzle
	if mode == "defense":
		return current_defense_puzzle
	if mode == "deflection":
		return current_deflection_puzzle
	return puzzles[current_index]

func _load_puzzle(i: int) -> void:
	mode = "mate"
	current_index = i
	var p = puzzles[i]
	_load_from_dict(p)
	title_label.text = "Задача %d / %d" % [i + 1, puzzles.size()]
	status_label.text = _mate_in_label(p.mate_in) + " (белые начинают и ставят мат)"

# Generators already retry internally (up to 300 attempts per call) and
# only return {} on genuinely bad luck — one or two immediate re-rolls
# almost always succeed, so failing straight to a dead-end message with no
# puzzle on screen is avoidable.
func _generate_with_retry(rng: RandomNumberGenerator, generator: Callable) -> Dictionary:
	for attempt in range(3):
		var p: Dictionary = generator.call(rng)
		if not p.is_empty():
			return p
	return {}

func _load_new_fork_puzzle() -> void:
	mode = "fork"
	var p = _generate_with_retry(fork_rng, ForkPuzzleGenerator.generate)
	if p.is_empty():
		feedback_label.text = "Не удалось создать задачу, попробуйте ещё раз"
		return
	current_fork_puzzle = p
	_load_from_dict(p)
	title_label.text = _mode_title("fork")
	status_label.text = _mode_status("fork")

func _load_new_pin_puzzle() -> void:
	mode = "pin"
	var p = _generate_with_retry(pin_rng, PinPuzzleGenerator.generate)
	if p.is_empty():
		feedback_label.text = "Не удалось создать задачу, попробуйте ещё раз"
		return
	current_pin_puzzle = p
	_load_from_dict(p)
	title_label.text = _mode_title("pin")
	status_label.text = _mode_status("pin")

func _load_new_backrank_puzzle() -> void:
	mode = "backrank"
	var p = _generate_with_retry(backrank_rng, BackRankPuzzleGenerator.generate)
	if p.is_empty():
		feedback_label.text = "Не удалось создать задачу, попробуйте ещё раз"
		return
	current_backrank_puzzle = p
	_load_from_dict(p)
	title_label.text = _mode_title("backrank")
	status_label.text = _mode_status("backrank")

func _load_new_defense_puzzle() -> void:
	mode = "defense"
	var p = _generate_with_retry(defense_rng, DefensePuzzleGenerator.generate)
	if p.is_empty():
		feedback_label.text = "Не удалось создать задачу, попробуйте ещё раз"
		return
	current_defense_puzzle = p
	_load_from_dict(p)
	title_label.text = _mode_title("defense")
	status_label.text = _mode_status("defense")

func _load_new_deflection_puzzle() -> void:
	mode = "deflection"
	var p = _generate_with_retry(deflection_rng, DeflectionPuzzleGenerator.generate)
	if p.is_empty():
		feedback_label.text = "Не удалось создать задачу, попробуйте ещё раз"
		return
	current_deflection_puzzle = p
	_load_from_dict(p)
	title_label.text = _mode_title("deflection")
	status_label.text = _mode_status("deflection")

func _load_new_mix3_puzzle() -> void:
	mode = "mix3"
	var t = MIX_THEMES[mix_rng.randi_range(0, MIX_THEMES.size() - 1)]
	mix_underlying = t
	var p: Dictionary
	match t:
		"mate": p = puzzles[mix_rng.randi_range(0, 9)] # mate-in-1 puzzles only
		"fork": p = _generate_with_retry(mix_rng, ForkPuzzleGenerator.generate)
		"pin": p = _generate_with_retry(mix_rng, PinPuzzleGenerator.generate)
	if p.is_empty():
		feedback_label.text = "Не удалось создать задачу, попробуйте ещё раз"
		return
	current_mix_puzzle = p
	_load_from_dict(p)
	title_label.text = "Микс: три приёма"
	status_label.text = MIX_STATUS_TEXT

# the puzzle board only accepts White moves, so keep white-to-move ones
func _white_blunders() -> Array:
	var blunders: Array = []
	for b in Profile.recent_blunders:
		if str(b.get("fen", "")).contains(" w "):
			blunders.append(b)
	return blunders

func _load_next_blunder_puzzle() -> void:
	var blunders = _white_blunders()
	if blunders.is_empty():
		# no recorded blunders yet — can't train on them
		_load_puzzle(0)
		feedback_label.text = "Сыграйте пару партий — зевки появятся здесь!"
		return
	_show_blunder(blunders, blunder_idx % blunders.size())
	blunder_idx += 1

# Symmetric with Next: stepping Prev then Next lands back on the same blunder.
func _load_prev_blunder_puzzle() -> void:
	var blunders = _white_blunders()
	if blunders.is_empty():
		_load_puzzle(0)
		feedback_label.text = "Сыграйте пару партий — зевки появятся здесь!"
		return
	var n = blunders.size()
	blunder_idx = ((blunder_idx - 2) % n + n) % n
	_show_blunder(blunders, blunder_idx)
	blunder_idx += 1

func _show_blunder(blunders: Array, idx: int) -> void:
	mode = "blunder"
	current_blunder = blunders[idx]
	_load_from_dict({"fen": current_blunder.fen, "moves": []})
	title_label.text = "Овраг зевков (Дорога домой)"
	status_label.text = "Момент из вашей партии! Тогда вы сыграли %s — найдите ход сильнее." % ChessEngine.ru_notation(str(current_blunder.move))
	feedback_label.text = "Исправлено зевков: %d / %d" % [Profile.road_blunders_fixed, Profile.ROAD_BLUNDERS_REQUIRED]

# Accept any move that doesn't lose serious material (engine-checked on a
# worker thread) — i.e. genuinely better than the blunder played back then.
func _attempt_blunder_move(move: Dictionary) -> void:
	if blunder_checking:
		return
	var notation = ChessEngine.square_name(move.from.x, move.from.y) + ChessEngine.square_name(move.to.x, move.to.y)
	if notation == str(current_blunder.move):
		feedback_label.text = "Это тот самый зевок! Поищите ход получше."
		feedback_label.modulate = Color(0.9, 0.35, 0.3)
		return
	blunder_checking = true
	feedback_label.text = "Проверяю ход..."
	feedback_label.modulate = Color(0.85, 0.85, 0.85)
	var snapshot = engine.clone()
	var result := {"loss": 0.0}
	await Global.run_bg(func(): result.loss = blunder_ai.move_loss(snapshot, move, 3))
	blunder_checking = false
	if result.loss <= 90.0:
		engine.apply_move(move)
		solved = true
		Profile.record_daily_activity()
		var counted: bool = Profile.record_road_blunder_fix(str(current_blunder.fen))
		if not counted:
			feedback_label.text = "Сильный ход! Но этот зевок вы уже исправляли — в зачёт этапа не идёт."
			feedback_label.modulate = Color(0.85, 0.75, 0.3)
			board_draw.queue_redraw()
			return
		feedback_label.text = "Сильный ход! Зевок исправлен (%d / %d)" % [min(Profile.road_blunders_fixed, Profile.ROAD_BLUNDERS_REQUIRED), Profile.ROAD_BLUNDERS_REQUIRED]
		if Profile.road_blunders_fixed >= Profile.ROAD_BLUNDERS_REQUIRED:
			feedback_label.text += " — этап пройден!"
		feedback_label.modulate = Color(0.4, 0.85, 0.35)
		board_draw.queue_redraw()
	else:
		feedback_label.text = "Этот ход тоже теряет материал — попробуйте ещё."
		feedback_label.modulate = Color(0.9, 0.35, 0.3)

func _load_new_practice_puzzle() -> void:
	in_practice = true
	var theme = PRACTICE_THEMES[practice_rng.randi_range(0, PRACTICE_THEMES.size() - 1)]
	match theme:
		"mate": _load_puzzle(practice_rng.randi_range(0, puzzles.size() - 1))
		"fork": _load_new_fork_puzzle()
		"pin": _load_new_pin_puzzle()
		"backrank": _load_new_backrank_puzzle()
		"defense": _load_new_defense_puzzle()
		"deflection": _load_new_deflection_puzzle()
	title_label.text = "Свободная практика — " + title_label.text

# "Prev" only means something for the static mate bank and the blunder list
# (real positions, real order) — every other mode generates a brand-new
# random puzzle each time, so there's nothing to actually step back to.
func _update_nav_buttons() -> void:
	prev_button.disabled = in_practice or not (mode == "mate" or mode == "blunder")

func _load_from_dict(p: Dictionary, resume_progress: int = 0) -> void:
	_update_nav_buttons()
	engine = ChessEngine.new()
	engine.setup_from_fen(p.fen)
	move_progress = 0
	solved = false
	attempt_clean = true
	deviated = false
	hint_square = null
	selected_square = null
	legal_targets = []
	dragging = false
	feedback_label.text = "Ваш ход"
	feedback_label.modulate = Color(0.85, 0.85, 0.85)
	if resume_progress > 0:
		var moves: Array = p.moves
		for i in range(min(resume_progress, moves.size())):
			var mv: String = moves[i]
			var from_f = "abcdefgh".find(mv[0])
			var from_r = int(mv[1]) - 1
			var to_f = "abcdefgh".find(mv[2])
			var to_r = int(mv[3]) - 1
			var m = _find_engine_move(from_f, from_r, to_f, to_r)
			if m == null:
				break
			engine.apply_move(m)
			move_progress += 1
		feedback_label.text = "Продолжаем с места, где остановились"
	_autosave_puzzle()
	board_draw.queue_redraw()

func _current_moves() -> Array:
	return _current_puzzle().moves

func _unhandled_input(event: InputEvent) -> void:
	if solved or engine == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var local = board_draw.get_global_transform().affine_inverse() * event.position
		if event.pressed:
			var sq = _pixel_to_square(local)
			if sq == null:
				return
			_handle_press(sq, local)
		else:
			if dragging:
				var sq = _pixel_to_square(local)
				_handle_release(sq)
	elif event is InputEventMouseMotion and dragging:
		var local = board_draw.get_global_transform().affine_inverse() * event.position
		drag_pos = local
		board_draw.queue_redraw()

func _pixel_to_square(pos: Vector2):
	var rel = pos - BOARD_ORIGIN
	if rel.x < 0 or rel.y < 0:
		return null
	var f = int(rel.x / SQUARE)
	var r_disp = int(rel.y / SQUARE)
	if f < 0 or f > 7 or r_disp < 0 or r_disp > 7:
		return null
	return Vector2i(f, 7 - r_disp)

func _square_to_pixel(sq: Vector2i) -> Vector2:
	return BOARD_ORIGIN + Vector2(sq.x * SQUARE, (7 - sq.y) * SQUARE)

func _handle_press(sq: Vector2i, local: Vector2) -> void:
	if engine.side_to_move != "w":
		return
	var p = engine.board[sq.y][sq.x]
	if selected_square != null:
		var move = _find_move(selected_square, sq)
		if move != null:
			dragging = false
			_attempt_move(move)
			board_draw.queue_redraw()
			return
		if p != null and p.color == "w":
			selected_square = sq
			legal_targets = engine.legal_moves_for_square(sq.x, sq.y)
			dragging = true
			drag_from = sq
			drag_pos = local
		else:
			selected_square = null
			legal_targets = []
			dragging = false
	else:
		if p != null and p.color == "w":
			selected_square = sq
			legal_targets = engine.legal_moves_for_square(sq.x, sq.y)
			dragging = true
			drag_from = sq
			drag_pos = local
	board_draw.queue_redraw()

func _handle_release(sq) -> void:
	dragging = false
	if sq == null or drag_from == null or sq == drag_from:
		board_draw.queue_redraw()
		return
	var move = _find_move(drag_from, sq)
	if move != null:
		_attempt_move(move)
	board_draw.queue_redraw()

func _find_move(from: Vector2i, to: Vector2i):
	for m in legal_targets:
		if m.from == from and m.to == to:
			return m
	return null

func _attempt_move(move: Dictionary) -> void:
	selected_square = null
	legal_targets = []
	# mate puzzles accept ANY move that forces mate in the remaining moves,
	# not just the single stored line — many positions have several mates
	if mode == "blunder":
		_attempt_blunder_move(move)
		return
	if mode == "mate" or (mode == "mix3" and mix_underlying == "mate"):
		_attempt_mate_move(move)
		return
	var expected: String = _current_moves()[move_progress]
	var expected_from = Vector2i("abcdefgh".find(expected[0]), int(expected[1]) - 1)
	var expected_to = Vector2i("abcdefgh".find(expected[2]), int(expected[3]) - 1)
	if move.from != expected_from or move.to != expected_to:
		# alternate checkmates are also a win (backrank puzzles are mate-in-1)
		var alt = engine.clone()
		alt.apply_move(move)
		if alt.game_status() == "checkmate":
			engine.apply_move(move)
			move_progress = _current_moves().size()
			_finish_solved()
			return
		# заложенное решение не всегда единственное лучшее (связка, отвлечение): ход, который
		# движок оценивает не хуже заложенного, засчитываем — иначе ребёнок наказан за верный ход
		if blunder_ai.move_loss(engine, move, 3) <= ALT_MOVE_MAX_LOSS:
			engine.apply_move(move)
			move_progress = _current_moves().size()
			_finish_solved()
			feedback_label.text = "Другой путь, но тоже сильный ход!"
			return
		attempt_clean = false
		feedback_label.text = "Не тот ход — попробуйте ещё раз"
		feedback_label.modulate = Color(0.9, 0.35, 0.3)
		return
	engine.apply_move(move)
	move_progress += 1
	hint_square = null
	var all_moves = _current_moves()
	if move_progress >= all_moves.size():
		solved = true
		_finish_solved()
		return
	feedback_label.text = "Верно! Продолжайте"
	feedback_label.modulate = Color(0.4, 0.85, 0.35)
	_auto_play_black_reply()
	_update_status()
	_autosave_puzzle()

# Mate puzzles accept any move that still forces mate in the remaining
# number of White moves — the stored line is just one path. Once the player
# deviates from it, Black defends as stubbornly as possible and resume-saves
# are cleared (they replay the stored line, which no longer applies).
func _attempt_mate_move(move: Dictionary) -> void:
	var remaining: int = _current_puzzle().mate_in - move_progress / 2
	if not _move_forces_mate(engine, move, remaining):
		attempt_clean = false
		feedback_label.text = "Этот ход не ведёт к мату — попробуйте ещё раз"
		feedback_label.modulate = Color(0.9, 0.35, 0.3)
		return
	var moves_list = _current_moves()
	var notation = ChessEngine.square_name(move.from.x, move.from.y) + ChessEngine.square_name(move.to.x, move.to.y)
	if move_progress >= moves_list.size() or notation != moves_list[move_progress]:
		deviated = true
		Profile.clear_puzzle_state()
	engine.apply_move(move)
	move_progress += 1
	hint_square = null
	if engine.game_status() == "checkmate":
		_finish_solved()
		return
	feedback_label.text = "Верно! Продолжайте"
	feedback_label.modulate = Color(0.4, 0.85, 0.35)
	if deviated:
		_play_resistant_black_reply(remaining - 1)
	else:
		_auto_play_black_reply()
		_autosave_puzzle()
	_update_status()

# Ход белых годится, если он ставит мат или после него КАЖДЫЙ ответ чёрных ведёт к мату
# в оставшиеся ходы. Тихие (нешахующие) первые ходы тоже годятся: у многих задач «мат в 2»
# есть несколько решений, и верный мат нельзя объявлять ошибкой.
func _move_forces_mate(e: ChessEngine, move: Dictionary, remaining: int) -> bool:
	var after = e.clone()
	after.apply_move(move)
	if after.game_status() == "checkmate":
		return true
	if remaining < 2:
		return false
	var replies = after.legal_moves("b")
	if replies.is_empty():
		return false # пат — не мат
	for r in replies:
		var c2 = after.clone()
		c2.apply_move(r)
		if _mate_solutions(c2, remaining - 1).is_empty():
			return false
	return true

# First white moves that force mate in <= n (checking moves only for n >= 2,
# same convention the offline generator was verified with).
func _mate_solutions(e: ChessEngine, n: int) -> Array:
	var res := []
	for m in e.legal_moves("w"):
		var c = e.clone()
		c.apply_move(m)
		if c.game_status() == "checkmate":
			res.append(m)
			continue
		if n < 2 or not c.is_in_check("b"):
			continue
		var replies = c.legal_moves("b")
		if replies.is_empty():
			continue
		var all_forced := true
		for r in replies:
			var c2 = c.clone()
			c2.apply_move(r)
			if _mate_solutions(c2, n - 1).is_empty():
				all_forced = false
				break
		if all_forced:
			res.append(m)
	return res

func _play_resistant_black_reply(depth: int) -> void:
	var best = null
	var best_d := -1
	for r in engine.legal_moves("b"):
		var c = engine.clone()
		c.apply_move(r)
		var d := 1
		while d < depth and _mate_solutions(c, d).is_empty():
			d += 1
		if d > best_d:
			best_d = d
			best = r
	if best != null:
		engine.apply_move(best)
		move_progress += 1

func _mix_theme_label(t: String) -> String:
	match t:
		"mate": return "мат в 1 ход"
		"fork": return "вилка"
		"pin": return "связка"
	return t

func _finish_solved() -> void:
	solved = true
	Profile.clear_puzzle_state()
	Profile.record_daily_activity()
	# повторное решение той же сгенерированной задачи в зачёт темы не идёт —
	# иначе ворота карты открывались повтором одной простой задачи
	var theme_kind: String = mix_underlying if mode == "mix3" else mode
	var fen0: String = str(_current_puzzle().get("fen", ""))
	if theme_kind != "mate" and fen0 != "" and not Profile.mark_solved_once(theme_kind, fen0):
		feedback_label.text = "Верно! Но эту задачу вы уже решали — в зачёт темы она не идёт. Возьмите новую."
		feedback_label.modulate = Color(0.85, 0.75, 0.3)
		_update_status()
		return
	if mode == "mix3":
		if attempt_clean:
			Profile.record_theme_clean("mix")
		Profile.record_mix_puzzle_solved()
		feedback_label.text = "Решено! Это была тема: %s" % _mix_theme_label(mix_underlying)
		feedback_label.modulate = Color(0.4, 0.85, 0.35)
		_update_status()
		return
	if attempt_clean:
		Profile.record_theme_clean(mode)
	if mode == "fork":
		feedback_label.text = "Решено! Вилка сработала!"
		Profile.record_fork_puzzle_solved()
	elif mode == "pin":
		feedback_label.text = "Решено! Конь связан и взят!"
		Profile.record_pin_puzzle_solved()
	elif mode == "backrank":
		feedback_label.text = "Решено! Мат на последней горизонтали!"
		Profile.record_backrank_puzzle_solved()
	elif mode == "defense":
		feedback_label.text = "Решено! Защитник уничтожен, фигура взята!"
		Profile.record_defense_puzzle_solved()
	elif mode == "deflection":
		feedback_label.text = "Решено! Короля отвлекли, ладья взята!"
		Profile.record_deflection_puzzle_solved()
	elif engine.game_status() == "checkmate":
		feedback_label.text = "Решено! Мат!"
		Profile.record_puzzle_solved(current_index, puzzles[current_index].mate_in)
	else:
		feedback_label.text = "Верно!"
	feedback_label.modulate = Color(0.4, 0.85, 0.35)
	_update_status()

func _auto_play_black_reply() -> void:
	var all_moves = _current_moves()
	if move_progress >= all_moves.size():
		return
	var reply: String = all_moves[move_progress]
	var from_f = "abcdefgh".find(reply[0])
	var from_r = int(reply[1]) - 1
	var to_f = "abcdefgh".find(reply[2])
	var to_r = int(reply[3]) - 1
	var m = _find_engine_move(from_f, from_r, to_f, to_r)
	if m != null:
		engine.apply_move(m)
		move_progress += 1

func _find_engine_move(from_f: int, from_r: int, to_f: int, to_r: int):
	var moves = engine.legal_moves_for_square(from_f, from_r)
	for m in moves:
		if m.to.x == to_f and m.to.y == to_r:
			return m
	return null

func _update_status() -> void:
	if mode == "blunder":
		board_draw.queue_redraw()
		return # status text is set by the loader and must not be overwritten
	var p = _current_puzzle()
	var total = p.moves.size()
	var label: String
	if mode == "mix3":
		label = "Микс"
	elif mode == "fork":
		label = "Вилка"
	elif mode == "pin":
		label = "Связка"
	elif mode == "backrank":
		label = "Мат на 1-й горизонтали"
	elif mode == "defense":
		label = "Уничтожение защиты"
	elif mode == "deflection":
		label = "Отвлечение"
	else:
		label = _mate_in_label(p.mate_in)
	status_label.text = label + "  ·  ход %d / %d" % [min(move_progress + 1, total), total]
	board_draw.queue_redraw()

func _on_hint_pressed() -> void:
	if solved:
		return
	attempt_clean = false
	if mode == "blunder":
		if blunder_checking:
			return
		blunder_checking = true
		feedback_label.text = "Ищу сильный ход..."
		var snapshot = engine.clone()
		var result := {"m": null}
		await Global.run_bg(func(): result.m = blunder_ai.best_move_clean(snapshot, 3))
		blunder_checking = false
		if result.m != null:
			hint_square = result.m.from
			feedback_label.text = "Подсказка: походите этой фигурой"
			feedback_label.modulate = Color(0.35, 0.65, 0.95)
			board_draw.queue_redraw()
		return
	if deviated:
		# off the stored line: ask the solver for a mating move instead
		var sols = _mate_solutions(engine, max(_current_puzzle().mate_in - move_progress / 2, 1))
		if sols.is_empty():
			return
		hint_square = sols[0].from
		feedback_label.text = "Подсказка: походите этой фигурой"
		feedback_label.modulate = Color(0.35, 0.65, 0.95)
		board_draw.queue_redraw()
		return
	if move_progress >= _current_moves().size():
		return
	var expected: String = _current_moves()[move_progress]
	hint_square = Vector2i("abcdefgh".find(expected[0]), int(expected[1]) - 1)
	feedback_label.text = "Подсказка: походите этой фигурой"
	feedback_label.modulate = Color(0.35, 0.65, 0.95)
	board_draw.queue_redraw()

func _on_reset_pressed() -> void:
	if mode == "blunder":
		if not current_blunder.is_empty():
			_load_from_dict({"fen": current_blunder.fen, "moves": []})
			status_label.text = "Момент из вашей партии! Тогда вы сыграли %s — найдите ход сильнее." % ChessEngine.ru_notation(str(current_blunder.move))
		return
	if mode == "mix3":
		_load_from_dict(_current_puzzle())
		status_label.text = MIX_STATUS_TEXT
	elif mode in ["fork", "pin", "backrank", "defense", "deflection"]:
		_load_from_dict(_current_puzzle())
		status_label.text = _mode_status(mode)
	else:
		_load_puzzle(current_index)
	# A replay of the same puzzle can't count as a clean solve
	attempt_clean = false

func _on_next_pressed() -> void:
	if in_practice:
		_load_new_practice_puzzle()
		return
	if mode == "blunder":
		_load_next_blunder_puzzle()
	elif mode == "mix3":
		_load_new_mix3_puzzle()
	elif mode == "fork":
		_load_new_fork_puzzle()
	elif mode == "pin":
		_load_new_pin_puzzle()
	elif mode == "backrank":
		_load_new_backrank_puzzle()
	elif mode == "defense":
		_load_new_defense_puzzle()
	elif mode == "deflection":
		_load_new_deflection_puzzle()
	else:
		_load_puzzle((current_index + 1) % puzzles.size())

func _on_prev_pressed() -> void:
	# disabled (see _update_nav_buttons) for every mode except the static
	# mate bank and the blunder list — the only two with a real "previous"
	if mode == "blunder":
		_load_prev_blunder_puzzle()
	elif mode == "mate":
		_load_puzzle((current_index - 1 + puzzles.size()) % puzzles.size())

func _on_hub_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/PuzzleHub.tscn")

func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")

func _on_board_draw() -> void:
	if engine == null:
		return
	for r in range(8):
		for f in range(8):
			var pos = BOARD_ORIGIN + Vector2(f * SQUARE, (7 - r) * SQUARE)
			var is_light = (f + r) % 2 == 1
			var col = Themes.board_light() if is_light else Themes.board_dark()
			board_draw.draw_rect(Rect2(pos, Vector2(SQUARE, SQUARE)), col, true)

	if engine.is_in_check(engine.side_to_move):
		var k = engine.find_king(engine.side_to_move)
		if k.x >= 0:
			var pos = _square_to_pixel(k)
			board_draw.draw_rect(Rect2(pos, Vector2(SQUARE, SQUARE)), COLOR_CHECK, true)

	if hint_square != null:
		var pos = _square_to_pixel(hint_square)
		board_draw.draw_rect(Rect2(pos, Vector2(SQUARE, SQUARE)), COLOR_HINT, true)

	if selected_square != null:
		var pos = _square_to_pixel(selected_square)
		board_draw.draw_rect(Rect2(pos, Vector2(SQUARE, SQUARE)), COLOR_SELECT, true)
		for m in legal_targets:
			var tpos = _square_to_pixel(m.to)
			var center = tpos + Vector2(SQUARE, SQUARE) / 2
			var is_capture = engine.board[m.to.y][m.to.x] != null or m.get("is_ep", false)
			if is_capture:
				board_draw.draw_arc(center, SQUARE * 0.42, 0, TAU, 24, COLOR_CAPTURE, 5.0, true)
			else:
				board_draw.draw_circle(center, SQUARE * 0.15, COLOR_MOVE)

	var font = ThemeDB.fallback_font
	for i in range(8):
		var fp = BOARD_ORIGIN + Vector2(i * SQUARE + 4, 8 * SQUARE - 2)
		board_draw.draw_string(font, fp, "abcdefgh"[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0, 0.5))
		var rp = BOARD_ORIGIN + Vector2(2, i * SQUARE + 14)
		board_draw.draw_string(font, rp, str(8 - i), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0, 0.5))

	for r in range(8):
		for f in range(8):
			var p = engine.board[r][f]
			if p == null:
				continue
			if dragging and drag_from != null and drag_from.x == f and drag_from.y == r:
				continue
			var pos = _square_to_pixel(Vector2i(f, r))
			var center = pos + Vector2(SQUARE, SQUARE) / 2
			PieceTextures.draw(board_draw, p.type, p.color, center, SQUARE * 0.92)

	if dragging and drag_from != null:
		var dp = engine.board[drag_from.y][drag_from.x]
		if dp != null:
			PieceTextures.draw(board_draw, dp.type, dp.color, drag_pos, SQUARE * 1.0)
