extends Control

# «Награды» — галерея карточек. Сверху общий прогресс и корона Каиссы, ниже вкладки по разделам
# (Достижения, Турниры, Карта, Задачи, Дорога домой, Внимательность) со счётчиками. Каждая награда —
# карточка: медальон цвета её ранга, название, как получить и прогресс до неё. Всё видно сразу,
# без кликов по мелким значкам. Оформление (карточки, кнопки, полосы) берётся из выбранной темы.

const TABS := [
	{"id": "ach", "name": "Достижения"},
	{"id": "tourney", "name": "Турниры"},
	{"id": "map", "name": "Карта"},
	{"id": "puzzles", "name": "Задачи"},
	{"id": "road", "name": "Дорога домой"},
	{"id": "attention", "name": "Внимательность"},
]

# Ранг каждого достижения (1 — легендарное … 5 — бронзовое).
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
	1: Color(1.0, 0.74, 0.14),  # легендарные — горячее золото (с ореолом и лучами)
	2: Color(0.62, 0.85, 1.0),  # платиновые
	3: Color(0.93, 0.82, 0.46), # золотые — светлое шампанское
	4: Color(0.79, 0.81, 0.86), # серебряные
	5: Color(0.82, 0.55, 0.32), # бронзовые
}
const TIER_NAMES := {1: "Легендарная", 2: "Платиновая", 3: "Золотая", 4: "Серебряная", 5: "Бронзовая"}
const LOCKED_COLOR := Color(0.45, 0.46, 0.5)

const TOURNEY_SLOTS := [
	{"key": "school_cup", "name": "Школьный кубок"},
	{"key": "rapid_cup", "name": "Кубок рапида"},
	{"key": "blitz_arena", "name": "Блиц-арена"},
	{"key": "masters", "name": "Турнир мастеров"},
	{"key": "legends", "name": "Турнир легенд"},
	{"key": "daily", "name": "Кубки дня"},
]

var current_tab := "ach"
var _tab_buttons := {}
var _grid: HFlowContainer
var _summary_label: Label
var _summary_bar: ProgressBar
var _crown_label: Label
var _ci: CanvasItem # холст, на котором сейчас рисуется медальон

func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	# шапка: заголовок, общий прогресс, корона, кнопки
	var head := PanelContainer.new()
	root.add_child(head)
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 18)
	head.add_child(head_row)
	var crown := Control.new()
	crown.custom_minimum_size = Vector2(92, 92)
	var crown_item := _crown_item()
	crown.draw.connect(func(): _draw_badge(crown, crown_item, 36.0))
	head_row.add_child(crown)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	head_row.add_child(info)
	var title := Label.new()
	title.text = "Награды"
	title.add_theme_font_size_override("font_size", 30)
	info.add_child(title)
	_summary_label = Label.new()
	info.add_child(_summary_label)
	_summary_bar = ProgressBar.new()
	_summary_bar.show_percentage = false
	_summary_bar.custom_minimum_size = Vector2(0, 10)
	info.add_child(_summary_bar)
	_crown_label = Label.new()
	_crown_label.add_theme_font_size_override("font_size", 13)
	_crown_label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	_crown_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_crown_label)
	var buttons := VBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	head_row.add_child(buttons)
	var back := Button.new()
	back.name = "BackButton"
	back.text = "← Назад"
	back.custom_minimum_size = Vector2(150, 44)
	back.pressed.connect(func(): Global.go_back("res://scenes/Diary.tscn"))
	buttons.add_child(back)
	var menu := Button.new()
	menu.name = "HomeButton"
	menu.text = "В меню"
	menu.custom_minimum_size = Vector2(150, 44)
	menu.pressed.connect(func():
		Global.back_stack.clear()
		get_tree().change_scene_to_file("res://scenes/Menu.tscn"))
	buttons.add_child(menu)

	# вкладки
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 8)
	tabs.add_theme_constant_override("v_separation", 8)
	root.add_child(tabs)
	for t in TABS:
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 44)
		b.pressed.connect(_switch_tab.bind(t.id))
		tabs.add_child(b)
		_tab_buttons[t.id] = b

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(_grid)

	_update_summary()
	_switch_tab(current_tab)

