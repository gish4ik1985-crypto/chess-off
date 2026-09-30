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
	print("checked %d puzzles, bad: %d" % [puzzles.size(), bad])
	get_tree().quit(1 if bad > 0 else 0)
