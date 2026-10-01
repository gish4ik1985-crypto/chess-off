extends Node

# Согласованность шкал рейтинга: таблица силы уровней ИИ, лиги ботов, пороги турниров,
# достижения и звания должны жить в одной шкале. Тест падает, если кто-то поменял одну
# часть и забыл остальные (например, порог турнира выше потолка, до которого можно дорасти).
# Запуск: scenes/tools/TestScales.tscn

const BotData = preload("res://scripts/BotData.gd")
const TournamentsScript = preload("res://scripts/Tournaments.gd")

var fails := 0

func check(name: String, ok: bool, info: String = "") -> void:
	print(("OK   " if ok else "FAIL ") + name + (" " + info if info != "" else ""))
	if not ok:
		fails += 1

func _ready() -> void:
	var tab: Array = Profile.LEVEL_RATING
	var ceiling: float = float(tab[tab.size() - 1]) + Profile.FARM_MARGIN # выше победами над ИИ не дорасти

	check("таблица силы: 25 уровней", tab.size() == Global.MAX_DIFFICULTY and Global.DIFFICULTY_NAMES.size() == tab.size())
	var mono := true
	for i in range(1, tab.size()):
		if tab[i] < tab[i - 1]:
			mono = false
	check("таблица силы не убывает", mono)
	check("старт рейтинга внутри шкалы уровней", Glicko2.DEFAULT_RATING >= float(tab[0]) and Glicko2.DEFAULT_RATING <= float(tab[tab.size() - 1]))

	# лиги: без дыр и перекрытий, потолок последней лиги выше потолка достижимого рейтинга
	var contiguous := true
	for i in range(1, BotData.LEAGUES.size()):
		if int(BotData.LEAGUES[i].min) != int(BotData.LEAGUES[i - 1].max) + 1:
			contiguous = false
	check("лиги идут встык, без дыр", contiguous)
	check("все лиги ниже потолка рейтинга (кроме верхней)", int(BotData.LEAGUES[BotData.LEAGUES.size() - 2].max) < ceiling)

	# боты: стартовый рейтинг в своей лиге и в пределах шкалы уровней
	var bots_ok := true
	var per_league := {}
	for d in BotData.all_defs():
		var li := int(d.league_idx)
		per_league[li] = int(per_league.get(li, 0)) + 1
		var b: Dictionary = BotData.league_band(li)
		if float(d.base_rating) < float(b.lo) or float(d.base_rating) > float(b.hi) or float(d.base_rating) > ceiling:
			bots_ok = false
	check("стартовые рейтинги ботов лежат в своих лигах и ниже потолка", bots_ok)
	var full := true
	for li in range(BotData.LEAGUES.size()):
		if int(per_league.get(li, 0)) != BotData.PER_LEAGUE:
			full = false
	check("в каждой лиге по %d ботов" % BotData.PER_LEAGUE, full)

	# турниры: пороги достижимы, диапазоны уровней в пределах 1…25, пороги растут
	var prev_min := -1
	var t_ok := true
	var info := ""
	for def in TournamentsScript.STANDING:
		var mn := int(def.min_rating)
		if mn < prev_min or float(mn) > ceiling or int(def.band[0]) < 1 or int(def.band[1]) > tab.size() or int(def.band[0]) > int(def.band[1]):
			t_ok = false
			info += " " + str(def.id)
		prev_min = mn
	check("пороги турниров достижимы и растут, диапазоны уровней верны", t_ok, info)
	# поле открытого турнира по силе не выше игрока с порогом + запас: верх диапазона не слабее порога
	var field_ok := true
	for def in TournamentsScript.STANDING:
		var top_lvl_rating := float(tab[int(def.band[1]) - 1])
		if top_lvl_rating + 400.0 < float(def.min_rating):
			field_ok = false
	check("в турнирах есть соперники по силе игрокам с порогом входа", field_ok)

	# достижения за рейтинг достижимы
	var ach_ok := true
	for a in [[1200, "rating_1600"], [1500, "rating_2000"], [1700, "rating_2400"], [1400, "tourney_rating_1800"]]:
		var found := false
		for x in Profile.ACHIEVEMENTS:
			if x.id == a[1]:
				found = true
				if not str(x.desc).contains(str(a[0])):
					ach_ok = false
		if not found or float(a[0]) > ceiling:
			ach_ok = false
	check("достижения за рейтинг: пороги совпадают с описанием и достижимы", ach_ok)

	# звания: от нижнего до верхнего без пустых и повторов подряд, нижний порог — не «Новичок» на старте
	var prev := ""
	var distinct := 0
	for r in range(0, 3000, 50):
		var t := Profile.title_for_rating(float(r))
		if t == "":
			distinct = -1000
		if t != prev:
			distinct += 1
		prev = t
	check("звания: все непустые и растут ступенями", distinct >= 6, "ступеней %d" % distinct)
	check("новичок с рейтингом по умолчанию — не выше «Любитель»", Profile.title_for_rating(Glicko2.DEFAULT_RATING) in ["Новичок", "Любитель"], Profile.title_for_rating(Glicko2.DEFAULT_RATING))

	# выбор поля турнира для каждой лиги даёт 7 соперников
	var field_all := true
	for li in range(BotData.LEAGUES.size()):
		if Profile.pick_tournament_field(7, li).size() != 7:
			field_all = false
	check("поле из 7 соперников собирается в каждой лиге", field_all)

	print("=== ИТОГО ошибок: %d ===" % fails)
	get_tree().quit(1 if fails > 0 else 0)
