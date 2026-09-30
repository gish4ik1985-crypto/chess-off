extends Control

# Разбор партии бота из «Базы игроков» — чтобы готовиться к сопернику, как
# перед настоящим турниром: посмотреть его партии, пройти ход за ходом,
# увидеть, где менялась оценка.
#
# ОТКУДА БЕРУТСЯ ПАРТИИ. Симуляция тура ходов не даёт вообще: там результат
# определяется броском по разнице рейтингов. Просчитать все партии заранее
# нельзя — замер (scripts/tools/bench_botgame.gd) дал 5 сек на партию при
# уровне ИИ 3, 8 сек при уровне 6 и почти минуту при уровне 10, а один тик
# мира это 56 партий по всем лигам. Поэтому в архив попадают только
# по-настоящему сыгранные партии:
#   1) ваши собственные встречи с ботом (турнир, товарищеская) — они уже
#      сыграны, ходы просто сохраняются, это бесплатно;
#   2) партии, сыгранные ботами между собой по вашему запросу (режим "live"):
#      65–720 мс на ход — это как раз темп, в котором партию удобно смотреть,
#      так что она играется прямо при вас и потом остаётся в архиве.
#
# Global.bot_match:
#   {"mode": "replay", "bot": id, "index": i} — разбор партии из архива
#   {"mode": "live",   "white": id, "black": id} — сыграть и записать

const BotData = preload("res://scripts/BotData.gd")
# у Board.gd нет class_name, поэтому статические функции берём через preload
const BoardScript = preload("res://scripts/Board.gd")
const SQ := 62.0
const MAX_PLIES := 220

@onready var title_label: Label = $TopBar/HBox/TitleLabel
@onready var status_label: Label = $TopBar/HBox/StatusLabel
@onready var board_draw: Node2D = $Main/BoardArea/BoardDraw
@onready var eval_label: Label = $Main/BoardArea/EvalLabel
@onready var controls: HBoxContainer = $Main/BoardArea/Controls
@onready var players_label: Label = $Main/InfoPanel/VBox/PlayersLabel
@onready var state_label: Label = $Main/InfoPanel/VBox/StateLabel
@onready var moves_label: Label = $Main/InfoPanel/VBox/MovesScroll/MovesLabel
@onready var result_label: Label = $Main/InfoPanel/VBox/ResultLabel

var mode := "replay"
var engine: ChessEngine
var white_rec: Dictionary = {}
var black_rec: Dictionary = {}
var game: Dictionary = {}

# --- разбор ---
var states: Array = []      # ChessEngine после каждого полухода (0 = начало)
var notations: Array = []   # человекочитаемая запись каждого полухода
var evals: Array = []       # статическая оценка позиции, сантипешки за белых
var cur := 0
var last_from := Vector2i(-1, -1)
var last_to := Vector2i(-1, -1)
var auto_play := false
var auto_left := 0.0

# --- живая партия ---
var ai_white: ChessAI
var ai_black: ChessAI
var live_coords: Array = []
var live_moves: Array = []
var finished := false
var paused := false
var wait_left := 0.0
var _thread: Thread = null
var _pending = null
var _sync_ready := false # в браузере (без потоков) ход считается сразу в основном потоке

var evaluator: ChessAI

func _ready() -> void:
	var m: Dictionary = Global.bot_match
	if m.is_empty():
		_back()
		return
	evaluator = ChessAI.new(6)
	board_draw.draw.connect(_on_board_draw)
	mode = str(m.get("mode", "replay"))
	if mode == "live":
		white_rec = Profile.bot_record(str(m.get("white", "")))
		black_rec = Profile.bot_record(str(m.get("black", "")))
		if white_rec.is_empty() or black_rec.is_empty():
			_back()
			return
		_build_live_controls()
		_start_live()
	else:
		var arr := Profile.games_of_bot(str(m.get("bot", "")))
		var idx = int(m.get("index", 0))
		if idx < 0 or idx >= arr.size():
			_back()
			return
		game = arr[idx]
		_build_replay_controls()
		_load_replay()

# ------------------------------------------------------------------ разбор

func _load_replay() -> void:
	title_label.text = "РАЗБОР ПАРТИИ"
	var eng := ChessEngine.new()
	eng.setup_start_position()
	states = [eng.clone()]
	notations = []
	evals = [evaluator.evaluate_position(eng)]
	for coord in game.get("moves", []):
		var mv := _find_move(eng, str(coord))
		if mv.is_empty():
			break # запись повреждена — показываем то, что удалось прочесть
		notations.append(BoardScript.move_notation(eng, mv))
		eng.apply_move(mv)
		states.append(eng.clone())
		evals.append(evaluator.evaluate_position(eng))
	players_label.text = "⚪ %s\n⚫ %s" % [str(game.get("w_name", "")), str(game.get("b_name", ""))]
	var res := float(game.get("result", 0.5))
	var res_txt = "1 : 0" if res >= 1.0 else ("0 : 1" if res <= 0.0 else "½ : ½")
	status_label.text = "%s · %s · %s" % [str(game.get("event", "")), str(game.get("day", "")), res_txt]
	result_label.text = "Итог: %s" % res_txt
	_seek(0)

