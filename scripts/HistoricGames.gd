extends Control

# «Партии великих шахматистов» — изучение знаменитых исторических партий.
# Навигация в два уровня: сначала выбор шахматиста (по фамилии), затем выбор
# его партии, затем сама доска с пошаговым разбором. Каждый ход сопровождается
# объяснением: у ключевых ходов оно написано вручную (поле "c" в данных), у
# остальных генерируется автоматически по типу хода (взятие, шах, рокировка,
# развитие фигуры и т.д.) — так объяснён буквально каждый ход.

const GamesData := preload("res://scripts/HistoricGamesData.gd")
const Comments := preload("res://scripts/HistoricComments.gd")

const SQ := 62.0
const LIGHT_COL := Color(0.32, 0.38, 0.5)
const DARK_COL := Color(0.14, 0.17, 0.26)
const AUTO_STEP := 2.2

@onready var list_scroll: ScrollContainer = $Main/ListScroll
@onready var list_vbox: VBoxContainer = $Main/ListScroll/ListVBox
@onready var list_title: Label = $Main/ListScroll/ListVBox/ListTitle
@onready var list_toggle_button: Button = $Main/BoardArea/ListToggleButton
@onready var board_area: Control = $Main/BoardArea
@onready var board_draw: Node2D = $Main/BoardArea/BoardDraw
@onready var title_label: Label = $Main/BoardArea/InfoPanel/VBox/TitleLabel
@onready var meta_label: Label = $Main/BoardArea/InfoPanel/VBox/MetaLabel
@onready var comment_label: Label = $Main/BoardArea/InfoPanel/VBox/CommentScroll/CommentLabel
@onready var counter_label: Label = $Main/BoardArea/Controls/CounterLabel
@onready var auto_check: CheckButton = $Main/BoardArea/Controls/AutoCheck

var players: Array = []
var current_player: Dictionary = {}
var current_game: Dictionary = {}
var nav_button_group: ButtonGroup
var states: Array = [] # ChessEngine snapshots, index 0 = start position
var moves: Array = [] # move dicts, index 0 = null
var comments: Array = [] # display text, index 0 = intro
var evals: Array = [] # позиционная оценка (сантипешки, + за белых) для каждого состояния
var cur := 0
var _auto_accum := 0.0

# Статический оценщик позиции — та же оценка, что показывает движок ИИ.
# Используется только для шкалы перевеса, поэтому уровень не важен.
var evaluator: ChessAI = ChessAI.new(1)

func _ready() -> void:
	players = GamesData.players()
	board_draw.draw.connect(_on_board_draw)
	_show_players()

# --- уровень 1: список шахматистов ---
func _show_players() -> void:
	current_player = {}
	current_game = {}
	states = []
	board_area.visible = false
	list_scroll.visible = true
	list_title.text = "Выберите шахматиста:"
	_clear_nav()
	nav_button_group = ButtonGroup.new()
	for p in players:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 62)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_fit_list_button(b)
		var seen := 0
		for g in p.games:
			if int(Profile.historic_games_viewed.get(str(g.id), 0)) > 0:
				seen += 1
		var mark = "  (изучено %d/%d)" % [seen, p.games.size()] if seen > 0 else "  (%d партий)" % p.games.size()
		b.text = "%s\n%s%s" % [p.name, p.years, mark]
		b.pressed.connect(_show_games.bind(p))
		list_vbox.add_child(b)

# --- уровень 2: список партий выбранного шахматиста ---
func _show_games(p: Dictionary) -> void:
	current_player = p
	current_game = {}
	states = []
	board_area.visible = false
	list_scroll.visible = true
	list_title.text = "%s — %s" % [p.name, p.years]
	_clear_nav()
	nav_button_group = ButtonGroup.new()
	var back := Button.new()
	back.custom_minimum_size = Vector2(0, 40)
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_fit_list_button(back)
	back.text = "◂ Ко всем шахматистам"
	back.pressed.connect(_show_players)
	list_vbox.add_child(back)
	for g in p.games:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 56)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_fit_list_button(b)
		b.toggle_mode = true
		b.button_group = nav_button_group
		var seen = int(Profile.historic_games_viewed.get(str(g.id), 0)) > 0
		var mark = "✔ " if seen else ""
		b.text = "%s%s\n%s vs %s · %d" % [mark, g.title, g.white, g.black, g.year]
		b.tooltip_text = "%s\n%s vs %s · %d" % [g.title, g.white, g.black, g.year]
		b.pressed.connect(_load_game.bind(g))
		list_vbox.add_child(b)

