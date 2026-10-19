extends Control

# «Школа юного шахматиста» — хаб тренировочных режимов против игры наугад.
# Каждый режим — обычная партия в Board.tscn с особым правилом, которое
# физически не даёт ходить не глядя. Прогресс — рекорды в Profile.

@onready var spot_button: Button = $Center/VBox/SpotButton
@onready var spot_hint: Label = $Center/VBox/SpotHint
@onready var patience_button: Button = $Center/VBox/PatienceButton
@onready var patience_hint: Label = $Center/VBox/PatienceHint
@onready var pause_buttons: Dictionary = {
	5: $Center/VBox/PauseRow/Pause5,
	10: $Center/VBox/PauseRow/Pause10,
	15: $Center/VBox/PauseRow/Pause15,
}

func _ready() -> void:
	Global.school_mode = "" # safety: никакого залипшего флага
	$Center/VBox/MenuButton.visible = false
	Global.add_floating_back(self, _on_menu_pressed)
	var spot_rec = ""
	if Profile.school_spot_record > 0:
		spot_rec = " · рекорд: %d" % Profile.school_spot_record
	_build_spot_levels()
	_update_spot_hint(spot_rec)
	var wis_rec = ""
	if Profile.school_wisdom_record > 0:
		wis_rec = " · рекорд: ⭐%d" % Profile.school_wisdom_record
	patience_hint.text = "Ход открывается только после паузы на обдумывание. Обдуманные ходы копят серию очков мудрости, зевок её сжигает. Учит НЕ СПЕШИТЬ.%s" % wis_rec
	# выбор длительности паузы: подсветить сохранённую и слушать нажатия
	if not pause_buttons.has(Profile.school_patience_seconds):
		Profile.school_patience_seconds = 10
	for secs in pause_buttons:
		var b: Button = pause_buttons[secs]
		b.button_pressed = secs == Profile.school_patience_seconds
		b.pressed.connect(_on_pause_chosen.bind(secs))

# Выбор уровня «Что изменилось?»: лёгкий / средний / сложный (растёт сам после серии верных ответов).
const SPOT_LEVEL_NAMES := {1: "Лёгкий", 2: "Средний", 3: "Сложный"}
var spot_level_buttons: Dictionary = {}

func _build_spot_levels() -> void:
	var vbox: VBoxContainer = $Center/VBox
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lab := Label.new()
	lab.text = "Уровень:"
	lab.add_theme_font_size_override("font_size", 13)
	row.add_child(lab)
	for lvl in SPOT_LEVEL_NAMES:
		var b := Button.new()
		b.text = SPOT_LEVEL_NAMES[lvl]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(110, 44)
		b.button_pressed = lvl == Profile.school_spot_level
		b.pressed.connect(_on_spot_level_chosen.bind(lvl))
		row.add_child(b)
		spot_level_buttons[lvl] = b
	vbox.add_child(row)
	vbox.move_child(row, spot_hint.get_index() + 1)

func _on_spot_level_chosen(lvl: int) -> void:
	Profile.school_spot_level = lvl
	Profile.school_spot_streak = 0
	Profile.save_profile()
	for l in spot_level_buttons:
		spot_level_buttons[l].button_pressed = l == lvl
	var rec := ""
	if Profile.school_spot_record > 0:
		rec = " · рекорд: %d" % Profile.school_spot_record
	_update_spot_hint(rec)

func _update_spot_hint(rec: String) -> void:
	var by_level := {
		1: "Фигуры на секунду исчезают — найди клетку, КУДА сходил соперник.",
		2: "Фигуры спрятаны на 3 секунды — покажи, ОТКУДА и КУДА он сходил (две клетки).",
		3: "Доска закрыта, пока не ответишь: назови ход соперника по памяти — откуда и куда.",
	}
	spot_hint.text = "%s Учит ЗАМЕЧАТЬ и ПОМНИТЬ чужие ходы. %d верных подряд — уровень растёт сам.%s" % [by_level[Profile.school_spot_level], 5, rec]

func _on_pause_chosen(secs: int) -> void:
	Profile.school_patience_seconds = secs
	Profile.save_profile()
	for s in pause_buttons:
		pause_buttons[s].button_pressed = s == secs

func _launch(mode: String) -> void:
	Global.school_mode = mode
	Global.player_color = "w"
	Global.map_character_id = ""
	Global.map_assist = false
	Global.coop_team = false
	Global.road_mode = ""
	Global.attention_level = 0
	Global.tournament_game = {}
	get_tree().change_scene_to_file("res://scenes/Board.tscn")

func _on_spot_pressed() -> void:
	_launch("spot")

func _on_patience_pressed() -> void:
	_launch("patience")

func _on_menu_pressed() -> void:
	Global.go_back()
