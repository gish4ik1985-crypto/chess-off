extends Node

# Проверка профиля навыков и «Индекса мастерства» (SkillProfile.compute): нет данных — нет числа,
# сильный игрок выше слабого, помощь снижает самостоятельность, совет указывает на слабое место,
# диапазон шире при малом числе данных, портрет стиля появляется только при достаточном числе партий.
# Запуск: scenes/tools/TestSkillProfile.tscn

const SP = preload("res://scripts/SkillProfile.gd")

var fails := 0

func check(name: String, ok: bool, info: String = "") -> void:
	print(("OK   " if ok else "FAIL ") + name + (" " + info if info != "" else ""))
	if not ok:
		fails += 1

func game(open := 0, mid := 0, end := 0, helped := false, moves: Array = [], color := "w") -> Dictionary:
	return {"err_opening": open, "err_middlegame": mid, "err_endgame": end, "help_hints": 1 if helped else 0,
		"help_undos": 0, "assist": false, "coop": "", "moves": moves, "color": color}

func strong_input() -> Dictionary:
	var games: Array = []
	for i in range(15):
		games.append(game(0, 0, 0))
	return {"games": games, "moves": {"good": 730, "inaccuracy": 200, "mistake": 60, "blunder": 10},
		"themes": {"fork": {"solved": 25, "clean": 22}, "pin": {"solved": 22, "clean": 19}},
		"attention_done": 40, "step": 20, "clean_wins_total": 40}

func weak_input() -> Dictionary:
	var games: Array = []
	for i in range(15):
		games.append(game(2, 3, 3))
	return {"games": games, "moves": {"good": 300, "inaccuracy": 200, "mistake": 350, "blunder": 150},
		"themes": {"fork": {"solved": 6, "clean": 1}, "pin": {"solved": 4, "clean": 0}},
		"attention_done": 3, "step": 2, "clean_wins_total": 4}

func _ready() -> void:
	var empty: Dictionary = SP.compute({})
	check("без данных индекса нет", not empty.has_data and empty.band == "")
	check("без данных совет — сыграть партии", str(empty.advice).contains("Сыграйте"))

	var strong: Dictionary = SP.compute(strong_input())
	var weak: Dictionary = SP.compute(weak_input())
	check("индекс сильного выше индекса слабого", strong.index > weak.index + 25.0, "%.0f против %.0f" % [strong.index, weak.index])
	check("индекс в пределах 0…100", strong.index <= 100.0 and weak.index >= 0.0)
	check("уверенность высокая при большом числе данных", strong.confidence > 0.7, "%.2f" % strong.confidence)
	check("названия полос", strong.band != "" and weak.band != "" and strong.band != weak.band, "%s / %s" % [strong.band, weak.band])

	# все восемь навыков присутствуют, у каждого оценка 0…100
	var ok_skills: bool = strong.skills.size() == 8
	for s in strong.skills:
		if s.score < 0.0 or s.score > 100.0 or s.conf < 0.0 or s.conf > 1.0:
			ok_skills = false
	check("восемь навыков с оценками 0…100", ok_skills)

	# линейка точности: «как у мастеров» ≈ отлично, «как старая линейка выдавала мастерам» — слабо
	var acc_master := SP.compute({"moves": {"good": 730, "inaccuracy": 200, "mistake": 60, "blunder": 10}})
	var acc_old := SP.compute({"moves": {"good": 430, "inaccuracy": 190, "mistake": 310, "blunder": 60}})
	var a1: float = acc_master.skills[0].score
	var a2: float = acc_old.skills[0].score
	check("73% сильных ходов — высокая точность, 43% — низкая", a1 >= 85.0 and a2 <= 30.0, "%.0f / %.0f" % [a1, a2])

	# помощь снижает самостоятельность и не повышает индекс
	var helped_in := strong_input()
	for g in helped_in.games:
		g["help_hints"] = 3
	var helped: Dictionary = SP.compute(helped_in)
	var ind_strong: float = 0.0
	var ind_helped: float = 0.0
	for s in strong.skills:
		if s.id == "independence":
			ind_strong = s.score
	for s in helped.skills:
		if s.id == "independence":
			ind_helped = s.score
	check("партии с подсказками снижают самостоятельность", ind_helped < ind_strong - 50.0, "%.0f → %.0f" % [ind_strong, ind_helped])
	check("помощь не повышает индекс", helped.index <= strong.index)

	# диапазон шире при малом числе данных
	var little := SP.compute({"moves": {"good": 20, "inaccuracy": 10, "mistake": 5, "blunder": 1}})
	check("при малом числе данных диапазон шире", (little.hi - little.lo) > (strong.hi - strong.lo) + 5.0, "%.0f против %.0f" % [little.hi - little.lo, strong.hi - strong.lo])

	# совет указывает на слабое место
	var end_in := strong_input()
	end_in.games = []
	for i in range(15):
		end_in.games.append(game(0, 0, 4))
	check("много ошибок в эндшпиле — совет про эндшпиль", str(SP.compute(end_in).advice).to_lower().contains("эндшпил"), str(SP.compute(end_in).advice))
	var tac_in := strong_input()
	tac_in.themes = {"fork": {"solved": 25, "clean": 24}, "backrank": {"solved": 12, "clean": 0}}
	var tac := SP.compute(tac_in)
	tac_in.moves = {"good": 900, "inaccuracy": 60, "mistake": 30, "blunder": 10}
	tac_in.attention_done = 50
	tac_in.step = 25
	var tac_advice: String = str(SP.compute(tac_in).advice)
	check("слабая тема задач названа в совете", tac_advice.contains("последней горизонтали") or str(tac.advice).contains("последней горизонтали"), tac_advice)

	# портрет стиля
	var fewer: Array = []
	for i in range(4):
		fewer.append(game(0, 0, 0, false, ["e2-e4", "e7-e5", "Ng1-f3", "Nb8-c6", "Bf1-c4", "Bf8-c5", "O-O", "Ng8-f6", "d2-d3", "d7-d6"]))
	check("меньше 5 партий — портрета стиля нет", SP.style_labels(fewer).is_empty())
	var grabby: Array = []
	for i in range(6):
		grabby.append(game(0, 0, 0, false, ["e2-e4", "d7-d5", "e4xd5", "Qd8xd5", "Nb1-c3", "Qd5xa5", "Bf1xb5", "c6xb5", "Nc3xb5", "Qa5xb5", "a2-a3", "Qb5-a5"]))
	var labels: Array = SP.style_labels(grabby)
	var joined := " ".join(labels)
	check("много взятий — «любит взятия и размены»", joined.contains("взятия"), joined)
	check("не рокируется — отмечено", joined.contains("не рокируется"), joined)

	_check_step()

	print("=== ИТОГО ошибок: %d ===" % fails)
	get_tree().quit(1 if fails > 0 else 0)

