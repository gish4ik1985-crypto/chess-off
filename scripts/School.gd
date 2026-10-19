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
	var spot_rec = ""
	if Profile.school_spot_record > 0:
		spot_rec = " · рекорд: %d" % Profile.school_spot_record
	spot_hint.text = "После хода соперника фигуры на миг исчезают, и надо показать, куда он сходил. Учит ЗАМЕЧАТЬ чужие ходы.%s" % spot_rec
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