# Находит легальный ход по координатной записи "e2e4" / "e7e8Q".
func _find_move(eng: ChessEngine, coord: String) -> Dictionary:
	if coord.length() < 4:
		return {}
	var f := _sq(coord.substr(0, 2))
	var t := _sq(coord.substr(2, 2))
	var promo := coord.substr(4, 1) if coord.length() > 4 else ""
	for mv in eng.legal_moves(eng.side_to_move):
		if mv.from == f and mv.to == t:
			if promo != "" and str(mv.get("promo", "")) != promo:
				var copy: Dictionary = mv.duplicate()
				copy["promo"] = promo
				return copy
			return mv
	return {}

func _sq(s: String) -> Vector2i:
	return Vector2i(s.unicode_at(0) - 97, s.unicode_at(1) - 49)

func _seek(i: int) -> void:
	if states.is_empty():
		return
	cur = clampi(i, 0, states.size() - 1)
	engine = states[cur]
	if cur > 0:
		var coord := str(game.get("moves", [])[cur - 1])
		last_from = _sq(coord.substr(0, 2))
		last_to = _sq(coord.substr(2, 2))
	else:
		last_from = Vector2i(-1, -1)
		last_to = Vector2i(-1, -1)
	_refresh_moves(notations, cur)
	_update_eval()
	state_label.text = "Ход %d из %d" % [cur, states.size() - 1]
	board_draw.queue_redraw()

# Оценка позиции и то, как её изменил последний ход — главное, ради чего
# партию соперника вообще разбирают.
func _update_eval() -> void:
	if evals.is_empty():
		eval_label.text = ""
		return
	var ev = float(evals[cur]) / 100.0
	var who = "у белых" if ev > 0 else "у чёрных"
	var line = "Перевес: примерно равно" if absf(ev) < 0.4 else "Перевес %s: %.1f пешки" % [who, absf(ev)]
	if cur > 0:
		var d = (float(evals[cur]) - float(evals[cur - 1])) / 100.0
		if absf(d) >= 0.5:
			line += "   (этот ход изменил оценку на %+.1f)" % d
	eval_label.text = line

func _refresh_moves(list: Array, highlight: int) -> void:
	var out := []
	var i := 0
	while i < list.size():
		var num = i / 2 + 1
		var w = str(list[i])
		var b = str(list[i + 1]) if i + 1 < list.size() else ""
		if highlight == i + 1:
			w = "[" + w + "]"
		if highlight == i + 2 and b != "":
			b = "[" + b + "]"
		out.append("%d. %s  %s" % [num, w, b])
		i += 2
	moves_label.text = "\n".join(out)

func _build_replay_controls() -> void:
	for spec in [["⏮", "first"], ["◀", "prev"], ["▶", "next"], ["⏭", "last"], ["▶▶ Авто", "auto"]]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(70 if spec[1] != "auto" else 110, 40)
		b.text = str(spec[0])
		b.pressed.connect(_on_replay_control.bind(str(spec[1])))
		controls.add_child(b)

func _on_replay_control(what: String) -> void:
	match what:
		"first": auto_play = false; _seek(0)
		"prev": auto_play = false; _seek(cur - 1)
		"next": auto_play = false; _seek(cur + 1)
		"last": auto_play = false; _seek(states.size() - 1)
		"auto":
			auto_play = not auto_play
			auto_left = 0.0
			controls.get_child(4).text = "⏸ Стоп" if auto_play else "▶▶ Авто"

# ---------------------------------------------------------- живая партия

func _build_live_controls() -> void:
	for spec in [["⏸ Пауза", "pause"], ["К базе", "back"]]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(140, 40)
		b.text = str(spec[0])
		b.pressed.connect(_on_live_control.bind(str(spec[1])))
		controls.add_child(b)

func _on_live_control(what: String) -> void:
	if what == "back":
		_back()
		return
	if finished:
		return
	paused = not paused
	controls.get_child(0).text = "▶ Продолжить" if paused else "⏸ Пауза"

func _start_live() -> void:
	title_label.text = "ПАРТИЯ ИГРАЕТСЯ"
	engine = ChessEngine.new()
	engine.setup_start_position()
	ai_white = ChessAI.new(int(white_rec.level))
	ai_black = ChessAI.new(int(black_rec.level))
	live_coords = []
	live_moves = []
	finished = false
	players_label.text = "⚪ %s (%d)\n⚫ %s (%d)" % [
		str(white_rec.name), int(round(float(white_rec.rating))),
		str(black_rec.name), int(round(float(black_rec.rating)))]
	status_label.text = "Партия играется прямо сейчас и попадёт в архив обоих"
	board_draw.queue_redraw()

