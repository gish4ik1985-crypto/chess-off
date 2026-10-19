extends Control

# «Записная книжка партий»: записывать партии нотацией или ходами на доске, вставлять PGN, листать,
# комментировать, разбирать движком, играть с любой позиции и делиться с школой. Строится кодом.

const RESULTS := ["*", "1-0", "0-1", "1/2-1/2"]

var _root: VBoxContainer
var _status: Label
var _view: VBoxContainer

# редактор
var _headers: Dictionary = {}
var _sans: Array = []
var _ucis: Array = []
var _comments: Array = []
var _fens: Array = [GameRecord.START_FEN]
var _cur := 0
var _result := "*"
var _rec_id := ""
var _analysis: Array = [] # на каждый ход: {loss, cat, best}
var _board: BoardView
var _moves_lbl: RichTextLabel
var _info: Label
var _comment: LineEdit
var _input: LineEdit
var _ed_status: Label
var _edit_headers: Dictionary = {}
var _res_opt: OptionButton
var _busy := false
var _external := false # открыто из турнира: «Назад» возвращает туда, а не к списку записей

func _ready() -> void:
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.02, 0.02, 0.05)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 72.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_root = VBoxContainer.new()
	_root.custom_minimum_size = Vector2(1000, 0)
	_root.add_theme_constant_override("separation", 12)
	center.add_child(_root)
	Global.add_floating_back(self, _on_back)
	var title := Label.new()
	title.text = "ЗАПИСНАЯ КНИЖКА ПАРТИЙ"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.96, 0.76, 0.3))
	title.position = Vector2(24, 16)
	add_child(title)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 13)
	_root.add_child(_status)
	_view = VBoxContainer.new()
	_view.add_theme_constant_override("separation", 10)
	_root.add_child(_view)
	if Global.pending_pgn != "":
		var t := Global.pending_pgn
		Global.pending_pgn = ""
		_external = true
		_open_record({"id": "", "pgn": t})
	else:
		_show_list()

func _on_back() -> void:
	if _board != null and not _external:
		_show_list()
		return
	Global.go_back()

func _clear() -> void:
	for ch in _view.get_children():
		ch.queue_free()
	_board = null

func _lbl(text: String, size := 14, color := Color(1, 1, 1, 0.92)) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	if color != Color(1, 1, 1, 0.92):
		l.add_theme_color_override("font_color", color)
	return l

