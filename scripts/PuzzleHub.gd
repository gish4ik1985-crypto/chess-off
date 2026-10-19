extends Control

# Хаб задач: раньше все режимы задач были кнопками сбоку внутри самого
# решателя — их было не найти. Теперь это отдельный экран выбора: карточка
# на каждый режим с прогрессом, а внутри решателя остаётся только
# навигация по текущему режиму и кнопка возврата сюда.
#
# Экран собран как GridContainer с крупными карточками-иконками — весь
# список помещается на одном экране без прокрутки (раньше ScrollContainer
# терял позицию скролла при пересборке списка).

@onready var grid: GridContainer = $Grid

func _ready() -> void:
	_build()

func _build() -> void:
	for c in grid.get_children():
		c.queue_free()
	if not Profile.puzzle_state.is_empty():
		_add_card("▶", "Продолжить", "с места остановки", func():
			Global.puzzle_jump = -1
			_open(""))
	_add_card("♔1", "Мат в 1 ход", "решено: %d/10" % _solved_in_range(0, 9), func(): _jump(0))
	_add_card("♔2", "Мат в 2 хода", "решено: %d/30" % _solved_in_range(10, 39), func(): _jump(10))
	_add_card("♔3", "Мат в 3 хода", "решено: %d/10" % _solved_in_range(40, 49), func(): _jump(40))
	_add_card("⑂", "Вилка", "решено: %d" % Profile.fork_puzzles_solved, func(): _open("fork"))
	_add_card("⛓", "Связка", "решено: %d" % Profile.pin_puzzles_solved, func(): _open("pin"))
	_add_card("♖8", "Мат на 8-й линии", "решено: %d" % Profile.backrank_puzzles_solved, func(): _open("backrank"))
	_add_card("✕", "Уничтожение защиты", "решено: %d" % Profile.defense_puzzles_solved, func(): _open("defense"))
	_add_card("➤", "Отвлечение", "решено: %d" % Profile.deflection_puzzles_solved, func(): _open("deflection"))
	_add_card("⚂", "Микс без подсказок", "решено: %d" % Profile.mix_puzzles_solved, func(): _open("mix"))
	_add_card("∞", "Свободная практика", "все темы вперемешку", func(): _open("practice"))
	var blunders = _my_blunder_count()
	if blunders > 0:
		_add_card("⚠", "Мои зевки", "позиций: %d" % blunders, func(): _open("blunders"))

func _solved_in_range(a: int, b: int) -> int:
	var n := 0
	for i in range(a, b + 1):
		if Profile.solved_puzzles.has(str(i)):
			n += 1
	return n

func _my_blunder_count() -> int:
	var n := 0
	for bl in Profile.recent_blunders:
		if str(bl.get("fen", "")).contains(" w "):
			n += 1
	return n

func _add_card(icon: String, title: String, subtitle: String, on_press: Callable) -> void:
	var b = Button.new()
	b.custom_minimum_size = Vector2(150, 118)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.text = ""
	b.pressed.connect(on_press)
	grid.add_child(b)

	var vb = VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 4)
	b.add_child(vb)

	var icon_l = Label.new()
	icon_l.text = icon
	icon_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_l.add_theme_font_size_override("font_size", 30)
	icon_l.add_theme_color_override("font_color", Color(0.1, 0.95, 1, 1))
	vb.add_child(icon_l)

	var title_l = Label.new()
	title_l.text = title
	title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_l.autowrap_mode = TextServer.AUTOWRAP_WORD
	title_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_l.add_theme_font_size_override("font_size", 14)
	vb.add_child(title_l)

	var sub_l = Label.new()
	sub_l.text = subtitle
	sub_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_l.autowrap_mode = TextServer.AUTOWRAP_WORD
	sub_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_l.add_theme_font_size_override("font_size", 11)
	sub_l.add_theme_color_override("font_color", Color(0.6, 0.75, 0.85, 0.85))
	vb.add_child(sub_l)

func _jump(index: int) -> void:
	Global.puzzle_jump = index
	_open("")

func _open(theme: String) -> void:
	Global.puzzle_theme = theme
	Global.puzzle_start_index = 0
	get_tree().change_scene_to_file("res://scenes/Puzzle.tscn")

func _on_menu_pressed() -> void:
	Global.go_back()