func _process(delta: float) -> void:
	if mode == "replay":
		if not auto_play or states.is_empty():
			return
		auto_left -= delta
		if auto_left > 0.0:
			return
		auto_left = 1.1
		if cur >= states.size() - 1:
			auto_play = false
			controls.get_child(4).text = "▶▶ Авто"
			return
		_seek(cur + 1)
		return
	if finished:
		return
	if _sync_ready or (_thread != null and not _thread.is_alive()):
		if _thread != null:
			_thread.wait_to_finish()
		_thread = null
		_sync_ready = false
		var mv = _pending
		_pending = null
		if mv == null or (mv is Dictionary and mv.is_empty()):
			_finish_live("no_move")
			return
		last_from = mv.from
		last_to = mv.to
		live_moves.append(BoardScript.move_notation(engine, mv))
		live_coords.append(BoardScript.move_coord(mv))
		engine.apply_move(mv)
		_refresh_moves(live_moves, -1)
		board_draw.queue_redraw()
		state_label.text = "Ход %d · думает %s" % [engine.fullmove_number,
			str(white_rec.name) if engine.side_to_move == "w" else str(black_rec.name)]
		if live_moves.size() >= MAX_PLIES:
			_finish_live("limit")
			return
		var st = engine.game_status()
		if st != "playing" and st != "check":
			_finish_live(st)
			return
		wait_left = 0.4
		return
	if _thread != null or _sync_ready or paused:
		return
	wait_left -= delta
	if wait_left > 0.0:
		return
	var ai: ChessAI = ai_white if engine.side_to_move == "w" else ai_black
	var snapshot: ChessEngine = engine.clone()
	if Global.can_thread:
		_thread = Thread.new()
		_thread.start(func(): _pending = ai.choose_move(snapshot))
	else:
		_pending = ai.choose_move(snapshot)
		_sync_ready = true

func _finish_live(status: String) -> void:
	finished = true
	var score := 0.5
	var txt := ""
	match status:
		"checkmate":
			# ходить некому — мат поставил тот, кто сходил последним
			var winner_white = engine.side_to_move == "b"
			score = 1.0 if winner_white else 0.0
			txt = "Мат! Победил %s" % [str(white_rec.name) if winner_white else str(black_rec.name)]
		"stalemate": txt = "Пат — ничья"
		"draw50": txt = "Ничья по правилу 50 ходов"
		"insufficient": txt = "Ничья: не хватает материала"
		"repetition": txt = "Ничья: троекратное повторение"
		"limit": txt = "Ничья: партия затянулась"
		_: txt = "Партия окончена"
	result_label.text = txt
	state_label.text = "Партия сыграна и записана в архив обоих игроков."
	# настоящая сыгранная партия — двигает рейтинги и остаётся в архиве
	Profile.apply_bot_result(str(white_rec.id), float(black_rec.rating), score)
	Profile.apply_bot_result(str(black_rec.id), float(white_rec.rating), 1.0 - score)
	Profile.record_bot_game(str(white_rec.id), str(black_rec.id),
		str(white_rec.name), str(black_rec.name), live_coords, score, "Партия в лиге")
	Profile.save_profile()

func _back() -> void:
	Global.bot_match = {}
	# call_deferred: _back() вызывается в том числе из _ready(), когда контекст
	# пуст, а менять сцену прямо во время её построения нельзя
	get_tree().change_scene_to_file.call_deferred("res://scenes/BotsHub.tscn")

func _on_back_pressed() -> void:
	_back()

func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
		_thread = null

# ------------------------------------------------------------- отрисовка

func _on_board_draw() -> void:
	var cr := board_draw
	var font := ThemeDB.fallback_font
	for r in range(8):
		for f in range(8):
			var pos = Vector2(f * SQ, (7 - r) * SQ)
			var light = (f + r) % 2 == 1
			var col = Color(0.24, 0.28, 0.4) if light else Color(0.13, 0.15, 0.23)
			cr.draw_rect(Rect2(pos, Vector2(SQ, SQ)), col, true)
			if Vector2i(f, r) == last_from or Vector2i(f, r) == last_to:
				cr.draw_rect(Rect2(pos, Vector2(SQ, SQ)), Color(0.95, 0.8, 0.35, 0.35), true)
	cr.draw_rect(Rect2(Vector2.ZERO, Vector2(SQ * 8, SQ * 8)), Color(0.11, 0.85, 0.95, 0.5), false, 2.0)
	for f in range(8):
		cr.draw_string(font, Vector2(f * SQ + SQ - 14, SQ * 8 - 5), char(97 + f),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.45))
	for r in range(8):
		cr.draw_string(font, Vector2(4, (7 - r) * SQ + 14), str(r + 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.45))
	if engine == null:
		return
	for r in range(8):
		for f in range(8):
			var p = engine.board[r][f]
			if p == null:
				continue
			var center = Vector2(f * SQ + SQ / 2, (7 - r) * SQ + SQ / 2)
			PieceTextures.draw(cr, p.type, p.color, center, SQ * 0.92)
