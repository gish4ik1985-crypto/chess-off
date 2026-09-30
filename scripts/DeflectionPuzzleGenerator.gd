extends RefCounted
class_name DeflectionPuzzleGenerator

const PuzzleGenUtils = preload("res://scripts/PuzzleGenUtils.gd")

# Procedurally builds "deflection" tactics puzzles: the black king stands
# right next to (and so effectively guards) a black rook. White gives
# check from a distance, forcing the king away — deflecting it from its
# defensive post — and a second white rook then captures the now-
# undefended black rook. Every generated puzzle is played out move-by-move
# against the real ChessEngine, including a dynamic re-check after black's
# actual reply (in case the rook itself had to block/capture instead of
# the king moving), so only genuinely working puzzles are ever returned.

static func generate(rng: RandomNumberGenerator) -> Dictionary:
	return PuzzleGenUtils.generate(rng, _try_generate)

static func _try_generate(rng: RandomNumberGenerator):
	var king_sq := Vector2i(rng.randi_range(1, 6), rng.randi_range(1, 6))

	var koff = PuzzleGenUtils.KING_OFFSETS[rng.randi_range(0, PuzzleGenUtils.KING_OFFSETS.size() - 1)]
	var target_sq := king_sq + Vector2i(koff[0], koff[1])
	if target_sq.x < 0 or target_sq.x >= 8 or target_sq.y < 0 or target_sq.y >= 8:
		return null

	var groups = [["R", PuzzleGenUtils.ROOK_DIRS], ["B", PuzzleGenUtils.BISHOP_DIRS]]
	groups.shuffle()
	var cp1_type: String = groups[0][0]
	var cp1_dirs: Array = groups[0][1]
	var dir = cp1_dirs[rng.randi_range(0, cp1_dirs.size() - 1)]

	var check_candidates: Array = []
	for d in range(1, 7):
		var cand = king_sq + Vector2i(dir[0] * d, dir[1] * d)
		if cand.x < 0 or cand.x >= 8 or cand.y < 0 or cand.y >= 8:
			break
		if cand == target_sq:
			break
		check_candidates.append(cand)
	if check_candidates.is_empty():
		return null
	var check_sq: Vector2i = check_candidates[rng.randi_range(0, check_candidates.size() - 1)]
	var path_king_check = PuzzleGenUtils.path_between(king_sq, check_sq)
	if path_king_check.has(target_sq):
		return null

	var n0_candidates = PuzzleGenUtils.slide_candidates(check_sq, cp1_dirs, [king_sq, target_sq])
	if n0_candidates.is_empty():
		return null
	n0_candidates.shuffle()
	var n0: Vector2i = n0_candidates[0]
	var path_n0_check = PuzzleGenUtils.path_between(n0, check_sq)

	var n2_candidates = PuzzleGenUtils.slide_candidates(target_sq, PuzzleGenUtils.ROOK_DIRS, [king_sq, check_sq, n0] + path_n0_check)
	if n2_candidates.is_empty():
		return null
	n2_candidates.shuffle()
	var n2: Vector2i = n2_candidates[0]
	var path_n2_target = PuzzleGenUtils.path_between(n2, target_sq)

	var occupied = [king_sq, target_sq, n0, n2]
	var wk_candidates = PuzzleGenUtils.wk_candidates(occupied + path_king_check + path_n0_check + path_n2_target, king_sq)
	if wk_candidates.is_empty():
		return null
	var wk_sq: Vector2i = wk_candidates[rng.randi_range(0, wk_candidates.size() - 1)]

	var e = PuzzleGenUtils.new_empty_engine()
	e.board[king_sq.y][king_sq.x] = {"type": "K", "color": "b"}
	e.board[target_sq.y][target_sq.x] = {"type": "R", "color": "b"}
	e.board[n0.y][n0.x] = {"type": cp1_type, "color": "w"}
	e.board[n2.y][n2.x] = {"type": "R", "color": "w"}
	e.board[wk_sq.y][wk_sq.x] = {"type": "K", "color": "w"}

	if e.is_in_check("w") or e.is_in_check("b"):
		return null
	if e.game_status() != "playing":
		return null

	var start_fen = e.to_fen()
	var moves := []

	var m1 = null
	for m in e.legal_moves_for_square(n0.x, n0.y):
		if m.to == check_sq:
			m1 = m
			break
	if m1 == null:
		return null
	e.apply_move(m1)
	moves.append(PuzzleGenUtils.sq(n0.x, n0.y) + PuzzleGenUtils.sq(check_sq.x, check_sq.y))

	if not e.is_in_check("b"):
		return null
	if e.game_status() != "playing":
		return null

	var black_replies = e.legal_moves("b")
	if black_replies.is_empty():
		return null
	var reply = black_replies[rng.randi_range(0, black_replies.size() - 1)]
	var reply_from = reply.from
	e.apply_move(reply)
	moves.append(PuzzleGenUtils.sq(reply_from.x, reply_from.y) + PuzzleGenUtils.sq(reply.to.x, reply.to.y))

	# find the rook wherever it ended up (it may have moved to block instead
	# of the king stepping away) and make sure it's actually undefended now.
	var rook_sq2 = null
	for r in range(8):
		for f in range(8):
			var p = e.board[r][f]
			if p != null and p.color == "b" and p.type == "R":
				rook_sq2 = Vector2i(f, r)
	if rook_sq2 == null:
		return null
	var king_sq2 = e.find_king("b")
	if king_sq2.distance_to(rook_sq2) < 1.5:
		return null # king still guards it — deflection didn't work this time

	var m3 = null
	for m in e.legal_moves_for_square(n2.x, n2.y):
		if m.to == rook_sq2:
			m3 = m
			break
	if m3 == null:
		return null
	e.apply_move(m3)
	moves.append(PuzzleGenUtils.sq(n2.x, n2.y) + PuzzleGenUtils.sq(rook_sq2.x, rook_sq2.y))

	return {
		"fen": start_fen,
		"moves": moves,
		"theme": "deflection",
		"piece_lost": "R",
	}
