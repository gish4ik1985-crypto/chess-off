extends Node2D

# «Зал наград» — теперь это несколько комнат, по одной на каждый режим,
# за который выдаются награды: Достижения (полки + корона Каиссы),
# Турниры, Карта страны, Задачи, Дорога домой и Внимательность.
# Комнаты переключаются кнопками под шапкой. Каждый предмет кликабелен:
# панель объясняет, что это и как это получить.

@onready var wall_draw: Node2D = $WallDraw
@onready var detail_panel: Panel = $UI/DetailPanel
@onready var detail_name: Label = $UI/DetailPanel/VBox/NameLabel
@onready var detail_status: Label = $UI/DetailPanel/VBox/StatusLabel
@onready var detail_blurb: Label = $UI/DetailPanel/VBox/BlurbLabel

const DESIGN_WIDTH := 1280.0
const HIT_RADIUS := 40.0

const ROOMS := [
	{"id": "ach", "name": "Достижения", "accent": Color(1.0, 0.4, 0.85), "wall": Color(0.09, 0.07, 0.13)},
	{"id": "tourney", "name": "Турниры", "accent": Color(1.0, 0.8, 0.2), "wall": Color(0.12, 0.10, 0.06)},
	{"id": "map", "name": "Карта страны", "accent": Color(0.55, 0.9, 0.35), "wall": Color(0.06, 0.11, 0.07)},
	{"id": "puzzles", "name": "Задачи", "accent": Color(0.1, 0.95, 1.0), "wall": Color(0.05, 0.09, 0.12)},
	{"id": "road", "name": "Дорога домой", "accent": Color(0.95, 0.8, 0.35), "wall": Color(0.11, 0.09, 0.05)},
	{"id": "attention", "name": "Внимательность", "accent": Color(1.0, 0.55, 0.3), "wall": Color(0.12, 0.07, 0.06)},
]

# Полка каждого достижения (1 — легендарная верхняя, 5 — бронзовая нижняя).
const TIER_OF := {
	"beat_level_10": 1, "rating_2400": 1, "puzzle_50": 1, "act3_legend": 1,
	"wins_50": 2, "rating_2000": 2, "fork_50": 2, "pin_50": 2, "backrank_50": 2,
	"defense_50": 2, "deflection_50": 2, "tourney_win_5": 2, "tourney_rating_1800": 2,
	"act2_champion": 2, "map_boss": 2,
	"wins_20": 3, "streak_5": 3, "rating_1600": 3, "puzzle_25": 3, "puzzle_mate3": 3,
	"moves_good_50": 3, "streak_7": 3, "tourney_win": 3, "tourney_daily": 3,
	"wins_5": 4, "streak_3": 4, "puzzle_10": 4, "fork_10": 4, "pin_10": 4,
	"backrank_10": 4, "defense_10": 4, "deflection_10": 4, "mix_10": 4,
}

const TIER_COLORS := {
	1: Color(1.0, 0.4, 0.85),   # легендарные — неоновый пурпур
	2: Color(0.75, 0.9, 1.0),   # платиновые
	3: Color(1.0, 0.8, 0.2),    # золотые
	4: Color(0.8, 0.82, 0.88),  # серебряные
	5: Color(0.85, 0.55, 0.3),  # бронзовые
}
const TIER_NAMES := {
	1: "ЛЕГЕНДАРНЫЕ", 2: "ПЛАТИНОВЫЕ", 3: "ЗОЛОТЫЕ", 4: "СЕРЕБРЯНЫЕ", 5: "БРОНЗОВЫЕ",
}
const TIER_Y := {1: 280.0, 2: 370.0, 3: 460.0, 4: 550.0, 5: 640.0}
const CROWN_POS := Vector2(640, 188)
const LOCKED_COLOR := Color(0.32, 0.33, 0.38)

const TOURNEY_SLOTS := [
	{"key": "school_cup", "name": "Школьный кубок"},
	{"key": "rapid_cup", "name": "Кубок рапида"},
	{"key": "blitz_arena", "name": "Блиц-арена"},
	{"key": "masters", "name": "Турнир мастеров"},
	{"key": "legends", "name": "Турнир легенд"},
	{"key": "daily", "name": "Кубки дня"},
]

