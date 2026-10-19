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
	print("ИТОГО ошибок: %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
