extends ScrollContainer

# Вкладка «Обо мне» в «Моём профиле»: личная информация игрока — аватар, как называть, возраст, город,
# группа, опыт, разряд, цель, пара слов о себе и настройки приватности. Кнопка «Сохранить» — наверху.
# Ник (имя в игре) не меняется: на нём держатся вход, рейтинг и перенос профиля.

const AGE_GROUPS := [["kid", "Ребёнок (до 12)"], ["teen", "Подросток (12–17)"], ["adult", "Взрослый"]]
const EXPERIENCE := ["Только учусь", "Играю для себя", "Играю в турнирах"]
const RANKS := ["Нет разряда", "3 разряд", "2 разряд", "1 разряд", "КМС и выше"]
const GOALS := ["Научиться играть", "Поднять рейтинг", "Готовлюсь к турнирам", "Просто для удовольствия"]
const AVATARS := ["♞", "♛", "♜", "♝", "♚", "♟", "⚡", "🦁", "🐯", "🐺", "🦅", "🐉", "🚀", "🔥"]

var _avatar := ""
var _avatar_buttons: Dictionary = {}
var _avatar_big: Label
var _fio: LineEdit
var _call: LineEdit
var _age: OptionButton
var _city: LineEdit
var _group: LineEdit
var _exp: OptionButton
var _rank: OptionButton
var _goal: OptionButton
var _about: LineEdit
var _visible_chk: CheckButton
var _details_chk: CheckButton
var _status: Label
var _save_btn: Button
var _reset_btn: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_top = 112.0
	offset_left = 24.0
	offset_right = -24.0
	offset_bottom = -8.0
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(640, 0)
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)

	# верхняя строка: сохранить и результат
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	col.add_child(top)
	_save_btn = Button.new()
	_save_btn.text = "💾 Сохранить"
	_save_btn.custom_minimum_size = Vector2(170, 46)
	_save_btn.pressed.connect(_on_save)
	top.add_child(_save_btn)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 13)
	top.add_child(_status)

	# визитка: аватар, ник, где хранится профиль
	var card := PanelContainer.new()
	col.add_child(card)
	var card_row := HBoxContainer.new()
	card_row.add_theme_constant_override("separation", 16)
	card.add_child(card_row)
	_avatar_big = Label.new()
	_avatar_big.add_theme_font_size_override("font_size", 52)
	_avatar_big.custom_minimum_size = Vector2(80, 0)
	_avatar_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_avatar_big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card_row.add_child(_avatar_big)
	var card_col := VBoxContainer.new()
	card_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_row.add_child(card_col)
	var nick := Label.new()
	nick.text = Profile.shown_name()
	nick.add_theme_font_size_override("font_size", 24)
	card_col.add_child(nick)
	if Profile.shown_name() != Profile.display_name:
		var nk := Label.new()
		nk.text = "Вход в школу: %s" % Profile.display_name
		nk.add_theme_font_size_override("font_size", 13)
		card_col.add_child(nk)
	var cls := Label.new()
	cls.text = "%s%s" % [Roles.class_text(Profile.tournament_rating, Profile.title_for_rating(Profile.tournament_rating)), ("  ·  🏅 " + Profile.award) if Profile.award != "" else ""]
	cls.add_theme_font_size_override("font_size", 14)
	cls.add_theme_color_override("font_color", Color(0.96, 0.76, 0.3))
	card_col.add_child(cls)
	var role_l := Label.new()
	role_l.text = "Роль: " + Roles.badge(Profile.role)
	role_l.add_theme_font_size_override("font_size", 13)
	card_col.add_child(role_l)
	var acc := Label.new()
	acc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	acc.add_theme_font_size_override("font_size", 12)
	acc.text = _account_text()
	card_col.add_child(acc)
	var nick_hint := Label.new()
	nick_hint.text = "Имя для входа в школу не меняется: на нём держатся рейтинг и перенос профиля. Если нужно исправить — обратитесь к администратору."
	nick_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nick_hint.add_theme_font_size_override("font_size", 11)
	nick_hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	card_col.add_child(nick_hint)

	# аватар
	col.add_child(_section("Аватар"))
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	col.add_child(grid)
	_avatar = Profile.avatar if Profile.avatar != "" else AVATARS[0]
	for a in AVATARS:
		var b := Button.new()
		b.text = a
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(70, 56)
		b.add_theme_font_size_override("font_size", 26)
		b.pressed.connect(_pick_avatar.bind(a))
		grid.add_child(b)
		_avatar_buttons[a] = b
	_pick_avatar(_avatar)

	# личное
	col.add_child(_section("О вас"))
	_fio = _line(col, "ФИО", Profile.full_name, "Фамилия Имя Отчество", 60)
	_call = _line(col, "Как к вам обращаться", Profile.call_name, "Например: Саша", 24)
	_age = _option(col, "Возрастная группа", AGE_GROUPS.map(func(g): return g[1]), _age_index())
	_city = _line(col, "Город", Profile.city, "Ярославль", 30)
	_group = _line(col, "Группа или тренер", Profile.club_group, "Например: группа Ивана Петровича", 40)
	_about = _line(col, "Пара слов о себе", Profile.about, "Люблю гамбиты и мультики", 80)

	col.add_child(_section("Шахматы"))
	_exp = _option(col, "Опыт", EXPERIENCE, Profile.experience)
	_rank = _option(col, "Разряд", RANKS, Profile.rank_level)
	_goal = _option(col, "Цель", GOALS, Profile.goal)

	col.add_child(_section("Приватность"))
	_visible_chk = CheckButton.new()
	_visible_chk.text = "Показывать меня в таблице «Игроки школы»"
	_visible_chk.button_pressed = Profile.public_visible
	col.add_child(_visible_chk)
	_details_chk = CheckButton.new()
	_details_chk.text = "Показывать другим моё ФИО, город и «пару слов о себе»"
	_details_chk.button_pressed = Profile.public_details
	col.add_child(_details_chk)
	var priv := Label.new()
	priv.text = "Статистика ходов, сильные и слабые стороны всегда остаются только у вас."
	priv.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	priv.add_theme_font_size_override("font_size", 12)
	priv.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	col.add_child(priv)

	# аккаунт
	if Cloud.enabled and Cloud.signed_in and Cloud.email != "":
		col.add_child(_section("Аккаунт"))
		_reset_btn = Button.new()
		_reset_btn.text = "Сменить пароль — письмо на %s" % Cloud.email
		_reset_btn.custom_minimum_size = Vector2(0, 46)
		_reset_btn.pressed.connect(_on_reset_password)
		col.add_child(_reset_btn)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 24)
	col.add_child(pad)

