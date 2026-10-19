extends Control

# «Расписание и планы»: занятия на неделю, события и турниры (в школе и в других местах), годовой план.
# Все видят; учитель (тренер/модератор/администратор) добавляет и удаляет пункты. Строится кодом.

var _root: VBoxContainer
var _tabs: HBoxContainer
var _status: Label
var _view: VBoxContainer
var _tab := 0
var _week_start := ""
var _plan_year := 0

func _ready() -> void:
	var bg := ColorRect.new()
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
	_root.custom_minimum_size = Vector2(780, 0)
	_root.add_theme_constant_override("separation", 12)
	center.add_child(_root)
	Global.add_floating_back(self, func(): Global.go_back())
	var title := Label.new()
	title.text = "РАСПИСАНИЕ И ПЛАНЫ"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.96, 0.76, 0.3))
	title.position = Vector2(24, 16)
	add_child(title)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	_root.add_child(_tabs)
	for i in range(3):
		var b := Button.new()
		b.text = ["Неделя", "События и турниры", "Годовой план"][i]
		b.custom_minimum_size = Vector2(190, 46)
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
	_plan_year = SchoolData.school_year_of(SchoolData.today_iso())
	if not (Cloud.enabled and Cloud.signed_in):
		_status.text = "Расписание приходит из облака: войдите онлайн."
		return
	_status.text = "Загружаю…"
	var ok := await SchoolData.load_all()
	if not is_inside_tree():
		return
	_status.text = "" if ok else "Не удалось загрузить расписание. Проверьте интернет."
	_render()

func _teacher() -> bool:
	return Roles.can(Profile.role, "open_admin")

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

