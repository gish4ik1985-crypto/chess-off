extends Node

# Юнит-тесты правил шахмат в ChessEngine: рокировка, взятие на проходе, превращение,
# мат/пат, связка, ничьи (материал, повторение, 50 ходов), FEN.
# Запуск: scenes/tools/TestRules.tscn

var fails := 0

func check(name: String, ok: bool, info: String = "") -> void:
	print(("OK   " if ok else "FAIL ") + name + (" " + info if info != "" else ""))
	if not ok:
		fails += 1

func eng(fen: String) -> ChessEngine:
	var e := ChessEngine.new()
	e.setup_from_fen(fen)
	return e

func has_move(e: ChessEngine, from: String, to: String) -> bool:
	for m in e.legal_moves():
		if ChessEngine.square_name(m.from.x, m.from.y) == from and ChessEngine.square_name(m.to.x, m.to.y) == to:
			return true
	return false

func play(e: ChessEngine, from: String, to: String, promo: String = "") -> bool:
	for m in e.legal_moves():
		if ChessEngine.square_name(m.from.x, m.from.y) == from and ChessEngine.square_name(m.to.x, m.to.y) == to:
			if promo == "" or str(m.get("promo", "")) == promo:
				e.apply_move(m)
				return true
	return false

func count_promotions(e: ChessEngine) -> int:
	var n := 0
	for m in e.legal_moves():
		if str(m.get("promo", "")) != "":
			n += 1
	return n

