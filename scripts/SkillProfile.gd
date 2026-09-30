extends RefCounted

# «Индекс мастерства» и профиль навыков игрока — замена «виртуального рейтинга» из партий
# с компьютером. Это НЕ шахматный рейтинг и не претендует на соответствие турнирному:
# он складывается из отдельных навыков, каждый из которых виден и объясним, и показывается
# вместе с диапазоном (чем меньше данных, тем шире).
#
# Чистая функция: compute() получает словарь с данными профиля (см. Profile.skill_input())
# и ничего не читает сама — поэтому её легко проверять тестами (scenes/tools/TestSkillProfile.tscn).

# id, название, вес в итоговом индексе
const SKILLS := [
	["accuracy", "Точность ходов", 0.20],
	["attention", "Внимательность", 0.12],
	["opening", "Дебют", 0.08],
	["middlegame", "Миттельшпиль", 0.12],
	["endgame", "Эндшпиль", 0.12],
	["tactics", "Тактика", 0.16],
	["independence", "Самостоятельность", 0.05],
	["results", "Победы над компьютером", 0.15],
]

const THEME_NAMES := {
	"mate": "Мат в 1–3 хода", "fork": "Вилка", "pin": "Связка", "backrank": "Мат на последней горизонтали",
	"defense": "Уничтожение защиты", "deflection": "Отвлечение",
}

static func _c01(x: float) -> float:
	return clampf(x, 0.0, 1.0)

static func _is_helped(g: Dictionary) -> bool:
	return int(g.get("help_hints", 0)) > 0 or int(g.get("help_undos", 0)) > 0 \
		or bool(g.get("assist", false)) or str(g.get("coop", "")) != ""