# Кнопки списка не должны диктовать ширину панели: у названий партий текст
# длинный, а горизонтальная прокрутка у ListScroll отключена — без clip_text
# минимальная ширина списка разрасталась до ~500px, распирала Main/HBox
# и сдвигала доску с панелью комментария. Обрезаем многоточием,
# полный текст — в подсказке.
func _fit_list_button(b: Button) -> void:
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

func _clear_nav() -> void:
	for c in list_vbox.get_children():
		if c == list_title:
			continue
		c.queue_free()

# --- уровень 3: доска с разбором ---
func _load_game(g: Dictionary) -> void:
	current_game = g
	states = []
	moves = [null]
	comments = ["%s\n%s — %s, %d (%s)\n\n%s" % [g.opening, g.white, g.black, g.year, g.event, g.blurb]]
	var eng := ChessEngine.new()
	if str(g.get("start_fen", "")) != "":
		eng.setup_from_fen(g.start_fen)
	else:
		eng.setup_start_position()
	states.append(eng.clone())
	evals = [evaluator.evaluate_position(eng)]
	var notes: Dictionary = g.get("notes", {})
	var ply := 0
	for san in game_moves(g):
		var before = eng.clone()
		var mv = _parse_san(eng, san)
		if mv.is_empty():
			comments.append("(запись партии дальше не читается)")
			break
		eng.apply_move(mv)
		ply += 1
		var hand = str(notes.get(ply, ""))
		var text = hand if hand != "" else _auto_comment(before, eng, mv, san, ply)
		moves.append(mv)
		states.append(eng.clone())
		evals.append(evaluator.evaluate_position(eng))
		comments.append(text)
	title_label.text = g.title
	meta_label.text = "%s · %s vs %s (%d) · %s" % [g.opening, g.white, g.black, g.year, g.result]
	Profile.historic_games_viewed[str(g.id)] = maxi(int(Profile.historic_games_viewed.get(str(g.id), 0)), 1)
	Profile.save_profile()
	board_area.visible = true
	_seek(0)

# Пояснение для рядового хода, если у него нет написанного вручную комментария.
# Не шаблон "фигура пошла туда-то", а разбор ПОЧЕМУ ход мог быть сыгран:
# движок проверяет, была ли фигура под боем, создаёт ли ход угрозу сопернику,
# первое ли это развитие фигуры, борьба ли это за центр, открытая ли линия
# для ладьи и т.д. — и складывает из найденных причин живое объяснение.
func _auto_comment(before: ChessEngine, after: ChessEngine, mv: Dictionary, san: String, ply: int) -> String:
	var num = (ply + 1) / 2
	var mover = "Белые" if (ply % 2 == 1) else "Чёрные"
	var prefix = "%d. %s (%s): " % [num, mover, san]
	var body := ""
	var mover_color: String = "w" if ply % 2 == 1 else "b"
	var opp_color: String = "b" if mover_color == "w" else "w"
	var v: int = (ply + mv.to.x + mv.to.y) % 3
	if mv.get("is_castle", "") != "":
		var short: bool = mv.get("is_castle", "") == "K"
		var late: bool = num > 12
		if short:
			body = [
				"короткая рокировка: король прячется за пешками в угол, а ладья сразу выходит на центральную линию — двойная польза одним ходом.",
				"рокировка в короткую сторону — король в безопасности, ладья включена в игру; хороший момент сделать её, пока центр ещё не вскрыт.",
				"король уходит в короткую рокировку: за его спиной пешки f, g, h, а ладья становится ближе к центру.",
			][v]
		else:
			body = [
				"длинная рокировка: король уходит на ферзевый фланг, ладья занимает центральную линию d — но король тут обычно менее защищён, чем при короткой.",
				"рокировка в длинную сторону: обе ладьи скоро смогут работать в центре, а король уходит подальше от открытой игры — хотя и оказывается ближе к ферзевому флангу.",
				"длинная рокировка — ладья сразу встаёт на линию d, а король становится в стороне; такой выбор часто означает планы штурма на противоположном фланге.",
			][v]
		if late:
			body += " Рокировка на %d-м ходу — король долго оставался в центре." % num
	else:
		body = Comments.explain(before, after, mv, ply)
	var status = after.game_status()
	if status == "checkmate":
		body += " Мат — партия окончена!"
	elif status == "stalemate":
		body += " Пат — ничья."
	elif after.is_in_check(after.side_to_move):
		body += " Шах королю!"
	if ply == 1:
		body += "
