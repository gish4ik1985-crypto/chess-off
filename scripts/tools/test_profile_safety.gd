extends SceneTree

# Сохранение профиля: атомарная запись, откат к .bak, запрет затирать нечитаемое.
#   godot --headless -s res://scripts/tools/test_profile_safety.gd
# Работает только с собственным игроком "zz_safety_test" и убирает за собой.

const KEY := "zz_safety_test"
var failures := 0

func check(cond: bool, what: String) -> void:
	if cond:
		print("OK   ", what)
	else:
		failures += 1
		print("FAIL ", what)

func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)

func _fresh():
	var p = load("res://scripts/Profile.gd").new()
	p.current_user = KEY
	p.display_name = "Zz"
	return p

func _init() -> void:
	var dir: String = load("res://scripts/Profile.gd").USERS_DIR
	DirAccess.make_dir_recursive_absolute(dir)
	var path: String = dir + KEY + ".cfg"

	var p = _fresh()
	p.games_played = 7
	p.save_profile()
	check(FileAccess.file_exists(path), "профиль записан")
	check(not FileAccess.file_exists(path + ".tmp"), "временного файла не осталось")
	p.games_played = 8
	p.save_profile()
	check(FileAccess.file_exists(path + ".bak"), "после второй записи есть .bak")

	# обрыв записи: файл обрезан посреди словаря
	_write(path, "[meta]\ndisplay_name=\"Zz\"\n[puzzles]\nsolved={\n\"1\": tru")
	var p2 = _fresh()
	p2.load_profile()
	check(p2.games_played == 7, "обрезанный файл восстановлен из .bak (games_played=%d)" % p2.games_played)
	check(not p2._load_failed, "после восстановления профиль не помечен сломанным")

	# сломаны и файл, и копия
	_write(path, "[stats]\ngames_played=")
	_write(path + ".bak", "[stats\nmusor")
	var p3 = _fresh()
	p3.load_profile()
	check(p3._load_failed, "нечитаемый профиль без копии помечен сломанным")
	var before := _read(path)
	p3.save_profile()
	check(_read(path) == before, "нечитаемый профиль не затёрт пустым")

	# новый игрок (файла нет) — не ошибка
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".bak")
	var p4 = _fresh()
	p4.load_profile()
	check(not p4._load_failed, "новый игрок не считается сломанным")
	p4.save_profile()
	check(FileAccess.file_exists(path), "новый игрок сохраняется")

	# мягкое удаление
	p4.delete_user(KEY)
	check(not FileAccess.file_exists(path), "после удаления файла в списке нет")
	var moved := 0
	var d := DirAccess.open(dir + "_deleted")
	if d != null:
		for f in d.get_files():
			if f.begins_with(KEY + "_"):
				moved += 1
				DirAccess.remove_absolute(dir + "_deleted/" + f)
	check(moved == 1, "удалённый профиль лежит в _deleted/ (%d)" % moved)

	DirAccess.remove_absolute(path + ".bak")

	# объединение копий с двух устройств: планшет решил 5 вилок и прошёл узел карты, компьютер со
	# старым профилем сохранился позже — после объединения ничего из решённого не пропадает
	var P = load("res://scripts/Profile.gd")
	var tab := ConfigFile.new()
	tab.set_value("meta", "last_played_unix", 1000)
	tab.set_value("puzzles", "fork_solved", 5)
	tab.set_value("map", "defeated", {"pawn_timofey": true, "task_mate": true})
	tab.set_value("achievements", "unlocked", {"fork_first": true})
	tab.set_value("puzzles", "generated_solved", {"fork|a": true})
	tab.set_value("rating", "value", 1300.0)
	tab.set_value("about", "city", "Ярославль")
	var pc := ConfigFile.new()
	pc.set_value("meta", "last_played_unix", 2000)
	pc.set_value("puzzles", "fork_solved", 0)
	pc.set_value("map", "defeated", {"pawn_timofey": true})
	pc.set_value("stats", "games_played", 3)
	pc.set_value("puzzles", "generated_solved", {"pin|b": true})
	pc.set_value("rating", "value", 1250.0)
	pc.set_value("about", "city", "")
	check(P.merge_cfg(pc, tab), "объединение что-то добавило")
	check(int(pc.get_value("puzzles", "fork_solved")) == 5, "вилки: 5 с планшета не потерялись")
	check((pc.get_value("map", "defeated") as Dictionary).has("task_mate"), "узел карты с планшета сохранился")
	check((pc.get_value("achievements", "unlocked") as Dictionary).has("fork_first"), "награда с планшета появилась")
	check((pc.get_value("puzzles", "generated_solved") as Dictionary).size() == 2, "решённые задачи объединены")
	check(int(pc.get_value("stats", "games_played")) == 3, "партии с компьютера остались")
	check(float(pc.get_value("rating", "value")) == 1250.0, "рейтинг — с более свежей копии")
	check(String(pc.get_value("about", "city")) == "", "анкета — с более свежей копии")
	check(not P.merge_cfg(pc, tab), "повторное объединение ничего не меняет")

	print("ИТОГО ошибок: %d" % failures)
	quit(1 if failures > 0 else 0)