var current_room := "ach"
var items: Array = [] # {pos, kind, color, unlocked, name, blurb, status, count}
var room_buttons: Array = []

func _ready() -> void:
	wall_draw.position.x = (get_viewport_rect().size.x - DESIGN_WIDTH) / 2.0
	wall_draw.draw.connect(_on_draw)
	detail_panel.visible = false
	_build_room_buttons()
	_build_items()

func _build_room_buttons() -> void:
	var bar = HBoxContainer.new()
	bar.theme = load("res://theme/NeonTheme.tres")
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 24
	bar.offset_top = 68
	bar.offset_right = -24
	bar.offset_bottom = 106
	bar.add_theme_constant_override("separation", 8)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	$UI.add_child(bar)
	for room in ROOMS:
		var b = Button.new()
		b.text = room.name
		b.custom_minimum_size = Vector2(150, 0)
		b.pressed.connect(_switch_room.bind(room.id))
		bar.add_child(b)
		room_buttons.append({"id": room.id, "btn": b})
	_update_room_buttons()

func _update_room_buttons() -> void:
	for rb in room_buttons:
		rb.btn.disabled = rb.id == current_room

func _switch_room(id: String) -> void:
	current_room = id
	detail_panel.visible = false
	_update_room_buttons()
	_build_items()
	wall_draw.queue_redraw()

func _room_def() -> Dictionary:
	for r in ROOMS:
		if r.id == current_room:
			return r
	return ROOMS[0]

# ------------------------------------------------------------------ items

func _build_items() -> void:
	items.clear()
	match current_room:
		"ach": _build_ach_items()
		"tourney": _build_tourney_items()
		"map": _build_map_items()
		"puzzles": _build_puzzle_items()
		"road": _build_road_items()
		"attention": _build_attention_items()

func _build_ach_items() -> void:
	var total = Profile.ACHIEVEMENTS.size()
	var have = Profile.achievement_count()
	var crown_unlocked = have >= total
	items.append({
		"pos": CROWN_POS, "kind": "crown",
		"color": Color(1.0, 0.85, 0.25), "unlocked": crown_unlocked,
		"name": "Корона Каиссы",
		"status": "✔ Получена! Вы — легенда этого зала." if crown_unlocked else "Ещё не получена (%d / %d достижений)" % [have, total],
		"blurb": "Самая престижная награда зала — корона Каиссы, богини шахмат. Достаётся тому, кто соберёт ВСЕ остальные награды на этой стене.",
		"count": 0,
	})
	var by_tier := {1: [], 2: [], 3: [], 4: [], 5: []}
	for a in Profile.ACHIEVEMENTS:
		by_tier[int(TIER_OF.get(a.id, 5))].append(a)
	for tier in by_tier:
		var list: Array = by_tier[tier]
		var n = list.size()
		if n == 0:
			continue
		var spacing = minf(96.0, 1080.0 / maxf(n, 1))
		var start_x = 640.0 - spacing * (n - 1) / 2.0
		for i in range(n):
			var a: Dictionary = list[i]
			var unlocked = Profile.unlocked_achievements.has(a.id)
			items.append({
				"pos": Vector2(start_x + spacing * i, TIER_Y[tier]),
				"kind": _shape_for(a.id),
				"color": TIER_COLORS[tier],
				"unlocked": unlocked,
				"name": a.name,
				"status": "✔ Получено!" if unlocked else "Ещё не получено",
				"blurb": "Как получить: %s." % a.desc,
				"count": 0,
			})

func _grid_positions(n: int) -> Array:
	# до 5 наград в ряд, ряды на «полках» комнаты
	var out := []
	var per_row = 5
	var rows = int(ceil(float(n) / per_row))
	for i in range(n):
		var row = i / per_row
		var in_row = mini(n - row * per_row, per_row)
		var idx = i % per_row
		var spacing = minf(220.0, 1120.0 / maxf(in_row, 1))
		var start_x = 640.0 - spacing * (in_row - 1) / 2.0
		var y = 330.0 + row * 210.0 if rows > 1 else 420.0
		out.append(Vector2(start_x + spacing * idx, y))
	return out