func _update_summary() -> void:
	var have := 0
	var total := 0
	for t in TABS:
		var items := _items_for(t.id)
		var got := 0
		for it in items:
			if it.unlocked:
				got += 1
		have += got
		total += items.size()
		var b: Button = _tab_buttons[t.id]
		b.text = "%s  %d/%d" % [t.name, got, items.size()]
	_summary_label.text = "Получено наград: %d из %d" % [have, total]
	_summary_bar.max_value = maxi(total, 1)
	_summary_bar.value = have
	var c := _crown_item()
	_crown_label.text = "Корона Каиссы — %s" % c.status

func _switch_tab(id: String) -> void:
	current_tab = id
	for k in _tab_buttons:
		(_tab_buttons[k] as Button).set_pressed_no_signal(k == id)
	for ch in _grid.get_children():
		ch.queue_free()
	var items := _items_for(id)
	# полученные — первыми, внутри — по рангу
	items.sort_custom(func(a, b):
		if a.unlocked != b.unlocked:
			return a.unlocked
		return int(a.tier) < int(b.tier))
	for it in items:
		_grid.add_child(_card(it))

# ------------------------------------------------------------------ карточка

func _card(it: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(380, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if it.unlocked:
		var box := Themes.card_box()
		box.set_border_width_all(3 if int(it.tier) == 1 else 2)
		box.border_color = Color(it.color, 0.9)
		if int(it.tier) == 1:
			box.shadow_color = Color(it.color, 0.35)
			box.shadow_size = 12
		card.set_meta("themed", true) # рамка уже в цвете ранга — переводить не нужно
		card.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(96, 96)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	badge.draw.connect(func(): _draw_badge(badge, it, 38.0))
	row.add_child(badge)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	var tier := Label.new()
	tier.text = String(it.tier_name).to_upper()
	tier.add_theme_font_size_override("font_size", 11)
	tier.add_theme_color_override("font_color", it.color if it.unlocked else (it.color as Color).lerp(LOCKED_COLOR, 0.5))
	tier.set_meta("themed", true)
	col.add_child(tier)
	var title := Label.new()
	title.text = it.name
	title.add_theme_font_size_override("font_size", 18)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	var desc := Label.new()
	desc.text = it.blurb
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(desc)
	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", 10)
	col.add_child(status)
	if int(it.need) > 0 and not it.unlocked:
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = int(it.need)
		bar.value = mini(int(it.cur), int(it.need))
		bar.custom_minimum_size = Vector2(0, 8)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		status.add_child(bar)
	var st := Label.new()
	st.text = it.status
	st.add_theme_font_size_override("font_size", 13)
	st.add_theme_color_override("font_color", Color(0.4, 0.95, 0.5) if it.unlocked else Color(0.55, 0.6, 0.7))
	if int(it.need) <= 0 or it.unlocked:
		st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_child(st)
	return card

# ------------------------------------------------------------------ данные

func _item(kind: String, tier: int, unlocked: bool, title: String, blurb: String, status: String,
		cur: int = 0, need: int = 0, count: int = 0) -> Dictionary:
	return {"kind": kind, "tier": tier, "tier_name": TIER_NAMES[tier], "color": TIER_COLORS[tier],
		"unlocked": unlocked, "name": title, "blurb": blurb, "status": status,
		"cur": cur, "need": need, "count": count}

func _crown_item() -> Dictionary:
	var total = Profile.ACHIEVEMENTS.size()
	var have = Profile.achievement_count()
	var it := _item("crown", 1, have >= total, "Корона Каиссы",
		"Достаётся тому, кто соберёт все достижения.",
		"получена! Вы — легенда." if have >= total else "соберите все достижения (%d из %d)" % [have, total],
		have, total)
	it.color = Color(1.0, 0.82, 0.3)
	return it

func _items_for(tab: String) -> Array:
	match tab:
		"ach": return _ach_items()
		"tourney": return _tourney_items()
		"map": return _map_items()
		"puzzles": return _puzzle_items()
		"road": return _road_items()
		"attention": return _attention_items()
	return []

func _ach_items() -> Array:
	var out := []
	for a in Profile.ACHIEVEMENTS:
		var unlocked = Profile.unlocked_achievements.has(a.id)
		out.append(_item(_shape_for(a.id), int(TIER_OF.get(a.id, 5)), unlocked, a.name,
			"%s." % a.desc, "✔ Получено" if unlocked else "Ещё не получено"))
	return out

func _tourney_items() -> Array:
	var out := []
	var tiers := {"school_cup": 5, "rapid_cup": 4, "blitz_arena": 3, "masters": 2, "legends": 1, "daily": 3}
	for slot in TOURNEY_SLOTS:
		var wins = int(Profile.tournament_titles.get(slot.key, 0))
		var blurb: String
		if slot.key == "daily":
			blurb = "Кубки за победы в «Турнире дня». Каждый день — новый турнир, каждая победа — ещё кубок."
		else:
			blurb = "Займите 1-е место в турнире «%s» (раздел «Турниры»)." % slot.name
		out.append(_item("cup", int(tiers[slot.key]), wins > 0, slot.name, blurb,
			("✔ Выигран · побед: %d" % wins) if wins > 0 else "Кубок ещё не выигран", wins, 1, wins))
	return out

func _map_items() -> Array:
	var out := []
	var boss_ids = {1: "king_magnus", 2: "king_magnus_2", 3: "king_magnus_3"}
	for act in [1, 2, 3]:
		var total := 0
		var beaten := 0
		for c in MapData.CHARACTERS:
			if int(c.get("act", 1)) == act:
				total += 1
				if Profile.is_character_defeated(c.id):
					beaten += 1
		var unlocked = Profile.is_character_defeated(boss_ids[act])
		out.append(_item("shield", [4, 3, 1][act - 1], unlocked, "Акт %d: %s" % [act, MapData.ACT_NAMES[act]],
			"Победите босса акта на карте шахматной страны.",
			("✔ Босс повержен · пройдено %d из %d" % [beaten, total]) if unlocked else "Пройдено %d из %d" % [beaten, total],
			beaten, total))
	return out

func _puzzle_items() -> Array:
	var defs = [
		["Банк матов", Profile.solved_puzzles.size(), "Задачи «Мат в 1–3 хода»."],
		["Вилка", Profile.fork_puzzles_solved, "Задачи на вилку."],
		["Связка", Profile.pin_puzzles_solved, "Задачи на связку."],
		["Последняя горизонталь", Profile.backrank_puzzles_solved, "Мат по последней горизонтали."],
		["Уничтожение защиты", Profile.defense_puzzles_solved, "Задачи на уничтожение защиты."],
		["Отвлечение", Profile.deflection_puzzles_solved, "Задачи на отвлечение."],
		["Микс", Profile.mix_puzzles_solved, "Задачи без подсказки темы."],
	]
	var out := []
	for d in defs:
		var cnt = int(d[1])
		var gold = cnt >= 50
		var need = 50 if cnt >= 10 else 10
		var status := "✔ Золотая звезда · решено %d" % cnt if gold else ("Решено %d из %d" % [cnt, need])
		out.append(_item("star", 3 if gold else 4, cnt >= 10, d[0],
			"%s Звезда — за 10 решённых, золотая — за 50." % d[2], status if cnt < 10 or gold else "✔ Звезда · до золотой %d из 50" % cnt,
			cnt, need, cnt))
	return out

func _road_items() -> Array:
	var out := []
	var focus_n = Profile.road_focus_done.size()
	out.append(_item("cup", 2, Profile.road_stage >= 5, "Дорога пройдена",
		"Пройдите все 5 остановок «Дороги домой» и победите свою Тень.",
		"✔ Все остановки позади" if Profile.road_stage >= 5 else "Остановок %d из 5" % Profile.road_stage,
		Profile.road_stage, 5))
	out.append(_item("diploma", 4, Profile.road_blunders_fixed > 0, "Работа над ошибками",
		"Исправьте свой зевок в «Овраге зевков» — каждый исправленный делает сильнее.",
		("✔ Исправлено зевков: %d" % Profile.road_blunders_fixed) if Profile.road_blunders_fixed > 0 else "Пока нет исправленных зевков",
		Profile.road_blunders_fixed, 1, Profile.road_blunders_fixed))
	out.append(_item("medal", 3, focus_n > 0, "Победитель слабостей",
		"Пройдите остановку, выросшую из ваших слабых мест.",
		("✔ Пройдено: %d" % focus_n) if focus_n > 0 else "Пока не пройдено ни одной",
		focus_n, 1, focus_n))
	return out

func _attention_items() -> Array:
	var out := []
	var names = ["Зоркий глаз", "Стража обороны", "Хищный взгляд", "Молниеносный взор", "Глаз-алмаз"]
	for i in range(5):
		var need = (i + 1) * 10
		var unlocked = Profile.attention_done >= need
		out.append(_item("cup", 5 - i, unlocked, names[i],
			"Пройдите %d уровней «Внимательности».%s" % [need, " Последние — экзамен без подсказок!" if i == 4 else ""],
			"✔ Получен" if unlocked else "Уровней %d из %d" % [mini(Profile.attention_done, need), need],
			Profile.attention_done, need))
	return out

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

# ------------------------------------------------------------------ медальон

# Круглый медальон: объёмное кольцо цвета ранга, тёмная «линза» внутри, блик, фигурка награды.
# У легендарных — сияющий ореол, лучи и искры; у остальных полученных — мягкое свечение.
# Неполученные — приглушённые, с маленьким замком.
func _draw_badge(ci: Control, it: Dictionary, radius: float) -> void:
	_ci = ci
	var c := ci.size / 2.0
	var legendary: bool = int(it.tier) == 1 and it.unlocked
	# неполученная — приглушённый цвет ранга: видно, что за награда ждёт
	var col: Color = it.color if it.unlocked else (it.color as Color).lerp(LOCKED_COLOR, 0.6)
	if it.unlocked:
		var glow_n := 7 if legendary else 4
		for i in range(glow_n, 0, -1):
			ci.draw_circle(c, radius + i * (1.5 if legendary else 2.4), Color(col, 0.07 if legendary else 0.05))
	if legendary:
		_draw_rays(c, radius, col)
	# кольцо: тёмная кайма, цветной обод, светлая кромка сверху-слева
	ci.draw_circle(c, radius + 1.0, col.darkened(0.7))
	ci.draw_circle(c, radius - 0.5, col.darkened(0.25))
	ci.draw_circle(c, radius - 3.5, col)
	ci.draw_arc(c, radius - 2.5, PI * 0.95, PI * 1.55, 20, col.lightened(0.55), 2.2, true)
	ci.draw_circle(c, radius - 7.0, col.darkened(0.55))
	# «линза»: тёмный диск с чуть более светлой серединой
	ci.draw_circle(c, radius - 8.0, col.darkened(0.8))
	ci.draw_circle(c + Vector2(-1.5, -2.0), radius - 14.0, col.darkened(0.72))
	ci.draw_arc(c, radius - 9.5, 0, TAU, 48, Color(col, 0.4), 1.0, true)
	# бусинки по ободу — у золотых и выше
	if int(it.tier) <= 3:
		for i in range(16):
			var ang := TAU * i / 16.0
			ci.draw_circle(c + Vector2(cos(ang), sin(ang)) * (radius - 5.2), 1.0, col.lightened(0.5) if it.unlocked else Color(col, 0.7))
	var icon_col := col.lightened(0.28) if it.unlocked else Color(col, 0.75)
	var k := radius / 38.0
	ci.draw_set_transform(c, 0.0, Vector2(k, k))
	match it.kind:
		"crown": _draw_crown(Vector2(0, -2), icon_col, it.unlocked)
		"cup": _draw_cup(Vector2(0, 4), 1.0, icon_col, it.unlocked)
		"medal": _draw_medal(Vector2(0, 0), icon_col, it.unlocked)
		"diploma": _draw_diploma(Vector2(0, 0), icon_col, it.unlocked)
		"star": _draw_star(Vector2(0, 0), icon_col)
		"shield": _draw_shield(Vector2(0, 0), icon_col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if legendary:
		for sp in [[Vector2(-0.82, -0.72), 5.5], [Vector2(0.86, -0.55), 4.0], [Vector2(0.7, 0.82), 3.2]]:
			_draw_sparkle(c + (sp[0] as Vector2) * radius, float(sp[1]), Color(1.0, 0.97, 0.8))
	if not it.unlocked:
		_draw_padlock(c + Vector2(radius * 0.62, radius * 0.62))
	if int(it.count) > 1:
		var font := Themes.font_bold()
		var chip := Rect2(c + Vector2(radius * 0.25, -radius - 2.0), Vector2(30, 18))
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(9)
		sb.draw(ci.get_canvas_item(), chip)
		ci.draw_string(font, chip.position + Vector2(0, 14), "×%d" % int(it.count), HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, 12, col.darkened(0.75))

# Лучи вокруг легендарного медальона: длинные и короткие вперемешку.
func _draw_rays(c: Vector2, radius: float, col: Color) -> void:
	var n := 24
	for i in range(n):
		var ang := TAU * i / n
		var length := 9.5 if i % 2 == 0 else 5.0
		var dir := Vector2(cos(ang), sin(ang))
		var side := Vector2(-dir.y, dir.x)
		var base := c + dir * (radius - 1.0)
		_ci.draw_colored_polygon(PackedVector2Array([
			base + side * 2.6, c + dir * (radius + length), base - side * 2.6]),
			Color(col.lightened(0.25), 0.8 if i % 2 == 0 else 0.5))

# Четырёхконечная искра.
func _draw_sparkle(c: Vector2, r: float, col: Color) -> void:
	_ci.draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r * 0.22, -r * 0.22), c + Vector2(r, 0), c + Vector2(r * 0.22, r * 0.22),
		c + Vector2(0, r), c + Vector2(-r * 0.22, r * 0.22), c + Vector2(-r, 0), c + Vector2(-r * 0.22, -r * 0.22)]), col)

