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
	_brand_header() # последним: подпись организации оказывается под всеми кнопками

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
	sb.border_color = Color(0.95, 0.76, 0.31, 0.35)
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
	row.set_meta("brand", true) # строка игрока на тёмной карточке не перекрашивается темой
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	row.add_child(hbox)

	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	var name_label = Label.new()
	name_label.text = String(u.name)
	name_label.add_theme_color_override("font_color", Color("#F4EFE0"))
	name_label.set_meta("brand", true)
	name_label.add_theme_font_size_override("font_size", 16)
	info_vbox.add_child(name_label)

	var sub_label = Label.new()
	sub_label.text = "Турнирный рейтинг %d · партий: %d" % [int(round(float(u.rating))), int(u.games)]
	sub_label.add_theme_font_size_override("font_size", 12)
	sub_label.add_theme_color_override("font_color", Color("#9DA3C4"))
	sub_label.set_meta("brand", true)
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

# Печать клуба над заголовком; заголовок — название клуба.
func _brand_header() -> void:
	var vbox: VBoxContainer = $CenterPanel/VBox
	($CenterPanel/VBox/TitleLabel as Label).text = "ИРБИС"
	var sub: Label = $CenterPanel/VBox/SubtitleLabel
	sub.text = "Шахматный клуб · кто играет?"
	var seal := TextureRect.new()
	seal.texture = load("res://assets/brand/seal_512.png")
	var short_screen := get_viewport_rect().size.y < 860.0
	if short_screen:
		vbox.add_theme_constant_override("separation", 4)
		($CenterPanel/VBox/TitleLabel as Label).add_theme_font_size_override("font_size", 34)
	seal.custom_minimum_size = Vector2(44, 44) if short_screen else Vector2(72, 72)
	seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(seal)
	vbox.move_child(seal, 0)
	var org := Label.new()
	org.text = Global.CLUB_ORG
	org.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	org.add_theme_font_size_override("font_size", 12)
	org.add_theme_color_override("font_color", Color("#9DA3C4"))
	org.set_meta("brand", true)
	vbox.add_child(org)
	var full := Label.new()
	full.text = Global.CLUB_ORG_FULL
	full.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	full.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	full.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	full.custom_minimum_size = Vector2(200, 0)
	full.add_theme_font_size_override("font_size", 10)
	full.add_theme_color_override("font_color", Color("#7F86AB"))
	full.set_meta("brand", true)
	vbox.add_child(full)
	_add_backdrop()

# Фон входа в духе экрана загрузки: тёмно-синий градиент, крупная печать клуба водяным знаком,
# еле заметная шахматная плитка снизу, золотые искры и девиз. Цвета фирменные и не зависят от темы.
const BRAND_NAVY_TOP := Color("#1D2352")
const BRAND_NAVY_BOTTOM := Color("#0B0E24")
const BRAND_GOLD := Color("#F2C14E")

var _backdrop: Control