func _btn(text: String, w := 0.0, h := 44.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	return b

# ------------------------------------------------------------------ список

func _show_list() -> void:
	_clear()
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	_view.add_child(top)
	var add := _btn("+ Новая запись", 190, 48)
	add.pressed.connect(func(): _open_record({"id": "", "pgn": ""}))
	top.add_child(add)
	var paste := _btn("📋 Вставить PGN из буфера", 250, 48)
	paste.pressed.connect(_paste_pgn)
	top.add_child(paste)
	_view.add_child(_lbl("Мои записи (хранятся в вашем профиле)", 14, Color(0.96, 0.76, 0.3)))
	if Profile.notebook.is_empty():
		_view.add_child(_lbl("Пока пусто. Нажмите «Новая запись» и играйте ходы за обе стороны или вводите их нотацией."))
	for r in Profile.notebook:
		_view.add_child(_row(r, true))
	_view.add_child(_lbl("Записи школы (поделились ученики и учителя)", 14, Color(0.96, 0.76, 0.3)))
	var school_box := VBoxContainer.new()
	school_box.add_theme_constant_override("separation", 8)
	_view.add_child(school_box)
	_load_school(school_box)

func _row(r: Dictionary, mine: bool) -> Control:
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(_lbl(String(r.get("title", "Партия")), 17))
	if not mine:
		col.add_child(_lbl("автор: %s" % String(r.get("by_name", "")), 12, Color(0.55, 0.6, 0.7)))
	var open := _btn("Открыть", 120)
	open.pressed.connect(func(): _open_record(r))
	row.add_child(open)
	if mine or Roles.can(Profile.role, "open_admin"):
		var del := _btn("Удалить", 100)
		del.pressed.connect(func():
			if mine:
				Profile.notebook.erase(r)
				Profile.request_save()
			else:
				var res: Dictionary = await Cloud.del_doc("gamebook/" + String(r.get("_id", "")))
				_status.text = "" if res.ok else String(res.error)
			_show_list())
		row.add_child(del)
	return panel

func _load_school(box: VBoxContainer) -> void:
	if not (Cloud.enabled and Cloud.signed_in):
		box.add_child(_lbl("Появятся после онлайн-входа.", 13, Color(0.55, 0.6, 0.7)))
		return
	var r: Dictionary = await Cloud.query_top("gamebook", "at", 100)
	if not is_instance_valid(box):
		return
	if not r.ok:
		box.add_child(_lbl(String(r.error), 13))
		return
	if r.docs.is_empty():
		box.add_child(_lbl("Пока никто не поделился.", 13, Color(0.55, 0.6, 0.7)))
	for d in r.docs:
		box.add_child(_row(d, false))

func _paste_pgn() -> void:
	var t := DisplayServer.clipboard_get()
	if t.strip_edges() == "":
		_status.text = "Буфер обмена пуст: скопируйте запись партии (PGN) и нажмите ещё раз."
		return
	_open_record({"id": "", "pgn": t})

# ------------------------------------------------------------------ редактор

func _open_record(r: Dictionary) -> void:
	_clear()
	_status.text = ""
	_rec_id = String(r.get("id", ""))
	_headers = {"White": "", "Black": "", "Event": "", "Date": Time.get_date_string_from_system().replace("-", ".")}
	_sans = []
	_ucis = []
	_comments = []
	_fens = [GameRecord.START_FEN]
	_result = "*"
	_analysis = []
	var pgn := String(r.get("pgn", ""))
	if pgn.strip_edges() != "":
		var p := GameRecord.parse_pgn(pgn)
		for k in p.headers:
			_headers[k] = p.headers[k]
		_result = String(p.result)
		var start := String(_headers.get("FEN", GameRecord.START_FEN))
		if start == "":
			start = GameRecord.START_FEN
		var rp := GameRecord.replay(p.sans, start)
		_fens = rp.fens
		_sans = rp.sans
		_ucis = rp.moves
		_comments = p.comments.slice(0, _sans.size())
		if not rp.ok:
			_status.text = "Ход № %d в записи не удалось разобрать — показано всё до него." % (int(rp.bad) + 1)
	_build_editor()
	_goto(_sans.size())

func _build_editor() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_view.add_child(row)
	_board = BoardView.new()
	_board.custom_minimum_size = Vector2(540, 540)
	_board.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_board.interactive = true
	_board.sandbox = true
	_board.move_made.connect(_on_board_move)
	row.add_child(_board)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	row.add_child(col)
	# шапка
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 6)
	col.add_child(g)
	_edit_headers = {}
	for pair in [["White", "Белые"], ["Black", "Чёрные"], ["Event", "Событие"], ["Date", "Дата"]]:
		var e := LineEdit.new()
		e.placeholder_text = pair[1]
		e.text = String(_headers.get(pair[0], ""))
		e.custom_minimum_size = Vector2(0, 40)
		e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		e.text_changed.connect(func(t): _headers[pair[0]] = t)
		g.add_child(e)
		_edit_headers[pair[0]] = e
	_res_opt = OptionButton.new()
	for r in RESULTS:
		_res_opt.add_item("Результат: " + ("не закончена" if r == "*" else r))
	_res_opt.selected = maxi(0, RESULTS.find(_result))
	_res_opt.custom_minimum_size = Vector2(0, 40)
	_res_opt.item_selected.connect(func(i): _result = RESULTS[i])
	col.add_child(_res_opt)
	# ходы
	_moves_lbl = RichTextLabel.new()
	_moves_lbl.bbcode_enabled = true
	_moves_lbl.custom_minimum_size = Vector2(0, 170)
	_moves_lbl.meta_clicked.connect(func(m): _goto(int(str(m))))
	col.add_child(_moves_lbl)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	col.add_child(nav)
	for spec in [["⏮", 0], ["◀", -1], ["▶", 1], ["⏭", 99999]]:
		var b := _btn(spec[0], 64)
		var step: int = spec[1]
		b.pressed.connect(func():
			if step == 0:
				_goto(0)
			elif step == 99999:
				_goto(_sans.size())
			else:
				_goto(clampi(_cur + step, 0, _sans.size())))
		nav.add_child(b)
	var undo := _btn("↩ Убрать ход", 140)
	undo.pressed.connect(func():
		if _sans.is_empty():
			return
		_truncate(_sans.size() - 1)
		_goto(_sans.size()))
	nav.add_child(undo)
	_info = _lbl("", 13, Color(0.96, 0.76, 0.3))
	col.add_child(_info)
	# ввод нотацией
	var inrow := HBoxContainer.new()
	inrow.add_theme_constant_override("separation", 6)
	col.add_child(inrow)
	_input = LineEdit.new()
	_input.placeholder_text = "Ход нотацией: Nf3, Кf3, e4, O-O, e2e4…"
	_input.custom_minimum_size = Vector2(0, 42)
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(func(_t): _on_notation())
	inrow.add_child(_input)
	var go := _btn("Ход", 80, 42)
	go.pressed.connect(_on_notation)
	inrow.add_child(go)
	_comment = LineEdit.new()
	_comment.placeholder_text = "Комментарий к этому ходу"
	_comment.custom_minimum_size = Vector2(0, 40)
	_comment.text_changed.connect(func(t):
		if _cur > 0 and _cur <= _comments.size():
			_comments[_cur - 1] = t
			_render_moves())
	col.add_child(_comment)
	# действия
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 6)
	acts.add_theme_constant_override("v_separation", 6)
	col.add_child(acts)
	var save := _btn("💾 Сохранить", 140)
	save.pressed.connect(_on_save)
	acts.add_child(save)
	var an := _btn("🔍 Разбор", 120)
	an.pressed.connect(_on_analyze)
	acts.add_child(an)
	var play := _btn("♟ Играть отсюда", 160)
	play.pressed.connect(_on_play_from_here)
	acts.add_child(play)
	var share := _btn("📣 Поделиться с школой", 210)
	share.pressed.connect(_on_share)
	acts.add_child(share)
	var cp := _btn("📋 Копировать PGN", 180)
	cp.pressed.connect(func():
		DisplayServer.clipboard_set(_pgn())
		_ed_status.text = "PGN скопирован в буфер обмена.")
	acts.add_child(cp)
	_ed_status = _lbl("", 13)
	col.add_child(_ed_status)

