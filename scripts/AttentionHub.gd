extends Control

# Хаб режима «Внимательность»: 50 уровней обычных партий, в которых доска
# подсказывает угрозы. Красный маркер — ваша фигура под боем, зелёный —
# фигура соперника под вашим ударом. С ростом уровня подсказок всё меньше,
# а ИИ всё сильнее; уровни 41–50 — экзамен: без подсказок и без зевков.

@onready var grid: GridContainer = $Grid
@onready var legend: Label = $Legend

const STAGE_NAMES := {
	0: "Полные подсказки",
	10: "Только оборона (красные)",
	20: "Только атака (зелёные)",
	30: "Подсказки гаснут через 5 сек",
	40: "ЭКЗАМЕН: без подсказок и без зевков",
}

func _ready() -> void:
	legend.text = "Красный ТРЕУГОЛЬНИК — ваша фигура под боем;  зелёный РОМБ — фигура соперника под вашим ударом.\nПодсказки постепенно исчезают: научитесь видеть угрозы сами!"
	for n in range(1, 51):
		var b = Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 64)
		var unlocked = n <= Profile.attention_done + 1
		var done = n <= Profile.attention_done
		if done:
			b.text = "✔ %d" % n
		elif unlocked:
			b.text = str(n)
		else:
			b.text = "🔒"
			b.disabled = true
		if unlocked:
			b.tooltip_text = "Уровень %d · сила ИИ: %s\n%s" % [n, Global.difficulty_label(Global.attention_ai_level(n)), _stage_name(n)]
			b.pressed.connect(_start_level.bind(n))
		grid.add_child(b)
		# подпись этапа над каждым десятком
		if (n - 1) % 10 == 0:
			b.text += "\n%s" % _stage_name(n)

func _stage_name(n: int) -> String:
	return STAGE_NAMES[((n - 1) / 10) * 10]

func _start_level(n: int) -> void:
	Global.attention_level = n
	Global.difficulty = Global.attention_ai_level(n)
	Global.map_character_id = ""
	Global.map_assist = false
	Global.coop_team = false
	Global.road_mode = ""
	Global.tournament_game = {}
	Global.player_color = "w"
	# уровень всегда начинается заново, а не из автосейва быстрой партии
	Profile.game_state = {}
	get_tree().change_scene_to_file("res://scenes/Board.tscn")

func _on_menu_pressed() -> void:
	Global.go_back()
