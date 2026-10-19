extends Control

# «Задачник учителя»: личные задачи со сроками, заметки и график недели (занятия, события школы и
# собственные задачи по дням). Видно и правится только владельцем (правила базы: tnotes).

var _root: VBoxContainer
var _tabs: HBoxContainer
var _status: Label
var _view: VBoxContainer
var _items: Array = []
var _tab := 0
var _week_start := ""

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
	Global.add_floating_back(self, func(): Global.go_back())
	var title := Label.new()
	title.text = "ЗАДАЧНИК УЧИТЕЛЯ"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.96, 0.76, 0.3))
	title.position = Vector2(24, 16)
	add_child(title)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	_root.add_child(_tabs)
	for i in range(3):
		var b := Button.new()
		b.text = ["Задачи", "Заметки", "График недели"][i]
		b.custom_minimum_size = Vector2(180, 46)
		b.pressed.connect(func():
			_tab = i
			_render())
		_tabs.add_child(b)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 13)
	_root.add_child(_status)
	_view = VBoxContainer.new()
	_view.add_theme_constant_override("separation", 8)
	_root.add_child(_view)
	_week_start = SchoolData.monday_of(SchoolData.today_iso())
	if not Roles.can(Profile.role, "open_admin"):
		_status.text = "Задачник доступен тренеру, модератору и администратору."
		return
	if not (Cloud.enabled and Cloud.signed_in):
		_status.text = "Задачник хранится в облаке: войдите онлайн."
		return
	_status.text = "Загружаю…"
	await SchoolData.load_all()
	var r: Dictionary = await Cloud.query_eq("tnotes", "owner", Cloud.uid, 400)
	if not is_inside_tree():
		return
	if not r.ok:
		_status.text = String(r.error)
		return
	_items = r.docs
	_status.text = ""
	_render()

func _clear() -> void:
	for ch in _view.get_children():
		ch.queue_free()

func _lbl(text: String, size := 14, color := Color(1, 1, 1, 0.92)) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	if color != Color(1, 1, 1, 0.92):
		l.add_theme_color_override("font_color", color)
	return l

func _render() -> void:
	_clear()
	for i in range(_tabs.get_child_count()):
		(_tabs.get_child(i) as Button).disabled = i == _tab
	match _tab:
		0: _render_tasks()
		1: _render_notes()
		_: _render_week()

func _save(d: Dictionary) -> Dictionary:
	var doc := d.duplicate()
	var id := String(doc.get("_id", ""))
	doc.erase("_id")
	return await Cloud.set_doc("tnotes/" + id, doc)

func _new_id() -> String:
	return "t%d%03d" % [int(Time.get_unix_time_from_system()), randi() % 1000]

# ------------------------------------------------------------------ задачи

func _tasks() -> Array:
	var out := []
	for it in _items:
		if String(it.get("kind", "")) == "task":
			out.append(it)
	return out

