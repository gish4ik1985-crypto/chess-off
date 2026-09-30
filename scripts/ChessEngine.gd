extends RefCounted
class_name ChessEngine

# Board is 8x8 Array of Array. board[rank][file], rank 0 = rank1 (white back rank), file 0 = 'a'.
# Piece: {"type":"P/N/B/R/Q/K", "color":"w"/"b"}

const WHITE := "w"
const BLACK := "b"

# Таблицы направлений вынесены в константы: раньше литералы-массивы
# пересоздавались при каждом вызове is_square_attacked / pseudo_moves_for.
const KNIGHT_D := [[1,2],[2,1],[2,-1],[1,-2],[-1,-2],[-2,-1],[-2,1],[-1,2]]
const DIAG_D := [[1,1],[1,-1],[-1,1],[-1,-1]]
const ORTH_D := [[1,0],[-1,0],[0,1],[0,-1]]
const ALL_D := [[1,1],[1,-1],[-1,1],[-1,-1],[1,0],[-1,0],[0,1],[0,-1]]
const KEY_LETTERS := {"P":"p","N":"n","B":"b","R":"r","Q":"q","K":"k"}

var board: Array = []
var side_to_move: String = WHITE
var castling := {"wk": true, "wq": true, "bk": true, "bq": true}
var en_passant_target = null # Vector2i(file, rank) square that can be captured en passant, or null
var halfmove_clock := 0
var fullmove_number := 1

var last_move = null # {from, to, piece, captured, is_castle, is_ep, promo}
# One _position_key() per position reached so far (including the starting
# one), for threefold-repetition detection — carried through clone() just
# like halfmove_clock, so a search branch correctly "remembers" the real
# game's history it descended from.
var position_history: Array = []

# game_status() runs a full legal_moves() generation (clone+apply per pseudo-
# move) — expensive enough that callers who ask twice per move (sound cue +
# UI label) would otherwise pay for it twice. Cached per-position, invalidated
# by anything that changes the position.
var _status_cache: String = ""
var _status_cache_valid: bool = false

func setup_start_position() -> void:
	board = []
	for r in range(8):
		var row := []
		for f in range(8):
			row.append(null)
		board.append(row)
	var back := ["R", "N", "B", "Q", "K", "B", "N", "R"]
	for f in range(8):
		board[0][f] = {"type": back[f], "color": WHITE}
		board[1][f] = {"type": "P", "color": WHITE}
		board[6][f] = {"type": "P", "color": BLACK}
		board[7][f] = {"type": back[f], "color": BLACK}
	side_to_move = WHITE
	castling = {"wk": true, "wq": true, "bk": true, "bq": true}
	en_passant_target = null
	halfmove_clock = 0
	fullmove_number = 1
	last_move = null
	position_history = [_position_key()]
	_status_cache_valid = false

func clone() -> ChessEngine:
	var c := ChessEngine.new()
	c.board = []
	for r in range(8):
		var row := []
		for f in range(8):
			var p = board[r][f]
			if p == null:
				row.append(null)
			else:
				row.append({"type": p.type, "color": p.color})
		c.board.append(row)
	c.side_to_move = side_to_move
	c.castling = castling.duplicate()
	c.en_passant_target = en_passant_target
	c.halfmove_clock = halfmove_clock
	c.fullmove_number = fullmove_number
	c.position_history = position_history.duplicate()
	return c

func in_bounds(f: int, r: int) -> bool:
	return f >= 0 and f < 8 and r >= 0 and r < 8

func piece_at(f: int, r: int):
	if not in_bounds(f, r):
		return null
	return board[r][f]

func opponent(color: String) -> String:
	return BLACK if color == WHITE else WHITE