Дебют: главное — развить фигуры и увести короля из центра, не тратя ходы впустую."
	elif ply == 2 and str(current_game.get("opening", "")) != "":
		body += "
Дебют партии: %s." % str(current_game.get("opening", ""))
	elif ply == 21:
		body += "
Миттельшпиль: фигуры развиты, начинается борьба планов и комбинаций."
	elif Comments.is_endgame(after) and not Comments.is_endgame(before):
		body += "
Эндшпиль: на доске осталось мало фигур, король становится активным бойцом. " + Comments.material_line(after)
	elif ply % 12 == 0 and status == "playing":
		body += "
" + Comments.material_line(after)
	return prefix + body

# Список ходов партии в SAN: из строки "pgn" (движущийся текст с номерами
# ходов) либо из массива "moves" (строки или словари {san,c}).
static func game_moves(g: Dictionary) -> Array:
	if g.has("pgn"):
		return tokenize_pgn(str(g.pgn))
	var out := []
	for entry in g.get("moves", []):
		out.append(str(entry.san) if entry is Dictionary else str(entry))
	return out

# Разбор PGN-движущегося текста в список SAN-ходов: выбрасывает номера ходов
# ("1.", "12...") и маркеры результата ("1-0", "0-1", "1/2-1/2", "*").
static func tokenize_pgn(pgn: String) -> Array:
	var text := pgn.replace("\n", " ").replace("\r", " ").replace("\t", " ")
	var out := []
	for raw in text.split(" ", false):
		var tok := raw.strip_edges()
		if tok == "" or tok in ["1-0", "0-1", "1/2-1/2", "*"]:
			continue
		var dot = tok.rfind(".")
		if dot >= 0:
			var head = tok.substr(0, dot).replace(".", "")
			var after = tok.substr(dot + 1)
			if head.is_valid_int():
				if after == "":
					continue
				tok = after
		if tok != "":
			out.append(tok)
	return out

static func _parse_san(eng: ChessEngine, text: String) -> Dictionary:
	var s := text.strip_edges().replace("+", "").replace("#", "").replace("!", "").replace("?", "")
	var legal = eng.legal_moves(eng.side_to_move)
	if s.begins_with("O-O-O") or s.begins_with("0-0-0"):
		for m in legal:
			if m.get("is_castle", "") == "Q":
				return m
		return {}
	if s.begins_with("O-O") or s.begins_with("0-0"):
		for m in legal:
			if m.get("is_castle", "") == "K":
				return m
		return {}
	var promo := ""
	var eq = s.find("=")
	if eq >= 0:
		promo = s.substr(eq + 1, 1)
		s = s.substr(0, eq)
	var piece := "P"
	if s.length() > 0 and s[0] in "NBRQK":
		piece = s[0]
		s = s.substr(1)
	s = s.replace("x", "")
	if s.length() < 2:
		return {}
	var dest = _square(s.substr(s.length() - 2, 2))
	var disamb = s.substr(0, s.length() - 2)
	var candidates := []
	for m in legal:
		if m.to != dest:
			continue
		var p = eng.board[m.from.y][m.from.x]
		var ptype = p.type if p != null else "P"
		if ptype != piece:
			continue
		if promo != "" and str(m.get("promo", "")) != "" and str(m.get("promo", "")) != promo:
			continue
		candidates.append(m)
	if candidates.size() == 1:
		return candidates[0]
	if disamb != "":
		for m in candidates:
			var sq_name = ChessEngine.square_name(m.from.x, m.from.y)
			if disamb.length() == 2 and sq_name == disamb:
				return m
			if disamb.length() == 1:
				if disamb[0].is_valid_int() and sq_name[1] == disamb:
					return m
				elif not disamb[0].is_valid_int() and sq_name[0] == disamb:
					return m
	if not candidates.is_empty():
		return candidates[0]
	return {}