func _build_tourney_items() -> void:
	var pos = _grid_positions(TOURNEY_SLOTS.size())
	for i in range(TOURNEY_SLOTS.size()):
		var slot: Dictionary = TOURNEY_SLOTS[i]
		var wins = int(Profile.tournament_titles.get(slot.key, 0))
		var blurb: String
		if slot.key == "daily":
			blurb = "Кубки за победы в «Турнире дня». Каждый день — новый турнир, каждая победа — ещё один кубок."
		else:
			blurb = "Кубок за 1-е место в турнире «%s». Выиграйте его в разделе «Турниры»!" % slot.name
		items.append({
			"pos": pos[i], "kind": "cup", "color": Color(1.0, 0.8, 0.2),
			"unlocked": wins > 0, "name": slot.name,
			"status": ("✔ Выигран! Побед: %d" % wins) if wins > 0 else "Кубок ещё не выигран",
			"blurb": blurb, "count": wins,
		})

func _build_map_items() -> void:
	var boss_ids = {1: "king_magnus", 2: "king_magnus_2", 3: "king_magnus_3"}
	var pos = _grid_positions(3)
	for act in [1, 2, 3]:
		var total := 0
		var beaten := 0
		for c in MapData.CHARACTERS:
			if int(c.get("act", 1)) == act:
				total += 1
				if Profile.is_character_defeated(c.id):
					beaten += 1
		var unlocked = Profile.is_character_defeated(boss_ids[act])
		items.append({
			"pos": pos[act - 1], "kind": "shield",
			"color": [Color(0.55, 0.9, 0.35), Color(1.0, 0.8, 0.2), Color(1.0, 0.4, 0.85)][act - 1],
			"unlocked": unlocked,
			"name": "Акт %d: %s" % [act, MapData.ACT_NAMES[act]],
			"status": ("✔ Босс повержен! Остановок пройдено: %d / %d" % [beaten, total]) if unlocked else "Пройдено %d / %d — босс ещё держится" % [beaten, total],
			"blurb": "Щит за победу над боссом акта «%s» на карте шахматной страны." % MapData.ACT_NAMES[act],
			"count": 0,
		})

func _build_puzzle_items() -> void:
	var defs = [
		["Банк матов", Profile.solved_puzzles.size(), "Решайте задачи «Мат в 1-3 хода» из банка 50 задач."],
		["Вилка", Profile.fork_puzzles_solved, "Решайте задачи на вилку в разделе «Задачи»."],
		["Связка", Profile.pin_puzzles_solved, "Решайте задачи на связку."],
		["Последняя горизонталь", Profile.backrank_puzzles_solved, "Решайте задачи на мат по последней горизонтали."],
		["Уничтожение защиты", Profile.defense_puzzles_solved, "Решайте задачи на уничтожение защиты."],
		["Отвлечение", Profile.deflection_puzzles_solved, "Решайте задачи на отвлечение."],
		["Микс", Profile.mix_puzzles_solved, "Решайте задачи-микс без подсказки темы."],
	]
	var pos = _grid_positions(defs.size())
	for i in range(defs.size()):
		var d = defs[i]
		var cnt = int(d[1])
		var unlocked = cnt >= 10
		var col = Color(1.0, 0.8, 0.2) if cnt >= 50 else Color(0.1, 0.95, 1.0)
		items.append({
			"pos": pos[i], "kind": "star", "color": col,
			"unlocked": unlocked, "name": d[0],
			"status": ("✔ Решено: %d (золото с 50)" % cnt) if unlocked else "Решено %d / 10 до награды" % cnt,
			"blurb": "%s Звезда вручается за 10 решённых, золотая — за 50." % d[2],
			"count": cnt,
		})

func _build_road_items() -> void:
	var pos = _grid_positions(3)
	var road_done = Profile.road_stage >= 5
	items.append({
		"pos": pos[0], "kind": "cup", "color": Color(0.95, 0.8, 0.35),
		"unlocked": road_done, "name": "Дорога пройдена",
		"status": "✔ Все 5 остановок позади!" if road_done else "Пройдено остановок: %d / 5" % Profile.road_stage,
		"blurb": "Кубок за полное прохождение «Дороги домой» — включая победу над своей Тенью на пороге дома.",
		"count": 0,
	})
	items.append({
		"pos": pos[1], "kind": "diploma", "color": Color(0.3, 0.8, 0.95),
		"unlocked": Profile.road_blunders_fixed > 0, "name": "Работа над ошибками",
		"status": "Исправлено зевков: %d" % Profile.road_blunders_fixed,
		"blurb": "Грамота за исправление собственных зевков в «Овраге зевков». Каждый исправленный зевок делает вас сильнее!",
		"count": Profile.road_blunders_fixed,
	})
	var focus_n = Profile.road_focus_done.size()
	items.append({
		"pos": pos[2], "kind": "medal", "color": Color(0.6, 0.4, 0.9),
		"unlocked": focus_n > 0, "name": "Победитель слабостей",
		"status": "Пройдено тренировочных остановок: %d" % focus_n,
		"blurb": "Медаль за прохождение «выросших» остановок дороги — тех, что появляются из ваших слабых мест.",
		"count": focus_n,
	})