# Ступень: два чистых победных результата над уровнем — уровень пройден. Профиль на время теста
# отключается от файла (current_user пуст → save_profile ничего не пишет), состояние возвращается.
func _check_step() -> void:
	var saved_user: String = Profile.current_user
	var saved_wins: Dictionary = Profile.clean_wins.duplicate()
	var saved_rating: float = Profile.rating
	var saved_rd: float = Profile.rd
	var saved_vol: float = Profile.volatility
	var saved_games := Profile.games_played
	var saved_w := Profile.wins
	var saved_l := Profile.losses
	var saved_streak := Profile.win_streak
	var saved_best := Profile.best_win_streak
	var saved_lvl := Profile.best_win_level
	Profile.current_user = ""
	Profile.clean_wins = {}
	check("ступень нового игрока — 0", Profile.clean_step() == 0 and Profile.step_wins_left() == Profile.STEP_WINS_REQUIRED)
	Profile.record_game_result(4, 1.0)
	check("одна победа над уровнем ступень не поднимает", Profile.clean_step() == 0 and Profile.last_step_gain == 0)
	check("до ступени осталась ещё одна чистая победа над уровнем 1", Profile.step_wins_left() == 2)
	Profile.record_game_result(4, 1.0)
	check("вторая победа над уровнем 4 даёт ступень 4", Profile.clean_step() == 4 and Profile.last_step_gain == 4, "ступень %d" % Profile.clean_step())
	Profile.record_game_result(4, 1.0)
	check("третья победа ступень уже не меняет", Profile.clean_step() == 4 and Profile.last_step_gain == 0)
	Profile.record_game_result(9, 0.0)
	Profile.record_game_result(9, 0.5)
	check("поражения и ничьи ступень не поднимают", Profile.clean_step() == 4)
	Profile.record_game_result(2, 1.0)
	Profile.record_game_result(2, 1.0)
	check("победы над слабым уровнем ступень не снижают", Profile.clean_step() == 4)
	Profile.record_game_result(6, 1.0)
	Profile.record_game_result(6, 1.0)
	check("ступень — самый сильный пройденный уровень (6)", Profile.clean_step() == 6)
	var inp: Dictionary = Profile.skill_input()
	check("skill_input отдаёт ступень и число чистых побед", int(inp.step) == 6 and int(inp.clean_wins_total) == 7, str(inp.clean_wins_total))
	Profile.current_user = saved_user
	Profile.clean_wins = saved_wins
	Profile.rating = saved_rating
	Profile.rd = saved_rd
	Profile.volatility = saved_vol
	Profile.games_played = saved_games
	Profile.wins = saved_w
	Profile.losses = saved_l
	Profile.win_streak = saved_streak
	Profile.best_win_streak = saved_best
	Profile.best_win_level = saved_lvl