# --- фигурки наград (рисуются на _ci в координатах медальона; свет падает сверху-слева) ---

func _star_points(c: Vector2, outer: float, inner: float, turn: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(10):
		var ang := -PI / 2.0 + turn + TAU * i / 10.0
		var rr := outer if i % 2 == 0 else inner
		pts.append(c + Vector2(cos(ang), sin(ang)) * rr)
	return pts

# Граненая пятиконечная звезда: каждый луч — светлая и тёмная половинки.
func _draw_facet_star(c: Vector2, outer: float, inner: float, col: Color) -> void:
	var pts := _star_points(c, outer, inner)
	for i in range(0, 10, 2):
		var tip := pts[i]
		var prev := pts[(i + 9) % 10]
		var nxt := pts[(i + 1) % 10]
		_ci.draw_colored_polygon(PackedVector2Array([c, prev, tip]), col.lightened(0.28))
		_ci.draw_colored_polygon(PackedVector2Array([c, tip, nxt]), col.darkened(0.22))
	_ci.draw_polyline(pts + PackedVector2Array([pts[0]]), col.darkened(0.5), 1.2, true)

func _draw_cup(c: Vector2, s: float, col: Color, unlocked: bool = true) -> void:
	var lt := col.lightened(0.38)
	var dk := col.darkened(0.3)
	var dd := col.darkened(0.55)
	# ручки
	_ci.draw_arc(c + Vector2(-17, -17) * s, 8.0 * s, PI * 0.5, PI * 1.5, 14, dk, 3.4 * s, true)
	_ci.draw_arc(c + Vector2(17, -17) * s, 8.0 * s, -PI * 0.5, PI * 0.5, 14, dk, 3.4 * s, true)
	_ci.draw_arc(c + Vector2(-17, -17) * s, 8.0 * s, PI * 0.6, PI * 1.2, 8, lt, 1.4 * s, true)
	# чаша: левая половина светлее, правая темнее — получается объём
	var left := PackedVector2Array([c + Vector2(0, -28) * s])
	var right := PackedVector2Array([c + Vector2(0, -28) * s])
	for i in range(9):
		var t := i / 8.0
		var w := 17.0 * (1.0 - 0.6 * pow(t, 1.5))
		var y := -28.0 + t * 27.0
		left.append(c + Vector2(-w, y) * s)
		right.append(c + Vector2(w, y) * s)
	left.append(c + Vector2(0, -1) * s)
	right.append(c + Vector2(0, -1) * s)
	_ci.draw_colored_polygon(left, col.lightened(0.12))
	_ci.draw_colored_polygon(right, dk)
	# ободок и тёмное «горлышко»
	_ci.draw_colored_polygon(_ellipse(c + Vector2(0, -28) * s, 17.0 * s, 3.4 * s), lt)
	_ci.draw_colored_polygon(_ellipse(c + Vector2(0, -27.6) * s, 14.6 * s, 2.3 * s), dd)
	# блик на левом боку и знак-звезда на чаше
	_ci.draw_line(c + Vector2(-12, -23) * s, c + Vector2(-9, -9) * s, Color(1, 1, 1, 0.55), 2.2 * s, true)
	_ci.draw_colored_polygon(_star_points(c + Vector2(2, -14) * s, 5.0 * s, 2.2 * s), Color(1, 1, 1, 0.7) if unlocked else Color(1, 1, 1, 0.2))
	# ножка, узел, подставка
	_ci.draw_rect(Rect2(c + Vector2(-2.6, -1) * s, Vector2(2.6, 10) * s), col)
	_ci.draw_rect(Rect2(c + Vector2(0, -1) * s, Vector2(2.6, 10) * s), dk)
	_ci.draw_circle(c + Vector2(0, 10) * s, 3.6 * s, col)
	_ci.draw_circle(c + Vector2(-1, 9) * s, 1.4 * s, lt)
	_ci.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-10, 13) * s, c + Vector2(10, 13) * s, c + Vector2(13, 19) * s, c + Vector2(-13, 19) * s]), col)
	_ci.draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, 13) * s, c + Vector2(10, 13) * s, c + Vector2(13, 19) * s, c + Vector2(0, 19) * s]), dk)
	_ci.draw_rect(Rect2(c + Vector2(-16, 19) * s, Vector2(32, 5) * s), dd)
	_ci.draw_rect(Rect2(c + Vector2(-16, 19) * s, Vector2(32, 1.6) * s), lt)

