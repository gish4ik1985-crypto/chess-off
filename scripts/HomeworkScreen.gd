extends Control

# Экран «Домашние задания»: ученик видит задания учителя, выполняет их и отправляет результат;
# учитель (тренер/модератор/администратор) во вкладке «Для учеников» создаёт задания и смотрит сдачу.
# Всё строится кодом.

const TeacherScript := preload("res://scripts/HomeworkTeacher.gd")

var _root: VBoxContainer
var _tabs: HBoxContainer
var _body: VBoxContainer
var _status: Label
var _reviews: Dictionary = {} # aid -> отзыв учителя мне
var _teacher: Control
var _current: Dictionary = {}
var _board: BoardView
var _tries := 0

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
	_root.custom_minimum_size = Vector2(760, 0)
	_root.add_theme_constant_override("separation", 12)
	center.add_child(_root)
	Global.add_floating_back(self, _on_back)
	var title := Label.new()
	title.text = "ДОМАШНИЕ ЗАДАНИЯ"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.96, 0.76, 0.3))
	title.position = Vector2(24, 16)
	add_child(title)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	_root.add_child(_tabs)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 13)
	_root.add_child(_status)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	_root.add_child(_body)
	if Roles.can(Profile.role, "open_admin"):
		var mine := _tab_button("Мои задания")
		mine.pressed.connect(_show_list)
		var t := _tab_button("Для учеников")
		t.pressed.connect(_show_teacher)
	if not (Cloud.enabled and Cloud.signed_in):
		_status.text = "Задания приходят из облака: войдите онлайн (экран выбора игрока → «Онлайн-вход»)."
		return
	_reload()

func _tab_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(170, 44)
	_tabs.add_child(b)
	return b

func _on_back() -> void:
	if not _current.is_empty():
		_show_list()
		return
	Global.go_back()

func _reload() -> void:
	_status.text = "Загружаю задания…"
	var ok := await Homework.load_all()
	if not is_inside_tree():
		return
	if not ok:
		_status.text = "Не удалось загрузить задания. Проверьте интернет."
		return
	var sent := await Homework.auto_submit_done()
	var rv: Dictionary = await Cloud.query_top("reviews", "at", 300)
	_reviews = {}
	if rv.ok:
		for d in rv.docs:
			if String(d.get("uid", "")) == Cloud.uid:
				_reviews[String(d.get("aid", ""))] = d
	if not is_inside_tree():
		return
	_status.text = "Отправлено результатов: %d." % sent if sent > 0 else ""
	_show_list()

func _clear_body() -> void:
	for ch in _body.get_children():
		ch.queue_free()
	if _teacher != null and is_instance_valid(_teacher):
		_teacher.queue_free()
		_teacher = null
	_board = null

# ------------------------------------------------------------------ список

func _show_list() -> void:
	_current = {}
	_clear_body()
	var mine := []
	for a in Homework.assignments:
		if Homework.for_me(a):
			mine.append(a)
	if mine.is_empty():
		var l := Label.new()
		l.text = "Пока заданий нет. Когда учитель отправит новое, оно появится здесь и в колокольчике на главном экране."
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(l)
		return
	for a in mine:
		_body.add_child(_card(a))

func _state_of(a: Dictionary) -> Dictionary:
	var aid := String(a.get("_id", ""))
	if Homework.my_done.has(aid):
		var rv: Dictionary = _reviews.get(aid, {})
		var extra := ""
		if not rv.is_empty():
			extra = "  · оценка учителя: %d" % int(rv.get("grade", 0)) if int(rv.get("grade", 0)) > 0 else "  · есть комментарий учителя"
		return {"text": "✅ Сдано" + extra, "color": Color(0.4, 0.95, 0.5)}
	if Homework.is_overdue(a):
		return {"text": "🔴 Срок прошёл", "color": Color(1, 0.45, 0.45)}
	if String(a.get("kind", "")) == "metric" and Homework.started(a):
		return {"text": "⏳ В работе: %d из %d" % [Homework.progress(a), int(a.get("target", 1))], "color": Color(0.96, 0.76, 0.3)}
	return {"text": "🆕 Новое", "color": Color(0.35, 0.75, 1.0)}

