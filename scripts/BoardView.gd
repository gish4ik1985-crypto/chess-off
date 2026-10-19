class_name BoardView
extends Control

# Простая доска для заданий и онлайн-партий: рисует позицию движка, даёт сделать ход
# по двум нажатиям (выбрал фигуру — выбрал клетку). Ферзя при превращении ставит сам.
# Режимы: interactive + turn_color — ходит только эта сторона; sandbox — можно ходить за обе стороны
# (конструктор заданий). Ход сообщается сигналом move_made; применяет его сама доска.

signal move_made(move: Dictionary, uci: String)

var engine := ChessEngine.new()
var perspective := "w" # с чьей стороны смотрим на доску
var interactive := false
var turn_color := "" # кому разрешено ходить ("w"/"b"); пусто — никому
var sandbox := false
var _sel = null
var _targets: Array = []
var _hint: Array = [] # две клетки подсветки (Vector2i)

func _ready() -> void:
	custom_minimum_size = Vector2(360, 360)
	mouse_filter = Control.MOUSE_FILTER_STOP
	engine.setup_start_position()
	resized.connect(queue_redraw)

# ---- хелперы записи ходов ----

static func sq_name(v: Vector2i) -> String:
	return char(97 + v.x) + str(v.y + 1)

static func uci_of(m: Dictionary) -> String:
	return sq_name(m.from) + sq_name(m.to) + String(m.get("promo", "")).to_lower()

# Находит среди допустимых ходов позиции ход по записи «e2e4» (превращение — пятой буквой).
static func find_move(eng: ChessEngine, uci: String) -> Dictionary:
	for m in eng.legal_moves(eng.side_to_move):
		var u := uci_of(m)
		if u == uci or (u.length() == 5 and u.substr(0, 4) == uci and u[4] == "q"):
			return m
	return {}

func set_fen(fen: String) -> void:
	engine = ChessEngine.new()
	engine.setup_from_fen(fen)
	_sel = null
	_targets = []
	queue_redraw()

func play_uci(uci: String) -> bool:
	var m := find_move(engine, uci)
	if m.is_empty():
		return false
	engine.apply_move(m)
	_sel = null
	_targets = []
	queue_redraw()
	return true

func show_hint(a: Vector2i, b: Vector2i) -> void:
	_hint = [a, b]
	queue_redraw()

func clear_hint() -> void:
	_hint = []
	queue_redraw()

func clear_selection() -> void:
	_sel = null
	_targets = []
	queue_redraw()

# ---- геометрия ----

func _sq() -> float:
	return minf(size.x, size.y) / 8.0

func _origin() -> Vector2:
	return (size - Vector2(_sq(), _sq()) * 8.0) / 2.0

func _to_pixel(v: Vector2i) -> Vector2:
	var f := v.x if perspective == "w" else 7 - v.x
	var r := 7 - v.y if perspective == "w" else v.y
	return _origin() + Vector2(f, r) * _sq()

func _to_square(p: Vector2) -> Vector2i:
	var q := (p - _origin()) / _sq()
	var f := int(floor(q.x))
	var r := int(floor(q.y))
	if f < 0 or f > 7 or r < 0 or r > 7:
		return Vector2i(-1, -1)
	return Vector2i(f if perspective == "w" else 7 - f, 7 - r if perspective == "w" else r)

# ---- рисование ----

func _draw() -> void:
	var s := _sq()
	for r in range(8):
		for f in range(8):
			Themes.draw_square(self, Rect2(_to_pixel(Vector2i(f, r)), Vector2(s, s)), (f + r) % 2 == 1, r * 8 + f)
	if engine.last_move != null:
		for v in [engine.last_move.from, engine.last_move.to]:
			draw_rect(Rect2(_to_pixel(v), Vector2(s, s)), Themes.hl_last(), true)
	if engine.is_in_check(engine.side_to_move):
		var k := engine.find_king(engine.side_to_move)
		if k.x >= 0:
			draw_rect(Rect2(_to_pixel(k), Vector2(s, s)), Themes.hl_check(), true)
	for v in _hint:
		draw_rect(Rect2(_to_pixel(v), Vector2(s, s)), Themes.hl_hint(), true)
	if _sel != null:
		draw_rect(Rect2(_to_pixel(_sel), Vector2(s, s)), Themes.hl_select(), true)
		for m in _targets:
			var c: Vector2 = _to_pixel(m.to) + Vector2(s, s) / 2.0
			if engine.board[m.to.y][m.to.x] != null or m.get("is_ep", false):
				draw_arc(c, s * 0.42, 0, TAU, 24, Themes.capture_ring(), 4.0, true)
			else:
				draw_circle(c, s * 0.15, Themes.move_dot())
	for r in range(8):
		for f in range(8):
			var p = engine.board[r][f]
			if p != null:
				PieceTextures.draw(self, p.type, p.color, _to_pixel(Vector2i(f, r)) + Vector2(s, s) / 2.0, s * 0.92)
	# подписи a–h и 1–8 по краям
	var font := ThemeDB.fallback_font
	for i in range(8):
		var fx := i if perspective == "w" else 7 - i
		draw_string(font, _to_pixel(Vector2i(fx, 0 if perspective == "w" else 7)) + Vector2(s - 11, s - 4), char(97 + fx), HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(10, int(s * 0.18)), Themes.coord_color((fx + (0 if perspective == "w" else 7)) % 2 == 1))
		var ry := i if perspective == "w" else 7 - i
		draw_string(font, _to_pixel(Vector2i(0 if perspective == "w" else 7, ry)) + Vector2(3, maxi(12, int(s * 0.2))), str(ry + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(10, int(s * 0.18)), Themes.coord_color(((0 if perspective == "w" else 7) + ry) % 2 == 1))

# ---- ввод ----

func _mover() -> String:
	if not interactive:
		return ""
	return engine.side_to_move if sandbox else turn_color

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var v := _to_square(event.position)
	if v.x < 0:
		return
	var mover := _mover()
	if mover == "" or engine.side_to_move != mover:
		return
	if _sel != null:
		for m in _targets:
			if m.to == v:
				var chosen: Dictionary = m
				engine.apply_move(chosen)
				_sel = null
				_targets = []
				queue_redraw()
				move_made.emit(chosen, uci_of(chosen))
				return
	var p = engine.board[v.y][v.x]
	if p != null and p.color == mover:
		_sel = v
		_targets = engine.legal_moves_for_square(v.x, v.y)
	else:
		_sel = null
		_targets = []
	queue_redraw()