func _build_attention_items() -> void:
	var pos = _grid_positions(5)
	var names = ["Зоркий глаз", "Стража обороны", "Хищный взгляд", "Молниеносный взор", "Глаз-алмаз"]
	for i in range(5):
		var need = (i + 1) * 10
		var unlocked = Profile.attention_done >= need
		items.append({
			"pos": pos[i], "kind": "cup",
			"color": [Color(0.85, 0.55, 0.3), Color(0.8, 0.82, 0.88), Color(1.0, 0.8, 0.2), Color(0.75, 0.9, 1.0), Color(1.0, 0.4, 0.85)][i],
			"unlocked": unlocked, "name": "%s (ур. %d)" % [names[i], need],
			"status": "✔ Получен!" if unlocked else "Пройдено уровней: %d / %d" % [Profile.attention_done, need],
			"blurb": "Кубок за прохождение %d уровней режима «Внимательность». Уровни 41-50 — экзамен без подсказок и без зевков!" % need,
			"count": 0,
		})

func _shape_for(id: String) -> String:
	if id.begins_with("tourney") or id.begins_with("wins") or id == "first_win":
		return "cup"
	if id.begins_with("rating"):
		return "medal"
	if id.begins_with("map") or id.begins_with("act"):
		return "shield"
	if id.begins_with("streak") or id == "moves_good_50" or id.begins_with("mix"):
		return "star"
	return "diploma"

# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local = wall_draw.get_global_transform().affine_inverse() * event.position
		for it in items:
			if local.distance_to(it.pos) <= HIT_RADIUS:
				_show_detail(it)
				return
		detail_panel.visible = false

func _show_detail(it: Dictionary) -> void:
	detail_name.text = it.name
	detail_status.text = it.status
	detail_status.add_theme_color_override("font_color",
		Color(0.4, 0.95, 0.5) if it.unlocked else Color(0.85, 0.6, 0.3))
	detail_blurb.text = it.blurb
	detail_panel.visible = true

func _on_close_pressed() -> void:
	detail_panel.visible = false

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Achievements.tscn")

func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")

# ------------------------------------------------------------------ drawing

func _on_draw() -> void:
	var font = ThemeDB.fallback_font
	var room = _room_def()
	_draw_room(font, room)
	for it in items:
		var col: Color = it.color if it.unlocked else LOCKED_COLOR
		if current_room == "ach":
			match it.kind:
				"crown": _draw_crown(it.pos, col, it.unlocked)
				"cup": _draw_cup(it.pos, 1.0, col, it.unlocked)
				"medal": _draw_medal(it.pos, col, it.unlocked)
				"diploma": _draw_diploma(it.pos, col, it.unlocked)
				"star": _draw_star(it.pos, col)
				"shield": _draw_shield(it.pos, col)
		else:
			_draw_display(it, col, font)
		if not it.unlocked and it.kind != "crown" and current_room == "ach":
			_draw_padlock(it.pos + Vector2(16, 16))

