extends VBoxContainer

# Часть экрана «Домашние задания» для учителя: список заданий со сдачей, конструктор нового задания
# (в том числе позиция с правильным ответом — расставляется ходами прямо на доске) и оценки.

var _screen: Control
var _status: Label
var _subs: Array = []
var _players: Array = []
var _reviews: Dictionary = {} # sid -> отзыв
var _view: VBoxContainer

func start(screen: Control) -> void:
	_screen = screen
	add_theme_constant_override("separation", 10)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 13)
	add_child(_status)
	_view = VBoxContainer.new()
	_view.add_theme_constant_override("separation", 10)
	add_child(_view)
	_load()

func _load() -> void:
	_status.text = "Загружаю…"
	await Homework.load_all()
	var s: Dictionary = await Cloud.query_top("submissions", "at", 1000)
	var p: Dictionary = await Cloud.query_top("players", "rating", 300)
	var rv: Dictionary = await Cloud.query_top("reviews", "at", 1000)
	if not is_inside_tree():
		return
	_subs = s.docs if s.ok else []
	_players = p.docs if p.ok else []
	_reviews = {}
	if rv.ok:
		for d in rv.docs:
			_reviews[String(d.get("_id", ""))] = d
	_status.text = ""
	_show_list()

func _clear() -> void:
	for ch in _view.get_children():
		ch.queue_free()

