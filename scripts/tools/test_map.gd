# Offline check of the 3-act map roster: node count, unique ids, and that
# every drill/restriction start_fen loads into a playable position.
# Runs as a scene, not `-s`/SceneTree script mode — that mode skips autoload
# init, and ChessEngine.gd references the Global autoload, so it fails to
# compile there (same issue test_scenes.gd's header documents).
# godot --headless --path . res://scenes/tools/TestMap.tscn
extends Node

const LEVEL_STEP_MAX := 1

func _ready() -> void:
	var chars = MapData.CHARACTERS
	print("total nodes: ", chars.size())
	var ids := {}
	var bad := 0
	for c in chars:
		if ids.has(c.id):
			print("DUPLICATE id: ", c.id)
			bad += 1
		ids[c.id] = true
		for key in ["name", "pos", "palette", "music", "act"]:
			if not c.has(key):
				print("missing %s on %s" % [key, c.id])
				bad += 1
		if c.has("start_fen"):
			var e = ChessEngine.new()
			e.setup_from_fen(c.start_fen)
			if e.game_status() != "playing" or e.is_in_check("b"):
				print("BAD start_fen on %s: %s" % [c.id, c.start_fen])
				bad += 1
	for act in [1, 2, 3]:
		var n = 0
		for c in chars:
			if c.act == act:
				n += 1
		print("act %d: %d nodes" % [act, n])
	# кривая сложности: соседние узлы акта отличаются не больше чем на LEVEL_STEP_MAX,
	# а уровень не падает (иначе «учебный» узел страшнее босса)
	for act in [1, 2, 3]:
		var seq := []
		var prev := -1
		for c in chars:
			if c.act != act:
				continue
			var lvl := int(c.ai_level)
			seq.append(lvl)
			if prev >= 0 and (lvl - prev > LEVEL_STEP_MAX or prev - lvl > 0):
				print("РВАНАЯ КРИВАЯ в акте %d на %s: %d -> %d" % [act, c.id, prev, lvl])
				bad += 1
			prev = lvl
		print("act %d levels: %s" % [act, seq])
	print("problems: ", bad)
	get_tree().quit(1 if bad > 0 else 0)