func _draw_room(font: Font, room: Dictionary) -> void:
	var wall: Color = room.wall
	var accent: Color = room.accent
	# стена, пол, плинтус
	wall_draw.draw_rect(Rect2(40, 110, 1200, 580), wall)
	wall_draw.draw_rect(Rect2(40, 110, 1200, 580), Color(accent.r, accent.g, accent.b, 0.35), false, 3.0)
	for r in range(7):
		for c in range(20):
			wall_draw.draw_circle(Vector2(70 + c * 60, 150 + r * 80), 2.0, Color(1, 1, 1, 0.04))
	wall_draw.draw_rect(Rect2(40, 690, 1200, 80), Color(0.13, 0.09, 0.07))
	for i in range(12):
		wall_draw.draw_line(Vector2(40 + i * 100, 690), Vector2(40 + i * 100, 770), Color(0, 0, 0, 0.25), 2.0)
	wall_draw.draw_line(Vector2(40, 690), Vector2(1240, 690), Color(0.5, 0.38, 0.28, 0.8), 4.0)
	# название комнаты на стене
	wall_draw.draw_string(font, Vector2(0, 148), "— %s —" % str(room.name).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 1280, 17, Color(accent.r, accent.g, accent.b, 0.85))
	if current_room == "ach":
		# лампа над короной и полки
		var lamp = CROWN_POS + Vector2(0, -52)
		wall_draw.draw_circle(lamp, 7.0, Color(1, 0.9, 0.6))
		var cone = PackedVector2Array([lamp, CROWN_POS + Vector2(-70, 46), CROWN_POS + Vector2(70, 46)])
		wall_draw.draw_colored_polygon(cone, Color(1.0, 0.9, 0.5, 0.10))
		_draw_shelf_plank(Rect2(CROWN_POS.x - 90, CROWN_POS.y + 34, 180, 12))
		for tier in TIER_Y:
			var y: float = TIER_Y[tier] + 30.0
			_draw_shelf_plank(Rect2(90, y, 1100, 10))
			wall_draw.draw_string(font, Vector2(96, y + 26), TIER_NAMES[tier], HORIZONTAL_ALIGNMENT_LEFT, 300, 12, TIER_COLORS[tier] * Color(1, 1, 1, 0.75))
	else:
		# полки-подиумы под рядами наград
		var rows := {}
		for it in items:
			rows[snappedf(it.pos.y, 1.0)] = true
		for y in rows:
			_draw_shelf_plank(Rect2(120, y + 78, 1040, 12))

func _draw_shelf_plank(r: Rect2) -> void:
	wall_draw.draw_rect(r, Color(0.42, 0.3, 0.2))
	wall_draw.draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color(0.6, 0.45, 0.3))
	var y = r.position.y + r.size.y
	for x in [r.position.x + 24, r.end.x - 24]:
		wall_draw.draw_colored_polygon(PackedVector2Array([
			Vector2(x - 7, y), Vector2(x + 7, y), Vector2(x, y + 14)]), Color(0.3, 0.22, 0.15))

# универсальная «витрина» для тематических комнат: награда + постамент + имя
func _draw_display(it: Dictionary, col: Color, font: Font) -> void:
	var c: Vector2 = it.pos
	# постамент
	wall_draw.draw_rect(Rect2(c + Vector2(-30, 34), Vector2(60, 30)), Color(0.2, 0.16, 0.24))
	wall_draw.draw_rect(Rect2(c + Vector2(-35, 60), Vector2(70, 9)), Color(0.15, 0.12, 0.18))
	wall_draw.draw_rect(Rect2(c + Vector2(-30, 34), Vector2(60, 4)), Color(1, 1, 1, 0.08))
	match it.kind:
		"cup": _draw_cup(c, 1.35, col, it.unlocked)
		"medal": _draw_medal(c, col, it.unlocked)
		"diploma": _draw_diploma(c, col, it.unlocked)
		"star": _draw_star(c, col)
		"shield": _draw_shield(c, col)
	if not it.unlocked:
		_draw_padlock(c + Vector2(20, 18))
	if int(it.count) > 1:
		wall_draw.draw_string(font, c + Vector2(-35, 82), "×%d" % int(it.count), HORIZONTAL_ALIGNMENT_CENTER, 70, 13, Color(1, 0.8, 0.2))
	wall_draw.draw_multiline_string(font, c + Vector2(-75, 96), it.name, HORIZONTAL_ALIGNMENT_CENTER, 150, 12, 2, Color(0.85, 0.88, 0.95, 0.95) if it.unlocked else Color(0.5, 0.5, 0.55))

# --- фигурки наград ---

