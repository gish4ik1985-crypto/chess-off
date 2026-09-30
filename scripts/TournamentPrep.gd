extends Control

# Подготовка к турниру: тренировочный режим для тех, кто скоро едет на
# настоящий турнир. Три уровня сложности, растущие вместе с длиной турнира
# (4 → 6 → 8 туров), чтобы ребёнок не испугался и втягивался постепенно.
# Своя (тренировочная) статистика — рейтинг за настоящие турниры не трогаем.

@onready var status_label: Label = $TopBar/HBox/RatingLabel
@onready var list_vbox: VBoxContainer = $Main/ListScroll/ListVBox
@onready var detail_panel: PanelContainer = $Main/DetailPanel
@onready var detail_name: Label = $Main/DetailPanel/VBox/NameLabel
@onready var detail_info: Label = $Main/DetailPanel/VBox/InfoLabel
@onready var detail_table: Label = $Main/DetailPanel/VBox/TableLabel
@onready var play_button: Button = $Main/DetailPanel/VBox/PlayButton

const LEVELS := [
	{
		"id": "prep_easy", "name": "Разминка", "format": "Классика (без часов)",
		"tc": 0, "inc": 0, "rounds": 4, "band": [1, 4], "requires": "",
		"desc": "Первый шаг перед настоящим турниром. Соперники несложные, часов нет — можно спокойно думать над каждым ходом. Четыре тура, чтобы привыкнуть к турнирному режиму: играть до конца, не отменять ходы, не подсматривать подсказки.",
	},
	{
		"id": "prep_medium", "name": "Уверенный шаг", "format": "Рапид 10+5",
		"tc": 600, "inc": 5, "rounds": 6, "band": [5, 10], "requires": "prep_easy",
		"desc": "Соперники сильнее, туров больше (шесть), и уже есть часы — 10 минут и +5 секунд за ход. Открывается после «Разминки».",
	},
	{
		"id": "prep_hard", "name": "Большая сцена", "format": "Рапид 15+10",
		"tc": 900, "inc": 10, "rounds": 7, "band": [10, 18], "requires": "prep_medium",
		"desc": "Полноценная генеральная репетиция: семь туров — вы сыграете с каждым из 7 соперников по разу, серьёзные соперники, боевой контроль времени. Пройдёшь это — настоящий турнир не испугает. Открывается после «Уверенного шага».",
	},
]

const BotData = preload("res://scripts/BotData.gd")

var selected_def: Dictionary = {}

func _ready() -> void:
	_update_status_label()
	_build_list()
	detail_panel.visible = false

func _update_status_label() -> void:
	var done := 0
	for def in LEVELS:
		var st = Profile.active_tournament_prep.get(def.id, {})
		if st.get("done", false):
			done += 1
	status_label.text = "Пройдено уровней подготовки: %d из %d" % [done, LEVELS.size()]

func _is_unlocked(def: Dictionary) -> bool:
	if def.requires == "":
		return true
	var st = Profile.active_tournament_prep.get(def.requires, {})
	return st.get("done", false)

func _build_list() -> void:
	for c in list_vbox.get_children():
		c.queue_free()
	for def in LEVELS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 52)
		var unlocked = _is_unlocked(def)
		var status := ""
		var state = Profile.active_tournament_prep.get(def.id, {})
		if not state.is_empty():
			if state.get("done", false):
				status = "  · 🏆 1-е место!" if state.get("won", false) else "  · пройден (%d-е место)" % Profile.tournament_place(state)
			else:
				status = "  · идёт: тур %d/%d" % [int(state.round) + 1, int(state.rounds)]
		if unlocked:
			b.text = "%s · %d туров · %s%s" % [def.name, def.rounds, def.format, status]
		else:
			b.text = "🔒 %s — сначала пройдите «%s»" % [def.name, _level_name(def.requires)]
			b.disabled = true
		b.pressed.connect(_on_level_selected.bind(def))
		list_vbox.add_child(b)

func _level_name(id: String) -> String:
	for def in LEVELS:
		if def.id == id:
			return def.name
	return ""

# Соперники — те же постоянные игроки из «Базы игроков», чтобы имена были
# знакомыми. Но лига берётся не по игроку, а по сложности самой тренировки
# (у «Разминки» соперники всегда лёгкие), и результаты тренировки НЕ меняют
# ни рейтинг игрока, ни рейтинги ботов — см. _simulate_bot_round(rated=false).
func _new_state(def: Dictionary) -> Dictionary:
	var base = (int(def.band[0]) + int(def.band[1])) / 2
	var band_rating = float(Profile.LEVEL_RATING[clampi(base, 1, Profile.LEVEL_RATING.size()) - 1])
	var league = BotData.league_idx_for_rating(band_rating)
	var bots := []
	for rec in Profile.pick_tournament_field(7, league):
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

func _on_level_selected(def: Dictionary) -> void:
	selected_def = def
	detail_name.text = def.name
	var state = Profile.active_tournament_prep.get(def.id, {})
	var info = "%s · %d туров · 8 участников\n\n%s" % [def.format, def.rounds, def.desc]
	if state.is_empty():
		detail_table.text = ""
		play_button.text = "Начать подготовку!"
		play_button.visible = true
	elif state.get("done", false):
		var place = Profile.tournament_place(state)
		info += "\n\nЗавершено — ваше место: %d из 8." % place
		if state.get("won", false):
			info += " 🏆 Отлично, вы готовы!"
		detail_table.text = _standings_text(state)
		play_button.text = "Пройти заново"
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
	var state = Profile.active_tournament_prep.get(selected_def.id, {})
	if state.is_empty() or state.get("done", false):
		state = _new_state(selected_def)
		Profile.active_tournament_prep[selected_def.id] = state
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
		"practice": true,
	}
	Global.map_character_id = ""
	Global.coop_team = false
	Global.road_mode = ""
	get_tree().change_scene_to_file("res://scenes/Board.tscn")

func _on_close_pressed() -> void:
	detail_panel.visible = false

func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")
