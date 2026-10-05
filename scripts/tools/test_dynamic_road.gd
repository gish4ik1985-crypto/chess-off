extends SceneTree

# Headless sanity test for the dynamic road stages:
#   godot --headless -s res://scripts/tools/test_dynamic_road.gd
# Feeds a fake game log into a bare Profile instance and checks that
# weakness stages appear, disappear when games get clean, and that stale
# "done" marks are dropped.

func _init() -> void:
	var profile = load("res://scripts/Profile.gd").new()

	# empty log -> no stages
	assert(profile.dynamic_road_stages().is_empty(), "empty log must yield no stages")

	# 5 games full of blunders and opening errors
	for i in range(5):
		profile.game_log.append({"blunder": 2, "err_opening": 1, "err_middlegame": 0, "err_endgame": 0})
	var st = profile.dynamic_road_stages()
	var kinds = st.map(func(s): return s.kind)
	assert("focus_blunders" in kinds, "blunder weakness must appear")
	assert("focus_opening" in kinds, "opening weakness must appear")
	assert(not "focus_endgame" in kinds, "no endgame weakness expected")
	print("grow OK: ", kinds)

	# mark one done, then play clean games until the window is clean
	profile.road_focus_done["focus_blunders"] = true
	for i in range(8):
		profile.game_log.append({"blunder": 0, "err_opening": 0, "err_middlegame": 0, "err_endgame": 0})
	st = profile.dynamic_road_stages()
	assert(st.is_empty(), "clean window must remove all stages")
	assert(profile.road_focus_done.is_empty(), "stale done marks must be dropped")
	print("shrink OK")

	# legacy entries without err_* fields fall back to worst_move_no
	profile.game_log.clear()
	for i in range(5):
		profile.game_log.append({"blunder": 0, "worst_move_no": 30})
	st = profile.dynamic_road_stages()
	kinds = st.map(func(s): return s.kind)
	assert("focus_endgame" in kinds, "legacy worst_move_no must map to endgame")
	print("legacy OK: ", kinds)

	# слабая тема задач даёт остановку-тренажёр, чистая тема — нет
	profile.game_log.clear()
	profile.fork_puzzles_solved = 8
	profile.theme_clean["fork"] = 1
	st = profile.dynamic_road_stages()
	kinds = st.map(func(s): return s.kind)
	assert("focus_tactics" in kinds and st[0].theme == "fork", "weak theme must add a tactics stage")
	profile.theme_clean["fork"] = 6
	assert(profile.dynamic_road_stages().is_empty(), "clean theme must not add a stage")
	print("tactics OK")

	# ворота нельзя пройти повтором: одна и та же задача/зевок в зачёт идёт один раз
	var gp = load("res://scripts/Profile.gd").new()
	assert(gp.mark_solved_once("fork", "fen-a"), "первое решение засчитывается")
	assert(not gp.mark_solved_once("fork", "fen-a"), "повтор той же задачи не засчитывается")
	assert(gp.mark_solved_once("pin", "fen-a"), "та же позиция в другой теме — отдельная задача")
	assert(gp.record_road_blunder_fix("fen-z"), "первое исправление зевка засчитывается")
	assert(not gp.record_road_blunder_fix("fen-z"), "тот же зевок второй раз не засчитывается")
	assert(gp.road_blunders_fixed == 1, "счётчик зевков не вырос от повтора")
	print("gates OK")

	print("ALL DYNAMIC ROAD TESTS PASSED")
	quit(0)
