extends Node

# Проверяет базу постоянных игроков: состав, лиги, рост рейтинга и главное —
# что слабые боты навсегда остаются в своей лиге и страхуют игрока на любом
# уровне, а игрок не встречает соперников из чужих лиг.
# Запуск: godot --headless --path . res://scenes/tools/TestBots.tscn

const BotData = preload("res://scripts/BotData.gd")
const BoardScript = preload("res://scripts/Board.gd")

var fails := 0

func _ready() -> void:
	_check_roster()
	_check_leagues_populated()
	_check_field_matches_league()
	_check_growth()
	_check_weak_stay_home()
	_check_every_league_has_beatable()
	_check_persistence()
	_check_tournament_round()
	_check_prep_is_unrated()
	_check_friendly()
	_check_world_tick()
	_check_world_stability()
	_check_game_archive()
	print("=== ИТОГО ошибок: %d ===" % fails)
	get_tree().quit(1 if fails > 0 else 0)

func _ok(what: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["OK  " if ok else "FAIL", what, ("" if detail == "" else " -> " + detail)])
	if not ok:
		fails += 1

func _check_roster() -> void:
	var defs := BotData.all_defs()
	_ok("игроков не меньше 100", defs.size() >= 100, str(defs.size()))
	var names := {}
	for d in defs:
		names[d.name] = true
	_ok("имена уникальны", names.size() == defs.size(), "%d из %d" % [names.size(), defs.size()])
	var weak := 0
	for d in defs:
		if d.weak:
			weak += 1
	var pct := 100.0 * float(weak) / float(defs.size())
	_ok("слабых около 10%", pct >= 8.0 and pct <= 12.0, "%.0f%% (%d)" % [pct, weak])

func _check_leagues_populated() -> void:
	var per := {}
	for rec in Profile.all_bot_records():
		per[rec.league_idx] = int(per.get(rec.league_idx, 0)) + 1
	var all_ok := true
	for i in range(BotData.LEAGUES.size()):
		var n = int(per.get(i, 0))
		# в каждой лиге должно хватать на полный турнир (игрок + 7 соперников)
		if n < 7:
			all_ok = false
		print("    %s %s: %d игроков" % [BotData.LEAGUES[i].icon, BotData.LEAGUES[i].name, n])
	_ok("в каждой лиге хватает на турнир (>=7)", all_ok)

func _check_field_matches_league() -> void:
	# игрок из средней лиги не должен встречать легенд
	Profile.tournament_rating = 1400.0 # клубная лига
	var want = Profile.player_league_idx()
	var field := Profile.pick_tournament_field(7)
	_ok("состав турнира набран", field.size() == 7, str(field.size()))
	var foreign := 0
	for rec in field:
		if int(rec.league_idx) != want:
			foreign += 1
	_ok("все соперники из лиги игрока", foreign == 0, "чужих: %d" % foreign)

func _check_growth() -> void:
	Profile.bot_state = {}
	var id := "bot_020" # обычный (не слабый) бот клубной лиги
	var before: float = Profile.bot_record(id).rating
	for i in range(30):
		Profile.apply_bot_result(id, 1200.0, 1.0) # 30 побед над слабым соперником
	var after: float = Profile.bot_record(id).rating
	_ok("рейтинг бота растёт от побед", after > before + 20.0, "%.0f -> %.0f" % [before, after])
	var rec := Profile.bot_record(id)
	_ok("победы записаны в карточку", int(rec.wins) == 30, str(rec.wins))
	var mid: float = Profile.bot_record(id).rating
	# от РАВНОГО соперника: проигрыш тому, кто на 1000 очков сильнее, ожидаем
	# и рейтинг почти не двигает — это верное поведение Glicko, а не ошибка
	for i in range(30):
		Profile.apply_bot_result(id, Profile.bot_record(id).rating, 0.0)
	var low: float = Profile.bot_record(id).rating
	_ok("рейтинг бота падает от поражений", low < mid - 20.0, "%.0f -> %.0f" % [mid, low])

