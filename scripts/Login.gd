extends Control

@onready var user_list: VBoxContainer = $CenterPanel/VBox/UsersScroll/UserList
@onready var name_edit: LineEdit = $CenterPanel/VBox/NewUserRow/NameEdit
@onready var empty_label: Label = $CenterPanel/VBox/EmptyLabel

func _ready() -> void:
	_refresh_list()
	name_edit.text_submitted.connect(func(_t): _on_create_pressed())

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
	enter_button.custom_minimum_size = Vector2(90, 0)
	enter_button.pressed.connect(func(): _login(String(u.name)))
	hbox.add_child(enter_button)

	var delete_button = Button.new()
	delete_button.text = "✕"
	delete_button.custom_minimum_size = Vector2(40, 0)
	delete_button.pressed.connect(func(): _delete(String(u.name)))
	hbox.add_child(delete_button)

	return row

func _login(name: String) -> void:
	Profile.switch_user(name)
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")

func _delete(name: String) -> void:
	Profile.delete_user(name)
	_refresh_list()

func _on_create_pressed() -> void:
	var name = name_edit.text.strip_edges()
	if name == "":
		return
	Profile.switch_user(name)
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")
