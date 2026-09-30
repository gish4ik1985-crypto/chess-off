extends RefCounted
class_name ChessAI

# Difficulty 1..25 -> search depth + blunder chance + eval noise.
# 1-10: the original ladder (noise/blunders fade out by 10).
# 11-14: perfect play at depth 3 plus a capture-only quiescence search at
#        the leaves, so it stops missing hanging pieces beyond the horizon.
# 15-20: depth 4 with progressively deeper quiescence — slow to think, but
#        the search runs on a worker thread so the UI never freezes.
# 21-25: depth 4 with a very deep quiescence tail (up to 8 plies of
#        captures) — the "beyond human" tier for players who outgrew 20.
var level: int = 5
var rng := RandomNumberGenerator.new()
# When >= 0, replaces the level-derived blunder chance — used by the
# "Тень" (shadow twin) to reproduce the player's own real blunder rate.
var custom_blunder := -1.0
# Лимит времени на ход (мс) для итеративного углубления: не уложились в глубину —
# берём лучший ход последней завершённой итерации. 0 = без лимита.
var move_time_ms: int = 6000

const FastSearch = preload("res://scripts/FastSearch.gd")

const PIECE_VALUE := {"P": 100, "N": 320, "B": 330, "R": 500, "Q": 900, "K": 0}

const PAWN_PST := [
	0,0,0,0,0,0,0,0,
	50,50,50,50,50,50,50,50,
	10,10,20,30,30,20,10,10,
	5,5,10,25,25,10,5,5,
	0,0,0,20,20,0,0,0,
	5,-5,-10,0,0,-10,-5,5,
	5,10,10,-20,-20,10,10,5,
	0,0,0,0,0,0,0,0
]
const KNIGHT_PST := [
	-50,-40,-30,-30,-30,-30,-40,-50,
	-40,-20,0,0,0,0,-20,-40,
	-30,0,10,15,15,10,0,-30,
	-30,5,15,20,20,15,5,-30,
	-30,0,15,20,20,15,0,-30,
	-30,5,10,15,15,10,5,-30,
	-40,-20,0,5,5,0,-20,-40,
	-50,-40,-30,-30,-30,-30,-40,-50
]
const BISHOP_PST := [
	-20,-10,-10,-10,-10,-10,-10,-20,
	-10,0,0,0,0,0,0,-10,
	-10,0,5,10,10,5,0,-10,
	-10,5,5,10,10,5,5,-10,
	-10,0,10,10,10,10,0,-10,
	-10,10,10,10,10,10,10,-10,
	-10,5,0,0,0,0,5,-10,
	-20,-10,-10,-10,-10,-10,-10,-20
]
const ROOK_PST := [
	0,0,0,0,0,0,0,0,
	5,10,10,10,10,10,10,5,
	-5,0,0,0,0,0,0,-5,
	-5,0,0,0,0,0,0,-5,
	-5,0,0,0,0,0,0,-5,
	-5,0,0,0,0,0,0,-5,
	-5,0,0,0,0,0,0,-5,
	0,0,0,5,5,0,0,0
]
const QUEEN_PST := [
	-20,-10,-10,-5,-5,-10,-10,-20,
	-10,0,0,0,0,0,0,-10,
	-10,0,5,5,5,5,0,-10,
	-5,0,5,5,5,5,0,-5,
	0,0,5,5,5,5,0,-5,
	-10,5,5,5,5,5,0,-10,
	-10,0,5,0,0,0,0,-10,
	-20,-10,-10,-5,-5,-10,-10,-20
]
const KING_PST := [
	-30,-40,-40,-50,-50,-40,-40,-30,
	-30,-40,-40,-50,-50,-40,-40,-30,
	-30,-40,-40,-50,-50,-40,-40,-30,
	-30,-40,-40,-50,-50,-40,-40,-30,
	-20,-30,-30,-40,-40,-30,-30,-20,
	-10,-20,-20,-20,-20,-20,-20,-10,
	20,20,0,0,0,0,20,20,
	20,30,10,0,0,10,30,20
]

func _init(lvl: int = 5):
	level = clampi(lvl, 1, 25)
	rng.randomize()
	if OS.has_feature("web"):
		move_time_ms = 2500 # без потоков ход идёт в основном потоке — держим паузу короткой

func _search_depth() -> int:
	# levels map to depth with quality scaling via noise/blunder (low levels)
	# and quiescence (high levels) instead of pure depth, to stay fast in GDScript.
	if level <= 2:
		return 1
	if level <= 6:
		return 2
	if level <= 14:
		return 3
	return 4

