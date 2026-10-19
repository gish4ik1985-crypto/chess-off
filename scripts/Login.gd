extends Control

@onready var user_list: VBoxContainer = $CenterPanel/VBox/UsersScroll/UserList
@onready var empty_label: Label = $CenterPanel/VBox/EmptyLabel

func _ready() -> void:
	_refresh_list()
	if Cloud.enabled:
		var online := Button.new()
		online.text = "Онлайн-вход (школа, любой компьютер)"
		online.custom_minimum_size = Vector2(0, 48)
		online.pressed.connect(_open_online_window)
		$CenterPanel/VBox.add_child(online)

func _refresh_list() -> void:
	for c in user_list.get_children():
		c.queue_free()
	var users = Profile.list_users()
	empty_label.visible = users.is_empty()
	for u in users:
		user_list.add_child(_build_user_row(u))

func _build_user_row(u: Dictionary) -> Control:
	var row = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.09, 0.85)
	sb.border_color = Color(0.11, 0.85, 0.95, 0.4)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 12
	sb.content_margin_top = 8
	sb.content_margin_right = 12
	sb.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", sb)
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	row.add_child(hbox)

	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	var name_label = Label.new()
	name_label.text = String(u.name)
	name_label.add_theme_color_override("font_color", Color(0.1, 0.95, 1))
	name_label.add_theme_font_size_override("font_size", 16)
	info_vbox.add_child(name_label)

	var sub_label = Label.new()
	sub_label.text = "Турнирный рейтинг %d · партий: %d" % [int(round(float(u.rating))), int(u.games)]
	sub_label.add_theme_font_size_override("font_size", 12)
	sub_label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	info_vbox.add_child(sub_label)

	var enter_button = Button.new()
	enter_button.text = "Войти"
	enter_button.custom_minimum_size = Vector2(100, 48)
	enter_button.pressed.connect(func(): _login(String(u.name)))
	hbox.add_child(enter_button)

	var delete_button = Button.new()
	delete_button.text = "✕"
	delete_button.custom_minimum_size = Vector2(48, 48)
	delete_button.pressed.connect(func(): _delete(String(u.name)))
	hbox.add_child(delete_button)

	return row

func _login(name: String) -> void:
	Profile.switch_user(name)
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")

func _delete(name: String) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Удалить игрока?"
	dlg.dialog_text = "Удалить игрока «%s»?\nПрофиль уберётся из списка. Копия сохранится в папке _deleted." % name
	dlg.ok_button_text = "Удалить"
	dlg.cancel_button_text = "Отмена"
	dlg.confirmed.connect(func():
		Profile.delete_user(name)
		_refresh_list())
	dlg.canceled.connect(dlg.queue_free)
	dlg.confirmed.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()

const AGE_GROUPS := [["kid", "Ребёнок (до 12)"], ["teen", "Подросток (12–17)"], ["adult", "Взрослый"]]

# Отдельное окно создания игрока: имя + возрастная группа. Если такое имя уже есть —
# просто входим в него (профиль не затирается).
func _open_new_user_window() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Новый игрок"
	dlg.ok_button_text = "Создать и играть"
	dlg.cancel_button_text = "Отмена"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(380, 0)
	dlg.add_child(box)
	var l1 := Label.new()
	l1.text = "Как тебя зовут?"
	box.add_child(l1)
	var edit := LineEdit.new()
	edit.placeholder_text = "Имя (до 24 символов)"
	edit.max_length = 24
	edit.custom_minimum_size = Vector2(0, 48)
	box.add_child(edit)
	var l2 := Label.new()
	l2.text = "Кто играет? (подсказки подстроятся)"
	box.add_child(l2)
	var ages := OptionButton.new()
	ages.custom_minimum_size = Vector2(0, 48)
	for g in AGE_GROUPS:
		ages.add_item(g[1])
	ages.select(2)
	box.add_child(ages)
	var note := Label.new()
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	var create := func():
		var nm := edit.text.strip_edges()
		if nm == "":
			note.text = "Введите имя."
			return false
		var existed := Profile.user_exists(nm)
		Profile.switch_user(nm)
		if not existed:
			Profile.age_group = AGE_GROUPS[ages.selected][0]
			Profile.save_profile()
		get_tree().change_scene_to_file("res://scenes/Menu.tscn")
		return true
	dlg.confirmed.connect(create)
	edit.text_submitted.connect(func(_t): dlg.get_ok_button().pressed.emit())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()
	edit.grab_focus()

# --- онлайн-вход -------------------------------------------------------------------------------
# Отдельное окно: почта + пароль (+ ник при регистрации). Аккаунт общий для школы и работает на любом
# устройстве; профиль (с историей и обучением) подтягивается из облака. Почта обязательна: на неё
# приходит письмо для сброса пароля.
var _online_overlay: Control

