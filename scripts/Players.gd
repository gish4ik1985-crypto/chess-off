extends Control

# «Игроки школы»: общая таблица с публичным рейтингом из облака. Здесь только то, что игрок
# сам делает публичным (ник, турнирный рейтинг, звание, число партий, кубки). Статистика ходов,
# сильные и слабые стороны остаются в личном профиле и никому не показываются.

var _list: VBoxContainer
var _status: Label

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.05, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var top := HBoxContainer.new()
	vbox.add_child(top)
	var title := Label.new()
	title.text = "ИГРОКИ ШКОЛЫ"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.1, 0.95, 1))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var refresh := Button.new()
	refresh.text = "Обновить"
	refresh.custom_minimum_size = Vector2(130, 48)
	refresh.pressed.connect(_load)
	top.add_child(refresh)
	var back := Button.new()
	back.name = "BackButton"
	back.text = "← Назад"
	back.custom_minimum_size = Vector2(130, 48)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Menu.tscn"))
	top.add_child(back)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	vbox.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	_load()

func _clear() -> void:
	for c in _list.get_children():
		c.queue_free()

func _load() -> void:
	_clear()
	if not Cloud.enabled:
		_status.text = "Облако не настроено: заполните res://firebase_config.json (см. docs/firebase-setup.md)."
		return
	if not Cloud.signed_in:
		_status.text = "Чтобы видеть игроков школы, войдите онлайн: на экране выбора игрока — «Онлайн-вход»."
		return
	_status.text = "Загружаю…"
	await Cloud.push_profile() # свежая карточка — чтобы свой рейтинг в таблице был актуален
	var r: Dictionary = await Cloud.query_top("players", "rating", 100)
	if not r.ok:
		_status.text = String(r.error)
		return
	_status.text = "Игроков: %d. Рейтинг — турнирный. Подробная статистика ходов у каждого только своя." % r.docs.size()
	_clear()
	var place := 0
	for d in r.docs:
		place += 1
		_list.add_child(_row(place, d))

func _row(place: int, d: Dictionary) -> Control:
	var mine := String(d.get("nick", "")) == Cloud.nick
	var panel := PanelContainer.new()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	panel.add_child(h)
	var rank := Label.new()
	rank.text = "%d." % place
	rank.custom_minimum_size = Vector2(44, 0)
	h.add_child(rank)
	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name_box)
	var nm := Label.new()
	nm.text = ("⭐ " if mine else "") + String(d.get("nick", "?"))
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color", Color(1, 0.65, 0.95) if mine else Color(0.1, 0.95, 1))
	name_box.add_child(nm)
	var sub := Label.new()
	sub.text = "%s · партий: %d · кубков: %d" % [d.get("title", ""), int(d.get("games", 0)), int(d.get("cups", 0))]
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	name_box.add_child(sub)
	var rt := Label.new()
	rt.text = str(int(d.get("rating", 0)))
	rt.add_theme_font_size_override("font_size", 22)
	h.add_child(rt)
	return panel
