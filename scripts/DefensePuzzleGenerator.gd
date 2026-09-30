extends RefCounted
class_name DefensePuzzleGenerator

const PuzzleGenUtils = preload("res://scripts/PuzzleGenUtils.gd")

# Procedurally builds "destroy the defender" puzzles: a black rook is
# defended only by a black knight. White's bishop captures the knight —
# with check, since the bishop lands exactly where the knight stood, on
# the same diagonal as the black king. Because the rook cannot block the
# check or capture the bishop (verified below), black's only legal replies
# are king moves; the rook is left undefended and a second white rook
# captures it. Same rigor as the other generators: every puzzle is played
# out move-by-move against the real ChessEngine before being handed back.

static func generate(rng: RandomNumberGenerator) -> Dictionary:
	return PuzzleGenUtils.generate(rng, _try_generate)

static func _try_generate(rng: RandomNumberGenerator):
	var king_sq := Vector2i(rng.randi_range(1, 6), rng.randi_range(1, 6))
	var dir = PuzzleGenUtils.BISHOP_DIRS[rng.randi_range(0, 3)]

	var def_candidates: Array = []
	for d in range(2, 7):
		var cand = king_sq + Vector2i(dir[0] * d, dir[1] * d)
		if cand.x >= 0 and cand.x < 8 and cand.y >= 0 and cand.y < 8:
			def_candidates.append(cand)
	if def_candidates.is_empty():
		return null
	var def_sq: Vector2i = def_candidates[rng.randi_range(0, def_candidates.size() - 1)]

	var path_king_def = PuzzleGenUtils.path_between(king_sq, def_sq)

	var offsets = PuzzleGenUtils.KNIGHT_OFFSETS.duplicate()
	offsets.shuffle()
	var target_sq = null
	for off in offsets:
		var cand = def_sq + Vector2i(off[0], off[1])
		if cand.x < 0 or cand.x >= 8 or cand.y < 0 or cand.y >= 8:
			continue
		if cand == king_sq or path_king_def.has(cand):
			continue
		if cand.x == def_sq.x or cand.y == def_sq.y:
			continue # could let the rook capture the bishop on def_sq, skip
		target_sq = cand
		break
	if target_sq == null:
		return null

	var n0_candidates = PuzzleGenUtils.slide_candidates(def_sq, PuzzleGenUtils.BISHOP_DIRS, [king_sq, target_sq])
	if n0_candidates.is_empty():
		return null
	n0_candidates.shuffle()
	var n0: Vector2i = n0_candidates[0]
	var path_n0_def = PuzzleGenUtils.path_between(n0, def_sq)

	var n2_candidates = PuzzleGenUtils.slide_candidates(target_sq, PuzzleGenUtils.ROOK_DIRS, [king_sq, def_sq, n0] + path_n0_def)
	if n2_candidates.is_empty():
		return null
	n2_candidates.shuffle()
	var n2: Vector2i = n2_candidates[0]
	var path_n2_target = PuzzleGenUtils.path_between(n2, target_sq)

	var occupied = [king_sq, def_sq, target_sq, n0, n2]
	var wk_candidates = PuzzleGenUtils.wk_candidates(occupied + path_king_def + path_n0_def + path_n2_target, king_sq)
	if wk_candidates.is_empty():
		return null
	var wk_sq: Vector2i = wk_candidates[rng.randi_range(0, wk_candidates.size() - 1)]

	var e = PuzzleGenUtils.new_empty_engine()
	e.board[king_sq.y][king_sq.x] = {"type": "K", "color": "b"}
	e.board[def_sq.y][def_sq.x] = {"type": "N", "color": "b"}
	e.board[target_sq.y][target_sq.x] = {"type": "R", "color": "b"}
	e.board[n0.y][n0.x] = {"type": "B", "color": "w"}
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
		if m.to == def_sq:
			m1 = m
			break
	if m1 == null:
		return null
	e.apply_move(m1)
	moves.append(PuzzleGenUtils.sq(n0.x, n0.y) + PuzzleGenUtils.sq(def_sq.x, def_sq.y))

	if not e.is_in_check("b"):
		return null
	if e.game_status() != "playing":
		return null

	var black_replies = e.legal_moves("b")
	if black_replies.is_empty():
		return null
	# Clean puzzle requirements: the check must be answerable ONLY by king
	# moves (otherwise the rook could block/capture and leave its square,
	# making "capture the rook" land on an empty square), and after EVERY
	# reply the rook must stay undefended (otherwise black would just pick
	# the defending move and the tactic wouldn't win material).
	if not PuzzleGenUtils.only_king_replies_leave_undefended(e, black_replies, target_sq):
		return null
	var reply = black_replies[rng.randi_range(0, black_replies.size() - 1)]
	var reply_from = reply.from
	e.apply_move(reply)
	moves.append(PuzzleGenUtils.sq(reply_from.x, reply_from.y) + PuzzleGenUtils.sq(reply.to.x, reply.to.y))

	var m3 = null
	for m in e.legal_moves_for_square(n2.x, n2.y):
		if m.to == target_sq:
			m3 = m
			break
	if m3 == null:
		return null
	e.apply_move(m3)
	moves.append(PuzzleGenUtils.sq(n2.x, n2.y) + PuzzleGenUtils.sq(target_sq.x, target_sq.y))

	return {
		"fen": start_fen,
		"moves": moves,
		"theme": "defense",
		"piece_lost": "R",
	}