# Красивый кубок: сияние, чаша с градиентом, блик, гравировка-звезда,
# ручки в две дуги, ножка с шариком и двухступенчатое основание с табличкой.
func _draw_cup(c: Vector2, s: float, col: Color, unlocked: bool = true) -> void:
	var dark = col * Color(0.5, 0.5, 0.5)
	var mid = col * Color(0.78, 0.78, 0.78)
	if unlocked:
		for i in range(3, 0, -1):
			wall_draw.draw_circle(c + Vector2(0, -12) * s, (26.0 + i * 8.0) * s, Color(col.r, col.g, col.b, 0.045))
	# чаша — три яруса от светлого к тёмному
	wall_draw.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-17, -28) * s, c + Vector2(17, -28) * s,
		c + Vector2(15, -18) * s, c + Vector2(-15, -18) * s]), col)
	wall_draw.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-15, -18) * s, c + Vector2(15, -18) * s,
		c + Vector2(12, -8) * s, c + Vector2(-12, -8) * s]), mid)
	wall_draw.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-12, -8) * s, c + Vector2(12, -8) * s,
		c + Vector2(7, -1) * s, c + Vector2(-7, -1) * s]), dark)
	# ободок и блик
	wall_draw.draw_line(c + Vector2(-17, -28) * s, c + Vector2(17, -28) * s, Color(1, 1, 1, 0.5), 2.0 * s)
	wall_draw.draw_line(c + Vector2(-11, -25) * s, c + Vector2(-8, -10) * s, Color(1, 1, 1, 0.4), 2.2 * s)
	# гравировка-звезда на чаше
	var star_c = c + Vector2(3, -18) * s
	var star_pts := PackedVector2Array()
	for i in range(10):
		var ang = -PI / 2.0 + TAU * i / 10.0
		var rr = (4.6 if i % 2 == 0 else 2.0) * s
		star_pts.append(star_c + Vector2(cos(ang), sin(ang)) * rr)
	wall_draw.draw_colored_polygon(star_pts, Color(1, 1, 1, 0.55) if unlocked else Color(1, 1, 1, 0.18))
	# ручки — двойные дуги
	wall_draw.draw_arc(c + Vector2(-19, -19) * s, 8.5 * s, PI * 0.45, PI * 1.65, 12, col, 3.2 * s)
	wall_draw.draw_arc(c + Vector2(19, -19) * s, 8.5 * s, -PI * 0.65, PI * 0.55, 12, col, 3.2 * s)
	wall_draw.draw_arc(c + Vector2(-19, -19) * s, 5.5 * s, PI * 0.5, PI * 1.55, 10, dark, 1.6 * s)
	wall_draw.draw_arc(c + Vector2(19, -19) * s, 5.5 * s, -PI * 0.55, PI * 0.5, 10, dark, 1.6 * s)
	# ножка с шариком
	wall_draw.draw_rect(Rect2(c + Vector2(-2.5, -1) * s, Vector2(5, 9) * s), mid)
	wall_draw.draw_circle(c + Vector2(0, 10) * s, 3.4 * s, col)
	# двухступенчатое основание + табличка
	wall_draw.draw_rect(Rect2(c + Vector2(-11, 13) * s, Vector2(22, 5) * s), dark)
	wall_draw.draw_rect(Rect2(c + Vector2(-15, 18) * s, Vector2(30, 6) * s), dark * Color(0.8, 0.8, 0.8))
	wall_draw.draw_rect(Rect2(c + Vector2(-6, 19) * s, Vector2(12, 4) * s), Color(1, 0.9, 0.55, 0.8) if unlocked else Color(1, 1, 1, 0.12))

func _draw_medal(c: Vector2, col: Color, unlocked: bool = true) -> void:
	var ribbon_a = Color(0.85, 0.2, 0.3) if unlocked else LOCKED_COLOR * Color(0.8, 0.8, 0.8)
	var ribbon_b = Color(0.2, 0.35, 0.85) if unlocked else LOCKED_COLOR * Color(0.6, 0.6, 0.6)
	wall_draw.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-10, -28), c + Vector2(-2, -28), c + Vector2(2, -6), c + Vector2(-6, -6)]), ribbon_a)
	wall_draw.draw_colored_polygon(PackedVector2Array([
		c + Vector2(2, -28), c + Vector2(10, -28), c + Vector2(6, -6), c + Vector2(-2, -6)]), ribbon_b)
	wall_draw.draw_circle(c + Vector2(0, 6), 13.0, col)
	wall_draw.draw_arc(c + Vector2(0, 6), 13.0, 0, TAU, 24, col * Color(0.6, 0.6, 0.6), 2.0)
	wall_draw.draw_circle(c + Vector2(0, 6), 8.0, col * Color(0.7, 0.7, 0.7))
	wall_draw.draw_arc(c + Vector2(-4, 2), 5.0, PI, PI * 1.7, 8, Color(1, 1, 1, 0.5), 1.5)

