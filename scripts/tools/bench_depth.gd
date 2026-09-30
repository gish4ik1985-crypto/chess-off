extends Node

# Сколько стоит ход на разных глубинах (для подбора верхних уровней). scenes/tools/BenchDepth.tscn
func _ready() -> void:
	var fens := [
		"r1bq1rk1/pp2bppp/2n1pn2/2pp4/3P1B2/2PBPN2/PP1N1PPP/R2QK2R w KQ - 0 8",
		"r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
		"2rq1rk1/pp1bppbp/2np1np1/8/3NP3/2N1BP2/PPPQ2PP/2KR1B1R w - - 0 10",
	]
	for d in [3, 4, 5, 6]:
		var total := 0
		for f in fens:
			var e := ChessEngine.new()
			e.setup_from_fen(f)
			var ai := ChessAI.new(12)
			ai.move_time_ms = 60000
			ChessAI.PARAMS[11] = {"d": d, "q": 2, "b": 0.0, "n": 0.0}
			var t := Time.get_ticks_msec()
			ai.choose_move(e)
			total += Time.get_ticks_msec() - t
		print("глубина %d (q2): в среднем %d мс на ход" % [d, total / fens.size()])
	get_tree().quit()