# Returns list of pseudo-legal moves (not checking own-king-in-check) for a piece at f,r
func pseudo_moves_for(f: int, r: int) -> Array:
	var p = board[r][f]
	if p == null:
		return []
	var moves := []
	var color = p.color
	var dir = 1 if color == WHITE else -1
	match p.type:
		"P":
			var one_r = r + dir
			if in_bounds(f, one_r) and board[one_r][f] == null:
				moves.append(_mk_pawn_move(f, r, f, one_r))
				var start_rank = 1 if color == WHITE else 6
				var two_r = r + dir * 2
				if r == start_rank and board[two_r][f] == null:
					moves.append({"from": Vector2i(f, r), "to": Vector2i(f, two_r), "double": true})
			for df in [-1, 1]:
				var nf = f + df
				var nr = r + dir
				if in_bounds(nf, nr):
					var target = board[nr][nf]
					if target != null and target.color != color:
						moves.append(_mk_pawn_move(f, r, nf, nr))
					elif en_passant_target != null and en_passant_target == Vector2i(nf, nr):
						moves.append({"from": Vector2i(f, r), "to": Vector2i(nf, nr), "is_ep": true})
		"N":
			for d in KNIGHT_D:
				var nf = f + d[0]
				var nr = r + d[1]
				if in_bounds(nf, nr):
					var target = board[nr][nf]
					if target == null or target.color != color:
						moves.append({"from": Vector2i(f, r), "to": Vector2i(nf, nr)})
		"B":
			moves += _slide_moves(f, r, color, DIAG_D)
		"R":
			moves += _slide_moves(f, r, color, ORTH_D)
		"Q":
			moves += _slide_moves(f, r, color, ALL_D)
		"K":
			for df in [-1,0,1]:
				for dr in [-1,0,1]:
					if df == 0 and dr == 0:
						continue
					var nf = f + df
					var nr = r + dr
					if in_bounds(nf, nr):
						var target = board[nr][nf]
						if target == null or target.color != color:
							moves.append({"from": Vector2i(f, r), "to": Vector2i(nf, nr)})
			# Castling
			var rank = 0 if color == WHITE else 7
			if r == rank and f == 4:
				var kkey = "wk" if color == WHITE else "bk"
				var qkey = "wq" if color == WHITE else "bq"
				if castling.get(kkey, false):
					if board[rank][5] == null and board[rank][6] == null:
						if not is_square_attacked(4, rank, opponent(color)) \
						and not is_square_attacked(5, rank, opponent(color)) \
						and not is_square_attacked(6, rank, opponent(color)):
							moves.append({"from": Vector2i(f, r), "to": Vector2i(6, rank), "is_castle": "K"})
				if castling.get(qkey, false):
					if board[rank][3] == null and board[rank][2] == null and board[rank][1] == null:
						if not is_square_attacked(4, rank, opponent(color)) \
						and not is_square_attacked(3, rank, opponent(color)) \
						and not is_square_attacked(2, rank, opponent(color)):
							moves.append({"from": Vector2i(f, r), "to": Vector2i(2, rank), "is_castle": "Q"})
	return moves

func _mk_pawn_move(f: int, r: int, nf: int, nr: int) -> Dictionary:
	var promo_rank = 7 if board[r][f].color == WHITE else 0
	if nr == promo_rank:
		return {"from": Vector2i(f, r), "to": Vector2i(nf, nr), "promo": "Q"}
	return {"from": Vector2i(f, r), "to": Vector2i(nf, nr)}

func _slide_moves(f: int, r: int, color: String, dirs: Array) -> Array:
	var moves := []
	for d in dirs:
		var nf = f + d[0]
		var nr = r + d[1]
		while in_bounds(nf, nr):
			var target = board[nr][nf]
			if target == null:
				moves.append({"from": Vector2i(f, r), "to": Vector2i(nf, nr)})
			else:
				if target.color != color:
					moves.append({"from": Vector2i(f, r), "to": Vector2i(nf, nr)})
				break
			nf += d[0]
			nr += d[1]
	return moves