func _card(a: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var t := Label.new()
	t.text = String(a.get("title", "Задание"))
	t.add_theme_font_size_override("font_size", 18)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(t)
	var st := _state_of(a)
	var s := Label.new()
	s.text = "%s  ·  %s  ·  %s" % [st.text, String(Homework.KINDS.get(String(a.get("kind", "")), "")), Homework.deadline_text(a)]
	s.add_theme_font_size_override("font_size", 12)
	s.add_theme_color_override("font_color", st.color)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(s)
	var b := Button.new()
	b.text = "Открыть"
	b.custom_minimum_size = Vector2(130, 46)
	b.pressed.connect(func(): _open(a))
	row.add_child(b)
	return panel

# ------------------------------------------------------------------ задание

func _open(a: Dictionary) -> void:
	_current = a
	_tries = 0
	_clear_body()
	var aid := String(a.get("_id", ""))
	var t := Label.new()
	t.text = String(a.get("title", ""))
	t.add_theme_font_size_override("font_size", 22)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(t)
	var meta := Label.new()
	meta.text = "От: %s  ·  %s" % [String(a.get("by_name", "учитель")), Homework.deadline_text(a)]
	meta.add_theme_font_size_override("font_size", 12)
	meta.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	_body.add_child(meta)
	var txt := Label.new()
	txt.text = String(a.get("text", ""))
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(txt)
	var done: Dictionary = Homework.my_done.get(aid, {})
	if not done.is_empty():
		var d := Label.new()
		d.text = "✅ Вы сдали это задание. %s" % String(done.get("detail", ""))
		d.add_theme_color_override("font_color", Color(0.4, 0.95, 0.5))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(d)
		var rv: Dictionary = _reviews.get(aid, {})
		if not rv.is_empty():
			var r := Label.new()
			r.text = "Учитель: %s%s" % [("оценка %d. " % int(rv.grade)) if int(rv.get("grade", 0)) > 0 else "", String(rv.get("note", ""))]
			r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			r.add_theme_color_override("font_color", Color(0.96, 0.76, 0.3))
			_body.add_child(r)
		return
	match String(a.get("kind", "")):
		"metric": _build_metric(a)
		"position": _build_position(a)
		_: _build_text(a)

func _build_metric(a: Dictionary) -> void:
	var target := int(a.get("target", 1))
	var metric := String(a.get("metric", ""))
	var info := Label.new()
	info.text = "Нужно: %s — %d." % [String(Homework.METRICS.get(metric, metric)), target]
	_body.add_child(info)
	if not Homework.started(a):
		var b := Button.new()
		b.text = "▶ Начать"
		b.custom_minimum_size = Vector2(0, 50)
		b.pressed.connect(func():
			Homework.begin(a)
			_open(a))
		_body.add_child(b)
		return
	var bar := ProgressBar.new()
	bar.max_value = target
	bar.value = mini(Homework.progress(a), target)
	bar.custom_minimum_size = Vector2(0, 22)
	bar.show_percentage = false
	_body.add_child(bar)
	var p := Label.new()
	p.text = "Сделано: %d из %d. Когда цель будет достигнута, результат уйдёт учителю сам." % [Homework.progress(a), target]
	p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(p)
	var go := Button.new()
	go.text = "Заниматься →"
	go.custom_minimum_size = Vector2(0, 50)
	go.pressed.connect(func():
		Global.open(Homework.scene_for(metric), "res://scenes/Homework.tscn"))
	_body.add_child(go)
	var chk := Button.new()
	chk.text = "🔄 Проверить и отправить"
	chk.custom_minimum_size = Vector2(0, 46)
	chk.pressed.connect(func():
		var n := await Homework.auto_submit_done()
		if not is_inside_tree():
			return
		_status.text = "Результат отправлен учителю." if n > 0 else "Цель ещё не достигнута."
		_open(a))
	_body.add_child(chk)

func _build_position(a: Dictionary) -> void:
	var fen := String(a.get("fen", ""))
	_board = BoardView.new()
	_board.custom_minimum_size = Vector2(520, 520)
	_board.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_body.add_child(_board)
	_board.set_fen(fen)
	_board.perspective = _board.engine.side_to_move
	_board.interactive = true
	_board.turn_color = _board.engine.side_to_move
	var side := Label.new()
	side.text = "Ход %s. Нажмите фигуру, затем клетку." % ("белых" if _board.engine.side_to_move == "w" else "чёрных")
	_body.add_child(side)
	var fb := Label.new()
	fb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(fb)
	var sol: Array = a.get("solution", [])
	_board.move_made.connect(func(_m, uci: String):
		_tries += 1
		if uci in sol or (uci.length() == 5 and uci.substr(0, 4) in sol):
			fb.text = "✅ Верно! Отправляю результат…"
			_board.interactive = false
			var r: Dictionary = await Homework.submit(a, 1, "Решено с попытки № %d" % _tries)
			if not is_inside_tree():
				return
			fb.text = "✅ Верно! Результат отправлен учителю." if r.ok else "Верно, но отправить не удалось: %s" % String(r.error)
		else:
			fb.text = "Не то. Попробуйте ещё раз (попыток: %d)." % _tries
			await get_tree().create_timer(0.6).timeout
			if is_instance_valid(_board):
				_board.set_fen(fen))

func _build_text(a: Dictionary) -> void:
	var c := TextEdit.new()
	c.placeholder_text = "Напишите, что сделали или что получилось (до 300 символов)"
	c.custom_minimum_size = Vector2(0, 120)
	c.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_body.add_child(c)
	var b := Button.new()
	b.text = "📨 Отправить учителю"
	b.custom_minimum_size = Vector2(0, 50)
	b.pressed.connect(func():
		b.disabled = true
		var r: Dictionary = await Homework.submit(a, 1, "Сдано", c.text)
		if not is_inside_tree():
			return
		if r.ok:
			_open(a)
		else:
			_status.text = String(r.error)
			b.disabled = false)
	_body.add_child(b)

# ------------------------------------------------------------------ учитель

func _show_teacher() -> void:
	_current = {}
	_clear_body()
	_teacher = TeacherScript.new()
	_root.add_child(_teacher)
	_teacher.call("start", self)

# Для снимков экрана (инструмент Shots): сразу открыть конструктор учителя.
func _open_builder_for_shot() -> void:
	Profile.role = "admin"
	_show_teacher()
	await get_tree().create_timer(0.3).timeout
	if _teacher != null:
		_teacher.call("_show_builder")
