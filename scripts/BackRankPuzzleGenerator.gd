extends RefCounted
class_name BackRankPuzzleGenerator

const PuzzleGenUtils = preload("res://scripts/PuzzleGenUtils.gd")

# Procedurally builds "back-rank mate" puzzles: the black king is trapped on
# its home rank behind its own pawns (no escape squares), and White delivers
# an immediate checkmate by moving a rook or queen onto that same rank, far
# enough away that the king cannot capture it. Unlike the fork/pin
# generators this is a single-move mate (no black reply to script) — the
# generated move is verified to be an actual checkmate against the real
# ChessEngine before being handed back, so every puzzle is different and
# always genuinely mates.

const BACK_RANK := 7 # row index for black's home rank (rank 8)

static func generate(rng: RandomNumberGenerator) -> Dictionary:
	return PuzzleGenUtils.generate(rng, _try_generate)

static func _try_generate(rng: RandomNumberGenerator):
	var king_x := rng.randi_range(0, 7)
	var king_sq := Vector2i(king_x, BACK_RANK)

	var escape_files: Array = []
	for dx in [-1, 0, 1]:
		var x = king_x + dx
		if x >= 0 and x < 8:
			escape_files.append(x)
	var pawn_squares: Array = []
	for x in escape_files:
		pawn_squares.append(Vector2i(x, BACK_RANK - 1))

	var mating_piece_type = "R" if rng.randf() < 0.5 else "Q"

	var landing_candidates: Array = []
	for x in range(8):
		if x == king_x:
			continue
		if abs(x - king_x) < 2:
			continue # must stay out of the king's reach
		landing_candidates.append(x)
	if landing_candidates.is_empty():
		return null
	var landing_x: int = landing_candidates[rng.randi_range(0, landing_candidates.size() - 1)]
	var landing_sq := Vector2i(landing_x, BACK_RANK)

	# origin square for the mating piece: anywhere off the back rank in the
	# same file as the landing square (a clean vertical approach), or
	# elsewhere on the back rank itself with a clear path is also fine
	# since only the king and pawns occupy squares so far.
	var n0_candidates: Array = []
	for r in range(0, 7):
		n0_candidates.append(Vector2i(landing_x, r))
	n0_candidates.shuffle()
	var n0: Vector2i = n0_candidates[rng.randi_range(0, n0_candidates.size() - 1)]

	var wk_candidates = PuzzleGenUtils.wk_candidates([king_sq, n0, landing_sq] + pawn_squares, king_sq)
	if wk_candidates.is_empty():
		return null
	var wk_sq: Vector2i = wk_candidates[rng.randi_range(0, wk_candidates.size() - 1)]

	var e = PuzzleGenUtils.new_empty_engine()
	e.board[king_sq.y][king_sq.x] = {"type": "K", "color": "b"}
	for x in escape_files:
		e.board[BACK_RANK - 1][x] = {"type": "P", "color": "b"}
	e.board[n0.y][n0.x] = {"type": mating_piece_type, "color": "w"}
	e.board[wk_sq.y][wk_sq.x] = {"type": "K", "color": "w"}

	if e.game_status() != "playing":
		return null

	var start_fen = e.to_fen()

	var m1 = null
	for m in e.legal_moves_for_square(n0.x, n0.y):
		if m.to == landing_sq:
			m1 = m
			break
	if m1 == null:
		return null
	e.apply_move(m1)

	if e.game_status() != "checkmate":
		return null

	return {
		"fen": start_fen,
		"moves": [PuzzleGenUtils.sq(n0.x, n0.y) + PuzzleGenUtils.sq(landing_sq.x, landing_sq.y)],
		"theme": "backrank",
		"piece_lost": "",
	}
