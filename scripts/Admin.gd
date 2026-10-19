extends Control

# Панель управления: настройки игры (только администратор) и список игроков с ролями и именными титулами
# (администратор назначает роли, тренер и модератор — титулы). Строится кодом, сцена пустая.

var _body: VBoxContainer
var _status: Label
var _players_box: VBoxContainer

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
	_body = VBoxContainer.new()
	_body.custom_minimum_size = Vector2(720, 0)
	_body.add_theme_constant_override("separation", 14)
	center.add_child(_body)
	Global.add_floating_back(self, func(): Global.go_back())

	var title := Label.new()
	title.text = "ПАНЕЛЬ УПРАВЛЕНИЯ"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.96, 0.76, 0.3))
	title.position = Vector2(24, 16)
	add_child(title)

	var me := Label.new()
	me.text = "Вы вошли как: %s · %s" % [Profile.shown_name(), Roles.badge(Profile.role)]
	me.add_theme_font_size_override("font_size", 14)
	_body.add_child(me)
	if not Roles.can(Profile.role, "open_admin"):
		var no := Label.new()
		no.text = "Для этого раздела нужна роль тренера, модератора или администратора."
		_body.add_child(no)
		return
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 13)
	_body.add_child(_status)
	if Roles.can(Profile.role, "game_settings"):
		_build_game_settings()
	_build_players()
	_build_roles_legend()

func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.96, 0.76, 0.3))
	return l

func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	return l

# ------------------------------------------------------------------ настройки игры

func _build_game_settings() -> void:
	_body.add_child(_section("Настройки игры"))
	_toggle("Игра «с форой»", "Когда включено, на карте у каждого персонажа появляется кнопка «С форой» — начать партию сразу с материальным перевесом.",
		Global.handicap_enabled, func(v: bool): Global.handicap_enabled = v)
	_toggle("Живая сложность", "Сила каждого соперника подстраивается под вашу силу: слишком сильный — слабеет, слишком слабый — растёт.",
		Global.adaptive_difficulty, func(v: bool): Global.adaptive_difficulty = v)
	_toggle("Ничья по правилу 50 ходов", "Партия без взятий и ходов пешками 50 ходов подряд заканчивается вничью.",
		Global.fifty_move_rule_enabled, func(v: bool): Global.fifty_move_rule_enabled = v)
	# настоящий рейтинг игрока (этого профиля)
	var title := Label.new()
	title.text = "Настоящий рейтинг (если есть)"
	_body.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = Profile.REAL_RATING_MAX
	spin.step = 10
	spin.value = Profile.real_rating
	spin.editable = Profile.has_user()
	row.add_child(spin)
	var btn := Button.new()
	btn.text = "Применить"
	btn.disabled = not Profile.has_user()
	row.add_child(btn)
	_body.add_child(row)
	var msg := _note("Рейтинг федерации или клуба для текущего профиля: турнирный рейтинг начнётся с него. 0 — рейтинга нет.")
	_body.add_child(msg)
	btn.pressed.connect(func():
		var v := int(spin.value)
		if v != 0 and v < Profile.REAL_RATING_MIN:
			msg.text = "Рейтинг должен быть от %d до %d или 0." % [Profile.REAL_RATING_MIN, Profile.REAL_RATING_MAX]
			return
		Profile.set_real_rating(v)
		msg.text = "Сохранено. Турнирный рейтинг: %d." % int(Profile.tournament_rating) if v > 0 else "Настоящий рейтинг убран.")

func _toggle(caption: String, hint: String, value: bool, apply: Callable) -> void:
	var c := CheckButton.new()
	c.text = caption
	c.button_pressed = value
	c.toggled.connect(func(v: bool):
		apply.call(v)
		Global.save_settings())
	_body.add_child(c)
	_body.add_child(_note(hint))

# ------------------------------------------------------------------ игроки и роли

func _build_players() -> void:
	_body.add_child(_section("Игроки школы"))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	var refresh := Button.new()
	refresh.text = "🔄 Обновить список"
	refresh.custom_minimum_size = Vector2(0, 44)
	refresh.pressed.connect(_load_players)
	top.add_child(refresh)
	_body.add_child(top)
	var hint := "Администратор выдаёт роли и титулы, тренер и модератор — только именные титулы."
	if not Roles.can(Profile.role, "manage_roles"):
		hint = "Вы можете присваивать игрокам именные титулы (например, «Чемпион школы 2026»)."
	_body.add_child(_note(hint))
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 8)
	_body.add_child(_players_box)
	_load_players()

func _load_players() -> void:
	for ch in _players_box.get_children():
		ch.queue_free()
	if not (Cloud.enabled and Cloud.signed_in):
		_status.text = "Список игроков доступен после онлайн-входа."
		return
	_status.text = "Загружаю игроков…"
	var pl: Dictionary = await Cloud.query_top("players", "rating", 200)
	var rl: Dictionary = await Cloud.list_roles()
	if not is_inside_tree():
		return
	if not pl.ok:
		_status.text = String(pl.error)
		return
	var roles := {}
	if rl.ok:
		for d in rl.docs:
			roles[String(d.get("_id", ""))] = d
	_status.text = "Игроков: %d." % pl.docs.size()
	for d in pl.docs:
		_players_box.add_child(_player_row(d, roles.get(String(d.get("_id", "")), {})))

func _player_row(d: Dictionary, rd: Dictionary) -> Control:
	var uid_target := String(d.get("_id", ""))
	var panel := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var cur_role := String(rd.get("role", "player"))
	if not Roles.valid(cur_role):
		cur_role = "player"
	var head := Label.new()
	var nm := String(d.get("name", ""))
	head.text = "%s%s  ·  ник %s  ·  %s" % [String(d.get("avatar", "")) + " " if String(d.get("avatar", "")) != "" else "", nm if nm != "" else String(d.get("nick", "?")), String(d.get("nick", "?")), Roles.class_text(float(d.get("rating", 0)))]
	head.add_theme_font_size_override("font_size", 15)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var opt := OptionButton.new()
	for r in Roles.ORDER:
		opt.add_item(Roles.badge(r))
	opt.selected = Roles.ORDER.find(cur_role)
	opt.disabled = not Roles.can(Profile.role, "manage_roles")
	opt.custom_minimum_size = Vector2(190, 42)
	row.add_child(opt)
	var award := LineEdit.new()
	award.placeholder_text = "Именной титул (необязательно)"
	award.text = String(rd.get("award", ""))
	award.max_length = 40
	award.editable = Roles.can(Profile.role, "award_titles")
	award.custom_minimum_size = Vector2(0, 42)
	award.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(award)
	var save := Button.new()
	save.text = "Сохранить"
	save.custom_minimum_size = Vector2(120, 42)
	save.disabled = not Roles.can(Profile.role, "award_titles")
	save.pressed.connect(func():
		save.disabled = true
		var r: Dictionary = await Cloud.set_role(uid_target, Roles.ORDER[opt.selected], award.text, String(d.get("nick", "")))
		if not is_inside_tree():
			return
		_status.text = ("✔ Сохранено: %s." % String(d.get("nick", ""))) if r.ok else ("Не сохранилось: %s" % String(r.error))
		save.disabled = false)
	row.add_child(save)
	return panel

func _build_roles_legend() -> void:
	_body.add_child(_section("Какие бывают роли"))
	for r in Roles.ORDER:
		_body.add_child(_note("%s — %s" % [Roles.badge(r), Roles.INFO[r].about]))
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 24)
	_body.add_child(pad)
