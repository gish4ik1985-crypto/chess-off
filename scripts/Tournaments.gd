extends Control

# Турниры против ИИ: 8 участников (игрок + 7 именованных ботов), швейцарская
# рассадка по очкам, отдельный турнирный рейтинг Glicko-2 (Profile.tournament_
# rating). Постоянные турниры доступны всегда (сильные — по мере роста
# рейтинга), плюс «Турнир дня»: каждый день новый формат и новое поле
# соперников, живёт ровно один день. Сила ботов подстраивается под турнирный
# рейтинг игрока в пределах диапазона конкретного турнира, так что с ростом
# рейтинга соперники становятся сильнее даже в том же самом турнире.

@onready var rating_label: Label = $TopBar/HBox/RatingLabel
@onready var list_vbox: VBoxContainer = $Main/ListScroll/ListVBox
@onready var detail_panel: PanelContainer = $Main/DetailPanel
@onready var detail_name: Label = $Main/DetailPanel/VBox/NameLabel
@onready var detail_info: Label = $Main/DetailPanel/VBox/InfoLabel
@onready var detail_table: Label = $Main/DetailPanel/VBox/TableLabel
@onready var play_button: Button = $Main/DetailPanel/VBox/PlayButton

# Постоянные турниры. band — допустимые уровни ИИ [min, max]: реальная сила
# поля берётся из турнирного рейтинга игрока и зажимается в этот диапазон.
const STANDING := [
	{
		"id": "school_cup", "name": "Школьный кубок", "format": "Классика (без часов)",
		"tc": 0, "inc": 0, "rounds": 3, "band": [1, 6], "min_rating": 0,
		"desc": "Дружеский турнир без часов — думайте сколько хотите. Три тура, соперники попроще. Отличное место, чтобы заработать первый турнирный рейтинг.",
	},
	{
		"id": "rapid_cup", "name": "Кубок рапида", "format": "Рапид 10+5",
		"tc": 600, "inc": 5, "rounds": 4, "band": [3, 10], "min_rating": 0,
		"desc": "10 минут на партию и +5 секунд за каждый ход. Четыре тура. Здесь уже нельзя засыпать над доской!",
	},
	{
		"id": "blitz_arena", "name": "Блиц-арена", "format": "Блиц 3+2",
		"tc": 180, "inc": 2, "rounds": 5, "band": [6, 14], "min_rating": 1000,
		"desc": "3 минуты и +2 секунды за ход. Пять туров молниеносных партий. Открывается с турнирного рейтинга 1000.",
	},
	{
		"id": "masters", "name": "Турнир мастеров", "format": "Рапид 15+10",
		"tc": 900, "inc": 10, "rounds": 4, "band": [10, 18], "min_rating": 1250,
		"desc": "Серьёзный контроль, серьёзные соперники. Четыре тура. Открывается с турнирного рейтинга 1250.",
	},
	{
		"id": "legends", "name": "Турнир легенд", "format": "Блиц 5+3",
		"tc": 300, "inc": 3, "rounds": 5, "band": [14, 25], "min_rating": 1450,
		"desc": "Поле из машин и титанов, пять туров быстрой игры. Только для тех, чей турнирный рейтинг перевалил за 1450.",
	},
]

# День недели -> формат турнира дня (Time weekday: 0 = воскресенье).
const DAILY_FORMATS := [
	{"name": "Воскресная классика", "format": "Классика (без часов)", "tc": 0, "inc": 0, "rounds": 3},
	{"name": "Блиц-понедельник", "format": "Блиц 3+2", "tc": 180, "inc": 2, "rounds": 4},
	{"name": "Рапид-вторник", "format": "Рапид 10+5", "tc": 600, "inc": 5, "rounds": 3},
	{"name": "Классическая среда", "format": "Классика (без часов)", "tc": 0, "inc": 0, "rounds": 3},
	{"name": "Молниеносный четверг", "format": "Блиц 3+2", "tc": 180, "inc": 2, "rounds": 4},
	{"name": "Пятничный рапид", "format": "Рапид 10+5", "tc": 600, "inc": 5, "rounds": 3},
	{"name": "Субботний марафон", "format": "Рапид 10+5", "tc": 600, "inc": 5, "rounds": 6},
]

var selected_def: Dictionary = {}

func _ready() -> void:
	Profile.prune_daily_tournaments(_daily_id())
	_update_rating_label()
	_build_list()
	detail_panel.visible = false

func _update_rating_label() -> void:
	rating_label.text = "Турнирный рейтинг: %d (%s) · Кубков: %d" % [
		round(Profile.tournament_rating), Profile.title_for_rating(Profile.tournament_rating), Profile.tournaments_won]

func _daily_id() -> String:
	return "daily_" + Time.get_date_string_from_system()

# Definition of today's daily event — deterministic from the date, so the
# player sees the same tournament all day and a fresh one tomorrow.
func _daily_def() -> Dictionary:
	var weekday = Time.get_datetime_dict_from_system().weekday
	var f: Dictionary = DAILY_FORMATS[weekday % DAILY_FORMATS.size()]
	var lvl = _level_for_rating(Profile.tournament_rating)
	return {
		"id": _daily_id(),
		"name": "🔥 Турнир дня: %s" % f.name,
		"format": f.format,
		"tc": f.tc, "inc": f.inc, "rounds": f.rounds,
		"band": [clampi(lvl - 3, 1, 25), clampi(lvl + 3, 1, 25)],
		"min_rating": 0,
		"desc": "Каждый день — новый турнир! Сегодня: %s, %d туров. Поле соперников подобрано под твой турнирный рейтинг. Завтра будет другой — не пропусти этот." % [f.format, f.rounds],
		"daily": true,
	}