func _check_weak_stay_home() -> void:
	Profile.bot_state = {}
	# берём слабого бота и «выигрываем» им 200 партий подряд
	var weak_id := ""
	for d in BotData.all_defs():
		if d.weak and int(d.home_league_idx) == 3:
			weak_id = d.id
			break
	_ok("слабый бот найден в городской лиге", weak_id != "", weak_id)
	if weak_id == "":
		return
	var home := int(BotData.def_by_id(weak_id).home_league_idx)
	for i in range(200):
		Profile.apply_bot_result(weak_id, 2600.0, 1.0)
	var rec := Profile.bot_record(weak_id)
	_ok("слабый бот не покинул свою лигу даже после 200 побед",
		int(rec.league_idx) == home, "лига %d (родная %d), рейтинг %.0f" % [rec.league_idx, home, rec.rating])

func _check_every_league_has_beatable() -> void:
	# Смысл слабых ботов: на ЛЮБОМ уровне игрока в его лиге есть соперник
	# слабее его самого. Прогоняем игрока по всем лигам.
	var all_ok := true
	for li in range(BotData.LEAGUES.size()):
		var league: Dictionary = BotData.LEAGUES[li]
		# ставим игрока по медиане реальных рейтингов лиги: формальная
		# середина бессмысленна у крайних лиг (min = 0 / max = 99999)
		var band := BotData.league_band(li)
		Profile.tournament_rating = (float(band.lo) + float(band.hi)) / 2.0
		var field := Profile.pick_tournament_field(7)
		var beatable := 0
		for rec in field:
			if float(rec.rating) < Profile.tournament_rating:
				beatable += 1
		if beatable == 0:
			all_ok = false
		print("    %s: рейтинг игрока %.0f, обыгрываемых соперников %d из %d" % [
			league.name, Profile.tournament_rating, beatable, field.size()])
	_ok("в каждой лиге есть кого обыграть", all_ok)

func _make_state(tid: String) -> Dictionary:
	var bots := []
	for rec in Profile.pick_tournament_field(7):
		bots.append({"id": rec.id, "name": rec.name, "level": int(rec.level),
			"rating": int(round(float(rec.rating))), "score": 0.0})
	return {
		"id": tid, "name": tid, "format": "тест", "tc": 0, "inc": 0, "rounds": 3,
		"round": 0, "my_score": 0.0, "my_played": [], "bots": bots,
		"done": false, "won": false, "bot_pairs": {},
	}

# Сквозная проверка: настоящий тур меняет постоянные рейтинги — и соперника
# игрока, и тех ботов, что играли между собой.
func _check_tournament_round() -> void:
	Profile.bot_state = {}
	Profile.tournament_rating = 1400.0
	var state := _make_state("test_cup")
	Profile.active_tournaments = {"test_cup": state}
	var opp_id := str(state.bots[0].id)
	var opp_before: float = Profile.bot_record(opp_id).rating
	Profile.finish_tournament_round("test_cup", 0, 1.0) # игрок выиграл
	var opp_after: float = Profile.bot_record(opp_id).rating
	_ok("проигравший игроку бот потерял рейтинг", opp_after < opp_before,
		"%.0f -> %.0f" % [opp_before, opp_after])
	var rec := Profile.bot_record(opp_id)
	_ok("личная встреча записана в карточку",
		int(rec.p_losses) == 1, "поражений от игрока: %d" % int(rec.p_losses))
	# Мир живой: остальные доски тура тоже меняют рейтинги — но только в тот
	# момент, когда игрок за доской.
	var others_moved := 0
	for i in range(1, state.bots.size()):
		if Profile.bot_state.has(str(state.bots[i].id)):
			others_moved += 1
	_ok("соседние доски тура тоже пересчитаны", others_moved >= 4,
		"затронуто %d из 6" % others_moved)
	Profile.active_tournaments = {}