# Основной вход. d:
#   "games": Array — последние партии из журнала (err_opening/err_middlegame/err_endgame, help_*, moves, color)
#   "moves": {good, inaccuracy, mistake, blunder} — качество ходов за всё время
#   "themes": {theme_id: {"solved": int, "clean": int}}
#   "attention_done": int (0..50)
#   "step": int (0..25), "clean_wins_total": int
static func compute(d: Dictionary) -> Dictionary:
	var games: Array = d.get("games", [])
	var mv: Dictionary = d.get("moves", {})
	var res := {}

	# --- точность ходов ---
	var total := int(mv.get("good", 0)) + int(mv.get("inaccuracy", 0)) + int(mv.get("mistake", 0)) + int(mv.get("blunder", 0))
	var pct := 100.0 * float(mv.get("good", 0)) / maxf(float(total), 1.0)
	# на партиях гроссмейстеров эта линейка даёт около 73% сильных ходов (см. TestQualityRuler)
	res["accuracy"] = {"score": _c01((pct - 35.0) / 40.0) * 100.0, "conf": _c01(total / 150.0),
		"note": "%.0f%% ходов — сильные (у мастеров около 73%%)" % pct if total > 0 else "пока нет разобранных ходов"}

	# --- внимательность: зевки + режим «Внимательность» ---
	var blunder_pct := 100.0 * float(mv.get("blunder", 0)) / maxf(float(total), 1.0)
	var bs := (1.0 - _c01(blunder_pct / 6.0)) * 100.0
	var att_done := int(d.get("attention_done", 0))
	var att_score := bs
	var att_conf := _c01(total / 150.0)
	if att_done > 0:
		att_score = 0.6 * bs + 0.4 * (att_done / 50.0 * 100.0)
		att_conf = maxf(att_conf, 0.6)
	res["attention"] = {"score": att_score, "conf": att_conf,
		"note": "зевков %.1f%% ходов, пройдено уровней «Внимательности»: %d из 50" % [blunder_pct, att_done] if total > 0 or att_done > 0 else "пока нет данных"}

	# --- фазы партии: серьёзные ошибки за партию (последние 15 партий) ---
	var window: Array = games.slice(maxi(games.size() - 15, 0))
	for ph in [["opening", "err_opening", "Дебют"], ["middlegame", "err_middlegame", "Миттельшпиль"], ["endgame", "err_endgame", "Эндшпиль"]]:
		var sum := 0.0
		for g in window:
			sum += float(g.get(ph[1], 0))
		var n := window.size()
		var avg := sum / maxf(float(n), 1.0)
		res[ph[0]] = {"score": (1.0 - _c01(avg / 2.5)) * 100.0, "conf": _c01(n / 8.0),
			"note": "%.1f серьёзных ошибок за партию (последние %d партий)" % [avg, n] if n > 0 else "пока нет сыгранных партий"}

	# --- тактика по темам задач ---
	var themes: Dictionary = d.get("themes", {})
	var t_sum := 0.0
	var t_cnt := 0
	var solved_all := 0
	var weakest_theme := ""
	var weakest_val := 2.0
	for k in themes:
		var solved := int(themes[k].get("solved", 0))
		if solved <= 0:
			continue
		var clean := int(themes[k].get("clean", 0))
		var v := 0.6 * _c01(float(clean) / float(solved)) + 0.4 * _c01(solved / 20.0)
		t_sum += v
		t_cnt += 1
		solved_all += solved
		if v < weakest_val:
			weakest_val = v
			weakest_theme = str(k)
	res["tactics"] = {"score": (t_sum / maxf(float(t_cnt), 1.0)) * 100.0, "conf": _c01(solved_all / 25.0),
		"weakest": weakest_theme,
		"note": "решено задач: %d по %d темам" % [solved_all, t_cnt] if t_cnt > 0 else "пока не решено ни одной задачи"}

	# --- самостоятельность: доля партий без подсказок/откатов/форы ---
	var recent: Array = games.slice(maxi(games.size() - 20, 0))
	var clean_games := 0
	for g in recent:
		if not _is_helped(g):
			clean_games += 1
	res["independence"] = {"score": 100.0 * float(clean_games) / maxf(float(recent.size()), 1.0), "conf": _c01(recent.size() / 8.0),
		"note": "%d из %d последних партий сыграны без помощи" % [clean_games, recent.size()] if recent.size() > 0 else "пока нет партий"}

	# --- победы над компьютером: ступень ---
	var step := int(d.get("step", 0))
	var cw := int(d.get("clean_wins_total", 0))
	res["results"] = {"score": _c01(step / 25.0) * 100.0, "conf": _c01(cw / 3.0),
		"note": "ступень %d из 25 (чистые победы без подсказок)" % step if cw > 0 else "пока нет чистых побед"}

	# --- итог ---
	var skills: Array = []
	var w_sum := 0.0
	var wc_sum := 0.0
	var ws_sum := 0.0
	for s in SKILLS:
		var r: Dictionary = res[s[0]]
		var item := {"id": s[0], "name": s[1], "weight": s[2], "score": float(r.score), "conf": float(r.conf), "note": str(r.note)}
		if r.has("weakest"):
			item["weakest"] = r.weakest
		skills.append(item)
		w_sum += float(s[2])
		wc_sum += float(s[2]) * float(r.conf)
		ws_sum += float(s[2]) * float(r.conf) * float(r.score)
	var confidence := wc_sum / w_sum
	var have_data := wc_sum > 0.05
	var index := ws_sum / wc_sum if have_data else 0.0
	var half := (1.0 - confidence) * 25.0 + 3.0
	return {
		"skills": skills,
		"index": index,
		"confidence": confidence,
		"has_data": have_data,
		"lo": maxf(index - half, 0.0),
		"hi": minf(index + half, 100.0),
		"band": band_for_index(index) if have_data else "",
		"style": style_labels(games),
		"advice": advice(skills),
	}

static func band_for_index(idx: float) -> String:
	if idx < 20.0:
		return "Начинающий"
	if idx < 40.0:
		return "Развивающийся"
	if idx < 60.0:
		return "Уверенный"
	if idx < 80.0:
		return "Сильный"
	return "Очень сильный"