func is_square_attacked(f: int, r: int, by_color: String) -> bool:
	# Pawn attacks
	var pdir = 1 if by_color == WHITE else -1
	for df in [-1, 1]:
		var pf = f + df
		var pr = r - pdir
		if in_bounds(pf, pr):
			var p = board[pr][pf]
			if p != null and p.color == by_color and p.type == "P":
				return true
	# Knight attacks
	for d in KNIGHT_D:
		var nf = f + d[0]
		var nr = r + d[1]
		if in_bounds(nf, nr):
			var p = board[nr][nf]
			if p != null and p.color == by_color and p.type == "N":
				return true
	# King attacks
	for df in [-1,0,1]:
		for dr in [-1,0,1]:
			if df == 0 and dr == 0:
				continue
			var nf = f + df
			var nr = r + dr
			if in_bounds(nf, nr):
				var p = board[nr][nf]
				if p != null and p.color == by_color and p.type == "K":
					return true
	# Sliding: bishop/queen diagonals
	for d in DIAG_D:
		var nf = f + d[0]
		var nr = r + d[1]
		while in_bounds(nf, nr):
			var p = board[nr][nf]
			if p != null:
				if p.color == by_color and (p.type == "B" or p.type == "Q"):
					return true
				break
			nf += d[0]
			nr += d[1]
	# Sliding: rook/queen straight
	for d in ORTH_D:
		var nf = f + d[0]
		var nr = r + d[1]
		while in_bounds(nf, nr):
			var p = board[nr][nf]
			if p != null:
				if p.color == by_color and (p.type == "R" or p.type == "Q"):
					return true
				break
			nf += d[0]
			nr += d[1]
	return false

func find_king(color: String) -> Vector2i:
	for r in range(8):
		for f in range(8):
			var p = board[r][f]
			if p != null and p.color == color and p.type == "K":
				return Vector2i(f, r)
	return Vector2i(-1, -1)

func is_in_check(color: String) -> bool:
	var k = find_king(color)
	if k.x < 0:
		return false
	return is_square_attacked(k.x, k.y, opponent(color))

# Applies a move in-place (mutates this engine). Returns undo info dictionary.
func apply_move(move: Dictionary) -> void:
	var from: Vector2i = move.from
	var to: Vector2i = move.to
	var p = board[from.y][from.x]
	var captured = board[to.y][to.x]
	var is_ep = move.get("is_ep", false)
	var is_castle = move.get("is_castle", "")
	var promo = move.get("promo", "")
	var is_double = move.get("double", false)

	en_passant_target = null

	if is_ep:
		# capture the pawn behind the target square
		var cap_r = to.y - (1 if p.color == WHITE else -1)
		board[cap_r][to.x] = null

	board[to.y][to.x] = p
	board[from.y][from.x] = null

	if promo != "":
		board[to.y][to.x] = {"type": promo, "color": p.color}

	if is_castle == "K":
		var rank = from.y
		board[rank][5] = board[rank][7]
		board[rank][7] = null
	elif is_castle == "Q":
		var rank = from.y
		board[rank][3] = board[rank][0]
		board[rank][0] = null

	if is_double:
		en_passant_target = Vector2i(from.x, (from.y + to.y) / 2)

	# Update castling rights
	if p.type == "K":
		if p.color == WHITE:
			castling["wk"] = false
			castling["wq"] = false
		else:
			castling["bk"] = false
			castling["bq"] = false
	if p.type == "R":
		if from.x == 0 and from.y == 0:
			castling["wq"] = false
		elif from.x == 7 and from.y == 0:
			castling["wk"] = false
		elif from.x == 0 and from.y == 7:
			castling["bq"] = false
		elif from.x == 7 and from.y == 7:
			castling["bk"] = false
	if to.x == 0 and to.y == 0:
		castling["wq"] = false
	elif to.x == 7 and to.y == 0:
		castling["wk"] = false
	elif to.x == 0 and to.y == 7:
		castling["bq"] = false
	elif to.x == 7 and to.y == 7:
		castling["bk"] = false

	if p.type == "P" or captured != null or is_ep:
		halfmove_clock = 0
	else:
		halfmove_clock += 1

	if side_to_move == BLACK:
		fullmove_number += 1

	last_move = {"from": from, "to": to, "piece": p, "captured": captured, "is_castle": is_castle, "is_ep": is_ep, "promo": promo}
	side_to_move = opponent(side_to_move)
	position_history.append(_position_key())
	_status_cache_valid = false

