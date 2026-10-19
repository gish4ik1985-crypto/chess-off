extends Control

# «Объявления»: сообщения учителя для всех, кто вошёл в игру. Учитель пишет, закрепляет и удаляет;
# при входе новое объявление показывается всплывающим окном (см. Menu.gd).

var _root: VBoxContainer
var _status: Label
var _view: VBoxContainer

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
	title.text = "ОБЪЯВЛЕНИЯ"
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
	if not (Cloud.enabled and Cloud.signed_in):
		_status.text = "Объявления приходят из облака: войдите онлайн."
		return
	_status.text = "Загружаю…"
	var ok := await SchoolData.load_all()
	if not is_inside_tree():
		return
	_status.text = "" if ok else "Не удалось загрузить объявления."
	_show_list()
	SchoolData.mark_announcements_seen()

var _form_open := false

func _on_back() -> void:
	if _form_open:
		_show_list()
		return
	Global.go_back()

func _teacher() -> bool:
	return Roles.can(Profile.role, "open_admin")

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

func _show_list() -> void:
	_form_open = false
	_clear()
	if _teacher():
		var add := Button.new()
		add.text = "+ Новое объявление"
		add.custom_minimum_size = Vector2(0, 50)
		add.pressed.connect(_show_form)
		_view.add_child(add)
	var list: Array = SchoolData.announcements if _teacher() else SchoolData.visible_announcements()
	if _teacher():
		list = list.duplicate()
		list.sort_custom(func(a, b):
			if bool(a.get("pinned", false)) != bool(b.get("pinned", false)):
				return bool(a.get("pinned", false))
			return int(a.get("at", 0)) > int(b.get("at", 0)))
	if list.is_empty():
		_view.add_child(_lbl("Объявлений пока нет."))
	for a in list:
		_view.add_child(_card(a))

func _card(a: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	var pin := "📌 " if bool(a.get("pinned", false)) else ""
	col.add_child(_lbl(pin + String(a.get("title", "")), 18))
	col.add_child(_lbl(String(a.get("text", "")), 15))
	var when := Time.get_datetime_dict_from_unix_time(int(a.get("at", 0)) + 3 * 3600)
	var meta := "%s · %02d.%02d.%d" % [String(a.get("by_name", "учитель")), when.day, when.month, when.year]
	if String(a.get("group", "")) != "":
		meta += " · для группы: " + String(a.get("group", ""))
	col.add_child(_lbl(meta, 12, Color(0.55, 0.6, 0.7)))
	if _teacher():
		var side := VBoxContainer.new()
		row.add_child(side)
		var pb := Button.new()
		pb.text = "Открепить" if bool(a.get("pinned", false)) else "Закрепить"
		pb.custom_minimum_size = Vector2(120, 40)
		pb.pressed.connect(func():
			a["pinned"] = not bool(a.get("pinned", false))
			var d := a.duplicate()
			var id := String(d.get("_id", ""))
			d.erase("_id")
			var r: Dictionary = await Cloud.set_doc("announcements/" + id, d)
			_status.text = "" if r.ok else String(r.error)
			_show_list())
		side.add_child(pb)
		var del := Button.new()
		del.text = "Удалить"
		del.custom_minimum_size = Vector2(120, 40)
		del.pressed.connect(func():
			var r: Dictionary = await Cloud.del_doc("announcements/" + String(a.get("_id", "")))
			if r.ok:
				SchoolData.announcements.erase(a)
			_status.text = "" if r.ok else String(r.error)
			_show_list())
		side.add_child(del)
	return panel

func _show_form() -> void:
	_form_open = true
	_clear()
	_view.add_child(_lbl("НОВОЕ ОБЪЯВЛЕНИЕ", 20, Color(0.96, 0.76, 0.3)))
	var title := LineEdit.new()
	title.placeholder_text = "Заголовок"
	title.max_length = 80
	title.custom_minimum_size = Vector2(0, 46)
	_view.add_child(title)
	var text := TextEdit.new()
	text.placeholder_text = "Текст объявления"
	text.custom_minimum_size = Vector2(0, 140)
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_view.add_child(text)
	var group := LineEdit.new()
	group.placeholder_text = "Группа (как в анкете учеников). Пусто — для всех"
	group.custom_minimum_size = Vector2(0, 46)
	_view.add_child(group)
	var pinned := CheckButton.new()
	pinned.text = "Закрепить вверху списка"
	_view.add_child(pinned)
	var days_row := HBoxContainer.new()
	var dl := Label.new()
	dl.text = "Показывать дней (0 — всегда):  "
	days_row.add_child(dl)
	var days := SpinBox.new()
	days.min_value = 0
	days.max_value = 365
	days.value = 14
	days_row.add_child(days)
	_view.add_child(days_row)
	var msg := _lbl("", 13)
	var send := Button.new()
	send.text = "📢 Опубликовать"
	send.custom_minimum_size = Vector2(0, 54)
	send.pressed.connect(func():
		if title.text.strip_edges() == "" or text.text.strip_edges() == "":
			msg.text = "Впишите заголовок и текст."
			return
		var now := int(Time.get_unix_time_from_system())
		var doc := {
			"title": title.text.strip_edges(), "text": text.text.strip_edges(), "group": group.text.strip_edges(),
			"pinned": pinned.button_pressed, "until": now + int(days.value) * 86400 if int(days.value) > 0 else 0,
			"by": Cloud.uid, "by_name": Profile.shown_name(), "at": now,
		}
		var id := "n%d%03d" % [now, randi() % 1000]
		send.disabled = true
		var r: Dictionary = await Cloud.set_doc("announcements/" + id, doc)
		if not is_inside_tree():
			return
		if r.ok:
			doc["_id"] = id
			SchoolData.announcements.push_front(doc)
			SchoolData.mark_announcements_seen()
			_status.text = "✔ Объявление опубликовано: его увидят все при входе."
			_show_list()
		else:
			msg.text = String(r.error)
			send.disabled = false)
	_view.add_child(send)
	_view.add_child(msg)
