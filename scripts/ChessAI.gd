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

# --- Линейка качества хода (Дневник, «Ходы», подсказки) ---
# Замер на партиях гроссмейстеров (scenes/tools/MeasureAccuracy.tscn) показал, что поиск
# без взятий на горизонте (уровень ≤10) считает «ошибкой» каждую третью игру мастера
# (43% сильных ходов, 6% зевков). С поиском взятий (уровень 12) и порогами ниже у мастеров
# около 73% сильных ходов, 5% ошибок и <1% зевков. Глубина 4 почти не меняет картину, но в 6 раз дороже.
const ANALYSIS_LEVEL := 12
const LOSS_INACCURACY := 50.0 # потеря больше — «неточность», сантипешки
const LOSS_MISTAKE := 150.0
const LOSS_BLUNDER := 350.0

static func quality_category(loss: float) -> String:
	if loss > LOSS_BLUNDER:
		return "blunder"
	if loss > LOSS_MISTAKE:
		return "mistake"
	if loss > LOSS_INACCURACY:
		return "inaccuracy"
	return "good"

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
# Эндшпиль: король — боевая фигура, ему место в центре (а не в углу, как в миттельшпиле)
const KING_EG_PST := [
	-50,-40,-30,-20,-20,-30,-40,-50,
	-30,-20,-10,0,0,-10,-20,-30,
	-30,-10,20,30,30,20,-10,-30,
	-30,-10,30,40,40,30,-10,-30,
	-30,-10,30,40,40,30,-10,-30,
	-30,-10,20,30,30,20,-10,-30,
	-30,-30,0,0,0,0,-30,-30,
	-50,-30,-30,-30,-30,-30,-30,-50
]
# Эндшпиль: чем дальше продвинута пешка, тем она ценнее (проходные решают партии)
const PAWN_EG_PST := [
	0,0,0,0,0,0,0,0,
	90,90,90,90,90,90,90,90,
	60,60,60,60,60,60,60,60,
	40,40,40,40,40,40,40,40,
	25,25,25,25,25,25,25,25,
	10,10,10,10,10,10,10,10,
	0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0
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

# --- Параметры уровней ---
# Каждый уровень: d — глубина поиска (полуходов), q — глубина поиска взятий на горизонте,
# b — шанс сыграть случайный ход вместо лучшего, n — «шум» оценки в сантипешках.
# Таблица подобрана ЗАМЕРАМИ партий уровней друг с другом (scenes/tools/CalibrateLevels.tscn),
# чтобы каждый следующий уровень был заметно сильнее предыдущего; проверяет TestLevelLadder.
static var PARAMS: Array = [
	{"d": 1, "q": 0, "b": 0.55, "n": 130.0},
	{"d": 1, "q": 0, "b": 0.42, "n": 100.0},
	{"d": 1, "q": 0, "b": 0.30, "n": 60.0},
	{"d": 2, "q": 0, "b": 0.40, "n": 90.0},
	{"d": 2, "q": 0, "b": 0.30, "n": 60.0},
	{"d": 2, "q": 0, "b": 0.20, "n": 40.0},
	{"d": 2, "q": 0, "b": 0.12, "n": 25.0},
	{"d": 3, "q": 0, "b": 0.12, "n": 35.0},
	{"d": 3, "q": 0, "b": 0.07, "n": 20.0},
	{"d": 3, "q": 0, "b": 0.04, "n": 10.0},
	{"d": 3, "q": 1, "b": 0.10, "n": 20.0},
	{"d": 3, "q": 2, "b": 0.07, "n": 15.0},
	{"d": 3, "q": 2, "b": 0.04, "n": 8.0},
	{"d": 3, "q": 3, "b": 0.02, "n": 4.0},
	{"d": 3, "q": 3, "b": 0.0, "n": 0.0},
	{"d": 4, "q": 2, "b": 0.10, "n": 20.0},
	{"d": 4, "q": 3, "b": 0.07, "n": 12.0},
	{"d": 4, "q": 3, "b": 0.04, "n": 6.0},
	{"d": 4, "q": 3, "b": 0.02, "n": 3.0},
	{"d": 4, "q": 3, "b": 0.0, "n": 0.0},
	{"d": 5, "q": 2, "b": 0.10, "n": 20.0},
	{"d": 5, "q": 2, "b": 0.06, "n": 10.0},
	{"d": 5, "q": 2, "b": 0.03, "n": 5.0},
	{"d": 5, "q": 2, "b": 0.01, "n": 2.0},
	{"d": 5, "q": 2, "b": 0.0, "n": 0.0},
]

func _p() -> Dictionary:
	return PARAMS[clampi(level, 1, PARAMS.size()) - 1]

func _search_depth() -> int:
	return int(_p().d)

# поиск только взятий на горизонте: оценка берётся в «тихой» позиции
func _quiescence_depth() -> int:
	return int(_p().q)

func _blunder_chance() -> float:
	if custom_blunder >= 0.0:
		return custom_blunder
	return float(_p().b)

func _eval_noise() -> float:
	return float(_p().n)

# Оценка позиции в сантипешках (плюс — у белых): та же, что использует поиск.
# Один экземпляр ядра на ИИ — чтобы не пересоздавать таблицы при оценке каждого хода партии.
var _eval_fs = null
func evaluate_position(engine: ChessEngine) -> float:
	if _eval_fs == null:
		_eval_fs = FastSearch.new(tables(), 0)
	_eval_fs.load_engine(engine, false)
	return float(_eval_fs.eval_white())

# Быстрое ядро поиска (см. FastSearch.gd) для позиции engine. Делает ход
# корневых вариантов из engine.legal_moves() — ChessEngine остаётся эталоном правил.
static func tables() -> Array:
	return [PAWN_PST, KNIGHT_PST, BISHOP_PST, ROOK_PST, QUEEN_PST, KING_PST, KING_EG_PST, PAWN_EG_PST]

# Быстрое ядро поиска (см. FastSearch.gd) для позиции engine. Корневые ходы берутся
# из ChessEngine (он остаётся эталоном правил).
func _fast(engine: ChessEngine, with_history: bool = true):
	var fs = FastSearch.new(tables(), _quiescence_depth())
	fs.load_engine(engine, with_history)
	return fs

# Все легальные ходы, включая превращение в ладью/слона/коня — ИИ они нужны
# (иногда конь с превращением даёт шах-вилку); игроку и задачам лишние ходы не отдаём.
func _legal_all(engine: ChessEngine) -> Array:
	var e := engine.clone()
	e.underpromotions = true
	return e.legal_moves(e.side_to_move)

func _encode_root(moves: Array, engine: ChessEngine) -> PackedInt32Array:
	var root := PackedInt32Array()
	for m in moves:
		root.append(FastSearch.encode(m, engine))
	return root

# Best move with no randomness/blunders — used for hints and coaching, not
# as an opponent (so hints are always genuinely good, not level-limited).
func best_move_clean(engine: ChessEngine, depth: int = 3):
	var moves = _legal_all(engine)
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
	var moves = _legal_all(engine)
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

	moves = _legal_all(engine) # для поиска — с превращением в любую фигуру
	var fs = _fast(engine)
	return moves[fs.choose(_encode_root(moves, engine), _search_depth(), _eval_noise(), rng, move_time_ms)]