static func _square(sq_name: String) -> Vector2i:
	return Vector2i(sq_name.unicode_at(0) - 97, sq_name.unicode_at(1) - 49)

func _seek(i: int) -> void:
	if states.is_empty():
		return
	cur = clampi(i, 0, states.size() - 1)
	var txt = comments[cur] if cur < comments.size() else ""
	if cur < evals.size():
		txt += "\n\n" + _advantage_text(cur)
	comment_label.text = txt
	counter_label.text = "%d / %d" % [cur, states.size() - 1]
	board_draw.queue_redraw()

# Текстовое описание перевеса: кто впереди и как ход изменил оценку.
func _advantage_text(idx: int) -> String:
	# статус мата/пата в самом конце важнее числовой оценки
	var st: ChessEngine = states[idx]
	if idx == states.size() - 1:
		var status = st.game_status()
		if status == "checkmate":
			var winner = "чёрные" if st.side_to_move == "w" else "белые"
			return "⚖ Мат — победили %s!" % winner
		if status in ["stalemate", "draw50", "insufficient", "repetition"]:
			return "⚖ Ничья."
	var ev = evals[idx] / 100.0
	var line := ""
	if absf(ev) < 0.4:
		line = "⚖ Перевес: примерно равная позиция"
	elif ev > 0:
		line = "⚖ Перевес: у белых +%.1f пешки" % ev
	else:
		line = "⚖ Перевес: у чёрных +%.1f пешки" % (-ev)
	if idx > 0:
		var d = (evals[idx] - evals[idx - 1]) / 100.0
		if d > 0.5:
			line += "\n↑ этот ход усилил позицию белых на %.1f пешки" % d
		elif d < -0.5:
			line += "\n↓ этот ход усилил позицию чёрных на %.1f пешки" % (-d)
	return line

func _on_first_pressed() -> void: _seek(0)
func _on_prev_pressed() -> void: _seek(cur - 1)
func _on_next_pressed() -> void: _seek(cur + 1)
func _on_last_pressed() -> void: _seek(states.size() - 1)

# Список партий занимает фиксированную полосу слева и на маленьком
# разрешении не оставляет месте под текст комментария — во время самой
# партии список можно свернуть одной кнопкой, освободив место под доску.
func _on_list_toggle_pressed() -> void:
	list_scroll.visible = not list_scroll.visible
	list_toggle_button.text = "▸" if not list_scroll.visible else "◂"

func _process(delta: float) -> void:
	if auto_check != null and auto_check.button_pressed and not states.is_empty():
		if cur >= states.size() - 1:
			auto_check.button_pressed = false
			return
		_auto_accum += delta
		if _auto_accum >= AUTO_STEP:
			_auto_accum = 0.0
			_seek(cur + 1)

func _on_board_draw() -> void:
	var eng: ChessEngine = states[cur] if cur < states.size() else null
	var from = Vector2i(-1, -1)
	var to = Vector2i(-1, -1)
	if cur > 0 and cur < moves.size() and moves[cur] != null:
		from = moves[cur].from
		to = moves[cur].to
	_draw_board(board_draw, eng, from, to)