# ------------------------------------------------------------------ работа с записью

func _pgn() -> String:
	var h := _headers.duplicate()
	if _fens[0] != GameRecord.START_FEN:
		h["FEN"] = _fens[0]
		h["SetUp"] = "1"
	return GameRecord.build_pgn(h, _sans, _comments, _result)

func _truncate(n: int) -> void:
	_sans = _sans.slice(0, n)
	_ucis = _ucis.slice(0, n)
	_comments = _comments.slice(0, n)
	_fens = _fens.slice(0, n + 1)
	_analysis = _analysis.slice(0, n)

func _goto(k: int) -> void:
	_cur = clampi(k, 0, _sans.size())
	_board.set_fen(String(_fens[_cur]))
	_board.perspective = "w"
	if _cur > 0:
		var u := String(_ucis[_cur - 1])
		_board.engine.last_move = {"from": Vector2i(u.unicode_at(0) - 97, int(u[1]) - 1), "to": Vector2i(u.unicode_at(2) - 97, int(u[3]) - 1)}
	_board.queue_redraw()
	_comment.text = String(_comments[_cur - 1]) if _cur > 0 else ""
	_comment.editable = _cur > 0
	_render_moves()
	_show_ply_info()

func _render_moves() -> void:
	var start_black: bool = String(_fens[0]).contains(" b ")
	var t := ""
	for i in range(_sans.size()):
		var ply := i + (1 if start_black else 0)
		if ply % 2 == 0:
			t += "%d. " % (ply / 2 + 1)
		elif i == 0:
			t += "%d… " % (ply / 2 + 1)
		var col := ""
		if i < _analysis.size():
			col = {"inaccuracy": "#e8c547", "mistake": "#f08a3c", "blunder": "#ff5a5a"}.get(String(_analysis[i].cat), "")
		var mark := ""
		if i < _analysis.size():
			mark = {"inaccuracy": "?!", "mistake": "?", "blunder": "??"}.get(String(_analysis[i].cat), "")
		var s := ChessEngine.ru_notation(String(_sans[i])) + mark
		if String(_comments[i]) != "":
			s += " 💬"
		if col != "":
			s = "[color=%s]%s[/color]" % [col, s]
		if i + 1 == _cur:
			s = "[b][bgcolor=#3a4a66]%s[/bgcolor][/b]" % s
		t += "[url=%d]%s[/url] " % [i + 1, s]
	_moves_lbl.text = t if t != "" else "[color=#888]Ходов пока нет — сделайте ход на доске или введите его нотацией.[/color]"