func _render_tasks() -> void:
	var box := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	box.add_child(v)
	_view.add_child(box)
	var text := LineEdit.new()
	text.placeholder_text = "Новая задача: что нужно сделать"
	text.max_length = 160
	text.custom_minimum_size = Vector2(0, 44)
	v.add_child(text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var due_chk := CheckBox.new()
	due_chk.text = "Срок:"
	row.add_child(due_chk)
	var due := FormFields.make_date(row, SchoolData.add_days(SchoolData.today_iso(), 3))
	var add := Button.new()
	add.text = "+ Добавить"
	add.custom_minimum_size = Vector2(150, 44)
	add.pressed.connect(func():
		if text.text.strip_edges() == "":
			return
		var d := {"_id": _new_id(), "owner": Cloud.uid, "kind": "task", "title": text.text.strip_edges(), "text": "",
			"done": false, "due": FormFields.read_date(due) if due_chk.button_pressed else "", "at": int(Time.get_unix_time_from_system())}
		var r: Dictionary = await _save(d)
		if r.ok:
			_items.append(d)
		_status.text = "" if r.ok else String(r.error)
		_render())
	row.add_child(add)
	var tasks := _tasks()
	tasks.sort_custom(func(a, b):
		if bool(a.get("done", false)) != bool(b.get("done", false)):
			return not bool(a.get("done", false))
		var da := String(a.get("due", "")) if String(a.get("due", "")) != "" else "9999"
		var db := String(b.get("due", "")) if String(b.get("due", "")) != "" else "9999"
		return da < db)
	if tasks.is_empty():
		_view.add_child(_lbl("Задач пока нет.", 13, Color(0.55, 0.6, 0.7)))
	var today := SchoolData.today_iso()
	for t in tasks:
		var panel := PanelContainer.new()
		var r2 := HBoxContainer.new()
		r2.add_theme_constant_override("separation", 8)
		panel.add_child(r2)
		var chk := CheckBox.new()
		chk.button_pressed = bool(t.get("done", false))
		chk.toggled.connect(func(on: bool):
			t["done"] = on
			await _save(t)
			_render())
		r2.add_child(chk)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r2.add_child(col)
		var done := bool(t.get("done", false))
		var l := _lbl(("✔ " if done else "") + String(t.get("title", "")), 16, Color(0.5, 0.55, 0.6) if done else Color(1, 1, 1, 0.92))
		col.add_child(l)
		var due_s := String(t.get("due", ""))
		if due_s != "":
			var late := due_s < today and not done
			col.add_child(_lbl(("⚠ просрочено · " if late else "до ") + SchoolData.fmt_date(due_s), 12, Color(1, 0.45, 0.45) if late else Color(0.55, 0.6, 0.7)))
		var del := Button.new()
		del.text = "✖"
		del.custom_minimum_size = Vector2(44, 40)
		del.pressed.connect(func():
			var r: Dictionary = await Cloud.del_doc("tnotes/" + String(t.get("_id", "")))
			if r.ok:
				_items.erase(t)
			_render())
		r2.add_child(del)
		_view.add_child(panel)

# ------------------------------------------------------------------ заметки

func _render_notes() -> void:
	var box := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	box.add_child(v)
	_view.add_child(box)
	var title := LineEdit.new()
	title.placeholder_text = "Заголовок заметки"
	title.max_length = 80
	title.custom_minimum_size = Vector2(0, 44)
	v.add_child(title)
	var body := TextEdit.new()
	body.placeholder_text = "Текст заметки (виден только вам)"
	body.custom_minimum_size = Vector2(0, 110)
	body.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	v.add_child(body)
	var add := Button.new()
	add.text = "+ Сохранить заметку"
	add.custom_minimum_size = Vector2(0, 46)
	add.pressed.connect(func():
		if title.text.strip_edges() == "" and body.text.strip_edges() == "":
			return
		var d := {"_id": _new_id(), "owner": Cloud.uid, "kind": "note", "title": title.text.strip_edges(), "text": body.text.strip_edges(),
			"done": false, "due": "", "at": int(Time.get_unix_time_from_system())}
		var r: Dictionary = await _save(d)
		if r.ok:
			_items.append(d)
		_status.text = "" if r.ok else String(r.error)
		_render())
	v.add_child(add)
	var notes := []
	for it in _items:
		if String(it.get("kind", "")) == "note":
			notes.append(it)
	notes.sort_custom(func(a, b): return int(a.get("at", 0)) > int(b.get("at", 0)))
	if notes.is_empty():
		_view.add_child(_lbl("Заметок пока нет.", 13, Color(0.55, 0.6, 0.7)))
	for n in notes:
		var panel := PanelContainer.new()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		panel.add_child(row)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		if String(n.get("title", "")) != "":
			col.add_child(_lbl(String(n.get("title", "")), 17))
		col.add_child(_lbl(String(n.get("text", "")), 14))
		var w := Time.get_datetime_dict_from_unix_time(int(n.get("at", 0)) + 3 * 3600)
		col.add_child(_lbl("%02d.%02d.%d" % [w.day, w.month, w.year], 12, Color(0.55, 0.6, 0.7)))
		var del := Button.new()
		del.text = "✖"
		del.custom_minimum_size = Vector2(44, 40)
		del.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		del.pressed.connect(func():
			var r: Dictionary = await Cloud.del_doc("tnotes/" + String(n.get("_id", "")))
			if r.ok:
				_items.erase(n)
			_render())
		row.add_child(del)
		_view.add_child(panel)

# ------------------------------------------------------------------ график недели

func _render_week() -> void:
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	_view.add_child(nav)
	var prev := Button.new()
	prev.text = "◀"
	prev.custom_minimum_size = Vector2(60, 44)
	prev.pressed.connect(func():
		_week_start = SchoolData.add_days(_week_start, -7)
		_render())
	nav.add_child(prev)
	var cur := _lbl("%s — %s" % [SchoolData.fmt_date(_week_start), SchoolData.fmt_date(SchoolData.add_days(_week_start, 6))], 16)
	cur.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cur.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav.add_child(cur)
	var nxt := Button.new()
	nxt.text = "▶"
	nxt.custom_minimum_size = Vector2(60, 44)
	nxt.pressed.connect(func():
		_week_start = SchoolData.add_days(_week_start, 7)
		_render())
	nav.add_child(nxt)
	var today := SchoolData.today_iso()
	for i in range(7):
		var iso := SchoolData.add_days(_week_start, i)
		var lines := []
		for ev in SchoolData.lessons():
			if int(ev.get("weekday", 0)) == i + 1:
				lines.append([String(ev.get("time", "")), "📘 %s %s%s" % [String(ev.get("time", "")), String(ev.get("title", "")), "  📍 " + String(ev.get("place", "")) if String(ev.get("place", "")) != "" else ""]])
		for ev in SchoolData.events_on(iso):
			lines.append([String(ev.get("time", "")), "%s %s %s%s" % [SchoolData.KIND_ICON.get(String(ev.get("kind", "")), "📌"), String(ev.get("time", "")), String(ev.get("title", "")), "  📍 " + String(ev.get("place", "")) if String(ev.get("place", "")) != "" else ""]])
		lines.sort_custom(func(a, b): return String(a[0]) < String(b[0]))
		var tasks := []
		for t in _tasks():
			if String(t.get("due", "")) == iso:
				tasks.append(t)
		var panel := PanelContainer.new()
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 3)
		panel.add_child(v)
		_view.add_child(panel)
		v.add_child(_lbl("%s · %s%s" % [SchoolData.WEEKDAYS[i], SchoolData.fmt_date(iso).get_slice(",", 0), "  ← сегодня" if iso == today else ""], 16, Color(0.96, 0.76, 0.3) if iso == today else Color(1, 1, 1, 0.92)))
		for l in lines:
			v.add_child(_lbl(String(l[1]).strip_edges(), 14))
		for t in tasks:
			v.add_child(_lbl("%s %s" % ["✔" if bool(t.get("done", false)) else "☐", String(t.get("title", ""))], 14, Color(0.4, 0.95, 0.5) if bool(t.get("done", false)) else Color(0.6, 0.85, 1.0)))
		if lines.is_empty() and tasks.is_empty():
			v.add_child(_lbl("— свободно —", 12, Color(0.45, 0.5, 0.6)))

# Для снимков экрана (инструмент Shots): график недели с примером данных.
func _open_demo_for_shot() -> void:
	_status.text = ""
	_items = [{"_id": "x1", "owner": "me", "kind": "task", "title": "Подготовить задания к субботе", "text": "", "done": false, "due": SchoolData.today_iso(), "at": 1},
		{"_id": "x2", "owner": "me", "kind": "task", "title": "Позвонить родителям", "text": "", "done": true, "due": SchoolData.add_days(SchoolData.today_iso(), 1), "at": 2}]
	SchoolData.events = [{"_id": "e1", "kind": "lesson", "title": "Занятие младшей группы", "weekday": SchoolData.weekday_of(SchoolData.today_iso()), "time": "17:00", "time_end": "18:30", "place": "Кабинет 12", "group": "", "text": "", "date": ""},
		{"_id": "e2", "kind": "tournament", "title": "Кубок школы", "date": SchoolData.today_iso(), "time": "11:00", "time_end": "15:00", "place": "Дворец творчества, Ярославль", "group": "", "text": "", "weekday": 0}]
	_tab = 2
	_render()