func _draw_board(cr: Node2D, eng: ChessEngine, from: Vector2i, to: Vector2i) -> void:
	var font = ThemeDB.fallback_font
	for r in range(8):
		for f in range(8):
			var pos = Vector2(f * SQ, (7 - r) * SQ)
			var col = LIGHT_COL if (f + r) % 2 == 1 else DARK_COL
			cr.draw_rect(Rect2(pos, Vector2(SQ, SQ)), col, true)
			if Vector2i(f, r) == from:
				cr.draw_rect(Rect2(pos, Vector2(SQ, SQ)), Color(0.95, 0.8, 0.35, 0.35), true)
			if Vector2i(f, r) == to:
				cr.draw_rect(Rect2(pos, Vector2(SQ, SQ)), Color(0.95, 0.8, 0.35, 0.55), true)
	cr.draw_rect(Rect2(Vector2.ZERO, Vector2(SQ * 8, SQ * 8)), Color(0.11, 0.85, 0.95, 0.5), false, 2.0)
	for f in range(8):
		cr.draw_string(font, Vector2(f * SQ + SQ - 14, SQ * 8 - 5), char(97 + f), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.45))
	for r in range(8):
		cr.draw_string(font, Vector2(4, (7 - r) * SQ + 14), str(r + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.45))
	if eng == null:
		return
	for r in range(8):
		for f in range(8):
			var p = eng.board[r][f]
			if p == null:
				continue
			var center = Vector2(f * SQ + SQ / 2, (7 - r) * SQ + SQ / 2)
			PieceTextures.draw(cr, p.type, p.color, center, SQ * 0.92)
	if from.x >= 0 and to.x >= 0:
		_draw_arrow(cr, from, to, Color(1.0, 0.35, 0.35, 0.9))
	_draw_eval_bar(cr)

# Вертикальная шкала перевеса справа от доски: белая доля снизу, чёрная сверху.
# Чем больше белая часть — тем сильнее перевес белых, и наоборот.
func _draw_eval_bar(cr: Node2D) -> void:
	if cur >= evals.size():
		return
	var ev = float(evals[cur])
	var white_frac = clampf(0.5 + ev / 1200.0, 0.04, 0.96)
	var h = SQ * 8
	var bar = Rect2(Vector2(SQ * 8 + 10, 0), Vector2(18, h))
	cr.draw_rect(bar, Color(0.1, 0.1, 0.14), true)
	cr.draw_rect(Rect2(bar.position + Vector2(0, h * (1.0 - white_frac)), Vector2(bar.size.x, h * white_frac)), Color(0.9, 0.92, 0.95), true)
	cr.draw_rect(bar, Color(0.11, 0.85, 0.95, 0.5), false, 1.5)
	# отметка середины (равенство)
	cr.draw_line(bar.position + Vector2(-2, h / 2), bar.position + Vector2(bar.size.x + 2, h / 2), Color(1, 0.65, 0.95, 0.7), 1.5)
	var font = ThemeDB.fallback_font
	cr.draw_string(font, bar.position + Vector2(2, 12), "Ч", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.45, 0.55))
	cr.draw_string(font, bar.position + Vector2(2, h - 4), "Б", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.45, 0.55))
	# без числа шкала ничего не говорит: подписываем перевес в пешках
	# (знак — с точки зрения белых, как и сама заливка)
	var pawns = ev / 100.0
	var cap_txt = "" if absf(pawns) < 6.0 else "!"
	cr.draw_string(font, bar.position + Vector2(-6, -6),
		("=" if absf(pawns) < 0.4 else "%+.1f%s" % [pawns, cap_txt]),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.9, 0.95))

func _draw_arrow(cr: Node2D, from: Vector2i, to: Vector2i, col: Color) -> void:
	var a = Vector2(from.x * SQ + SQ / 2, (7 - from.y) * SQ + SQ / 2)
	var b = Vector2(to.x * SQ + SQ / 2, (7 - to.y) * SQ + SQ / 2)
	var dir = (b - a).normalized()
	var tip = b - dir * SQ * 0.18
	cr.draw_line(a, tip - dir * 10.0, col, 5.0)
	var side = Vector2(-dir.y, dir.x) * 9.0
	cr.draw_colored_polygon(PackedVector2Array([tip, tip - dir * 18.0 + side, tip - dir * 18.0 - side]), col)

func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")