func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(24):
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

func _draw_medal(c: Vector2, col: Color, unlocked: bool = true) -> void:
	var ribbon_a := Color(0.86, 0.22, 0.3) if unlocked else Color(col, 0.6)
	var ribbon_b := Color(0.22, 0.38, 0.86) if unlocked else Color(col * Color(0.7, 0.7, 0.7), 0.6)
	# лента: два полотна «галочкой» и складка
	_ci.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-12, -27), c + Vector2(-1, -27), c + Vector2(4, -4), c + Vector2(-8, -4)]), ribbon_a)
	_ci.draw_colored_polygon(PackedVector2Array([
		c + Vector2(1, -27), c + Vector2(12, -27), c + Vector2(8, -4), c + Vector2(-4, -4)]), ribbon_b)
	_ci.draw_line(c + Vector2(-1, -27), c + Vector2(4, -4), Color(0, 0, 0, 0.25), 1.2)
	# диск медали: обод, фаска, звезда посередине
	var m := c + Vector2(0, 8)
	_ci.draw_circle(m, 16.0, col.darkened(0.45))
	_ci.draw_circle(m, 14.8, col)
	_ci.draw_arc(m, 13.0, PI * 0.9, PI * 1.6, 12, col.lightened(0.6), 2.0, true)
	_ci.draw_circle(m, 10.5, col.darkened(0.22))
	_draw_facet_star(m, 8.6, 3.6, col.lightened(0.15))