# capture-only lookahead at the leaves, levels 11+
func _quiescence_depth() -> int:
	if level <= 10:
		return 0
	if level == 14:
		# one step deeper right before the full-width search depth jumps
		# 3->4 at level 15 — softens what would otherwise be the single
		# biggest strength cliff on the whole ladder.
		return 3
	if level <= 16:
		return 2
	if level <= 20:
		return 4
	if level <= 22:
		return 6
	return 8

func _blunder_chance() -> float:
	# chance to pick a random legal move instead of the best one
	if custom_blunder >= 0.0:
		return custom_blunder
	if level == 11:
		# 10->11 already turns on quiescence search in one step (see
		# _quiescence_depth) — keep a tiny residual blunder chance here so
		# blunders/noise/tactical vision don't all vanish/appear at once.
		return 0.02
	return clampf((11 - level) * 0.05, 0.0, 0.5)

func _eval_noise() -> float:
	if level == 11:
		return 2.0
	return maxf(float(11 - level) * 8.0, 0.0)

func evaluate_position(engine: ChessEngine) -> float:
	return _evaluate(engine)

# Быстрое ядро поиска (см. FastSearch.gd) для позиции engine. Делает ход
# корневых вариантов из engine.legal_moves() — ChessEngine остаётся эталоном правил.
func _fast(engine: ChessEngine):
	var fs = FastSearch.new([PAWN_PST, KNIGHT_PST, BISHOP_PST, ROOK_PST, QUEEN_PST, KING_PST], _quiescence_depth())
	fs.load_engine(engine)
	return fs

func _encode_root(moves: Array, engine: ChessEngine) -> PackedInt32Array:
	var root := PackedInt32Array()
	for m in moves:
		root.append(FastSearch.encode(m, engine))
	return root

# Best move with no randomness/blunders — used for hints and coaching, not
# as an opponent (so hints are always genuinely good, not level-limited).
func best_move_clean(engine: ChessEngine, depth: int = 3):
	var moves = engine.legal_moves(engine.side_to_move)
	if moves.is_empty():
		return null
	if moves.size() == 1:
		return moves[0]
	var fs = _fast(engine)
	return moves[fs.best_clean(_encode_root(moves, engine), depth)]

# How many centipawns worse `move` is than the best available move, from the
# mover's own perspective (0 = it was the best move). Used by the move-quality
# tracker in Board.gd. The played move is scored once with a full window, then
# the remaining moves run with alpha seeded at that score, so anything worse
# than the played move is pruned immediately.
func move_loss(engine: ChessEngine, move: Dictionary, depth: int = 3) -> float:
	var moves = engine.legal_moves(engine.side_to_move)
	var root := _encode_root(moves, engine)
	var played := -1
	for i in range(moves.size()):
		if moves[i].from == move.from and moves[i].to == move.to and moves[i].get("promo", "") == move.get("promo", ""):
			played = i
			break
	if played < 0:
		root.append(FastSearch.encode(move, engine))
		played = root.size() - 1
	var fs = _fast(engine)
	return float(fs.move_loss(root, played, depth))

func choose_move(engine: ChessEngine):
	var moves = engine.legal_moves(engine.side_to_move)
	if moves.is_empty():
		return null

	if rng.randf() < _blunder_chance():
		return moves[rng.randi_range(0, moves.size() - 1)]
	if moves.size() == 1:
		return moves[0]

	var fs = _fast(engine)
	return moves[fs.choose(_encode_root(moves, engine), _search_depth(), _eval_noise(), rng, move_time_ms)]

func _evaluate(engine: ChessEngine) -> float:
	var score := 0.0
	for r in range(8):
		for f in range(8):
			var p = engine.board[r][f]
			if p == null:
				continue
			var val = PIECE_VALUE.get(p.type, 0)
			var pst_index = ((7 - r) * 8 + f) if p.color == ChessEngine.WHITE else (r * 8 + f)
			var pst_val = 0
			match p.type:
				"P": pst_val = PAWN_PST[pst_index]
				"N": pst_val = KNIGHT_PST[pst_index]
				"B": pst_val = BISHOP_PST[pst_index]
				"R": pst_val = ROOK_PST[pst_index]
				"Q": pst_val = QUEEN_PST[pst_index]
				"K": pst_val = KING_PST[pst_index]
			var total = val + pst_val
			if p.color == ChessEngine.WHITE:
				score += total
			else:
				score -= total
	return score