func _add_backdrop() -> void:
	$Background.visible = false # старая плоская заливка; тема её перекрашивала бы
	# карточка входа — в цветах клуба, чтобы сочеталась с фоном; цвет текста и кнопок остаётся от темы
	var card_style := Themes.card_box()
	card_style.bg_color = Color(BRAND_NAVY_BOTTOM.r + 0.04, BRAND_NAVY_BOTTOM.g + 0.05, BRAND_NAVY_BOTTOM.b + 0.12, 0.95)
	card_style.border_color = Color(BRAND_GOLD, 0.5)
	card_style.set_border_width_all(1)
	card_style.shadow_color = Color(0, 0, 0, 0.5)
	$CenterPanel.set_meta("brand", true)
	$CenterPanel.add_theme_stylebox_override("panel", card_style)
	# подписи на тёмно-синей карточке — всегда светлые, в какой бы теме ни была игра
	var title: Label = $CenterPanel/VBox/TitleLabel
	title.set_meta("brand", true)
	title.add_theme_color_override("font_color", Color("#F4EFE0"))
	title.add_theme_font_override("font", Themes.font_bold())
	var sub: Label = $CenterPanel/VBox/SubtitleLabel
	sub.set_meta("brand", true)
	sub.add_theme_color_override("font_color", BRAND_GOLD)
	for n in [empty_label, $CenterPanel/VBox/StorageNote]:
		(n as Label).set_meta("brand", true)
		(n as Label).add_theme_color_override("font_color", Color("#9DA3C4"))
	_backdrop = Control.new()
	_backdrop.name = "Backdrop"
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.set_meta("themed", true)
	add_child(_backdrop)
	move_child(_backdrop, 0)

	var g := Gradient.new()
	g.set_color(0, BRAND_NAVY_TOP)
	g.set_color(1, BRAND_NAVY_BOTTOM)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 8
	gt.height = 256
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	var sky := TextureRect.new()
	sky.texture = gt
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.add_child(sky)

	# плитка и искры рисуются одним узлом
	var deco := Control.new()
	deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.draw.connect(func(): _draw_deco(deco))
	deco.resized.connect(deco.queue_redraw)
	_backdrop.add_child(deco)

	var motto := Label.new()
	motto.text = "Играй · учись · побеждай"
	motto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	motto.add_theme_font_size_override("font_size", 16)
	motto.add_theme_color_override("font_color", Color(BRAND_GOLD, 0.7))
	motto.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 28)
	motto.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.add_child(motto)
	Global.add_version_label(_backdrop)

# Печать клуба водяным знаком: те же кольцо, шахматные отрезки и молния, но одной золотой линией
# с малой прозрачностью — фон не спорит с карточкой входа.
func _draw_watermark(c: Control) -> void:
	var center := c.size / 2.0
	var k := minf(c.size.x, c.size.y) * 0.5 * 1.02 / 60.0
	var col := Color(BRAND_GOLD, 0.14)
	c.draw_arc(center, 58.0 * k, 0.0, TAU, 96, col, 3.0 * k, true)
	for i in range(32):
		var a0 := i * TAU / 32.0
		c.draw_arc(center, 47.0 * k, a0, a0 + TAU / 64.0, 6, col, 9.0 * k, true)
	var bolt := PackedVector2Array([Vector2(7, -35), Vector2(-17, 4), Vector2(-2, 4), Vector2(-7.5, 35), Vector2(19, -5), Vector2(3, -5)])
	for i in range(bolt.size()):
		bolt[i] = center + bolt[i] * k
	c.draw_colored_polygon(bolt, Color(BRAND_GOLD, 0.16))