func _show_ply_info() -> void:
	if _cur > 0 and _cur <= _analysis.size():
		var a: Dictionary = _analysis[_cur - 1]
		var cat := String(a.cat)
		if cat == "good":
			_info.text = "Хороший ход."
		else:
			var name: String = {"inaccuracy": "Неточность", "mistake": "Ошибка", "blunder": "Грубая ошибка"}.get(cat, "")
			_info.text = "%s: потеря ≈ %.1f пешки. Лучше было: %s" % [name, float(a.loss) / 100.0, ChessEngine.ru_notation(String(a.best))]
		return
	_info.text = "Ход %s." % ("белых" if _board.engine.side_to_move == "w" else "чёрных")

func _on_board_move(_m: Dictionary, uci: String) -> void:
	# ход сделан на доске: если смотрели не конец записи — продолжение заменяется новой веткой
	var before := ChessEngine.new()
	before.setup_from_fen(String(_fens[_cur]))
	var mv := BoardView.find_move(before, uci)
	if mv.is_empty():
		_goto(_cur)
		return
	_truncate(_cur)
	_sans.append(GameRecord.san(before, mv))
	_ucis.append(uci)
	_comments.append("")
	_fens.append(_board.engine.to_fen())
	_goto(_sans.size())

func _on_notation() -> void:
	var cur := ChessEngine.new()
	cur.setup_from_fen(String(_fens[_cur]))
	var text := _input.text.strip_edges()
	if text == "":
		return
	# можно вписать сразу несколько ходов через пробел: «e4 e5 Nf3»
	var added := 0
	for w in text.split(" ", false):
		var tok: String = w
		var k := 0
		while k < tok.length() and (tok[k].is_valid_int() or tok[k] == "."):
			k += 1
		tok = tok.substr(k)
		if tok == "":
			continue
		var m := GameRecord.parse_move(cur, tok)
		if m.is_empty():
			_ed_status.text = "Ход «%s» не подходит: такого хода нет или он записан неоднозначно." % tok
			break
		_truncate(_cur)
		_sans.append(GameRecord.san(cur, m))
		_ucis.append(BoardView.uci_of(m))
		_comments.append("")
		cur.apply_move(m)
		_fens.append(cur.to_fen())
		_cur = _sans.size()
		added += 1
	if added > 0:
		_input.text = ""
		_ed_status.text = ""
	_goto(_sans.size() if added > 0 else _cur)

func _title() -> String:
	var w := String(_headers.get("White", "")).strip_edges()
	var b := String(_headers.get("Black", "")).strip_edges()
	var t := ("%s — %s" % [w if w != "" else "?", b if b != "" else "?"]) if (w != "" or b != "") else "Партия"
	var ev := String(_headers.get("Event", "")).strip_edges()
	if ev != "":
		t += " · " + ev
	return "%s · %s" % [t, _result if _result != "*" else "…"]

func _on_save() -> void:
	if _rec_id == "":
		_rec_id = "n%d%03d" % [int(Time.get_unix_time_from_system()), randi() % 1000]
	var rec := {"id": _rec_id, "title": _title(), "pgn": _pgn(), "at": int(Time.get_unix_time_from_system())}
	var found := false
	for i in range(Profile.notebook.size()):
		if String(Profile.notebook[i].get("id", "")) == _rec_id:
			Profile.notebook[i] = rec
			found = true
	if not found:
		Profile.notebook.push_front(rec)
		if Profile.notebook.size() > 100:
			Profile.notebook.resize(100)
	Profile.request_save()
	_ed_status.text = "✔ Сохранено в вашей записной книжке."

