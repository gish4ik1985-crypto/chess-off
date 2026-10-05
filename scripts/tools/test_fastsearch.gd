extends Node

# Проверка быстрого ядра поиска: перебор ходов (perft) против эталонных чисел,
# согласованность хэша/оценки после случайных партий и совпадение качества
# выбора со старым алгоритмом ChessAI. Запуск: scenes/tools/TestFastSearch.tscn

const FS = preload("res://scripts/FastSearch.gd")
var fails := 0

func tables() -> Array:
	return ChessAI.tables()

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
	# превращения во все фигуры: сверяем с эталонными числами (позиции 4 и 5 из набора perft)
	var promo_cases := [
		["pos4", "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", [6, 264, 9467]],
		["pos5", "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", [44, 1486, 62379]],
	]
	for c in promo_cases:
		var fsp = fast_from_fen(c[1])
		var gotp := []
		for d in range(3):
			gotp.append(perft(fsp, d + 1))
		check("perft " + c[0] + " (FastSearch, все превращения)", gotp == c[2], str(gotp))
		var egp := ChessEngine.new()
		egp.setup_from_fen(c[1])
		egp.underpromotions = true
		var haveq := []
		for d in range(3):
			haveq.append(engine_perft(egp, d + 1))
		check("perft " + c[0] + " (ChessEngine, underpromotions)", haveq == c[2], str(haveq))
	# по умолчанию ChessEngine отдаёт игроку только ферзя
	var plain := ChessEngine.new()
	plain.setup_from_fen("8/P7/8/8/8/8/8/k6K w - - 0 1")
	var promo_n := 0
	for m in plain.legal_moves():
		if str(m.get("promo", "")) != "":
			promo_n += 1
	check("  игроку одно превращение на клетку", promo_n == 1, str(promo_n))
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
			var inc_se: int = fs.score_eg
			var inc_ph: int = fs.phase
			fs._recompute()
			if inc_h != fs.hash or inc_s != fs.score or inc_se != fs.score_eg or inc_ph != fs.phase:
				bad += 1
			if float(fs.eval_white()) != ai.evaluate_position(e):
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
	# эндшпиль: ИИ обязан довести ладью/ферзя против голого короля до мата и провести проходную пешку
	_endgame_mate("K+R против K", "8/8/8/4k3/8/8/8/R3K3 w - - 0 1", 50)
	_endgame_mate("K+Q против K", "8/8/8/4k3/8/8/8/Q3K3 w - - 0 1", 30)
	_endgame_mate("K+2R против K", "8/8/8/3k4/8/8/8/R3K2R w - - 0 1", 30)
	# мат в 1: даже уровни без поиска взятий (1–10) обязаны его ставить, если не выпал случайный ход
	var mates := [
		["Ra8#", "6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1"],
		["Qxf7#", "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4"],
	]
	for lvl in [1, 2, 3, 5, 8, 10]:
		var found := 0
		var total := 0
		for mt in mates:
			for rep in range(10):
				var e := ChessEngine.new()
				e.setup_from_fen(mt[1])
				var mai := ChessAI.new(lvl)
				mai.custom_blunder = 0.0
				var m = mai.choose_move(e)
				e.apply_move(m)
				total += 1
				if e.game_status() == "checkmate":
					found += 1
		check("уровень %d ставит мат в 1" % lvl, found == total, "%d/%d" % [found, total])
	print("=== ИТОГО ошибок: %d ===" % fails)
	get_tree().quit(1 if fails > 0 else 0)

# Играет сильная сторона (ИИ уровня 12) против случайных ходов слабой и проверяет мат за max_moves ходов.
# Защитник случайный, поэтому длина партии гуляет (замер на 10 семенах: K+Q 5–20, K+2R 4–20, K+R 8–33 ходов);
# лимиты стоят с запасом, а проверка идёт на нескольких семенах — иначе тест «мигает».
func _endgame_mate(name: String, fen: String, max_moves: int) -> void:
	var worst := 0
	var mated := 0
	var seeds := 5
	var t0 := Time.get_ticks_msec()
	for sd in range(1, seeds + 1):
		var e := ChessEngine.new()
		e.setup_from_fen(fen)
		var ai := ChessAI.new(12)
		ai.custom_blunder = 0.0
		ai.move_time_ms = 3000
		var rng := RandomNumberGenerator.new()
		rng.seed = sd
		var n := 0
		var status := "playing"
		while n < max_moves:
			var m = ai.choose_move(e)
			if m == null:
				break
			e.apply_move(m)
			n += 1
			status = e.game_status()
			if status != "playing":
				break
			var lm = e.legal_moves()
			e.apply_move(lm[rng.randi_range(0, lm.size() - 1)])
			status = e.game_status()
			if status != "playing":
				break
		if status == "checkmate":
			mated += 1
		worst = maxi(worst, n)
	check("эндшпиль %s: мат за ≤ %d ходов (%d семян)" % [name, max_moves, seeds], mated == seeds, "%d/%d, самая долгая %d ходов, %d мс" % [mated, seeds, worst, Time.get_ticks_msec() - t0])