# Что тренировать: самый слабый навык, по которому уже есть данные.
static func advice(skills: Array) -> String:
	var worst := {}
	for s in skills:
		if float(s.conf) < 0.3:
			continue
		if worst.is_empty() or float(s.score) < float(worst.score):
			worst = s
	if worst.is_empty():
		return "Сыграйте несколько партий и решите пару задач — тогда появится разбор."
	match str(worst.id):
		"tactics":
			var th := str(worst.get("weakest", ""))
			return "Слабее всего тактика%s. Потренируйтесь на задачах этой темы." % ((" — тема «%s»" % THEME_NAMES.get(th, th)) if th != "" else "")
		"endgame":
			return "Больше всего ошибок в эндшпиле: сыграйте учебные позиции карты и этапы «Дороги домой» про эндшпиль."
		"middlegame":
			return "Больше всего ошибок в миттельшпиле: перед ходом проверяйте, какие фигуры под боем — свои и чужие."
		"opening":
			return "Дебют даётся хуже всего: развивайте фигуры, рокируйтесь и не ходите одной фигурой дважды без нужды."
		"attention":
			return "Слабое место — внимательность: тренируйтесь в режиме «Внимательность» и перед каждым ходом смотрите, не оставляете ли фигуру без защиты."
		"accuracy":
			return "Точность ходов пока невысокая: старайтесь считать хотя бы на ход вперёд, что ответит соперник."
		"independence":
			return "Многие партии сыграны с подсказками или откатами. Попробуйте сыграть несколько партий полностью самостоятельно — так виден настоящий уровень."
		"results":
			return "Попробуйте сыграть с уровнем сильнее и победить без подсказок — так растёт ступень."
	return ""

# Портрет стиля по записи ходов игрока (нужно не меньше 5 партий).
static func style_labels(games: Array) -> Array:
	var labels: Array = []
	var used := 0
	var own_moves := 0
	var captures := 0
	var pawn_moves := 0
	var early_queen_games := 0
	var castle_sum := 0
	var castle_games := 0
	for g in games:
		var mv: Array = g.get("moves", [])
		if mv.size() < 10:
			continue
		used += 1
		var start := 0 if str(g.get("color", "w")) == "w" else 1
		var idx := 0
		var moved_queen_early := false
		var castled_at := -1
		for i in range(start, mv.size(), 2):
			var m := str(mv[i])
			idx += 1
			own_moves += 1
			if m.contains("x"):
				captures += 1
			if m.length() > 0 and m[0] == m[0].to_lower() and m[0] != "O":
				pawn_moves += 1
			if idx <= 10 and m.begins_with("Q"):
				moved_queen_early = true
			if castled_at < 0 and m.begins_with("O-O"):
				castled_at = idx
		if moved_queen_early:
			early_queen_games += 1
		if castled_at > 0:
			castle_sum += castled_at
			castle_games += 1
	if used < 5 or own_moves == 0:
		return labels
	var cap_rate := float(captures) / float(own_moves)
	if cap_rate >= 0.30:
		labels.append("Любит взятия и размены — играет прямолинейно")
	elif cap_rate <= 0.12:
		labels.append("Редко берёт и разменивает — предпочитает сохранять напряжение")
	var pawn_share := float(pawn_moves) / float(own_moves)
	if pawn_share >= 0.45:
		labels.append("Много ходит пешками — любит пространство и центр")
	elif pawn_share <= 0.22:
		labels.append("Больше играет фигурами, чем пешками")
	if float(early_queen_games) / float(used) >= 0.5:
		labels.append("Рано выводит ферзя — легко потерять темп под атакой")
	if castle_games == 0:
		labels.append("Почти не рокируется — король остаётся в центре")
	elif float(castle_sum) / float(castle_games) > 12.0:
		labels.append("Рокируется поздно (в среднем на %d-м ходу)" % int(round(float(castle_sum) / float(castle_games))))
	elif float(castle_sum) / float(castle_games) <= 8.0:
		labels.append("Быстро прячет короля рокировкой")
	return labels
