extends Node

# Снимки всех экранов в выбранных темах — для проверки оформления глазами.
# Запуск (НЕ headless, нужен рендер; профили — в песочнице через APPDATA):
#   godot --path . res://scenes/tools/Shots.tscn -- themes=neon,wood out=C:/tmp/shots [scenes=Menu,Board]
# Сцена-инструмент живёт отдельно от игровых: экраны грузятся как дети этого узла.

const SCENES := ["Login", "Menu", "Board", "Puzzle", "PuzzleHub", "Map", "RoadHome", "Tournaments",
	"TournamentPrep", "BotsHub", "Diary", "Achievements", "TrophyRoom", "AttentionHub", "School",
	"HistoricGames", "Settings", "Players", "Appearance", "Admin", "Homework"]

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var themes: PackedStringArray = String(args.get("themes", "neon")).split(",")
	var out := String(args.get("out", "user://shots"))
	var only: PackedStringArray = String(args.get("scenes", "")).split(",", false)
	DirAccess.make_dir_recursive_absolute(out)
	Profile.switch_user("Тест", false)
	if args.has("demo"):
		# немного прогресса, чтобы на снимках были видны полученные награды (только в песочнице)
		for id in ["first_win", "wins_5", "streak_3", "puzzle_10", "tourney_win", "rating_1600", "act3_legend", "rating_2400", "puzzle_50", "beat_level_10"]:
			Profile.unlocked_achievements[id] = true
		Profile.tournament_titles = {"school_cup": 2, "daily": 1}
		Profile.fork_puzzles_solved = 6
		Profile.game_state = {"fen": "", "move_history": ["e4", "e5", "Nf3"], "difficulty": 5, "player_color": "w"}
		Profile.streak_count = 4
		Profile.streak_last_day = "2000-01-01"
	if args.has("admin"):
		Profile.role = "admin"
	await get_tree().process_frame
	for t in themes:
		Themes.set_theme_id(t)
		for s in SCENES:
			if only.size() > 0 and not (s in only):
				continue
			await _shot("res://scenes/%s.tscn" % s, "%s/%s_%s.png" % [out, t, s])
			if s == "Homework":
				await _shot("res://scenes/Homework.tscn", "%s/%s_HomeworkBuilder.png" % [out, t], "_open_builder_for_shot")
			if s == "Diary":
				await _shot("res://scenes/Diary.tscn", "%s/%s_DiaryAbout.png" % [out, t], "_open_about_tab")
			if s == "Login" and Cloud.enabled:
				await _shot("res://scenes/Login.tscn", "%s/%s_LoginOnline.png" % [out, t], "_open_online_window")
			if s == "Menu":
				for extra in [["MenuPlay", "_on_play_menu_pressed"], ["MenuTrain", "_on_train_menu_pressed"],
						["MenuTourney", "_on_tourney_menu_pressed"], ["MenuBell", "_show_notifications"]]:
					await _shot("res://scenes/Menu.tscn", "%s/%s_%s.png" % [out, t, extra[0]], extra[1])
	get_tree().quit()

# Экран добавляется рядом с инструментом (change_scene_to_file выгрузил бы сам инструмент).
func _shot(path: String, file: String, call_after: String = "") -> void:
	var inst: Node = load(path).instantiate()
	get_tree().root.add_child(inst)
	get_tree().current_scene = inst
	for i in 4:
		await get_tree().process_frame
	if call_after != "" and is_instance_valid(inst) and inst.has_method(call_after):
		inst.call(call_after)
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(file)
	print("shot ", file)
	if is_instance_valid(inst):
		inst.queue_free()
	# экран мог сам сменить сцену (например, вход без игрока) — убираем всё лишнее
	for ch in get_tree().root.get_children():
		if ch != self and ch.scene_file_path != "" and not (ch.name in ["Global", "Profile", "Themes", "Cloud"]):
			ch.queue_free()
	await get_tree().process_frame