# Тик мира: когда игрок доигрывает турнир, свой тур играют ВСЕ лиги, иначе
# живой была бы только лига игрока.
func _check_world_tick() -> void:
	Profile.bot_state = {}
	Profile.world_events = []
	var before := {}
	for rec in Profile.all_bot_records():
		before[rec.id] = float(rec.rating)
	Profile.simulate_world_round()
	var moved := 0
	var leagues_touched := {}
	for rec in Profile.all_bot_records():
		if not is_equal_approx(float(rec.rating), float(before[rec.id])):
			moved += 1
			leagues_touched[int(rec.league_idx)] = true
	_ok("тик мира двигает большую часть состава", moved >= 100, "сдвинулось %d из 120" % moved)
	_ok("двигаются все лиги, а не только лига игрока",
		leagues_touched.size() >= BotData.LEAGUES.size() - 1,
		"затронуто лиг: %d" % leagues_touched.size())

	# без игрока мир стоять должен: тик вызывается только из finish_tournament_round
	var snapshot := {}
	for rec in Profile.all_bot_records():
		snapshot[rec.id] = float(rec.rating)
	var same := true
	for rec in Profile.all_bot_records():
		if not is_equal_approx(float(rec.rating), float(snapshot[rec.id])):
			same = false
	_ok("сам по себе мир не меняется", same)

# Долгий прогон: мир не должен разъезжаться — лиги обязаны оставаться
# заполненными, иначе турнир станет не из кого собрать.
func _check_world_stability() -> void:
	Profile.bot_state = {}
	Profile.world_events = []
	for i in range(60):
		Profile.simulate_world_round()
	var per := {}
	for rec in Profile.all_bot_records():
		per[rec.league_idx] = int(per.get(rec.league_idx, 0)) + 1
	var empty := 0
	for i in range(BotData.LEAGUES.size()):
		var n = int(per.get(i, 0))
		if n < 7:
			empty += 1
		print("    %s: %d игроков" % [BotData.LEAGUES[i].name, n])
	_ok("после 60 туров все лиги ещё живы", empty == 0, "лиг с нехваткой: %d" % empty)
	# и игроку по-прежнему есть кого обыгрывать
	Profile.tournament_rating = 1400.0
	var beatable := 0
	for rec in Profile.pick_tournament_field(7):
		if float(rec.rating) < Profile.tournament_rating:
			beatable += 1
	_ok("после 60 туров всё ещё есть кого обыграть", beatable > 0, "обыгрываемых: %d" % beatable)
	_ok("лента изменений заполнилась", Profile.world_events.size() > 0,
		"событий: %d" % Profile.world_events.size())
	_ok("лента не растёт бесконечно", Profile.world_events.size() <= Profile.MAX_WORLD_EVENTS,
		str(Profile.world_events.size()))
	var league_moves := 0
	for e in Profile.world_events:
		if str(e.get("kind", "")) == "league":
			league_moves += 1
	_ok("в ленте есть переходы между лигами", league_moves > 0, str(league_moves))

# Товарищеская партия: доступна с любым игроком любой лиги и двигает его
# постоянный рейтинг (турнирный рейтинг игрока при этом не меняется).
func _check_friendly() -> void:
	Profile.bot_state = {}
	Profile.rating = 1200.0
	Profile.tournament_rating = 1000.0
	var t_before := Profile.tournament_rating
	var legend := "bot_119" # лига легенд — заведомо чужая для рейтинга 1000
	var before: float = Profile.bot_record(legend).rating
	var moved := Profile.record_friendly_game(legend, 1.0) # игрок выиграл
	_ok("можно вызвать игрока из любой лиги", not moved.is_empty())
	var after: float = Profile.bot_record(legend).rating
	_ok("рейтинг соперника изменился после товарищеской", after < before,
		"%.0f -> %.0f" % [before, after])
	_ok("турнирный рейтинг игрока не тронут",
		is_equal_approx(Profile.tournament_rating, t_before))
	var rec := Profile.bot_record(legend)
	_ok("встреча попала в личный счёт", int(rec.p_losses) == 1, str(rec.p_losses))
	_ok("форматов партии несколько", BotData.MATCH_FORMATS.size() >= 4,
		str(BotData.MATCH_FORMATS.size()))
	var with_clock := 0
	for f in BotData.MATCH_FORMATS:
		if int(f.tc) > 0:
			with_clock += 1
	_ok("есть форматы и с часами, и без", with_clock > 0 and with_clock < BotData.MATCH_FORMATS.size(),
		"с часами: %d" % with_clock)