func _btn(text: String, w := 0.0, h := 44.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	return b

func _render() -> void:
	_clear()
	for i in range(_tabs.get_child_count()):
		(_tabs.get_child(i) as Button).disabled = i == _tab
	if _teacher():
		var add := _btn("+ Добавить в расписание / план", 0, 46)
		add.pressed.connect(_show_form)
		_view.add_child(add)
	match _tab:
		0: _render_week()
		1: _render_events()
		_: _render_plan()

# ------------------------------------------------------------------ неделя

func _render_week() -> void:
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	_view.add_child(nav)
	var prev := _btn("◀", 60)
	prev.pressed.connect(func():
		_week_start = SchoolData.add_days(_week_start, -7)
		_render())
	nav.add_child(prev)
	var cur := _lbl("%s — %s" % [SchoolData.fmt_date(_week_start), SchoolData.fmt_date(SchoolData.add_days(_week_start, 6))], 16)
	cur.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cur.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav.add_child(cur)
	var nxt := _btn("▶", 60)
	nxt.pressed.connect(func():
		_week_start = SchoolData.add_days(_week_start, 7)
		_render())
	nav.add_child(nxt)
	var today := SchoolData.today_iso()
	for i in range(7):
		var iso := SchoolData.add_days(_week_start, i)
		var panel := PanelContainer.new()
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		panel.add_child(v)
		_view.add_child(panel)
		v.add_child(_lbl("%s · %s%s" % [SchoolData.WEEKDAYS[i], SchoolData.fmt_date(iso).get_slice(",", 0), "  ← сегодня" if iso == today else ""], 16, Color(0.96, 0.76, 0.3) if iso == today else Color(1, 1, 1, 0.92)))
		var any := false
		for ev in SchoolData.lessons():
			if int(ev.get("weekday", 0)) == i + 1 and (_teacher() or SchoolData.group_ok(String(ev.get("group", "")))):
				v.add_child(_item_row(ev))
				any = true
		for ev in SchoolData.events_on(iso):
			if _teacher() or SchoolData.group_ok(String(ev.get("group", ""))):
				v.add_child(_item_row(ev))
				any = true
		if not any:
			v.add_child(_lbl("— ничего —", 12, Color(0.45, 0.5, 0.6)))

func _time_text(ev: Dictionary) -> String:
	var t := String(ev.get("time", ""))
	var e := String(ev.get("time_end", ""))
	if t == "":
		return ""
	return t + ("–" + e if e != "" else "")

func _item_row(ev: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var kind := String(ev.get("kind", "event"))
	var head := "%s  %s  %s" % [SchoolData.KIND_ICON.get(kind, "•"), _time_text(ev), String(ev.get("title", ""))]
	col.add_child(_lbl(head.strip_edges(), 15))
	var sub := ""
	if String(ev.get("place", "")) != "":
		sub += "📍 " + String(ev.get("place", ""))
	if String(ev.get("group", "")) != "":
		sub += ("   " if sub != "" else "") + "группа: " + String(ev.get("group", ""))
	if sub != "":
		col.add_child(_lbl(sub, 12, Color(0.55, 0.6, 0.7)))
	if String(ev.get("text", "")) != "":
		col.add_child(_lbl(String(ev.get("text", "")), 13, Color(0.75, 0.78, 0.85)))
	if _teacher():
		var del := _btn("✖", 44, 40)
		del.tooltip_text = "Удалить пункт"
		del.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		del.pressed.connect(func():
			var r: Dictionary = await Cloud.del_doc("events/" + String(ev.get("_id", "")))
			if r.ok:
				SchoolData.events.erase(ev)
			_status.text = "" if r.ok else String(r.error)
			_render())
		row.add_child(del)
	return row

# ------------------------------------------------------------------ события

func _render_events() -> void:
	var today := SchoolData.today_iso()
	var list := []
	var past := []
	for ev in SchoolData.events:
		if not String(ev.get("kind", "")) in ["event", "tournament"]:
			continue
		if not (_teacher() or SchoolData.group_ok(String(ev.get("group", "")))):
			continue
		if String(ev.get("date", "")) >= today:
			list.append(ev)
		else:
			past.append(ev)
	list.sort_custom(func(a, b): return String(a.get("date", "")) + String(a.get("time", "")) < String(b.get("date", "")) + String(b.get("time", "")))
	past.sort_custom(func(a, b): return String(a.get("date", "")) > String(b.get("date", "")))
	_view.add_child(_lbl("Ближайшие", 15, Color(0.96, 0.76, 0.3)))
	if list.is_empty():
		_view.add_child(_lbl("Пока ничего не запланировано.", 13, Color(0.55, 0.6, 0.7)))
	for ev in list:
		_view.add_child(_event_card(ev))
	if not past.is_empty():
		_view.add_child(_lbl("Прошедшие", 15, Color(0.55, 0.6, 0.7)))
		for ev in past.slice(0, 10):
			_view.add_child(_event_card(ev))

func _event_card(ev: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var v := VBoxContainer.new()
	panel.add_child(v)
	v.add_child(_lbl(SchoolData.fmt_date(String(ev.get("date", ""))), 13, Color(0.96, 0.76, 0.3)))
	v.add_child(_item_row(ev))
	return panel

# ------------------------------------------------------------------ годовой план

func _render_plan() -> void:
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	_view.add_child(nav)
	var prev := _btn("◀", 60)
	prev.pressed.connect(func():
		_plan_year -= 1
		_render())
	nav.add_child(prev)
	var cur := _lbl("Учебный год %d/%d" % [_plan_year, (_plan_year + 1) % 100], 18)
	cur.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cur.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav.add_child(cur)
	var nxt := _btn("▶", 60)
	nxt.pressed.connect(func():
		_plan_year += 1
		_render())
	nav.add_child(nxt)
	for k in range(12):
		var m := (8 + k) % 12 + 1 # сентябрь … август
		var y := _plan_year if m >= 9 else _plan_year + 1
		var items := []
		var prefix := "%04d-%02d" % [y, m]
		for ev in SchoolData.events:
			var d := String(ev.get("date", ""))
			if d.begins_with(prefix) and (String(ev.get("kind", "")) == "plan" or (String(ev.get("kind", "")) in ["event", "tournament"])):
				if _teacher() or SchoolData.group_ok(String(ev.get("group", ""))):
					items.append(ev)
		items.sort_custom(func(a, b): return String(a.get("date", "")) < String(b.get("date", "")))
		var panel := PanelContainer.new()
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		panel.add_child(v)
		_view.add_child(panel)
		v.add_child(_lbl("%s %d" % [SchoolData.MONTH_NOM[m - 1], y], 16, Color(0.96, 0.76, 0.3)))
		if items.is_empty():
			v.add_child(_lbl("— ничего не запланировано —", 12, Color(0.45, 0.5, 0.6)))
		for ev in items:
			var line := _item_row(ev)
			v.add_child(line)
			# дата перед названием пункта плана
			var head := (line.get_child(0) as VBoxContainer).get_child(0) as Label
			head.text = "%s · %s" % [SchoolData.fmt_date(String(ev.get("date", ""))).get_slice(",", 0), head.text]

# ------------------------------------------------------------------ форма учителя

func _show_form() -> void:
	_clear()
	var back := _btn("← Назад к расписанию", 0, 44)
	back.pressed.connect(_render)
	_view.add_child(back)
	_view.add_child(_lbl("НОВЫЙ ПУНКТ", 20, Color(0.96, 0.76, 0.3)))
	var keys := ["lesson", "event", "tournament", "plan"]
	var kind := OptionButton.new()
	for k in keys:
		kind.add_item(String(SchoolData.KINDS[k]))
	kind.custom_minimum_size = Vector2(0, 44)
	_view.add_child(kind)
	var title := LineEdit.new()
	title.placeholder_text = "Название (например: «Занятие младшей группы»)"
	title.max_length = 80
	title.custom_minimum_size = Vector2(0, 44)
	_view.add_child(title)
	var wd_row := HBoxContainer.new()
	wd_row.add_child(_lbl("День недели:  ", 14, Color(1, 1, 1, 0.92), false))
	var weekday := OptionButton.new()
	for d in SchoolData.WEEKDAYS:
		weekday.add_item(d)
	weekday.selected = SchoolData.weekday_of(SchoolData.today_iso()) - 1
	wd_row.add_child(weekday)
	_view.add_child(wd_row)
	var date_row := HBoxContainer.new()
	date_row.add_child(_lbl("Дата:  ", 14, Color(1, 1, 1, 0.92), false))
	var date_f := FormFields.make_date(date_row)
	_view.add_child(date_row)
	var time_row := HBoxContainer.new()
	time_row.add_child(_lbl("Начало:  ", 14, Color(1, 1, 1, 0.92), false))
	var t1 := FormFields.make_time(time_row, 18, 0)
	time_row.add_child(_lbl("    Конец:  ", 14, Color(1, 1, 1, 0.92), false))
	var t2 := FormFields.make_time(time_row, 19, 30)
	_view.add_child(time_row)
	var place := LineEdit.new()
	place.placeholder_text = "Место: кабинет, адрес, «онлайн»…"
	place.max_length = 100
	place.custom_minimum_size = Vector2(0, 44)
	_view.add_child(place)
	var group := LineEdit.new()
	group.placeholder_text = "Группа (как в анкете учеников). Пусто — для всех"
	group.custom_minimum_size = Vector2(0, 44)
	_view.add_child(group)
	var text := TextEdit.new()
	text.placeholder_text = "Описание (необязательно)"
	text.custom_minimum_size = Vector2(0, 80)
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_view.add_child(text)
	var refresh := func():
		var k: String = keys[kind.selected]
		wd_row.visible = k == "lesson"
		date_row.visible = k != "lesson"
		time_row.visible = k != "plan"
		place.visible = k != "plan"
	kind.item_selected.connect(func(_i): refresh.call())
	refresh.call()
	var msg := _lbl("", 13)
	var save := _btn("Сохранить", 0, 54)
	save.pressed.connect(func():
		if title.text.strip_edges() == "":
			msg.text = "Впишите название."
			return
		var k: String = keys[kind.selected]
		var doc := {
			"title": title.text.strip_edges(), "kind": k, "date": "", "time": "", "time_end": "", "weekday": 0,
			"place": place.text.strip_edges(), "text": text.text.strip_edges(), "group": group.text.strip_edges(),
			"by": Cloud.uid, "by_name": Profile.shown_name(), "at": int(Time.get_unix_time_from_system()),
		}
		if k == "lesson":
			doc["weekday"] = weekday.selected + 1
		else:
			doc["date"] = FormFields.read_date(date_f)
		if k != "plan":
			doc["time"] = FormFields.read_time(t1)
			doc["time_end"] = FormFields.read_time(t2)
		var id := "e%d%03d" % [int(Time.get_unix_time_from_system()), randi() % 1000]
		save.disabled = true
		var r: Dictionary = await Cloud.set_doc("events/" + id, doc)
		if not is_inside_tree():
			return
		if r.ok:
			doc["_id"] = id
			SchoolData.events.append(doc)
			_status.text = "✔ Добавлено."
			_render()
		else:
			msg.text = String(r.error)
			save.disabled = false)
	_view.add_child(save)
	_view.add_child(msg)

# Для снимков экрана (инструмент Shots): форма учителя.
func _open_form_for_shot() -> void:
	Profile.role = "admin"
	_show_form()
