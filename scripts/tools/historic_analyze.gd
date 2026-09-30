extends Node

# One-off diagnostic (not part of gameplay): for every historic game whose
# "notes" dict is empty or nearly empty, replays the PGN and prints every ply
# where something concrete happens — a big eval swing (mover's own material/
# position gain or blunder, white-centric _evaluate() before/after diffed and
# flipped to the mover's perspective), a capture of real value, a promotion,
# or checkmate — so hand-written commentary can be anchored to actual events
# in that specific game instead of invented from scratch.
# Run: godot --headless --path . res://scenes/tools/HistoricAnalyze.tscn

const HG = preload("res://scripts/HistoricGames.gd")
const GamesData = preload("res://scripts/HistoricGamesData.gd")

const SWING_THRESHOLD := 150.0
const CAPTURE_THRESHOLD := 300

func _ready() -> void:
	var coach := ChessAI.new(9)
	var players: Array = GamesData.players()
	for p in players:
		for g in p.games:
			var notes: Dictionary = g.get("notes", {})
			if notes.size() >= 3:
				continue # already has real hand commentary, skip
			print("\n=== GAME %s : %s vs %s (%d, %s) ===" % [g.id, g.white, g.black, g.year, g.event])
			print("PGN: " + str(g.get("pgn", "")))
			var eng := ChessEngine.new()
			if str(g.get("start_fen", "")) != "":
				eng.setup_from_fen(g.start_fen)
			else:
				eng.setup_start_position()
			var ply := 0
			var eval_before = coach.evaluate_position(eng)
			for san in HG.game_moves(g):
				var mv = HG._parse_san(eng, san)
				if mv.is_empty():
					print("  PARSE FAIL at ply %d (%s)" % [ply + 1, san])
					break
				var mover = eng.side_to_move
				var captured = eng.board[mv.to.y][mv.to.x]
				var cap_val = 0
				if captured != null:
					cap_val = ChessAI.PIECE_VALUE.get(captured.type, 0)
				elif mv.get("is_ep", false):
					cap_val = 100
				eng.apply_move(mv)
				ply += 1
				var eval_after = coach.evaluate_position(eng)
				var swing_white = eval_after - eval_before
				var swing_mover = swing_white if mover == ChessEngine.WHITE else -swing_white
				var status = eng.game_status()
				var flags := []
				if status == "checkmate":
					flags.append("MATE")
				elif eng.is_in_check(eng.side_to_move):
					flags.append("check")
				if mv.get("promo", "") != "":
					flags.append("promo=" + str(mv.promo))
				if cap_val >= CAPTURE_THRESHOLD:
					flags.append("captures %d" % cap_val)
				if absf(swing_mover) >= SWING_THRESHOLD:
					flags.append("swing %+d for mover" % int(swing_mover))
				if not flags.is_empty():
					var num = (ply + 1) / 2
					var mover_txt = "White" if mover == ChessEngine.WHITE else "Black"
					print("  ply %d (%d. %s, %s): eval %d -> %d [%s]" % [ply, num, mover_txt, san, int(eval_before), int(eval_after), ", ".join(flags)])
				eval_before = eval_after
	print("\n=== DONE ===")
	get_tree().quit()