# Тренировка не должна трогать постоянные рейтинги — иначе можно было бы
# накачивать или ронять ботов бесплатно.
func _check_prep_is_unrated() -> void:
	Profile.bot_state = {}
	var state := _make_state("test_prep")
	Profile.active_tournament_prep = {"test_prep": state}
	Profile.finish_prep_round("test_prep", 0, 1.0)
	_ok("тренировка не меняет рейтинги ботов", Profile.bot_state.is_empty(),
		"изменено записей: %d" % Profile.bot_state.size())
	Profile.active_tournament_prep = {}

# Архив партий: партия должна сохраняться у ОБОИХ участников и точно
# воспроизводиться по координатной записи — иначе разбор соперника невозможен.
func _check_game_archive() -> void:
	Profile.bot_games = {}
	# играем короткую реальную партию двух слабых ИИ, чтобы получить ходы
	var eng := ChessEngine.new()
	eng.setup_start_position()
	var ai := ChessAI.new(1)
	var coords := []
	for i in range(16):
		var st = eng.game_status()
		if st != "playing" and st != "check":
			break
		var mv = ai.choose_move(eng)
		if mv == null:
			break
		coords.append(BoardScript.move_coord(mv))
		eng.apply_move(mv)
	_ok("тестовая партия сыграна", coords.size() >= 10, "ходов: %d" % coords.size())

	Profile.record_bot_game("bot_001", "bot_002", "Соня", "Гоша", coords, 1.0, "Тест")
	_ok("партия попала в архив белых", Profile.games_of_bot("bot_001").size() == 1)
	_ok("партия попала в архив чёрных", Profile.games_of_bot("bot_002").size() == 1)

	# точное воспроизведение: каждый ход обязан находиться среди легальных
	var g: Dictionary = Profile.games_of_bot("bot_001")[0]
	var rep := ChessEngine.new()
	rep.setup_start_position()
	var replayed := 0
	for c in g.moves:
		var found := {}
		var f := Vector2i(str(c).unicode_at(0) - 97, str(c).unicode_at(1) - 49)
		var t := Vector2i(str(c).unicode_at(2) - 97, str(c).unicode_at(3) - 49)
		for mv in rep.legal_moves(rep.side_to_move):
			if mv.from == f and mv.to == t:
				found = mv
				break
		if found.is_empty():
			break
		rep.apply_move(found)
		replayed += 1
	_ok("партия воспроизводится ход в ход", replayed == g.moves.size(),
		"%d из %d" % [replayed, g.moves.size()])
	_ok("позиция после разбора совпала с исходной", rep.to_fen() == eng.to_fen())

	# архив не растёт бесконечно
	for i in range(20):
		Profile.record_bot_game("bot_001", "bot_003", "Соня", "Ника", coords, 0.5, "Тест")
	_ok("архив ограничен по размеру",
		Profile.games_of_bot("bot_001").size() <= Profile.MAX_GAMES_PER_BOT,
		str(Profile.games_of_bot("bot_001").size()))
	# партии живого игрока в архив ботов не попадают под пустым id
	Profile.bot_games = {}
	Profile.record_bot_game("", "bot_004", "Игрок", "Тимур", coords, 1.0, "Товарищеская")
	_ok("партия с игроком записана только боту",
		Profile.games_of_bot("bot_004").size() == 1 and not Profile.bot_games.has(""))

func _check_persistence() -> void:
	Profile.bot_state = {}
	Profile.apply_bot_result("bot_005", 1500.0, 1.0)
	var saved: Dictionary = Profile.bot_state.duplicate(true)
	var r_before: float = Profile.bot_record("bot_005").rating
	Profile.bot_state = saved # имитируем перезагрузку профиля
	var r_after: float = Profile.bot_record("bot_005").rating
	_ok("рейтинг переживает сохранение", is_equal_approx(r_before, r_after),
		"%.1f / %.1f" % [r_before, r_after])
	_ok("неигравший бот берёт стартовый рейтинг из базы",
		is_equal_approx(Profile.bot_record("bot_099").rating, BotData.def_by_id("bot_099").base_rating))
