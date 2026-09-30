extends Node

# ОДНОРАЗОВЫЙ диагностический скрипт, не общий инструмент — жёстко зашита
# ОДНА конкретная позиция, ничего не параметризуется. Написан, чтобы
# проверить конкретное историческое утверждение, и не предназначен для
# переиспользования на других партиях/позициях.
#
# Полный перебор (не эвристика): доказывает форсированный мат за белых из
# позиции после 27.Qh8+ (Карпов — Корчной, 1974) — проверяет, что мат
# неизбежен при ЛЮБОЙ защите чёрных, и находит кратчайшую линию.

const HG = preload("res://scripts/HistoricGames.gd")

const PGN_PREFIX = "1.e4 c5 2.Nf3 d6 3.d4 cxd4 4.Nxd4 Nf6 5.Nc3 g6 6.Be3 Bg7 7.f3 Nc6 8.Qd2 O-O 9.Bc4 Bd7 10.h4 Rc8 11.Bb3 Ne5 12.O-O-O Nc4 13.Bxc4 Rxc4 14.h5 Nxh5 15.g4 Nf6 16.Nde2 Qa5 17.Bh6 Bxh6 18.Qxh6 Rfc8 19.Rd3 R4c5 20.g5 Rxg5 21.Rd5 Rxd5 22.Nxd5 Re8 23.Nef4 Bc6 24.e5 Bxd5 25.exf6 exf6 26.Qxh7+ Kf8 27.Qh8+"

func _ready() -> void:
	var eng := ChessEngine.new()
	eng.setup_start_position()
	for san in _tokenize(PGN_PREFIX):
		var mv = HG._parse_san(eng, san)
		if mv.is_empty():
			print("PARSE FAIL at ", san)
			return
		eng.apply_move(mv)
	print("Position after 27.Qh8+ reached. FEN: ", eng.to_fen())
	for depth in [4, 6, 8]:
		print("--- exhaustive search: forced mate within ", depth / 2, " full move(s) for White? ---")
		var t0 = Time.get_ticks_msec()
		var line = _search(eng, depth, "w")
		var dt = Time.get_ticks_msec() - t0
		print("    (", dt, " ms)")
		if not line.is_empty():
			print("FORCED MATE CONFIRMED:")
			for m in line:
				print("  ", m)
			return
	print("No forced mate proven within searched depth (may still exist deeper, or 'resign' was based on overwhelming advantage rather than literal short mate).")

func _tokenize(pgn: String) -> Array:
	var out := []
	for raw in pgn.split(" ", false):
		var tok = raw.strip_edges()
		if tok == "" or tok in ["1-0","0-1","1/2-1/2","*"]:
			continue
		var dot = tok.rfind(".")
		if dot >= 0:
			var head = tok.substr(0, dot).replace(".", "")
			if head.is_valid_int():
				var after = tok.substr(dot+1)
				if after == "": continue
				tok = after
		out.append(tok)
	return out

func _order_score(eng: ChessEngine, m: Dictionary) -> int:
	var score := 0
	if eng.board[m.to.y][m.to.x] != null:
		score += 10
	var nxt = eng.clone()
	nxt.apply_move(m)
	if nxt.is_in_check(nxt.side_to_move):
		score += 20
	return score

func _mv_str(eng: ChessEngine, m: Dictionary) -> String:
	if m.get("is_castle","")=="K": return "O-O"
	if m.get("is_castle","")=="Q": return "O-O-O"
	var p = eng.board[m.from.y][m.from.x]
	var names = {"P":"","N":"N","B":"B","R":"R","Q":"Q","K":"K"}
	var cap = eng.board[m.to.y][m.to.x] != null or m.get("is_ep", false)
	return str(names.get(p.type if p!=null else "P","")) + ChessEngine.square_name(m.from.x,m.from.y) + ("x" if cap else "-") + ChessEngine.square_name(m.to.x,m.to.y)

# Возвращает форсированную линию для mover_color (список строк), либо []
# если мат в пределах depth_left полуходов не доказан.
func _search(eng: ChessEngine, depth_left: int, mover_color: String) -> Array:
	if depth_left <= 0:
		return []
	var legal = eng.legal_moves(eng.side_to_move)
	if legal.is_empty():
		return [] # пат или уже мат — обрабатывается на уровне выше через game_status
	var is_mover_turn = (eng.side_to_move == mover_color)
	if is_mover_turn:
		legal.sort_custom(func(a, b): return _order_score(eng, a) > _order_score(eng, b))
		for m in legal:
			var nxt = eng.clone()
			nxt.apply_move(m)
			var mv_txt = _mv_str(eng, m)
			if nxt.game_status() == "checkmate":
				return [mv_txt + "#"]
			var sub = _search(nxt, depth_left - 1, mover_color)
			if not sub.is_empty():
				var out = [mv_txt]
				out.append_array(sub)
				return out
		return []
	else:
		var best_line := []
		var have_line := false
		for m in legal:
			var nxt = eng.clone()
			nxt.apply_move(m)
			var mv_txt = _mv_str(eng, m)
			if nxt.game_status() == "checkmate":
				continue # соперник не может заматовать сам себя своим ходом
			var sub = _search(nxt, depth_left - 1, mover_color)
			if sub.is_empty():
				return [] # нашлась защита без мата -> не форсированно на этой глубине
			if not have_line:
				best_line = [mv_txt]
				best_line.append_array(sub)
				have_line = true
		if not have_line:
			return []
		return best_line