# Ход оставляет своего короля вне шаха? Проверка на месте: двигаем фигуры по
# доске, смотрим на короля и возвращаем всё назад. Раньше здесь для каждого
# псевдоходa делался clone() + apply_move() (со сборкой FEN-ключа позиции) —
# это и было главным тормозом всего движка. ksq — клетка короля стороны
# (или (-1,-1), если короля нет — тогда шаха не бывает, как и раньше).
func _leaves_king_safe(m: Dictionary, color: String, ksq: Vector2i) -> bool:
	if ksq.x < 0:
		return true
	var from: Vector2i = m.from
	var to: Vector2i = m.to
	var p = board[from.y][from.x]
	var captured = board[to.y][to.x]
	var ep_row := -1
	var ep_piece = null
	if m.get("is_ep", false):
		ep_row = to.y - (1 if color == WHITE else -1)
		ep_piece = board[ep_row][to.x]
		board[ep_row][to.x] = null
	board[to.y][to.x] = p
	board[from.y][from.x] = null
	var k := to if p.type == "K" else ksq
	var safe := not is_square_attacked(k.x, k.y, opponent(color))
	board[from.y][from.x] = p
	board[to.y][to.x] = captured
	if ep_row >= 0:
		board[ep_row][to.x] = ep_piece
	return safe

# Returns all legal moves for side_to_move (or given color)
func legal_moves(color: String = "") -> Array:
	if color == "":
		color = side_to_move
	var result := []
	var ksq := find_king(color)
	for r in range(8):
		for f in range(8):
			var p = board[r][f]
			if p == null or p.color != color:
				continue
			for m in pseudo_moves_for(f, r):
				if _leaves_king_safe(m, color, ksq):
					result.append(m)
	return result

func legal_moves_for_square(f: int, r: int) -> Array:
	var p = board[r][f]
	if p == null:
		return []
	var color = p.color
	var ksq := find_king(color)
	var result := []
	for m in pseudo_moves_for(f, r):
		if _leaves_king_safe(m, color, ksq):
			result.append(m)
	return result

func game_status() -> String:
	# returns "playing", "checkmate", "stalemate", "draw50", "insufficient", "repetition"
	if _status_cache_valid:
		return _status_cache
	var status: String
	var moves = legal_moves(side_to_move)
	if moves.is_empty():
		status = "checkmate" if is_in_check(side_to_move) else "stalemate"
	elif is_threefold_repetition():
		status = "repetition"
	elif Global.fifty_move_rule_enabled and halfmove_clock >= 100:
		status = "draw50"
	elif _insufficient_material():
		status = "insufficient"
	else:
		status = "playing"
	_status_cache = status
	_status_cache_valid = true
	return status

# Cheap draw check (no move generation) for callers that only need to know
# whether the position is an automatic draw, not the exact game_status()
# string — used by ChessAI so the search doesn't have to run legal_moves()
# twice per node just to catch the 50-move rule / insufficient material.
func is_draw_by_rule() -> bool:
	return (Global.fifty_move_rule_enabled and halfmove_clock >= 100) or _insufficient_material() or is_threefold_repetition()

# The current position has occurred (at least) a third time — simplified as
# an automatic draw rather than FIDE's claim-based rule, matching how
# draw50/insufficient material are already handled here.
func is_threefold_repetition() -> bool:
	if position_history.is_empty():
		return false
	var current = position_history[position_history.size() - 1]
	var count = 0
	for key in position_history:
		if key == current:
			count += 1
			if count >= 3:
				return true
	return false