func _draw_diploma(c: Vector2, col: Color, unlocked: bool = true) -> void:
	var paper := col.lerp(Color(1, 0.98, 0.9), 0.72)
	var edge := col.darkened(0.35)
	# развёрнутый свиток: бумага и два валика
	_ci.draw_rect(Rect2(c + Vector2(-14, -19), Vector2(28, 38)), paper)
	_ci.draw_rect(Rect2(c + Vector2(-14, -19), Vector2(6, 38)), Color(0, 0, 0, 0.07))
	_ci.draw_rect(Rect2(c + Vector2(-14, -19), Vector2(28, 38)), edge, false, 1.4)
	for r in [-22.0, 16.0]:
		_ci.draw_rect(Rect2(c + Vector2(-18, r), Vector2(36, 6)), col)
		_ci.draw_rect(Rect2(c + Vector2(-18, r), Vector2(36, 2)), col.lightened(0.45))
		_ci.draw_circle(c + Vector2(-18, r + 3), 3.4, edge)
		_ci.draw_circle(c + Vector2(18, r + 3), 3.4, edge)
	# строки текста и звёздочка-заглавие
	_ci.draw_colored_polygon(_star_points(c + Vector2(0, -11), 4.2, 1.8), edge)
	for i in range(3):
		_ci.draw_line(c + Vector2(-8, -3 + i * 5.5), c + Vector2(8 - (i % 2) * 4, -3 + i * 5.5), edge, 1.6)
	# сургучная печать с ленточками
	var seal := Color(0.86, 0.22, 0.3) if unlocked else col.darkened(0.2)
	_ci.draw_colored_polygon(PackedVector2Array([c + Vector2(5, 14), c + Vector2(9, 14), c + Vector2(5, 24), c + Vector2(2, 20)]), seal.darkened(0.2))
	_ci.draw_colored_polygon(PackedVector2Array([c + Vector2(8, 14), c + Vector2(12, 14), c + Vector2(13, 22), c + Vector2(9, 24)]), seal.darkened(0.35))
	_ci.draw_circle(c + Vector2(8, 11), 5.4, seal)
	_ci.draw_circle(c + Vector2(6.8, 9.8), 1.8, Color(1, 1, 1, 0.45))