func _account_text() -> String:
	if Cloud.enabled and Cloud.signed_in:
		return "Онлайн-аккаунт: %s. Профиль хранится в облаке и открывается с любого устройства." % Cloud.email
	return "Профиль хранится только на этом устройстве. Чтобы он открывался и на других, войдите онлайн."

func _age_index() -> int:
	for i in range(AGE_GROUPS.size()):
		if AGE_GROUPS[i][0] == Profile.age_group:
			return i
	return 2

func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.96, 0.76, 0.3))
	return l

func _field_row(parent: Control, caption: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = caption
	l.custom_minimum_size = Vector2(200, 0)
	l.add_theme_font_size_override("font_size", 14)
	row.add_child(l)
	parent.add_child(row)
	return row

func _line(parent: Control, caption: String, value: String, hint: String, max_len: int) -> LineEdit:
	var row := _field_row(parent, caption)
	var e := LineEdit.new()
	e.text = value
	e.placeholder_text = hint
	e.max_length = max_len
	e.custom_minimum_size = Vector2(0, 44)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(e)
	return e

func _option(parent: Control, caption: String, items: Array, selected: int) -> OptionButton:
	var row := _field_row(parent, caption)
	var o := OptionButton.new()
	for it in items:
		o.add_item(String(it))
	o.selected = clampi(selected, 0, items.size() - 1)
	o.custom_minimum_size = Vector2(0, 44)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(o)
	return o

func _pick_avatar(a: String) -> void:
	_avatar = a
	for k in _avatar_buttons:
		_avatar_buttons[k].button_pressed = k == a
	_avatar_big.text = a

func _on_save() -> void:
	_save_btn.disabled = true
	Profile.avatar = _avatar
	Profile.full_name = _fio.text.strip_edges()
	Profile.call_name = _call.text.strip_edges()
	Profile.age_group = AGE_GROUPS[_age.selected][0]
	Profile.city = _city.text.strip_edges()
	Profile.club_group = _group.text.strip_edges()
	Profile.about = _about.text.strip_edges()
	Profile.experience = _exp.selected
	Profile.rank_level = _rank.selected
	Profile.goal = _goal.selected
	Profile.public_visible = _visible_chk.button_pressed
	Profile.public_details = _details_chk.button_pressed
	Profile.save_profile()
	_status.text = "✔ Сохранено на этом устройстве."
	if Cloud.enabled and Cloud.signed_in:
		_status.text = "Сохраняю в облако…"
		var r: Dictionary = await Cloud.push_profile()
		if not is_inside_tree():
			return
		_status.text = "✔ Сохранено и отправлено в облако." if r.get("ok", false) else "Сохранено на устройстве. Облако: %s" % String(r.get("error", "не удалось отправить"))
	_save_btn.disabled = false

func _on_reset_password() -> void:
	_reset_btn.disabled = true
	_status.text = "Отправляю письмо…"
	var r: Dictionary = await Cloud.send_password_reset(Cloud.email)
	if not is_inside_tree():
		return
	_status.text = ("Письмо отправлено на %s. Проверьте и папку «Спам»." % Cloud.email) if r.get("ok", false) else String(r.get("error", "Не удалось отправить письмо."))
	_reset_btn.disabled = false
