extends Node

# Навигация «Назад»: стопка возвратов и подменю главного экрана, а также то, что каждый раздел,
# открываемый из меню, умеет вернуть обратно. Запуск: scenes/tools/TestNav.tscn

var fails := 0

func check(name: String, ok: bool, info: String = "") -> void:
	print(("OK   " if ok else "FAIL ") + name + (" " + info if info != "" else ""))
	if not ok:
		fails += 1

func _ready() -> void:
	Global.back_stack.clear()
	check("пустая стопка: «откуда» неизвестно", Global.came_from() == "")
	# меню → подменю «Учиться» → карта → задачи
	Global.back_stack.append({"scene": Global.MENU_SCENE, "panel": "train"})
	Global.back_stack.append({"scene": "res://scenes/Map.tscn", "panel": ""})
	check("из задач помним карту", Global.came_from().ends_with("Map.tscn"))
	var t: Dictionary = Global.back_stack.pop_back()
	check("после возврата с карты остаётся подменю", Global.came_from() == Global.MENU_SCENE and Global.back_stack.back().panel == "train", str(t))
	Global.back_stack.clear()

	# каждый раздел из меню возвращает через Global.go_back, а не жёстко на главный экран
	for f in ["Diary", "Tournaments", "TournamentPrep", "BotsHub", "HistoricGames", "School", "AttentionHub",
			"PuzzleHub", "Map", "RoadHome", "Settings"]:
		var src := FileAccess.get_file_as_string("res://scripts/%s.gd" % f)
		check("%s: «Назад» через go_back" % f, src.contains("Global.go_back("))
	var puzzle := FileAccess.get_file_as_string("res://scripts/Puzzle.gd")
	check("Puzzle: возврат на карту/дорогу", puzzle.contains("_origin_scene") and puzzle.contains("Global.go_back()"))
	for f in ["Map", "RoadHome"]:
		var src := FileAccess.get_file_as_string("res://scripts/%s.gd" % f)
		check("%s: задачи открываются с запоминанием возврата" % f, src.contains('Global.open("res://scenes/Puzzle.tscn"'))
	await _flow_tests()
	print("=== ИТОГО ошибок: %d ===" % fails)
	get_tree().quit(1 if fails > 0 else 0)

# Живой прогон: экраны открываются по-настоящему, «Назад» должен вернуть в то же подменю.
func _enter(path: String) -> Node:
	var inst: Node = load(path).instantiate()
	get_tree().root.add_child(inst)
	get_tree().current_scene = inst
	for i in 3:
		await get_tree().process_frame
	return inst

func _current() -> Node:
	for i in 4:
		await get_tree().process_frame
	return get_tree().current_scene

func _flow_tests() -> void:
	await get_tree().process_frame # корень дерева ещё занят добавлением этой сцены
	await get_tree().process_frame
	Profile.switch_user("НавТест", false)
	var menu := await _enter("res://scenes/Menu.tscn")
	menu._on_tourney_menu_pressed()
	menu._on_tournaments_pressed()
	var scr := await _current()
	check("из «Соревнований» открылись «Турниры»", scr != null and scr.name == "Tournaments")
	scr._on_menu_pressed()
	var back := await _current()
	check("«Назад» из турниров — снова подменю «Соревнования»", back != null and back.name == "Menu" and back.tourney_panel.visible)

	back._on_train_menu_pressed()
	back._on_road_pressed()
	scr = await _current()
	check("из «Учиться» открылась «Дорога домой»", scr != null and scr.name == "RoadHome")
	scr._on_menu_pressed()
	back = await _current()
	check("«Назад» с дороги — подменю «Учиться»", back != null and back.name == "Menu" and back.train_panel.visible)

	back._on_train_menu_pressed()
	back._open("res://scenes/Map.tscn")
	scr = await _current()
	Global.open("res://scenes/Puzzle.tscn", "res://scenes/Map.tscn")
	var pz := await _current()
	check("с карты открылись задачи", pz != null and pz.name == "Puzzle")
	pz._on_hub_pressed()
	scr = await _current()
	check("«Все задачи» с карты возвращает на карту", scr != null and scr.name == "Map")
	scr._on_menu_pressed()
	back = await _current()
	check("и из карты — снова в «Учиться»", back != null and back.name == "Menu" and back.train_panel.visible)
	Profile.delete_user("НавТест")