func _build_list() -> void:
	for c in list_vbox.get_children():
		c.queue_free()
	var defs := [_daily_def()]
	defs.append_array(STANDING)
	for def in defs:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 52)
		var locked = Profile.tournament_rating < def.min_rating
		var status := ""
		var state = Profile.active_tournaments.get(def.id, {})
		if not state.is_empty():
			if state.get("done", false):
				status = "  · 🏆 1-е место!" if state.get("won", false) else "  · сыгран (%d-е место)" % Profile.tournament_place(state)
			else:
				status = "  · идёт: тур %d/%d" % [int(state.round) + 1, int(state.rounds)]
		if locked:
			b.text = "🔒 %s — с рейтинга %d" % [def.name, def.min_rating]
			b.disabled = true
		else:
			b.text = "%s · %s%s" % [def.name, def.format, status]
		b.pressed.connect(_on_tournament_selected.bind(def))
		list_vbox.add_child(b)

func _level_for_rating(r: float) -> int:
	var lvl := 1
	for i in range(Profile.LEVEL_RATING.size()):
		if r >= float(Profile.LEVEL_RATING[i]) - 100.0:
			lvl = i + 1
	return lvl

# Состав турнира — 7 постоянных соперников из «Базы игроков» (BotData),
# отобранных по лиге игрока. Уровень ИИ каждого берётся из его собственного
# рейтинга и лишь зажимается диапазоном турнира, поэтому выросший бот и
# играет сильнее, чем в прошлый раз.
func _new_state(def: Dictionary) -> Dictionary:
	var field: Array = Profile.pick_tournament_field(7)
	var bots := []
	for rec in field:
		bots.append({
			"id": rec.id,
			"name": rec.name,
			"level": clampi(int(rec.level), def.band[0], def.band[1]),
			"rating": int(round(float(rec.rating))),
			"score": 0.0,
		})
	return {
		"id": def.id, "name": def.name, "format": def.format,
		"tc": def.tc, "inc": def.inc, "rounds": def.rounds,
		"round": 0, "my_score": 0.0, "my_played": [], "bots": bots,
		"done": false, "won": false, "bot_pairs": {},
	}

func _on_tournament_selected(def: Dictionary) -> void:
	selected_def = def
	detail_name.text = def.name
	var state = Profile.active_tournaments.get(def.id, {})
	var info = "%s · %d туров · 8 участников\n\n%s" % [def.format, def.rounds, def.desc]
	if state.is_empty():
		detail_table.text = ""
		play_button.text = "Записаться и играть!"
		play_button.visible = true
	elif state.get("done", false):
		var place = Profile.tournament_place(state)
		info += "\n\nТурнир завершён — ваше место: %d из 8." % place
		if state.get("won", false):
			info += " 🏆 Поздравляем с победой!"
		detail_table.text = _standings_text(state)
		if def.get("daily", false):
			play_button.visible = false # завтра будет новый
			info += "\nНовый турнир дня — завтра!"
		else:
			play_button.text = "Сыграть заново"
			play_button.visible = true
	else:
		info += "\n\nИдёт тур %d из %d. Ваши очки: %s." % [int(state.round) + 1, int(state.rounds), _fmt_score(state.my_score)]
		detail_table.text = _standings_text(state)
		play_button.text = "Играть тур %d" % (int(state.round) + 1)
		play_button.visible = true
	detail_info.text = info
	detail_panel.visible = true

func _fmt_score(s: float) -> String:
	return ("%.1f" % s).replace(".0", "")

func _standings_text(state: Dictionary) -> String:
	var rows := [{"name": "⭐ " + Profile.display_name, "score": float(state.my_score), "me": true}]
	for bt in state.bots:
		var label = "%s (%d)" % [bt.name, int(bt.get("rating", 0))] if bt.has("rating") else "%s (ур. %d)" % [bt.name, bt.level]
		rows.append({"name": label, "score": float(bt.score), "me": false})
	rows.sort_custom(func(a, b): return a.score > b.score)
	var txt := "Положение:\n"
	for i in range(rows.size()):
		txt += "%d. %s — %s\n" % [i + 1, rows[i].name, _fmt_score(rows[i].score)]
	return txt

# Swiss-ish pairing: the not-yet-played bot with the score closest to the
# player's; ties broken by list order.
func _pick_opponent(state: Dictionary) -> int:
	var best := -1
	var best_diff := INF
	for i in range(state.bots.size()):
		if i in state.my_played:
			continue
		var diff = absf(float(state.bots[i].score) - float(state.my_score))
		if diff < best_diff:
			best_diff = diff
			best = i
	return best if best >= 0 else 0

func _on_play_pressed() -> void:
	if selected_def.is_empty():
		return
	var state = Profile.active_tournaments.get(selected_def.id, {})
	if state.is_empty() or state.get("done", false):
		state = _new_state(selected_def)
		Profile.active_tournaments[selected_def.id] = state
		Profile.save_profile()
	var opp_idx = _pick_opponent(state)
	var bot: Dictionary = state.bots[opp_idx]
	Global.tournament_game = {
		"tid": state.id,
		"tname": state.name,
		"opp_idx": opp_idx,
		"opp_name": bot.name,
		"level": bot.level,
		"tc": state.tc,
		"inc": state.inc,
		"round": int(state.round) + 1,
		"rounds": int(state.rounds),
		"color": "w" if int(state.round) % 2 == 0 else "b",
	}
	Global.map_character_id = ""
	Global.coop_team = false
	Global.road_mode = ""
	get_tree().change_scene_to_file("res://scenes/Board.tscn")

func _on_close_pressed() -> void:
	detail_panel.visible = false

func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")
