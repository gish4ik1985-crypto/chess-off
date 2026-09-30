extends Node2D

# «Дорога домой» — персональный тренировочный путь из 5 остановок, каждая
# тренирует навык, который редко тренируют у детей:
#   1. Овраг зевков — исправь 3 зевка из СВОИХ партий (позиции из журнала);
#   2. Мост предсказаний — партия, где перед каждым ответом соперника надо
#      угадать его ход (мышление за соперника);
#   3. Туманный лес — партия, где фигуры прячутся в туман, если думать
#      дольше 12 секунд (визуализация «внутренней доски»);
#   4. Твоя Тень — бой с ИИ-двойником: твой рейтинг и твой процент зевков;
#   5. Дом — Тень стала на 2 уровня сильнее: победи себя завтрашнего.
# Прогресс хранится в Profile.road_stage (этапы строго по порядку).
# Плюс дорога РАСТЁТ: после «Дома» появляются тренировочные остановки
# (Profile.dynamic_road_stages) под текущие слабости игрока по всем его
# партиям — и исчезают, когда недавние партии становятся чистыми.

@onready var map_draw: Node2D = $MapDraw
@onready var status_label: Label = $UI/TopBar/HBox/StatusLabel
@onready var detail_panel: Panel = $UI/DetailPanel
@onready var detail_name: Label = $UI/DetailPanel/VBox/NameLabel
@onready var detail_blurb: Label = $UI/DetailPanel/VBox/BlurbLabel
@onready var detail_play: Button = $UI/DetailPanel/VBox/HBox/PlayButton
@onready var music: MusicPlayer = $Music

const NODE_RADIUS := 38.0

# Positions for dynamic remedial stops — the road keeps winding past "Дом"
# for as long as the player's recent games show recurring weaknesses.
const DYNAMIC_POSITIONS := [
	Vector2(700, 140), Vector2(470, 100), Vector2(240, 160), Vector2(90, 320),
]

var selected := -1
var base_count := 0 # how many of `stages` are the fixed story stops

var stages := [
	{
		"name": "Овраг зевков",
		"icon": "P",
		"kind": "blunders",
		"blurb": "Здесь лежат зевки из твоих собственных партий. Исправь %d — найди в тех самых позициях ход сильнее, чем сыграл тогда." % Profile.ROAD_BLUNDERS_REQUIRED,
		"pos": Vector2(120, 560),
		"accent": Color(0.95, 0.6, 0.3),
	},
	{
		"name": "Мост предсказаний",
		"icon": "N",
		"kind": "predict",
		"blurb": "Партия-испытание: после каждого твоего хода угадай, куда пойдёт соперник, и только потом он сходит. Учись думать за двоих! Победа открывает путь.",
		"pos": Vector2(330, 430),
		"accent": Color(0.3, 0.8, 0.95),
	},
	{
		"name": "Туманный лес",
		"icon": "B",
		"kind": "xray",
		"blurb": "Если думать дольше 12 секунд — фигуры прячутся в туман, и ходить придётся по памяти. Тренируй внутреннюю доску, как гроссмейстеры!",
		"pos": Vector2(540, 540),
		"accent": Color(0.7, 0.75, 0.85),
	},
	{
		"name": "Твоя Тень",
		"icon": "K",
		"kind": "shadow",
		"blurb": "Соперник — ты сам: твой рейтинг, твоя манера, твой процент зевков (из дневника). Победить себя — честнейший экзамен в мире.",
		"pos": Vector2(740, 400),
		"accent": Color(0.6, 0.4, 0.9),
	},
	{
		"name": "Дом",
		"icon": "Q",
		"kind": "shadow_final",
		"blurb": "Вот и дом! Но на пороге — Тень, ставшая на два уровня сильнее. Победи себя завтрашнего — и дорога домой пройдена.",
		"pos": Vector2(900, 260),
		"accent": Color(0.95, 0.8, 0.35),
	},
]

func _ready() -> void:
	base_count = stages.size()
	# the road grows: extra stops for the player's current weak spots,
	# derived from ALL logged games (quick play, map, road), and shrinks
	# back once recent games are clean
	var dynamic = Profile.dynamic_road_stages()
	for i in range(min(dynamic.size(), DYNAMIC_POSITIONS.size())):
		var d = dynamic[i]
		stages.append({
			"name": d.name,
			"icon": d.icon,
			"kind": d.kind,
			"blurb": d.blurb,
			"pos": DYNAMIC_POSITIONS[i],
			"accent": d.accent,
		})
	map_draw.position.x = (get_viewport_rect().size.x - 1020.0) / 2.0
	map_draw.draw.connect(_on_draw)
	detail_panel.visible = false
	_update_status()
	music.start_theme({"root": 196.0, "scale": [0, 2, 4, 7, 9], "note_dur": 2.0, "tri_mix": 0.1, "drone_vol": 0.05})

func _update_status() -> void:
	var extra = stages.size() - base_count
	if Profile.road_stage >= base_count:
		status_label.text = "Дорога пройдена! Можно переигрывать любые остановки."
	else:
		status_label.text = "Пройдено остановок: %d / %d" % [Profile.road_stage, base_count]
	if extra > 0:
		status_label.text += "  ·  Дорога выросла: тренировочных остановок — %d" % extra

func _stage_unlocked(i: int) -> bool:
	return true if i >= base_count else i <= Profile.road_stage

