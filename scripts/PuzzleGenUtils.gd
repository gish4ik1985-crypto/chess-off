extends RefCounted

# Shared plumbing for the five procedural tactics generators (Fork, Pin,
# BackRank, Defense, Deflection): square notation, the blank-board
# ChessEngine each one starts from, line/slide geometry, the white-king
# placement search, the "only king replies and none leave the target
# defended" check shared by the two forcing-check generators, and the
# generate() retry loop. Puzzle-specific setup (which squares to occupy,
# which piece delivers the tactic) stays in each generator — this only
# pulls out the scaffolding that was identical (or equivalent) across all five.

const FILES := "abcdefgh"
const KNIGHT_OFFSETS := [[1,2],[2,1],[2,-1],[1,-2],[-1,-2],[-2,-1],[-2,1],[-1,2]]
const ROOK_DIRS := [[1,0],[-1,0],[0,1],[0,-1]]
const BISHOP_DIRS := [[1,1],[1,-1],[-1,1],[-1,-1]]
const KING_OFFSETS := [[1,0],[-1,0],[0,1],[0,-1],[1,1],[1,-1],[-1,1],[-1,-1]]

static func sq(f: int, r: int) -> String:
	return FILES[f] + str(r + 1)

# Retries try_generate up to 300 times with the given rng; returns {} if
# every attempt is discarded.
static func generate(rng: RandomNumberGenerator, try_generate: Callable) -> Dictionary:
	for attempt in range(300):
		var result = try_generate.call(rng)
		if result != null and not result.is_empty():
			return result
	return {}

# Blank 8x8 board, white to move, no castling/en passant rights — every
# generator places its pieces onto this before verifying the position.
static func new_empty_engine() -> ChessEngine:
	var e := ChessEngine.new()
	e.board = []
	for r in range(8):
		var row := []
		for f in range(8):
			row.append(null)
		e.board.append(row)
	e.side_to_move = "w"
	e.castling = {"wk": false, "wq": false, "bk": false, "bq": false}
	e.en_passant_target = null
	return e

# Squares strictly between a and b if they're aligned on a rank, file, or
# diagonal (a valid rook/bishop line); empty array otherwise.
static func path_between(a: Vector2i, b: Vector2i) -> Array:
	var dx = b.x - a.x
	var dy = b.y - a.y
	if dx == 0 and dy == 0:
		return []
	if dx != 0 and dy != 0 and abs(dx) != abs(dy):
		return []
	var steps = max(abs(dx), abs(dy))
	var sx = sign(dx)
	var sy = sign(dy)
	var path: Array = []
	for i in range(1, steps):
		path.append(a + Vector2i(sx * i, sy * i))
	return path

# All empty squares reachable in a straight line from `from` along each of
# `dirs`, stopping (and excluding) at the first square that is in `blockers`.
static func slide_candidates(from: Vector2i, dirs: Array, blockers: Array) -> Array:
	var out: Array = []
	for d in dirs:
		var cur = from + Vector2i(d[0], d[1])
		while cur.x >= 0 and cur.x < 8 and cur.y >= 0 and cur.y < 8:
			if blockers.has(cur):
				break
			out.append(cur)
			cur += Vector2i(d[0], d[1])
	return out

# Legal white-king placement squares: anywhere not in `blocked` and kept a
# few squares away from `near` (keeps the white king out of the action).
static func wk_candidates(blocked: Array, near: Vector2i) -> Array:
	var out: Array = []
	for f in range(8):
		for r in range(8):
			var candidate := Vector2i(f, r)
			if blocked.has(candidate):
				continue
			if candidate.distance_to(near) < 2.5:
				continue
			out.append(candidate)
	return out

# True if every one of black's legal replies to a check is a king move, and
# none of them leaves `safe_target` defended — the shape a forcing check
# needs for the "then White wins the hanging piece" follow-up to always work.
static func only_king_replies_leave_undefended(e: ChessEngine, black_replies: Array, safe_target: Vector2i) -> bool:
	for r in black_replies:
		var piece = e.board[r.from.y][r.from.x]
		if piece == null or piece.type != "K":
			return false
		var test: ChessEngine = e.clone()
		test.apply_move(r)
		if test.is_square_attacked(safe_target.x, safe_target.y, "b"):
			return false
	return true
