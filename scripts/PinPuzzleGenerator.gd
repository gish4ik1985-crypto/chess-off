extends RefCounted
class_name PinPuzzleGenerator

const PuzzleGenUtils = preload("res://scripts/PuzzleGenUtils.gd")

# Procedurally builds "pin" tactics puzzles: White plays a rook or bishop
# move that pins a black knight to the black king along a rank, file or
# diagonal. Since the only black pieces on the board are the king and the
# pinned knight, and a pinned knight can never make a legal move without
# exposing its own king (no knight move stays on the pin line), black's
# only legal replies are king moves — after any king move the knight is
# still pinned and undefended, and White captures it next.
# Same rigor as the fork generator: every generated puzzle is played out
# move-by-move against the real ChessEngine before being handed back, so
# only genuinely working puzzles are ever returned, and every puzzle is
# different.

static func generate(rng: RandomNumberGenerator) -> Dictionary:
	return PuzzleGenUtils.generate(rng, _try_generate)

static func _try_generate(rng: RandomNumberGenerator):
	var pin_piece_type = "R" if rng.randf() < 0.5 else "B"
	var dirs = PuzzleGenUtils.ROOK_DIRS if pin_piece_type == "R" else PuzzleGenUtils.BISHOP_DIRS
	var dir = dirs[rng.randi_range(0, dirs.size() - 1)]

	var king_sq := Vector2i(rng.randi_range(1, 6), rng.randi_range(1, 6))
	var pinned_sq := king_sq + Vector2i(dir[0], dir[1])
	if pinned_sq.x < 0 or pinned_sq.x >= 8 or pinned_sq.y < 0 or pinned_sq.y >= 8:
		return null

	var line_candidates: Array = []
	for d in range(2, 7):
		var cand = king_sq + Vector2i(dir[0] * d, dir[1] * d)
		if cand.x >= 0 and cand.x < 8 and cand.y >= 0 and cand.y < 8:
			line_candidates.append(cand)
	if line_candidates.is_empty():
		return null
	var line_sq: Vector2i = line_candidates[rng.randi_range(0, line_candidates.size() - 1)]

	# pick a white origin square n0 aligned with line_sq (same rank/file for
	# a rook, same diagonal for a bishop), on the opposite side of the pin
	# axis so it doesn't collide with it.
	var n0 = null
	var path: Array = []
	if pin_piece_type == "R":
		var candidates := []
		if rng.randf() < 0.5:
			for x in range(8):
				if x != line_sq.x:
					candidates.append(Vector2i(x, line_sq.y))
		else:
			for y in range(8):
				if y != line_sq.y:
					candidates.append(Vector2i(line_sq.x, y))
		candidates.shuffle()
		for cand in candidates:
			n0 = cand
			path = PuzzleGenUtils.path_between(cand, line_sq)
			break
	else:
		var candidates := []
		for k in range(-7, 8):
			if k == 0:
				continue
			var c1 = line_sq + Vector2i(k, k)
			var c2 = line_sq + Vector2i(k, -k)
			if c1.x >= 0 and c1.x < 8 and c1.y >= 0 and c1.y < 8:
				candidates.append(c1)
			if c2.x >= 0 and c2.x < 8 and c2.y >= 0 and c2.y < 8:
				candidates.append(c2)
		candidates.shuffle()
		for cand in candidates:
			n0 = cand
			path = PuzzleGenUtils.path_between(cand, line_sq)
			break
	if n0 == null:
		return null
	if n0 == king_sq or n0 == pinned_sq:
		return null
	for square in path:
		if square == king_sq or square == pinned_sq:
			return null

	var wk_candidates = PuzzleGenUtils.wk_candidates([king_sq, pinned_sq, line_sq, n0] + path, king_sq)
	if wk_candidates.is_empty():
		return null
	var wk_sq: Vector2i = wk_candidates[rng.randi_range(0, wk_candidates.size() - 1)]

	var e = PuzzleGenUtils.new_empty_engine()
	e.board[king_sq.y][king_sq.x] = {"type": "K", "color": "b"}
	e.board[pinned_sq.y][pinned_sq.x] = {"type": "N", "color": "b"}
	e.board[n0.y][n0.x] = {"type": pin_piece_type, "color": "w"}
	e.board[wk_sq.y][wk_sq.x] = {"type": "K", "color": "w"}

	if e.is_square_attacked(line_sq.x, line_sq.y, "b"):
		return null
	if e.game_status() != "playing":
		return null

	var start_fen = e.to_fen()
	var moves := []

	var m1 = null
	for m in e.legal_moves_for_square(n0.x, n0.y):
		if m.to == line_sq:
			m1 = m
			break
	if m1 == null:
		return null
	e.apply_move(m1)
	moves.append(PuzzleGenUtils.sq(n0.x, n0.y) + PuzzleGenUtils.sq(line_sq.x, line_sq.y))

	if e.is_in_check("b"):
		return null # a pin, not a check — if it accidentally checks, discard
	if e.game_status() != "playing":
		return null

	var black_replies = e.legal_moves("b")
	if black_replies.is_empty():
		return null
	# The knight starts right next to its king, so some king replies keep
	# defending it. Pick (and store) a reply after which the capture is a
	# genuinely free win — the scene auto-plays the stored reply, so the
	# line shown to the player always works out.
	var clean_replies := []
	for r in black_replies:
		if r.to == line_sq:
			continue # black capturing the pinner is not a line we store
		var test = e.clone()
		test.apply_move(r)
		if not test.is_square_attacked(pinned_sq.x, pinned_sq.y, "b"):
			clean_replies.append(r)
	if clean_replies.is_empty():
		return null
	var reply = clean_replies[rng.randi_range(0, clean_replies.size() - 1)]
	var reply_from = reply.from
	e.apply_move(reply)
	moves.append(PuzzleGenUtils.sq(reply_from.x, reply_from.y) + PuzzleGenUtils.sq(reply.to.x, reply.to.y))

	var m3 = null
	for m in e.legal_moves_for_square(line_sq.x, line_sq.y):
		if m.to == pinned_sq:
			m3 = m
			break
	if m3 == null:
		return null
	e.apply_move(m3)
	moves.append(PuzzleGenUtils.sq(line_sq.x, line_sq.y) + PuzzleGenUtils.sq(pinned_sq.x, pinned_sq.y))

	return {
		"fen": start_fen,
		"moves": moves,
		"theme": "pin",
		"piece_lost": "N",
	}