func _draw_deco(c: Control) -> void:
	var sz := c.size
	_draw_watermark(c)
	# шахматная плитка вдоль нижней кромки, растворяющаяся к центру
	var sq := 64.0
	var rows := 4
	for r in range(rows):
		for f in range(int(ceil(sz.x / sq))):
			if (r + f) % 2 == 0:
				continue
			var y := sz.y - (r + 1) * sq
			var a := 0.05 * (1.0 - float(r) / rows)
			c.draw_rect(Rect2(f * sq, y, sq, sq), Color(1, 1, 1, a), true)
	# золотые искры: расположение фиксированное, не «прыгает» при перерисовке
	var rng := RandomNumberGenerator.new()
	rng.seed = 1909
	for i in range(34):
		var p := Vector2(rng.randf() * sz.x, rng.randf() * sz.y * 0.85)
		var r := 0.8 + rng.randf() * 1.6
		c.draw_circle(p, r, Color(BRAND_GOLD, 0.15 + rng.randf() * 0.35))
	for i in range(5):
		var p := Vector2(rng.randf() * sz.x, rng.randf() * sz.y * 0.7)
		var k := 5.0 + rng.randf() * 4.0
		c.draw_colored_polygon(PackedVector2Array([
			p + Vector2(0, -k), p + Vector2(k * 0.28, -k * 0.28), p + Vector2(k, 0), p + Vector2(k * 0.28, k * 0.28),
			p + Vector2(0, k), p + Vector2(-k * 0.28, k * 0.28), p + Vector2(-k, 0), p + Vector2(-k * 0.28, -k * 0.28)]),
			Color(BRAND_GOLD, 0.5))

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
	var fio_edit := LineEdit.new()
	fio_edit.placeholder_text = "Фамилия Имя Отчество"
	fio_edit.max_length = 60
	fio_edit.custom_minimum_size = Vector2(0, 44)
	reg_box.add_child(fio_edit)
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
	var state := {"needs_nick": false}

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
		if res.get("needs_nick", false):
			# аккаунт есть, но регистрация оборвалась до выбора ника: просим выбрать ник и завершаем
			state.needs_nick = true
			reg_box.visible = true
			btn_login.visible = false
			btn_reg.text = "Завершить регистрацию"
			busy.call(false)
			status.text = "Аккаунт найден. Осталось указать фамилию и имя — так вас увидят в школе."
			fio_edit.grab_focus()
			return
		await _finish_online_login(Cloud.nick, false, "", status)

	var do_register := func():
		if state.needs_nick:
			if not Cloud.valid_full_name(fio_edit.text):
				status.text = "Впишите фамилию и имя (можно с отчеством) — так вас будут видеть в школе."
				return
			busy.call(true)
			status.text = "Сохраняю…"
			var claim: Dictionary = await Cloud.claim_nick(Cloud.normalize_name(fio_edit.text))
			if not claim.ok:
				status.text = String(claim.error)
				busy.call(false)
				return
			await _finish_online_login(Cloud.nick, true, AGE_GROUPS[ages.selected][0], status, Cloud.normalize_name(fio_edit.text))
			return
		if not reg_box.visible:
			# первое нажатие открывает поля ника; второе — создаёт аккаунт
			reg_box.visible = true
			btn_login.visible = false
			status.text = "Впишите фамилию, имя и отчество и нажмите «Создать аккаунт» ещё раз."
			fio_edit.grab_focus()
			return
		var mail := mail_edit.text.strip_edges()
		if not Cloud.valid_email(mail):
			status.text = "Введите почту полностью, например имя@gmail.com."
			return
		if pass_edit.text.length() < 6:
			status.text = "Пароль — минимум 6 символов."
			return
		if not Cloud.valid_full_name(fio_edit.text):
			status.text = "Впишите фамилию и имя (можно с отчеством) — так вас будут видеть в школе."
			return
		busy.call(true)
		status.text = "Создаю аккаунт…"
		var res: Dictionary = await Cloud.register(mail, pass_edit.text, Cloud.normalize_name(fio_edit.text))
		if not res.ok:
			status.text = String(res.error)
			busy.call(false)
			return
		await _finish_online_login(Cloud.nick, true, AGE_GROUPS[ages.selected][0], status, Cloud.normalize_name(fio_edit.text))

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
func _finish_online_login(nm: String, registered: bool, age: String, status: Label, full_name: String = "") -> void:
	var key := Profile.sanitize_key(nm)
	var existed_local := Profile.user_exists(nm)
	Cloud.push_blocked = false
	if not registered:
		status.text = "Загружаю профиль из облака…"
		var pulled: Dictionary = await Cloud.pull_profile()
		if pulled.found and int(pulled.saved) > Profile.local_saved_unix(key):
			Profile.write_profile_bytes(key, pulled.bytes)
			existed_local = true
		elif not pulled.ok:
			status.text = "Профиль из облака не загрузился (%s). Продолжаю с локальным." % pulled.error
			if not existed_local:
				# на этом устройстве профиля нет, а облачный не скачался: пустой не отправляем поверх него
				Cloud.push_blocked = true
	Profile.switch_user(nm)
	Cloud.synced_saved = -1
	Profile.merge_replaced_backup()
	if not registered:
		# и при «локальный новее» облачный прогресс вливается, а не теряется
		await Cloud.sync_profile()
	if not existed_local:
		Profile.age_group = age
		Profile.save_profile()
	if full_name != "":
		Profile.full_name = full_name
		Profile.save_profile()
	Homework.assignments = []
	Homework.my_done = {}
	Homework.loaded = false
	await Cloud.refresh_role()
	status.text = "Сохраняю в облако…"
	await Cloud.push_profile()
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")