func _ready() -> void:
	# --- начальная позиция и FEN ---
	var start := ChessEngine.new()
	start.setup_start_position()
	check("в начальной позиции 20 ходов", start.legal_moves().size() == 20)
	check("FEN начальной позиции", start.to_fen() == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", start.to_fen())
	check("FEN читается и пишется без потерь", eng(start.to_fen()).to_fen() == start.to_fen())

	# --- рокировка ---
	var c1 := eng("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	check("рокировка в обе стороны возможна", has_move(c1, "e1", "g1") and has_move(c1, "e1", "c1"))
	var c2 := eng("r3k2r/8/8/8/8/5r2/8/R3K2R w KQkq - 0 1")
	check("нельзя рокироваться через битое поле (f1)", not has_move(c2, "e1", "g1") and has_move(c2, "e1", "c1"))
	var c3 := eng("r3k2r/8/8/8/8/4r3/8/R3K2R w KQkq - 0 1")
	check("нельзя рокироваться под шахом", not has_move(c3, "e1", "g1") and not has_move(c3, "e1", "c1"))
	var c4 := eng("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	play(c4, "e1", "g1")
	check("после короткой рокировки ладья на f1", c4.board[0][5] != null and c4.board[0][5].type == "R" and c4.board[0][7] == null)
	check("рокировка отнимает права белых", not c4.castling["wk"] and not c4.castling["wq"] and c4.castling["bk"])
	var c5 := eng("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	play(c5, "h1", "h2")
	check("ход ладьёй h1 отнимает право короткой рокировки", not c5.castling["wk"] and c5.castling["wq"])

	# --- взятие на проходе ---
	var ep := eng("4k3/8/8/8/3p4/8/4P3/4K3 w - - 0 1")
	play(ep, "e2", "e4")
	check("после двойного хода появляется поле для взятия на проходе", ep.en_passant_target != null and ChessEngine.square_name(ep.en_passant_target.x, ep.en_passant_target.y) == "e3")
	check("чёрная пешка может взять на проходе", has_move(ep, "d4", "e3"))
	play(ep, "d4", "e3")
	check("взятая на проходе пешка снята с доски", ep.board[3][4] == null and ep.board[2][4] != null)
	var ep2 := eng("4k3/8/8/8/3p4/8/4P3/4K3 w - - 0 1")
	play(ep2, "e2", "e3")
	check("одинарный ход не даёт права взятия на проходе", ep2.en_passant_target == null)

	# --- превращение ---
	var pr := eng("8/P7/8/8/8/8/8/k6K w - - 0 1")
	check("игроку — одно превращение (ферзь) на клетку", count_promotions(pr) == 1)
	play(pr, "a7", "a8", "Q")
	check("пешка стала ферзём", pr.board[7][0] != null and pr.board[7][0].type == "Q")
	var pr2 := eng("8/P7/8/8/8/8/8/k6K w - - 0 1")
	pr2.underpromotions = true
	check("с включённым флагом — четыре превращения", count_promotions(pr2) == 4)

	# --- шах, мат, пат, связка ---
	var fool := ChessEngine.new()
	fool.setup_start_position()
	for mv in [["f2", "f3"], ["e7", "e5"], ["g2", "g4"], ["d8", "h4"]]:
		play(fool, mv[0], mv[1])
	check("детский мат за четыре хода: шах и мат", fool.game_status() == "checkmate" and fool.is_in_check("w"))
	check("пат распознаётся", eng("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1").game_status() == "stalemate")
	var pinned := eng("4r1k1/8/8/8/8/8/4N3/4K3 w - - 0 1")
	var knight_moves := 0
	for m in pinned.legal_moves():
		if m.from == Vector2i(4, 1):
			knight_moves += 1
	check("связанный конь не ходит", knight_moves == 0, str(knight_moves))
	var into := eng("8/8/8/8/8/8/3r4/4K3 w - - 0 1")
	check("король не идёт на битое поле, но может взять ладью", not has_move(into, "e1", "d1") and has_move(into, "e1", "d2"))

	# --- ничьи ---
	check("король против короля — ничья по материалу", eng("8/8/8/4k3/8/8/8/4K3 w - - 0 1").game_status() == "insufficient")
	check("король и конь против короля — ничья", eng("8/8/8/4k3/8/8/8/4KN2 w - - 0 1").game_status() == "insufficient")
	check("король и ладья против короля — играют дальше", eng("8/8/8/4k3/8/8/8/4KR2 w - - 0 1").game_status() == "playing")
	var rep := eng("4k3/8/8/8/8/8/8/R3K3 w - - 0 1")
	for i in range(2):
		play(rep, "a1", "a2")
		play(rep, "e8", "d8")
		play(rep, "a2", "a1")
		play(rep, "d8", "e8")
	check("троекратное повторение — ничья", rep.game_status() == "repetition", rep.game_status())
	var old_rule: bool = Global.fifty_move_rule_enabled
	Global.fifty_move_rule_enabled = true
	check("правило 50 ходов включено — ничья", eng("4k3/8/8/8/8/8/4P3/R3K3 w - - 100 80").game_status() == "draw50")
	Global.fifty_move_rule_enabled = false
	check("правило 50 ходов выключено — партия идёт", eng("4k3/8/8/8/8/8/4P3/R3K3 w - - 100 80").game_status() == "playing")
	Global.fifty_move_rule_enabled = old_rule

	# --- копирование ---
	var cl := start.clone()
	play(cl, "e2", "e4")
	check("clone() независим от оригинала", start.to_fen() == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
	check("clone() помнит последний ход", cl.last_move != null and cl.clone().last_move != null)

	# некорректный внешний FEN не должен давать незаконные ходы
	var fe1 := ChessEngine.new()
	fe1.setup_from_fen("4k3/8/8/8/3p4/8/4P3/4K3 b - e3 0 1")
	var has_bad_ep := false
	for m in fe1.legal_moves():
		if ChessEngine.square_name(m.from.x, m.from.y) == "d4" and ChessEngine.square_name(m.to.x, m.to.y) == "e3":
			has_bad_ep = true
	check("FEN: взятие на проходе без пешки отбрасывается", not has_bad_ep and fe1.en_passant_target == null)
	var fe2 := ChessEngine.new()
	fe2.setup_from_fen("4k3/8/8/8/8/8/8/4K3 w KQ - 0 1")
	var has_bad_castle := false
	for m in fe2.legal_moves():
		if ChessEngine.square_name(m.from.x, m.from.y) == "e1" and absi(m.to.x - m.from.x) == 2:
			has_bad_castle = true
	check("FEN: рокировка без ладьи отбрасывается", not has_bad_castle)
	var fe3 := ChessEngine.new()
	fe3.setup_from_fen("4k3/8/8/8/3pP3/8/8/4K3 b - e3 0 1")
	check("FEN: настоящее взятие на проходе остаётся", fe3.en_passant_target != null)
	var fe4 := ChessEngine.new()
	fe4.setup_from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	check("FEN: настоящие права рокировки остаются", fe4.castling["wk"] and fe4.castling["wq"] and fe4.castling["bk"] and fe4.castling["bq"])
	print("=== ИТОГО ошибок: %d ===" % fails)
	get_tree().quit(1 if fails > 0 else 0)