func _insufficient_material() -> bool:
	var pieces := []
	var squares := []
	for r in range(8):
		for f in range(8):
			var p = board[r][f]
			if p != null and p.type != "K":
				pieces.append(p)
				squares.append(Vector2i(f, r))
	if pieces.is_empty():
		return true
	if pieces.size() == 1 and (pieces[0].type == "N" or pieces[0].type == "B"):
		return true
	# K+B vs K+B with both bishops on the same colored squares: neither
	# side can ever force mate, a dead draw (opposite-colored bishops, or
	# either side having a second minor piece, are NOT covered here —
	# those combinations can still win in principle).
	if pieces.size() == 2 and pieces[0].type == "B" and pieces[1].type == "B" and pieces[0].color != pieces[1].color:
		if (squares[0].x + squares[0].y) % 2 == (squares[1].x + squares[1].y) % 2:
			return true
	return false

static func square_name(f: int, r: int) -> String:
	var files = "abcdefgh"
	return files[f] + str(r + 1)

# The first four FEN fields (board + side to move + castling rights + en
# passant square) — everything that defines "the same position" for
# threefold-repetition purposes, deliberately excluding the two move
# counters (a repeated position is still repeated regardless of how many
# quiet moves led to it).
func _position_key() -> String:
	var rows := []
	for r in range(7, -1, -1):
		var row_str := ""
		var empty := 0
		for f in range(8):
			var p = board[r][f]
			if p == null:
				empty += 1
			else:
				if empty > 0:
					row_str += str(empty)
					empty = 0
				var letters = {"P":"p","N":"n","B":"b","R":"r","Q":"q","K":"k"}
				var letter = letters[p.type]
				row_str += letter.to_upper() if p.color == WHITE else letter
		if empty > 0:
			row_str += str(empty)
		rows.append(row_str)
	var board_part = "/".join(rows)
	var castle_str = ""
	if castling.get("wk", false): castle_str += "K"
	if castling.get("wq", false): castle_str += "Q"
	if castling.get("bk", false): castle_str += "k"
	if castling.get("bq", false): castle_str += "q"
	if castle_str == "":
		castle_str = "-"
	var ep_str = "-"
	if en_passant_target != null:
		ep_str = square_name(en_passant_target.x, en_passant_target.y)
	return "%s %s %s %s" % [board_part, side_to_move, castle_str, ep_str]

func to_fen() -> String:
	return "%s %d %d" % [_position_key(), halfmove_clock, fullmove_number]

func setup_from_fen(fen: String) -> void:
	board = []
	for r in range(8):
		var row := []
		for f in range(8):
			row.append(null)
		board.append(row)
	var parts = fen.strip_edges().split(" ")
	var board_part = parts[0]
	var ranks = board_part.split("/")
	var letters_to_type = {"p":"P", "n":"N", "b":"B", "r":"R", "q":"Q", "k":"K"}
	for ri in range(8):
		var rank_str = ranks[ri]
		var r = 7 - ri
		var f = 0
		for ch in rank_str:
			if ch.is_valid_int():
				f += ch.to_int()
			else:
				var color = WHITE if ch == ch.to_upper() else BLACK
				var ptype = letters_to_type[ch.to_lower()]
				board[r][f] = {"type": ptype, "color": color}
				f += 1
	side_to_move = parts[1] if parts.size() > 1 else WHITE
	castling = {"wk": false, "wq": false, "bk": false, "bq": false}
	if parts.size() > 2:
		var cs = parts[2]
		if cs.find("K") >= 0: castling["wk"] = true
		if cs.find("Q") >= 0: castling["wq"] = true
		if cs.find("k") >= 0: castling["bk"] = true
		if cs.find("q") >= 0: castling["bq"] = true
	en_passant_target = null
	if parts.size() > 3 and parts[3] != "-":
		var files = "abcdefgh"
		var sq = parts[3]
		var ff = files.find(sq[0])
		var rr = sq.substr(1).to_int() - 1
		en_passant_target = Vector2i(ff, rr)
	halfmove_clock = int(parts[4]) if parts.size() > 4 else 0
	fullmove_number = int(parts[5]) if parts.size() > 5 else 1
	last_move = null
	position_history = [_position_key()]
	_status_cache_valid = false