func _lbl(text: String, size := 14, color := Color(1, 1, 1, 0.92), wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	if color != Color(1, 1, 1, 0.92):
		l.add_theme_color_override("font_color", color)
	return l

# ------------------------------------------------------------------ список заданий

func _audience(a: Dictionary) -> Array:
	var g := String(a.get("group", "")).strip_edges().to_lower()
	var out := []
	for p in _players:
		if g == "" or String(p.get("group", "")).strip_edges().to_lower() == g:
			out.append(p)
	return out

func _subs_for(aid: String) -> Array:
	var out := []
	for d in _subs:
		if String(d.get("aid", "")) == aid:
			out.append(d)
	return out

func _show_list() -> void:
	_clear()
	var add := Button.new()
	add.text = "＋ Новое задание"
	add.custom_minimum_size = Vector2(0, 50)
	add.pressed.connect(_show_builder)
	_view.add_child(add)
	if Homework.assignments.is_empty():
		_view.add_child(_lbl("Заданий пока нет. Создайте первое — оно появится у учеников в колокольчике и в «Домашних заданиях»."))
	for a in Homework.assignments:
		_view.add_child(_row(a))

func _row(a: Dictionary) -> Control:
	var aid := String(a.get("_id", ""))
	var panel := PanelContainer.new()
	var v := VBoxContainer.new()
	panel.add_child(v)
	var done := _subs_for(aid).size()
	var total := _audience(a).size()
	var active := bool(a.get("active", true))
	v.add_child(_lbl("%s%s" % ["" if active else "⏸ ", String(a.get("title", ""))], 18))
	var grp := String(a.get("group", ""))
	v.add_child(_lbl("%s · %s · для: %s · сдали: %d из %d" % [String(Homework.KINDS.get(String(a.get("kind", "")), "")), Homework.deadline_text(a), grp if grp != "" else "всех", done, total], 12, Color(0.55, 0.6, 0.7)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var res := Button.new()
	res.text = "Результаты"
	res.custom_minimum_size = Vector2(130, 42)
	res.pressed.connect(func(): _show_results(a))
	row.add_child(res)
	var tg := Button.new()
	tg.text = "Закрыть" if active else "Открыть снова"
	tg.custom_minimum_size = Vector2(150, 42)
	tg.pressed.connect(func():
		a["active"] = not active
		var r: Dictionary = await Cloud.set_doc("assignments/" + aid, _doc_of(a))
		_status.text = "" if r.ok else String(r.error)
		_show_list())
	row.add_child(tg)
	var del := Button.new()
	del.text = "Удалить"
	del.custom_minimum_size = Vector2(110, 42)
	del.pressed.connect(func():
		var r: Dictionary = await Cloud.del_doc("assignments/" + aid)
		if r.ok:
			Homework.assignments.erase(a)
		_status.text = "" if r.ok else String(r.error)
		_show_list())
	row.add_child(del)
	return panel

func _doc_of(a: Dictionary) -> Dictionary:
	var d := a.duplicate()
	d.erase("_id")
	return d

# ------------------------------------------------------------------ результаты

func _show_results(a: Dictionary) -> void:
	_clear()
	var aid := String(a.get("_id", ""))
	var back := Button.new()
	back.text = "← К списку заданий"
	back.custom_minimum_size = Vector2(0, 44)
	back.pressed.connect(_show_list)
	_view.add_child(back)
	_view.add_child(_lbl(String(a.get("title", "")), 22))
	var by_uid := {}
	for d in _subs_for(aid):
		by_uid[String(d.get("uid", ""))] = d
	for p in _audience(a):
		var uid := String(p.get("_id", ""))
		var name := String(p.get("name", ""))
		if name == "":
			name = String(p.get("nick", "?"))
		var panel := PanelContainer.new()
		var v := VBoxContainer.new()
		panel.add_child(v)
		_view.add_child(panel)
		var sub: Dictionary = by_uid.get(uid, {})
		if sub.is_empty():
			v.add_child(_lbl("⬜ %s — не сдано" % name, 15, Color(0.7, 0.7, 0.75)))
			continue
		var when := Time.get_datetime_dict_from_unix_time(int(sub.get("at", 0)) + 3 * 3600)
		v.add_child(_lbl("✅ %s — %s  (%02d.%02d %02d:%02d)" % [name, String(sub.get("detail", "")), when.day, when.month, when.hour, when.minute], 15, Color(0.4, 0.95, 0.5)))
		if String(sub.get("comment", "")) != "":
			v.add_child(_lbl("«%s»" % String(sub.comment), 13))
		var sid := Homework.sub_id(aid, uid)
		var rv: Dictionary = _reviews.get(sid, {})
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		v.add_child(row)
		var grade := OptionButton.new()
		grade.add_item("Без оценки")
		for g in range(1, 6):
			grade.add_item("Оценка %d" % g)
		grade.selected = clampi(int(rv.get("grade", 0)), 0, 5)
		grade.custom_minimum_size = Vector2(150, 42)
		row.add_child(grade)
		var note := LineEdit.new()
		note.placeholder_text = "Комментарий ученику"
		note.text = String(rv.get("note", ""))
		note.max_length = 200
		note.custom_minimum_size = Vector2(0, 42)
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(note)
		var save := Button.new()
		save.text = "Сохранить"
		save.custom_minimum_size = Vector2(120, 42)
		save.pressed.connect(func():
			save.disabled = true
			var doc := {"aid": aid, "uid": uid, "grade": grade.selected, "note": note.text, "by": Cloud.uid, "at": int(Time.get_unix_time_from_system())}
			var r: Dictionary = await Cloud.set_doc("reviews/" + sid, doc)
			if r.ok:
				doc["_id"] = sid
				_reviews[sid] = doc
			_status.text = ("✔ Сохранено для: %s." % name) if r.ok else String(r.error)
			save.disabled = false)
		row.add_child(save)

# ------------------------------------------------------------------ конструктор

var _b_title: LineEdit
var _b_text: TextEdit
var _b_kind: OptionButton
var _b_group: LineEdit
var _b_days: SpinBox
var _b_metric: OptionButton
var _b_target: SpinBox
var _b_metric_box: VBoxContainer
var _b_pos_box: VBoxContainer
var _b_board: BoardView
var _b_phase := 1
var _b_fen := ""
var _b_solution: Array = []
var _b_hist: Array = []
var _b_cur := ""
var _b_phase_lbl: Label
var _b_sol_lbl: Label
var _b_msg: Label

func _show_builder() -> void:
	_clear()
	var back := Button.new()
	back.text = "← К списку заданий"
	back.custom_minimum_size = Vector2(0, 44)
	back.pressed.connect(_show_list)
	_view.add_child(back)
	_view.add_child(_lbl("НОВОЕ ЗАДАНИЕ", 20, Color(0.96, 0.76, 0.3)))
	_b_title = LineEdit.new()
	_b_title.placeholder_text = "Название (например: «Мат в два хода»)"
	_b_title.max_length = 60
	_b_title.custom_minimum_size = Vector2(0, 44)
	_view.add_child(_b_title)
	_b_text = TextEdit.new()
	_b_text.placeholder_text = "Что нужно сделать — своими словами"
	_b_text.custom_minimum_size = Vector2(0, 90)
	_b_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_view.add_child(_b_text)
	_b_kind = OptionButton.new()
	for k in Homework.KINDS:
		_b_kind.add_item(String(Homework.KINDS[k]))
	_b_kind.custom_minimum_size = Vector2(0, 44)
	_b_kind.item_selected.connect(func(_i): _refresh_kind())
	_view.add_child(_b_kind)
	# счётчики
	_b_metric_box = VBoxContainer.new()
	_view.add_child(_b_metric_box)
	_b_metric = OptionButton.new()
	for m in Homework.METRICS:
		_b_metric.add_item(String(Homework.METRICS[m]))
	_b_metric.custom_minimum_size = Vector2(0, 44)
	_b_metric_box.add_child(_b_metric)
	var trow := HBoxContainer.new()
	trow.add_child(_lbl("Сколько нужно:  ", 14, Color(1, 1, 1, 0.92), false))
	_b_target = SpinBox.new()
	_b_target.min_value = 1
	_b_target.max_value = 200
	_b_target.value = 5
	trow.add_child(_b_target)
	_b_metric_box.add_child(trow)
	# позиция
	_b_pos_box = VBoxContainer.new()
	_b_pos_box.add_theme_constant_override("separation", 8)
	_view.add_child(_b_pos_box)
	_build_position_editor()
	# кому и когда
	_b_group = LineEdit.new()
	_b_group.placeholder_text = "Группа (как у учеников в анкете). Пусто — всем"
	_b_group.custom_minimum_size = Vector2(0, 44)
	_view.add_child(_b_group)
	var drow := HBoxContainer.new()
	drow.add_child(_lbl("Срок, дней (0 — без срока):  ", 14, Color(1, 1, 1, 0.92), false))
	_b_days = SpinBox.new()
	_b_days.min_value = 0
	_b_days.max_value = 60
	_b_days.value = 7
	drow.add_child(_b_days)
	_view.add_child(drow)
	var send := Button.new()
	send.text = "📨 Отправить ученикам"
	send.custom_minimum_size = Vector2(0, 54)
	send.pressed.connect(_on_send)
	_view.add_child(send)
	_b_msg = _lbl("", 13)
	_view.add_child(_b_msg)
	_refresh_kind()

func _refresh_kind() -> void:
	var kind := String(Homework.KINDS.keys()[_b_kind.selected])
	_b_metric_box.visible = kind == "metric"
	_b_pos_box.visible = kind == "position"

func _build_position_editor() -> void:
	_b_phase = 1
	_b_fen = ""
	_b_solution = []
	_b_hist = []
	_b_phase_lbl = _lbl("1) Расставьте позицию: делайте ходы за обе стороны, пока на доске не получится нужное.", 14, Color(0.96, 0.76, 0.3))
	_b_pos_box.add_child(_b_phase_lbl)
	_b_board = BoardView.new()
	_b_board.custom_minimum_size = Vector2(480, 480)
	_b_board.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_b_pos_box.add_child(_b_board)
	_b_board.interactive = true
	_b_board.sandbox = true
	_b_board.move_made.connect(_on_builder_move)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_b_pos_box.add_child(row)
	var undo := Button.new()
	undo.text = "↩ Отменить ход"
	undo.custom_minimum_size = Vector2(0, 42)
	undo.pressed.connect(func():
		if _b_phase == 1 and not _b_hist.is_empty():
			_b_set(String(_b_hist.pop_back())))
	row.add_child(undo)
	var reset := Button.new()
	reset.text = "⟲ С начала"
	reset.custom_minimum_size = Vector2(0, 42)
	reset.pressed.connect(func():
		_b_hist = []
		_b_phase = 1
		_b_solution = []
		_b_phase_lbl.text = "1) Расставьте позицию: делайте ходы за обе стороны."
		_b_sol_lbl.text = ""
		_b_board.sandbox = true
		_b_set("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"))
	row.add_child(reset)
	var ready := Button.new()
	ready.text = "Позиция готова →"
	ready.custom_minimum_size = Vector2(0, 42)
	ready.pressed.connect(func():
		_b_fen = _b_board.engine.to_fen()
		_b_phase = 2
		_b_board.sandbox = false
		_b_board.turn_color = _b_board.engine.side_to_move
		_b_phase_lbl.text = "2) Сделайте правильный ход — он запишется как ответ. Можно добавить несколько верных вариантов."
		_b_sol_lbl.text = "Верные ходы: пока нет")
	row.add_child(ready)
	var fen_row := HBoxContainer.new()
	fen_row.add_theme_constant_override("separation", 8)
	_b_pos_box.add_child(fen_row)
	var fen_edit := LineEdit.new()
	fen_edit.placeholder_text = "или вставьте позицию в записи FEN"
	fen_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fen_edit.custom_minimum_size = Vector2(0, 42)
	fen_row.add_child(fen_edit)
	var load_b := Button.new()
	load_b.text = "Загрузить"
	load_b.custom_minimum_size = Vector2(110, 42)
	load_b.pressed.connect(func():
		if fen_edit.text.strip_edges().split(" ").size() >= 2:
			_b_hist = []
			_b_set(fen_edit.text.strip_edges()))
	fen_row.add_child(load_b)
	_b_sol_lbl = _lbl("", 13, Color(0.4, 0.95, 0.5))
	_b_pos_box.add_child(_b_sol_lbl)
	_b_set("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
	_b_board.perspective = "w"

func _b_set(fen: String) -> void:
	_b_board.set_fen(fen)
	_b_cur = _b_board.engine.to_fen()

func _on_builder_move(_m: Dictionary, uci: String) -> void:
	if _b_phase == 1:
		_b_hist.append(_b_cur)
		_b_cur = _b_board.engine.to_fen()
		return
	# этап 2: записываем ответ и возвращаем позицию
	if not (uci in _b_solution):
		_b_solution.append(uci)
	_b_sol_lbl.text = "Верные ходы: %s" % ", ".join(_b_solution)
	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(_b_board):
		_b_board.set_fen(_b_fen)
		_b_board.turn_color = _b_board.engine.side_to_move

func _on_send() -> void:
	var kind := String(Homework.KINDS.keys()[_b_kind.selected])
	if _b_title.text.strip_edges() == "":
		_b_msg.text = "Впишите название задания."
		return
	var doc := {
		"title": _b_title.text.strip_edges(), "text": _b_text.text.strip_edges(), "kind": kind,
		"metric": "", "target": 1, "fen": "", "solution": [],
		"deadline": 0, "group": _b_group.text.strip_edges(), "active": true,
		"by": Cloud.uid, "by_name": Profile.shown_name(), "created": int(Time.get_unix_time_from_system()),
	}
	if int(_b_days.value) > 0:
		doc["deadline"] = int(Time.get_unix_time_from_system()) + int(_b_days.value) * 86400
	if kind == "metric":
		doc["metric"] = String(Homework.METRICS.keys()[_b_metric.selected])
		doc["target"] = int(_b_target.value)
	elif kind == "position":
		if _b_fen == "" or _b_solution.is_empty():
			_b_msg.text = "Для позиции нужно: «Позиция готова» и хотя бы один верный ход."
			return
		doc["fen"] = _b_fen
		doc["solution"] = _b_solution
	var id := Homework.new_id()
	_b_msg.text = "Отправляю…"
	var r: Dictionary = await Cloud.set_doc("assignments/" + id, doc)
	if not is_inside_tree():
		return
	if not r.ok:
		_b_msg.text = String(r.error)
		return
	doc["_id"] = id
	Homework.assignments.push_front(doc)
	_status.text = "✔ Задание отправлено ученикам."
	_show_list()
