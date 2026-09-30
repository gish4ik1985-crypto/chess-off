extends RefCounted

# Партии между уровнями ИИ — основа честного рейтинга: сколько «очков рейтинга» реально
# отделяет уровень N от уровня N+1. Старты берутся из настоящих партий мастеров (8 полуходов),
# чтобы игры были разными, а цвета меняются по очереди.

const GamesData = preload("res://scripts/HistoricGamesData.gd")
const HG = preload("res://scripts/HistoricGames.gd")

const OPENING_PLIES := 8

static var _openings: Array = []

# n разных дебютных позиций (FEN) — по одной из разных партий мастеров, детерминированно.
static func openings(n: int) -> Array:
	if _openings.is_empty():
		for p in GamesData.players():
			for g in p.games:
				if str(g.get("start_fen", "")) != "":
					continue
				var eng := ChessEngine.new()
				eng.setup_start_position()
				var ply := 0
				for san in HG.game_moves(g):
					var mv = HG._parse_san(eng, san)
					if mv.is_empty() or ply >= OPENING_PLIES:
						break
					eng.apply_move(mv)
					ply += 1
				if ply == OPENING_PLIES and _openings.find(eng.to_fen()) < 0:
					_openings.append(eng.to_fen())
	var out: Array = []
	var step: int = maxi(_openings.size() / maxi(n, 1), 1)
	for i in range(n):
		out.append(_openings[(i * step) % _openings.size()])
	return out

# Одна партия; результат — очки БЕЛЫХ (1 / 0.5 / 0). По достижении max_plies партия
# присуждается тому, у кого перевес не меньше 3 пешек, иначе ничья.
static func play(fen: String, white_level: int, black_level: int, max_plies: int = 120) -> float:
	var e := ChessEngine.new()
	e.setup_from_fen(fen)
	var white := ChessAI.new(white_level)
	var black := ChessAI.new(black_level)
	var judge := ChessAI.new(1)
	for ply in range(max_plies):
		var st := e.game_status()
		if st == "checkmate":
			return 0.0 if e.side_to_move == "w" else 1.0
		if st != "playing":
			return 0.5
		var m = (white if e.side_to_move == "w" else black).choose_move(e)
		if m == null:
			return 0.5
		e.apply_move(m)
	var ev: float = judge.evaluate_position(e)
	if ev >= 300.0:
		return 1.0
	if ev <= -300.0:
		return 0.0
	return 0.5

# Матч уровней a и b: games партий (цвета чередуются). Возвращает очки уровня a и оценку разницы.
static func match_levels(a: int, b: int, games: int, max_plies: int = 120) -> Dictionary:
	var fens := openings((games + 1) / 2)
	var score := 0.0
	var wins := 0
	var draws := 0
	var losses := 0
	for i in range(games):
		var fen: String = fens[(i / 2) % fens.size()]
		var a_white := i % 2 == 0
		var w := play(fen, a if a_white else b, b if a_white else a, max_plies)
		var s: float = w if a_white else 1.0 - w
		score += s
		if s >= 0.99:
			wins += 1
		elif s <= 0.01:
			losses += 1
		else:
			draws += 1
	var frac := score / games
	return {"a": a, "b": b, "games": games, "score": frac, "wins": wins, "draws": draws, "losses": losses,
		"elo": elo_from_score(frac, games), "err": elo_error(frac, games)}

# Разница рейтингов по доле очков (ограничена, чтобы 100% не давало бесконечность).
static func elo_from_score(s: float, n: int) -> float:
	var lo := 0.5 / maxf(float(n), 1.0)
	var c := clampf(s, lo, 1.0 - lo)
	return 400.0 * log(c / (1.0 - c)) / log(10.0)

# Грубая погрешность (один стандартный разброс) в очках рейтинга.
static func elo_error(s: float, n: int) -> float:
	var c := clampf(s, 0.05, 0.95)
	return 400.0 / log(10.0) * sqrt(1.0 / (float(n) * c * (1.0 - c)))