func _open_online_window() -> void:
	if _online_overlay != null:
		return
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(440, 0)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Онлайн-вход в школу"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)

	var mail_edit := LineEdit.new()
	mail_edit.placeholder_text = "Почта (на неё придёт письмо для сброса пароля)"
	mail_edit.custom_minimum_size = Vector2(0, 44)
	mail_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	mail_edit.text = Cloud.email
	box.add_child(mail_edit)
	var pass_edit := LineEdit.new()
	pass_edit.placeholder_text = "Пароль (от 6 символов)"
	pass_edit.secret = true
	pass_edit.custom_minimum_size = Vector2(0, 44)
	box.add_child(pass_edit)

	# только для нового аккаунта
	var reg_box := VBoxContainer.new()
	reg_box.add_theme_constant_override("separation", 8)
	reg_box.visible = false
	box.add_child(reg_box)
	var nick_edit := LineEdit.new()
	nick_edit.placeholder_text = "Ник в школе (2–24 символа, будет виден всем)"
	nick_edit.max_length = 24
	nick_edit.custom_minimum_size = Vector2(0, 44)
	reg_box.add_child(nick_edit)
	var ages := OptionButton.new()
	ages.custom_minimum_size = Vector2(0, 44)
	for g in AGE_GROUPS:
		ages.add_item(g[1])
	ages.select(2)
	reg_box.add_child(ages)
	var tip := Label.new()
	tip.text = "Одна почта на нескольких детей: в Gmail подойдёт запись имя+саша@gmail.com — письма придут в тот же ящик."
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 12)
	tip.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	reg_box.add_child(tip)

	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 13)
	status.text = "Забыли пароль? Введите почту и нажмите «Забыли пароль?» — придёт письмо со ссылкой."
	box.add_child(status)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var btn_login := Button.new()
	btn_login.text = "Войти"
	var btn_reg := Button.new()
	btn_reg.text = "Создать аккаунт"
	btn_reg.theme_type_variation = "Button" # акцентной остаётся одна кнопка — «Войти»
	var btn_cancel := Button.new()
	btn_cancel.text = "Отмена"
	for b in [btn_login, btn_reg, btn_cancel]:
		b.custom_minimum_size = Vector2(0, 48)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	var btn_forgot := Button.new()
	btn_forgot.text = "Забыли пароль?"
	btn_forgot.flat = true
	btn_forgot.custom_minimum_size = Vector2(0, 40)
	box.add_child(btn_forgot)
	var buttons := [btn_login, btn_reg, btn_forgot]

	var busy := func(on: bool):
		for b in buttons:
			b.disabled = on

	var do_login := func():
		var mail := mail_edit.text.strip_edges()
		if not Cloud.valid_email(mail):
			status.text = "Введите почту полностью, например имя@gmail.com."
			return
		if pass_edit.text.length() < 6:
			status.text = "Пароль — минимум 6 символов."
			return
		busy.call(true)
		status.text = "Подключаюсь к облаку…"
		var res: Dictionary = await Cloud.login(mail, pass_edit.text)
		if not res.ok:
			status.text = String(res.error)
			busy.call(false)
			return
		await _finish_online_login(Cloud.nick, false, "", status)

	var do_register := func():
		if not reg_box.visible:
			# первое нажатие открывает поля ника; второе — создаёт аккаунт
			reg_box.visible = true
			btn_login.visible = false
			status.text = "Придумайте ник и нажмите «Создать аккаунт» ещё раз."
			nick_edit.grab_focus()
			return
		var mail := mail_edit.text.strip_edges()
		if not Cloud.valid_email(mail):
			status.text = "Введите почту полностью, например имя@gmail.com."
			return
		if pass_edit.text.length() < 6:
			status.text = "Пароль — минимум 6 символов."
			return
		if not Cloud.valid_nick(nick_edit.text):
			status.text = "Ник — от 2 до 24 символов."
			return
		busy.call(true)
		status.text = "Создаю аккаунт…"
		var res: Dictionary = await Cloud.register(mail, pass_edit.text, nick_edit.text)
		if not res.ok:
			status.text = String(res.error)
			busy.call(false)
			return
		await _finish_online_login(Cloud.nick, true, AGE_GROUPS[ages.selected][0], status)

	btn_login.pressed.connect(func(): do_login.call())
	btn_reg.pressed.connect(func(): do_register.call())
	pass_edit.text_submitted.connect(func(_t):
		if reg_box.visible:
			do_register.call()
		else:
			do_login.call())
	btn_forgot.pressed.connect(func():
		var mail := mail_edit.text.strip_edges()
		if not Cloud.valid_email(mail):
			status.text = "Сначала введите свою почту в первой строке."
			return
		busy.call(true)
		status.text = "Отправляю письмо…"
		var res: Dictionary = await Cloud.send_password_reset(mail)
		busy.call(false)
		status.text = ("Если эта почта зарегистрирована, на неё отправлено письмо со ссылкой. Проверьте и папку «Спам»." if res.ok else String(res.error)))
	btn_cancel.pressed.connect(func():
		overlay.queue_free()
		_online_overlay = null)
	add_child(overlay)
	_online_overlay = overlay
	mail_edit.grab_focus()

# После успешного входа: решаем, чей профиль новее — локальный или облачный — и переходим в меню.
func _finish_online_login(nm: String, registered: bool, age: String, status: Label) -> void:
	var key := Profile.sanitize_key(nm)
	var existed_local := Profile.user_exists(nm)
	if not registered:
		status.text = "Загружаю профиль из облака…"
		var pulled: Dictionary = await Cloud.pull_profile()
		if pulled.found and int(pulled.saved) > Profile.local_saved_unix(key):
			Profile.write_profile_bytes(key, pulled.bytes)
			existed_local = true
		elif not pulled.ok:
			status.text = "Профиль из облака не загрузился (%s). Продолжаю с локальным." % pulled.error
	Profile.switch_user(nm)
	if not existed_local:
		Profile.age_group = age
		Profile.save_profile()
	status.text = "Сохраняю в облако…"
	await Cloud.push_profile()
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")