func _draw_star(c: Vector2, col: Color) -> void:
	_draw_facet_star(c, 25.0, 10.5, col)
	_ci.draw_circle(c, 3.6, col.lightened(0.45))

func _draw_shield(c: Vector2, col: Color) -> void:
	var pts := PackedVector2Array([
		c + Vector2(-17, -21), c + Vector2(17, -21), c + Vector2(17, 1), c + Vector2(14, 12),
		c + Vector2(7, 19), c + Vector2(0, 24), c + Vector2(-7, 19), c + Vector2(-14, 12), c + Vector2(-17, 1)])
	_ci.draw_colored_polygon(pts, col.darkened(0.4))
	# левая половина светлая, правая тёмная
	var lh := PackedVector2Array([c + Vector2(0, -18), c + Vector2(-14, -18), c + Vector2(-14, 0), c + Vector2(-11.5, 10), c + Vector2(-5.5, 16), c + Vector2(0, 20)])
	var rh := PackedVector2Array([c + Vector2(0, -18), c + Vector2(14, -18), c + Vector2(14, 0), c + Vector2(11.5, 10), c + Vector2(5.5, 16), c + Vector2(0, 20)])
	_ci.draw_colored_polygon(lh, col.lightened(0.15))
	_ci.draw_colored_polygon(rh, col.darkened(0.12))
	_ci.draw_polyline(pts + PackedVector2Array([pts[0]]), col.lightened(0.35), 1.6, true)
	# эмблема: звезда на щите
	_ci.draw_colored_polygon(_star_points(c + Vector2(0, -1), 8.5, 3.6), Color(1, 1, 1, 0.82))

