# Offline check: replays every PuzzleData line move-by-move against the
# engine and confirms each ends in checkmate.
# Runs as a scene, not `-s`/SceneTree script mode — that mode skips autoload
# init, and ChessEngine.gd references the Global autoload, so it fails to
# compile there (same issue test_scenes.gd's header documents).
# godot --headless --path . res://scenes/tools/VerifyPuzzles.tscn
extends Node

func _ready() -> void:
	var bad := 0
	var puzzles = PuzzleData.all()
	for i in range(puzzles.size()):
		var p = puzzles[i]
		var e = ChessEngine.new()
		e.setup_from_fen(p.fen)
		var ok := true
		for mv in p.moves:
			var from = Vector2i("abcdefgh".find(mv[0]), int(mv[1]) - 1)
			var to = Vector2i("abcdefgh".find(mv[2]), int(mv[3]) - 1)
			var found = null
			for m in e.legal_moves():
				if m.from == from and m.to == to:
					found = m
					break
			if found == null:
				ok = false
				break
			e.apply_move(found)
		if not ok or e.game_status() != "checkmate":
			bad += 1
			print("BAD puzzle %d: %s" % [i, p.fen])
	# проверка ответов в UI: хранимый первый ход принимается, тихий альтернативный мат тоже,
	# а ход, после которого мат не форсирован, — нет
	var pz = load("res://scripts/Puzzle.gd").new()
	for i in range(puzzles.size()):
		var p2 = puzzles[i]
		var e2 = ChessEngine.new()
		e2.setup_from_fen(p2.fen)
		var mv0: String = p2.moves[0]
		var m0 = null
		for m in e2.legal_moves():
			if m.from == Vector2i("abcdefgh".find(mv0[0]), int(mv0[1]) - 1) and m.to == Vector2i("abcdefgh".find(mv0[2]), int(mv0[3]) - 1):
				m0 = m
				break
		if m0 == null or not pz._move_forces_mate(e2, m0, p2.mate_in):
			bad += 1
			print("UI не принимает хранимое решение задачи %d" % i)
	var q = ChessEngine.new()
	q.setup_from_fen("k7/8/2K5/5Q2/8/8/8/8 w - - 0 1")
	var quiet = null
	var wrong = null
	for m in q.legal_moves():
		if m.from == Vector2i(2, 5) and m.to == Vector2i(2, 6):
			quiet = m # Kc6-c7: тихий, но форсирует мат в 2
		if m.from == Vector2i(5, 4) and m.to == Vector2i(5, 3):
			wrong = m # Qf5-f4: мата не форсирует
	if quiet == null or not pz._move_forces_mate(q, quiet, 2):
		bad += 1
		print("тихий мат в 2 (Kc7) не принят")
	if wrong == null or pz._move_forces_mate(q, wrong, 2):
		bad += 1
		print("ход без форсированного мата принят")
	pz.free()
	print("checked %d puzzles, bad: %d" % [puzzles.size(), bad])
	get_tree().quit(1 if bad > 0 else 0)