func _stage_done(i: int) -> bool:
	if i >= base_count:
		return Profile.road_focus_done.has(stages[i].kind)
	return i < Profile.road_stage

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local = map_draw.get_global_transform().affine_inverse() * event.position
		for i in range(stages.size()):
			if local.distance_to(stages[i].pos) <= NODE_RADIUS:
				_on_node_clicked(i)
				return
		detail_panel.visible = false

func _on_node_clicked(i: int) -> void:
	var st = stages[i]
	detail_name.text = st.name
	if not _stage_unlocked(i):
		selected = -1
		detail_blurb.text = "Заперто. Пройдите предыдущую остановку дороги."
		detail_play.visible = false
	elif st.kind == "blunders" and _white_blunder_count() == 0:
		selected = -1
		detail_blurb.text = "%s\n\nПока здесь пусто: сыграйте пару обычных партий — ваши зевки попадут сюда сами." % st.blurb
		detail_play.visible = false
	else:
		selected = i
		var done = " ✔ Пройдено — можно переиграть." if _stage_done(i) else ""
		detail_blurb.text = st.blurb + done
		detail_play.visible = true
	detail_panel.visible = true
	map_draw.queue_redraw()

func _white_blunder_count() -> int:
	var n := 0
	for b in Profile.recent_blunders:
		if str(b.get("fen", "")).contains(" w "):
			n += 1
	return n

func _on_play_pressed() -> void:
	if selected < 0:
		return
	var st = stages[selected]
	if st.kind == "blunders":
		Global.puzzle_theme = "blunders"
		get_tree().change_scene_to_file("res://scenes/Puzzle.tscn")
		return
	Global.road_mode = st.kind
	# dynamic (focus_*) stops don't advance the base road counter
	Global.road_stage_playing = selected if selected < base_count else -1
	Global.map_character_id = ""
	Global.coop_team = false
	Global.player_color = "w"
	get_tree().change_scene_to_file("res://scenes/Board.tscn")

func _on_close_pressed() -> void:
	selected = -1
	detail_panel.visible = false

func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")

func _on_draw() -> void:
	var font = ThemeDB.fallback_font
	# winding path
	for i in range(stages.size() - 1):
		var unlocked = _stage_unlocked(i + 1)
		var col = Color(0.95, 0.8, 0.35, 0.55) if unlocked else Color(0.4, 0.4, 0.45, 0.3)
		if i + 1 >= base_count:
			col = Color(0.4, 0.85, 0.95, 0.45) # the "grown" part of the road
		_draw_dashed(stages[i].pos, stages[i + 1].pos, col)
	# home glow at the end of the story road
	var home = stages[base_count - 1].pos
	for i in range(4, 0, -1):
		var t = float(i) / 4.0
		var glow = Color(0.95, 0.8, 0.35, 0.05 + 0.04 * (1.0 - t))
		map_draw.draw_circle(home, NODE_RADIUS * (1.0 + 0.8 * t), glow)

	for i in range(stages.size()):
		var st = stages[i]
		var unlocked = _stage_unlocked(i)
		var done = _stage_done(i)
		var accent: Color = st.accent if unlocked else Color(0.35, 0.35, 0.4)
		map_draw.draw_circle(st.pos, NODE_RADIUS, Color(0.05, 0.05, 0.08, 0.95))
		map_draw.draw_arc(st.pos, NODE_RADIUS, 0, TAU, 32, accent, 3.0, true)
		if unlocked:
			PieceTextures.draw(map_draw, st.icon, "w", st.pos, NODE_RADIUS * 1.25)
		else:
			var body = Rect2(st.pos + Vector2(-9, -2), Vector2(18, 14))
			map_draw.draw_rect(body, Color(0.5, 0.5, 0.55), true)
			map_draw.draw_arc(st.pos + Vector2(0, -4), 8.0, PI, TAU, 16, Color(0.5, 0.5, 0.55), 3.0, true)
		if done:
			map_draw.draw_circle(st.pos + Vector2(0, NODE_RADIUS * 0.8), 13.0, Color(0.02, 0.1, 0.04, 0.9))
			var p1 = st.pos + Vector2(-NODE_RADIUS * 0.45, NODE_RADIUS * 0.8)
			var p2 = st.pos + Vector2(-NODE_RADIUS * 0.1, NODE_RADIUS * 1.05)
			var p3 = st.pos + Vector2(NODE_RADIUS * 0.5, NODE_RADIUS * 0.45)
			map_draw.draw_polyline(PackedVector2Array([p1, p2, p3]), Color(0.4, 0.95, 0.5), 3.0, true)
		var label_col = Color(0.9, 0.95, 1.0) if unlocked else Color(0.5, 0.5, 0.55)
		var label_text = st.name
		# blunder stage shows its own progress folded into the label
		if i == 0 and unlocked and not done:
			label_text += "\n%d/%d" % [min(Profile.road_blunders_fixed, Profile.ROAD_BLUNDERS_REQUIRED), Profile.ROAD_BLUNDERS_REQUIRED]
		map_draw.draw_multiline_string(font, st.pos + Vector2(-70, NODE_RADIUS + 22), label_text, HORIZONTAL_ALIGNMENT_CENTER, 140, 13, 3, label_col)

func _draw_dashed(a: Vector2, b: Vector2, col: Color) -> void:
	var dist = a.distance_to(b)
	var dir = (b - a).normalized()
	var t = 0.0
	while t < dist:
		var p1 = a + dir * t
		var p2 = a + dir * min(t + 14.0, dist)
		map_draw.draw_line(p1, p2, col, 3.0)
		t += 22.0
