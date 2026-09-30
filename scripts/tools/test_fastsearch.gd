extends Node

# Проверка быстрого ядра поиска: перебор ходов (perft) против эталонных чисел,
# согласованность хэша/оценки после случайных партий и совпадение качества
# выбора со старым алгоритмом ChessAI. Запуск: scenes/tools/TestFastSearch.tscn

const FS = preload("res://scripts/FastSearch.gd")
var fails := 0

func tables() -> Array:
	return [ChessAI.PAWN_PST, ChessAI.KNIGHT_PST, ChessAI.BISHOP_PST, ChessAI.ROOK_PST, ChessAI.QUEEN_PST, ChessAI.KING_PST]

func check(name: String, ok: bool, info: String = "") -> void:
	print(("OK   " if ok else "FAIL ") + name + " " + info)
	if not ok:
		fails += 1

func perft(fs, d: int) -> int:
	var moves = fs.gen(false)
	var n := 0
	for m in moves:
		fs.make(m)
		if not fs._illegal_after_make():
			n += 1 if d == 1 else perft(fs, d - 1)
		fs.unmake(m)
	return n

func engine_perft(e: ChessEngine, d: int) -> int:
	var moves = e.legal_moves()
	if d == 1:
		return moves.size()
	var n := 0
	for m in moves:
		var c = e.clone()
		c.apply_move(m)
		n += engine_perft(c, d - 1)
	return n

func fast_from_fen(fen: String):
	var e := ChessEngine.new()
	e.setup_from_fen(fen)
	var fs = FS.new(tables(), 0)
	fs.load_engine(e)
	return fs

func _ready() -> void:
	var cases := [
		["start", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", [20, 400, 8902, 197281]],
		["kiwipete", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", [48, 2039, 97862]],
		["pos3", "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", [14, 191, 2812, 43238]],
	]
	for c in cases:
		var fs = fast_from_fen(c[1])
		var h0: int = fs.hash
		var s0: int = fs.score
		var got := []
		var t := Time.get_ticks_msec()
		for d in range(c[2].size()):
			got.append(perft(fs, d + 1))
		check("perft " + c[0], got == c[2], str(got) + " " + str(Time.get_ticks_msec() - t) + "ms")
		check("  после перебора состояние восстановлено", fs.hash == h0 and fs.score == s0 and fs.sp == 0)
	# сам ChessEngine.legal_moves (проверка короля на месте, без клонов) против эталона
	for c in cases:
		var eg := ChessEngine.new()
		eg.setup_from_fen(c[1])
		var want: Array = c[2].slice(0, 3)
		var have := []
		for d in range(want.size()):
			have.append(engine_perft(eg, d + 1))
		check("ChessEngine perft " + c[0], have == want, str(have))
	# pos4: превращения только в ферзя — сверяем с движком ChessEngine, а не с эталоном
	var e4 := ChessEngine.new()
	e4.setup_from_fen("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1")
	var fs4 = FS.new(tables(), 0)
	fs4.load_engine(e4)
	var eng2 := 0
	for m in e4.legal_moves():
		var c2 = e4.clone(); c2.apply_move(m); eng2 += c2.legal_moves().size()
	check("pos4 совпадает с ChessEngine (только ферзь)", perft(fs4, 2) == eng2, str(perft(fs4, 2)) + " vs " + str(eng2))

	# случайные партии: инкрементальный хэш/оценка == пересчёт, и == ChessAI._evaluate
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ai := ChessAI.new(5)
	var bad := 0
	var plies := 0
	for g in range(25):
		var e := ChessEngine.new()
		e.setup_start_position()
		var fs = FS.new(tables(), 0)
		fs.load_engine(e)
		for i in range(120):
			var lm = e.legal_moves()
			if lm.is_empty() or e.is_draw_by_rule():
				break
			var mv = lm[rng.randi_range(0, lm.size() - 1)]
			fs.make(FS.encode(mv, e))
			e.apply_move(mv)
			plies += 1
			var inc_h: int = fs.hash
			var inc_s: int = fs.score
			fs._recompute()
			if inc_h != fs.hash or inc_s != fs.score or fs.score != int(ai.evaluate_position(e)):
				bad += 1
			# ключ движка -> хэш должен совпасть с хэшем позиции
			if fs._hash_of_key(e.position_history[e.position_history.size() - 1]) != fs.hash:
				bad += 1
	check("хэш, оценка и ключ позиции согласованы", bad == 0, "полуходов %d, расхождений %d" % [plies, bad])

	# повторение позиции: ходим конями туда-сюда, должна быть ничья
	var er := ChessEngine.new()
	er.setup_start_position()
	var fr = FS.new(tables(), 0)
	fr.load_engine(er)
	for san in [[Vector2i(6,0), Vector2i(5,2)], [Vector2i(6,7), Vector2i(5,5)], [Vector2i(5,2), Vector2i(6,0)], [Vector2i(5,5), Vector2i(6,7)],
			[Vector2i(6,0), Vector2i(5,2)], [Vector2i(6,7), Vector2i(5,5)], [Vector2i(5,2), Vector2i(6,0)], [Vector2i(5,5), Vector2i(6,7)]]:
		for m in er.legal_moves():
			if m.from == san[0] and m.to == san[1]:
				fr.make(FS.encode(m, er)); er.apply_move(m); break
	check("трёхкратное повторение распознаётся", fr.is_draw() and er.is_threefold_repetition())

	# ИИ целиком: мат в 1 находят все уровни, ферзя не зевают, время в норме
	var mate1 := ChessEngine.new()
	mate1.setup_from_fen("6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1")
	for lvl in [5, 12, 15, 25]:
		var ai2 := ChessAI.new(lvl)
		ai2.custom_blunder = 0.0
		var t0 := Time.get_ticks_msec()
		var mv = ai2.choose_move(mate1)
		var ms := Time.get_ticks_msec() - t0
		check("уровень %d: мат в 1 (Rd8#)" % lvl, ChessEngine.square_name(mv.to.x, mv.to.y) == "d8", "%d мс" % ms)
	var mid := ChessEngine.new()
	mid.setup_from_fen("r1bq1rk1/pp2bppp/2n1pn2/2pp4/3P1B2/2PBPN2/PP1N1PPP/R2QK2R w KQ - 0 8")
	for lvl in [3, 6, 10, 12, 15, 18, 22, 25]:
		var ai3 := ChessAI.new(lvl)
		var t1 := Time.get_ticks_msec()
		var mv3 = ai3.choose_move(mid)
		var ms3 := Time.get_ticks_msec() - t1
		check("уровень %d ходит и укладывается в лимит" % lvl, mv3 != null and ms3 < ai3.move_time_ms + 3000, "%d мс" % ms3)
	print("=== ИТОГО ошибок: %d ===" % fails)
	get_tree().quit(1 if fails > 0 else 0)
