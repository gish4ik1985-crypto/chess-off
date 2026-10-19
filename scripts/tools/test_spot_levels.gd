extends Node

# «Что изменилось?» (Школа): три уровня. Проверяем правила ответов на настоящей доске:
# лёгкий — одна клетка «куда»; средний и сложный — «откуда», потом «куда»; доска закрыта на сложном
# до ответа; серия из 5 верных повышает уровень, промах серию сбрасывает.
# Запуск: scenes/tools/TestSpotLevels.tscn

var fails := 0

func check(name: String, ok: bool, info: String = "") -> void:
	print(("OK   " if ok else "FAIL ") + name + (" " + info if info != "" else ""))
	if not ok:
		fails += 1

func _enter() -> Node:
	var inst: Node = load("res://scenes/Board.tscn").instantiate()
	get_tree().root.add_child(inst)
	get_tree().current_scene = inst
	for i in 3:
		await get_tree().process_frame
	return inst

# Подставляет ход соперника (чёрные e7-e5) и открывает вопрос, как после настоящего хода ИИ.
func _ask(b: Node) -> void:
	b.engine.setup_start_position()
	b.engine.apply_move({"from": Vector2i(4, 1), "to": Vector2i(4, 3)})
	b.engine.side_to_move = "w"
	b._school_after_ai_move()
	b.spot_flash_until = 0 # вспышка уже прошла

func _run_level(level: int) -> void:
	Profile.school_spot_level = level
	Profile.school_spot_streak = 0
	Global.school_mode = "spot"
	Global.player_color = "w"
	var b := await _enter()
	check("уровень %d: режим стартует с нужным уровнем" % level, b.spot_level == level)
	_ask(b)
	check("уровень %d: вопрос открыт" % level, b.awaiting_spot)
	if level == 3:
		check("сложный: доска закрыта, пока не ответишь", b._spot_flash_active())
	var last = b.engine.last_move
	if level == 1:
		b._spot_handle_click(last.to)
		check("лёгкий: верная клетка «куда» засчитана", b.spot_hits == 1 and not b.awaiting_spot)
	else:
		b._spot_handle_click(last.to)
		check("уровень %d: сначала нужна клетка «откуда» — «куда» не засчитывается" % level, b.awaiting_spot and b.spot_hits == 0 and b.spot_stage == 0)
		b._spot_handle_click(last.from)
		check("уровень %d: «откуда» принято, ждём «куда»" % level, b.awaiting_spot and b.spot_stage == 1)
		b._spot_handle_click(last.to)
		check("уровень %d: «откуда» и «куда» верно — ход засчитан" % level, b.spot_hits == 1 and not b.awaiting_spot)
		if level == 3:
			check("сложный: после ответа фигуры вернулись", not b._spot_flash_active())
	# две ошибки подряд — ответ показан, серия сброшена
	Profile.school_spot_streak = 3
	_ask(b)
	var wrong := Vector2i(0, 0) if b.engine.last_move.to != Vector2i(0, 0) and b.engine.last_move.from != Vector2i(0, 0) else Vector2i(7, 7)
	var want_first: Vector2i = b.engine.last_move.to if level == 1 else b.engine.last_move.from
	if wrong == want_first:
		wrong = Vector2i(6, 6)
	b._spot_handle_click(wrong)
	b._spot_handle_click(wrong)
	check("уровень %d: две ошибки — ответ показан, серия сброшена" % level, not b.awaiting_spot and Profile.school_spot_streak == 0)
	b.queue_free()
	await get_tree().process_frame

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	Profile.switch_user("ШколаТест", false)
	for lvl in [1, 2, 3]:
		await _run_level(lvl)
	# 5 верных подряд на лёгком — повышение до среднего
	Profile.school_spot_level = 1
	Profile.school_spot_streak = 0
	Global.school_mode = "spot"
	var b := await _enter()
	for i in 5:
		_ask(b)
		b._spot_handle_click(b.engine.last_move.to)
	check("5 верных подряд повысили уровень до среднего", b.spot_level == 2 and Profile.school_spot_level == 2)
	b.queue_free()
	Global.school_mode = ""
	Profile.delete_user("ШколаТест")
	print("=== ИТОГО ошибок: %d ===" % fails)
	get_tree().quit(1 if fails > 0 else 0)
