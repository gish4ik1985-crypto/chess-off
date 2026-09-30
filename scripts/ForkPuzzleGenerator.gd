extends RefCounted
class_name ForkPuzzleGenerator

const PuzzleGenUtils = preload("res://scripts/PuzzleGenUtils.gd")

# Procedurally builds "fork" tactics puzzles: White plays a knight move that
# simultaneously checks the black king AND attacks a second, undefended
# black piece (rook or queen). Since it's check, black's only legal replies
# are king moves (verified: the fork square is never attacked, so capturing
# or blocking is never possible) — after any king move the second piece is
# still hanging and White wins it. Every generated puzzle is played out
# move-by-move against the real ChessEngine before being handed back, so
# only genuinely working puzzles are ever returned (same rigor as the mate
# puzzle generator, just done live at runtime instead of once offline —
# which also means every puzzle is different).

static func generate(rng: RandomNumberGenerator) -> Dictionary:
	return PuzzleGenUtils.generate(rng, _try_generate)

static func _try_generate(rng: RandomNumberGenerator):
	var fork_sq = Vector2i(rng.randi_range(1, 6), rng.randi_range(1, 6))

	var targets: Array = []
	for off in PuzzleGenUtils.KNIGHT_OFFSETS:
		var t = fork_sq + Vector2i(off[0], off[1])
		if t.x >= 0 and t.x < 8 and t.y >= 0 and t.y < 8:
			targets.append(t)
	if targets.size() < 2:
		return null

	# Fisher-Yates using our own rng instance (not the global RNG), so the
	# whole generator is reproducible from a given seed if ever needed.
	for i in range(targets.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = targets[i]
		targets[i] = targets[j]
		targets[j] = tmp

	var king_sq: Vector2i = targets[0]
	var v_sq: Vector2i = targets[1]

	var start_offsets = PuzzleGenUtils.KNIGHT_OFFSETS.duplicate()
	start_offsets.shuffle()
	var n0 = null
	for off in start_offsets:
		var cand = fork_sq + Vector2i(off[0], off[1])
		if cand.x < 0 or cand.x >= 8 or cand.y < 0 or cand.y >= 8:
			continue
		if cand == king_sq or cand == v_sq:
			continue
		n0 = cand
		break
	if n0 == null:
		return null

	var wk_candidates = PuzzleGenUtils.wk_candidates([king_sq, v_sq, fork_sq, n0], king_sq)
	if wk_candidates.is_empty():
		return null
	var wk_sq: Vector2i = wk_candidates[rng.randi_range(0, wk_candidates.size() - 1)]

	var v_piece_type = "Q" if rng.randf() < 0.5 else "R"

	var e = PuzzleGenUtils.new_empty_engine()
	e.board[king_sq.y][king_sq.x] = {"type": "K", "color": "b"}
	e.board[v_sq.y][v_sq.x] = {"type": v_piece_type, "color": "b"}
	e.board[n0.y][n0.x] = {"type": "N", "color": "w"}
	e.board[wk_sq.y][wk_sq.x] = {"type": "K", "color": "w"}

	if e.is_square_attacked(fork_sq.x, fork_sq.y, "b"):
		return null
	if e.game_status() != "playing":
		return null

	var start_fen = e.to_fen()
	var moves := []

	var m1 = null
	for m in e.legal_moves_for_square(n0.x, n0.y):
		if m.to == fork_sq:
			m1 = m
			break
	if m1 == null:
		return null
	e.apply_move(m1)
	moves.append(PuzzleGenUtils.sq(n0.x, n0.y) + PuzzleGenUtils.sq(fork_sq.x, fork_sq.y))

	if not e.is_in_check("b"):
		return null
	if e.game_status() != "playing":
		return null # accidental checkmate/stalemate — not the puzzle shape we want

	var black_replies = e.legal_moves("b")
	if black_replies.is_empty():
		return null
	# clean puzzle: only king replies allowed (no blocking piece may vacate
	# the target square), and none of them may end up defending the target —
	# otherwise the "winning" capture would be a trade or hit an empty square
	if not PuzzleGenUtils.only_king_replies_leave_undefended(e, black_replies, v_sq):
		return null
	var reply = black_replies[rng.randi_range(0, black_replies.size() - 1)]
	var reply_from = reply.from
	e.apply_move(reply)
	moves.append(PuzzleGenUtils.sq(reply_from.x, reply_from.y) + PuzzleGenUtils.sq(reply.to.x, reply.to.y))

	var m3 = null
	for m in e.legal_moves_for_square(fork_sq.x, fork_sq.y):
		if m.to == v_sq:
			m3 = m
			break
	if m3 == null:
		return null
	e.apply_move(m3)
	moves.append(PuzzleGenUtils.sq(fork_sq.x, fork_sq.y) + PuzzleGenUtils.sq(v_sq.x, v_sq.y))

	return {
		"fen": start_fen,
		"moves": moves,
		"theme": "fork",
		"piece_lost": v_piece_type,
	}