func _on_share() -> void:
	if not (Cloud.enabled and Cloud.signed_in):
		_ed_status.text = "Чтобы поделиться, войдите онлайн."
		return
	_on_save()
	var pgn := _pgn()
	if pgn.length() > 12000:
		_ed_status.text = "Запись слишком длинная для публикации."
		return
	var r: Dictionary = await Cloud.set_doc("gamebook/" + _rec_id, {
		"title": _title(), "pgn": pgn, "by": Cloud.uid, "by_name": Profile.shown_name(),
		"at": int(Time.get_unix_time_from_system())})
	if is_inside_tree():
		_ed_status.text = "✔ Запись опубликована для школы." if r.ok else String(r.error)

func _on_play_from_here() -> void:
	var eng := ChessEngine.new()
	eng.setup_from_fen(String(_fens[_cur]))
	if eng.game_status() != "playing":
		_ed_status.text = "В этой позиции партия уже закончена."
		return
	Global.map_character_id = ""
	Global.map_assist = false
	Global.coop_team = false
	Global.friendly_game = {}
	Global.tournament_game = {}
	Global.road_mode = ""
	Global.school_mode = ""
	Global.attention_level = 0
	Profile.save_game_state({
		"fen": eng.to_fen(), "player_color": eng.side_to_move, "difficulty": Global.difficulty,
		"map_character_id": "", "map_assist": false, "coop_team": false, "move_history": [],
	})
	Global.open("res://scenes/Board.tscn", "res://scenes/Notebook.tscn")

# ------------------------------------------------------------------ разбор

func _on_analyze() -> void:
	if _busy or _sans.is_empty():
		return
	_busy = true
	_analysis = []
	var ai := ChessAI.new(ChessAI.ANALYSIS_LEVEL)
	for i in range(_sans.size()):
		if not is_inside_tree() or _board == null:
			_busy = false
			return
		_ed_status.text = "Разбор: ход %d из %d…" % [i + 1, _sans.size()]
		var eng := ChessEngine.new()
		eng.setup_from_fen(String(_fens[i]))
		var mv := BoardView.find_move(eng, String(_ucis[i]))
		var res := {"loss": 0.0, "best": ""}
		await Global.run_bg(func():
			res.loss = ai.move_loss(eng, mv, 3)
			if res.loss > ChessAI.LOSS_INACCURACY:
				var bm = ai.best_move_clean(eng, 3)
				if bm != null:
					res.best = GameRecord.san(eng, bm))
		_analysis.append({"loss": res.loss, "cat": ChessAI.quality_category(res.loss), "best": res.best})
		_render_moves()
	_busy = false
	_ed_status.text = _summary()
	_show_ply_info()

func _summary() -> String:
	var counts := {"w": [0, 0, 0, 0], "b": [0, 0, 0, 0]} # хорошие, неточности, ошибки, грубые
	var start_black: bool = String(_fens[0]).contains(" b ")
	for i in range(_analysis.size()):
		var side := "b" if ((i + (1 if start_black else 0)) % 2 == 1) else "w"
		var idx: int = {"good": 0, "inaccuracy": 1, "mistake": 2, "blunder": 3}.get(String(_analysis[i].cat), 0)
		counts[side][idx] += 1
	var out := "Разбор готов. "
	for side in ["w", "b"]:
		var c: Array = counts[side]
		var total: int = c[0] + c[1] + c[2] + c[3]
		if total > 0:
			out += "%s: точность %d%% (неточностей %d, ошибок %d, грубых %d).  " % ["Белые" if side == "w" else "Чёрные", int(100.0 * c[0] / total), c[1], c[2], c[3]]
	return out + "Нажмите на цветной ход — увидите, что было лучше."

# Для снимков экрана (инструмент Shots): открыть пример записи.
func _open_demo_for_shot() -> void:
	_open_record({"id": "", "pgn": "[White \"Иванов\"]
[Black \"Петров\"]
[Event \"Турнир школы\"]

1. e4 e5 2. Nf3 {развиваем коня} Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 1-0"})
	_goto(5)