func _draw_diploma(c: Vector2, col: Color, unlocked: bool = true) -> void:
	wall_draw.draw_rect(Rect2(c + Vector2(-16, -22), Vector2(32, 40)), col * Color(0.95, 0.92, 0.85))
	wall_draw.draw_rect(Rect2(c + Vector2(-16, -22), Vector2(32, 40)), col * Color(0.5, 0.5, 0.5), false, 2.0)
	for i in range(3):
		wall_draw.draw_line(c + Vector2(-10, -12 + i * 8), c + Vector2(10, -12 + i * 8), col * Color(0.45, 0.45, 0.45), 2.0)
	wall_draw.draw_circle(c + Vector2(8, 12), 5.0, Color(0.85, 0.2, 0.3) if unlocked else LOCKED_COLOR * Color(0.7, 0.7, 0.7))

func _draw_star(c: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(10):
		var ang = -PI / 2.0 + TAU * i / 10.0
		var r = 22.0 if i % 2 == 0 else 9.5
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
	wall_draw.draw_colored_polygon(pts, col)
	wall_draw.draw_polyline(pts + PackedVector2Array([pts[0]]), col * Color(0.6, 0.6, 0.6), 1.5)
	wall_draw.draw_circle(c, 5.0, col * Color(0.6, 0.6, 0.6))

func _draw_shield(c: Vector2, col: Color) -> void:
	var pts = PackedVector2Array([
		c + Vector2(-16, -20), c + Vector2(16, -20), c + Vector2(16, 4),
		c + Vector2(0, 22), c + Vector2(-16, 4)])
	wall_draw.draw_colored_polygon(pts, col)
	wall_draw.draw_polyline(pts + PackedVector2Array([pts[0]]), col * Color(0.5, 0.5, 0.5), 2.0)
	wall_draw.draw_line(c + Vector2(0, -20), c + Vector2(0, 22), Color(0, 0, 0, 0.2), 2.0)

func _draw_crown(c: Vector2, col: Color, unlocked: bool) -> void:
	if unlocked:
		for i in range(3, 0, -1):
			wall_draw.draw_circle(c, 26.0 + i * 10.0, Color(col.r, col.g, col.b, 0.05))
	var base = c + Vector2(0, 14)
	wall_draw.draw_colored_polygon(PackedVector2Array([
		base + Vector2(-26, 0), base + Vector2(26, 0),
		base + Vector2(26, -12), base + Vector2(17, -2), base + Vector2(13, -26),
		base + Vector2(6, -6), base + Vector2(0, -32),
		base + Vector2(-6, -6), base + Vector2(-13, -26),
		base + Vector2(-17, -2), base + Vector2(-26, -12)]), col)
	wall_draw.draw_rect(Rect2(base + Vector2(-26, 0), Vector2(52, 8)), col * Color(0.7, 0.7, 0.7))
	var gems = [Vector2(-13, -22), Vector2(0, -27), Vector2(13, -22)]
	var gem_col = Color(0.2, 0.9, 1.0) if unlocked else Color(0.2, 0.2, 0.25)
	for g in gems:
		wall_draw.draw_circle(base + g, 3.0, gem_col)
	wall_draw.draw_circle(base + Vector2(0, 4), 3.5, Color(0.85, 0.2, 0.3) if unlocked else Color(0.2, 0.2, 0.25))

func _draw_padlock(c: Vector2) -> void:
	wall_draw.draw_rect(Rect2(c + Vector2(-6, -3), Vector2(12, 10)), Color(0.15, 0.15, 0.18))
	wall_draw.draw_rect(Rect2(c + Vector2(-6, -3), Vector2(12, 10)), Color(0.55, 0.55, 0.6), false, 1.5)
	wall_draw.draw_arc(c + Vector2(0, -3), 4.5, PI, TAU, 10, Color(0.55, 0.55, 0.6), 1.5)
