extends Node

# Домашние задания, роли и доска заданий: расчёт прогресса, права, запись и поиск ходов.
# Запуск: scenes/tools/TestHomework.tscn

var fails := 0

func check(name: String, ok: bool, info: String = "") -> void:
	print(("OK   " if ok else "FAIL ") + name + (" " + info if info != "" else ""))
	if not ok:
		fails += 1

func _ready() -> void:
	Profile.switch_user("Тест ДЗ", false)
	# ходы: запись и поиск
	var eng := ChessEngine.new()
	eng.setup_start_position()
	var m := BoardView.find_move(eng, "e2e4")
	check("e2e4 найден на старте", not m.is_empty() and BoardView.uci_of(m) == "e2e4")
	check("e2e5 недопустим", BoardView.find_move(eng, "e2e5").is_empty())
	eng.setup_from_fen("8/P7/8/8/8/8/8/k6K w - - 0 1")
	var pm := BoardView.find_move(eng, "a7a8")
	check("превращение без буквы даёт ферзя", not pm.is_empty() and String(pm.get("promo", "")) == "Q")
	check("превращение с буквой", not BoardView.find_move(eng, "a7a8q").is_empty())
	# счётчики и прогресс
	var a := {"_id": "ztest", "kind": "metric", "metric": "wins", "target": 2, "active": true}
	check("до «Начать» не начато", not Homework.started(a))
	Homework.begin(a)
	check("после «Начать» начато", Homework.started(a))
	check("прогресс 0 сразу после старта", Homework.progress(a) == 0)
	Profile.wins += 2
	check("две победы — прогресс 2", Homework.progress(a) == 2)
	# срок и адресат
	var past := {"deadline": int(Time.get_unix_time_from_system()) - 10}
	var future := {"deadline": int(Time.get_unix_time_from_system()) + 1000}
	check("срок прошёл", Homework.is_overdue(past) and not Homework.is_overdue(future))
	check("без срока не просрочено", not Homework.is_overdue({"deadline": 0}))
	Profile.club_group = "Группа А"
	check("для всех", Homework.for_me({"group": "", "active": true}))
	check("для моей группы без учёта регистра", Homework.for_me({"group": "группа а", "active": true}))
	check("чужая группа не мне", not Homework.for_me({"group": "Б", "active": true}))
	check("закрытое не показывается", not Homework.for_me({"group": "", "active": false}))
	# роли
	check("ученик не открывает панель", not Roles.can("player", "open_admin"))
	check("тренер открывает, но не раздаёт роли", Roles.can("coach", "open_admin") and not Roles.can("coach", "manage_roles"))
	check("админ может всё", Roles.can("admin", "manage_roles") and Roles.can("admin", "game_settings"))
	check("настройки игры только у админа", not Roles.can("moderator", "game_settings"))
	check("разряд по рейтингу", Roles.approx_rank(1000) == "≈ 3 разряд" and Roles.approx_rank(500) == "без разряда")
	# ФИО
	check("два слова — подходит", Cloud.valid_full_name("Иванов Пётр"))
	check("одно слово — нет", not Cloud.valid_full_name("Иванов"))
	check("лишние пробелы убираются", Cloud.normalize_name("  Иванов   Пётр ") == "Иванов Пётр")
	# запись партий
	var e2 := ChessEngine.new()
	e2.setup_start_position()
	check("SAN e4", GameRecord.san(e2, BoardView.find_move(e2, "e2e4")) == "e4")
	check("SAN Nf3", GameRecord.san(e2, BoardView.find_move(e2, "g1f3")) == "Nf3")
	check("русское Кf3", not GameRecord.parse_move(e2, "Кf3").is_empty())
	check("русское е4 (кириллица)", not GameRecord.parse_move(e2, "е4").is_empty())
	check("координатами e2-e4", not GameRecord.parse_move(e2, "e2-e4").is_empty())
	check("мусор не ход", GameRecord.parse_move(e2, "Фh7").is_empty())
	var pgn := GameRecord.parse_pgn("[White \"Иванов\"]
[Black \"Петров\"]

1. e4 e5 2. Nf3 {хорошо} Nc6 (2... d6) 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 1-0")
	check("PGN: 10 ходов", pgn.sans.size() == 10, str(pgn.sans.size()))
	check("PGN: заголовок и результат", pgn.headers.get("White", "") == "Иванов" and pgn.result == "1-0")
	check("PGN: комментарий у 3-го хода", String(pgn.comments[2]) == "хорошо")
	var rp := GameRecord.replay(pgn.sans)
	check("PGN: все ходы допустимы", rp.ok, str(rp.bad))
	check("рокировка записана как O-O", rp.sans[8] == "O-O")
	var bad := GameRecord.replay(["e4", "e4"])
	check("плохой ход найден по номеру", not bad.ok and bad.bad == 1)
	var out := GameRecord.build_pgn({"White": "А", "Black": "Б"}, rp.sans, pgn.comments, "1-0")
	var back := GameRecord.parse_pgn(out)
	check("PGN туда-обратно", back.sans == rp.sans and String(back.comments[2]) == "хорошо")
	var e3 := ChessEngine.new()
	e3.setup_from_fen("7k/P7/8/8/8/8/8/K7 w - - 0 1")
	check("SAN превращение", GameRecord.san(e3, BoardView.find_move(e3, "a7a8q")).begins_with("a8=Q"))
	# турниры школы
	var four := []
	for n in ["А", "Б", "В", "Г"]:
		four.append({"uid": "u" + n, "name": n})
	var rr := ClubTourney.round_robin(four)
	var seen := {}
	var dup := false
	for rd in rr:
		for pr in rd:
			var k: String = pr.w.uid + "|" + pr.b.uid if pr.w.uid < pr.b.uid else pr.b.uid + "|" + pr.w.uid
			if seen.has(k):
				dup = true
			seen[k] = true
	check("круговая на 4: 3 тура, 6 разных пар", rr.size() == 3 and seen.size() == 6 and not dup, "%d/%d" % [rr.size(), seen.size()])
	var five := four.duplicate()
	five.append({"uid": "uД", "name": "Д"})
	var rr5 := ClubTourney.round_robin(five)
	var byes := {}
	for rd in rr5:
		for pr in rd:
			if pr.b == null:
				byes[pr.w.uid] = true
	check("круговая на 5: 5 туров, у каждого один пропуск", rr5.size() == 5 and byes.size() == 5)
	var sw := ClubTourney.swiss_round(four, {"uА": 1.0, "uБ": 1.0, "uВ": 0.0, "uГ": 0.0}, {}, {}, [])
	check("швейцарка: лидеры играют между собой", sw.size() == 2 and (sw[0].w.uid in ["uА", "uБ"]) and (sw[0].b.uid in ["uА", "uБ"]))
	var sw5 := ClubTourney.swiss_round(five, {}, {}, {}, [])
	var has_bye := false
	for pr in sw5:
		if pr.b == null:
			has_bye = true
	check("швейцарка на 5: один пропуск", sw5.size() == 3 and has_bye)
	var games := [
		{"status": "done", "wuid": "uА", "buid": "uБ", "wname": "А", "bname": "Б", "result": "1-0"},
		{"status": "done", "wuid": "uВ", "buid": "uГ", "wname": "В", "bname": "Г", "result": "1/2-1/2"},
		{"status": "play", "wuid": "uА", "buid": "uВ", "wname": "А", "bname": "В", "result": ""},
	]
	var st := ClubTourney.standings(games)
	check("таблица: лидер А с 1 очком", st[0].name == "А" and st[0].pts == 1.0)
	check("таблица: ничья по ½", st[1].pts == 0.5 and st[2].pts == 0.5 and st[3].pts == 0.0)
	var sm := ClubTourney.summarize(games)
	check("сводка: очки и сыгранные пары", sm.scores.get("uА", 0.0) == 1.0 and sm.played.size() == 2)
	check("очки текстом", ClubTourney.pts_text(2.5) == "2½" and ClubTourney.pts_text(0.5) == "½" and ClubTourney.pts_text(3.0) == "3")
	print("ИТОГО ошибок: %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