func _draw_crown(c: Vector2, col: Color, unlocked: bool) -> void:
	var base := c + Vector2(0, 14)
	var pts := PackedVector2Array([
		base + Vector2(-26, 0), base + Vector2(26, 0),
		base + Vector2(26, -12), base + Vector2(17, -2), base + Vector2(13, -26),
		base + Vector2(6, -6), base + Vector2(0, -32),
		base + Vector2(-6, -6), base + Vector2(-13, -26),
		base + Vector2(-17, -2), base + Vector2(-26, -12)])
	_ci.draw_colored_polygon(pts, col)
	# правая половина темнее — объём
	_ci.draw_colored_polygon(PackedVector2Array([
		base + Vector2(0, 0), base + Vector2(26, 0), base + Vector2(26, -12), base + Vector2(17, -2),
		base + Vector2(13, -26), base + Vector2(6, -6), base + Vector2(0, -32)]), col.darkened(0.2))
	_ci.draw_polyline(pts + PackedVector2Array([pts[0]]), col.lightened(0.4), 1.2, true)
	_ci.draw_rect(Rect2(base + Vector2(-26, 0), Vector2(52, 8)), col.darkened(0.3))
	_ci.draw_rect(Rect2(base + Vector2(-26, 0), Vector2(52, 1.8)), col.lightened(0.5))
	var gem_col := Color(0.3, 0.85, 1.0) if unlocked else Color(1, 1, 1, 0.25)
	for g in [Vector2(-13, -22), Vector2(0, -27), Vector2(13, -22)]:
		_ci.draw_circle(base + g, 3.2, gem_col)
		_ci.draw_circle(base + g + Vector2(-0.8, -0.8), 1.1, Color(1, 1, 1, 0.8 if unlocked else 0.2))
	for g in [Vector2(-18, 4), Vector2(-6, 4), Vector2(6, 4), Vector2(18, 4)]:
		_ci.draw_circle(base + g, 2.0, Color(0.86, 0.22, 0.3) if unlocked else Color(1, 1, 1, 0.25))

func _draw_padlock(c: Vector2) -> void:
	_ci.draw_circle(c, 11.0, Color(0.12, 0.12, 0.14, 0.95))
	_ci.draw_rect(Rect2(c + Vector2(-5, -2), Vector2(10, 8)), Color(0.85, 0.86, 0.9))
	_ci.draw_arc(c + Vector2(0, -2), 3.8, PI, TAU, 10, Color(0.85, 0.86, 0.9), 1.6)
