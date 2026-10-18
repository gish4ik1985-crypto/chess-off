extends Control

@onready var user_list: VBoxContainer = $CenterPanel/VBox/UsersScroll/UserList
@onready var empty_label: Label = $CenterPanel/VBox/EmptyLabel

func _ready() -> void:
	_refresh_list()

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
