extends Node

# Проверка «линейки» точности (Дневник): партии гроссмейстеров не должны выглядеть как
# сплошные ошибки, а явные зевки должны ловиться. Если тест упал, значит, кто-то
# изменил уровень анализа или пороги, и цифры в Дневнике перестали быть честными.
# Запуск: scenes/tools/TestQualityRuler.tscn

const GamesData = preload("res://scripts/HistoricGamesData.gd")
const HG = preload("res://scripts/HistoricGames.gd")

var fails := 0

func check(name: String, ok: bool, info: String = "") -> void:
	print(("OK   " if ok else "FAIL ") + name + (" " + info if info != "" else ""))
	if not ok:
		fails += 1

func find_move(e: ChessEngine, from: String, to: String) -> Dictionary:
	for m in e.legal_moves():
		if ChessEngine.square_name(m.from.x, m.from.y) == from and ChessEngine.square_name(m.to.x, m.to.y) == to:
			return m
	return {}

func _ready() -> void:
	check("границы категорий",
		ChessAI.quality_category(0.0) == "good"
		and ChessAI.quality_category(ChessAI.LOSS_INACCURACY + 1.0) == "inaccuracy"
		and ChessAI.quality_category(ChessAI.LOSS_MISTAKE + 1.0) == "mistake"
		and ChessAI.quality_category(ChessAI.LOSS_BLUNDER + 1.0) == "blunder")
	var ai := ChessAI.new(ChessAI.ANALYSIS_LEVEL)

	# ферзь берёт пешку, которую защищает ладья, — ферзь потерян за пешку
	var hang := ChessEngine.new()
	hang.setup_from_fen("3rk3/8/8/3p4/8/8/8/3QK3 w - - 0 1")
	var bad_move := find_move(hang, "d1", "d5")
	var loss: float = ai.move_loss(hang, bad_move, 3)
	check("ферзь берёт защищённую пешку — это зевок", ChessAI.quality_category(loss) == "blunder", "потеря %.0f" % loss)

	# лучший ход в позиции никогда не считается ошибкой
	var start := ChessEngine.new()
	start.setup_start_position()
	var best = ai.best_move_clean(start, 3)
	check("лучший ход в позиции — «сильный»", ChessAI.quality_category(ai.move_loss(start, best, 3)) == "good")

	# партии мастеров: ходы 9..50 нескольких игроков
	var players: Array = GamesData.players()
	var total := 0
	var good := 0
	var blunders := 0
	var t0 := Time.get_ticks_msec()
	for pi in [0, 3, 6, 9]:
		var g: Dictionary = players[pi].games[0]
		var eng := ChessEngine.new()
		eng.setup_start_position()
		var ply := 0
		for san in HG.game_moves(g):
			var mv = HG._parse_san(eng, san)
			if mv.is_empty() or ply >= 50:
				break
			if ply >= 8:
				var cat := ChessAI.quality_category(ai.move_loss(eng, mv, 3))
				total += 1
				if cat == "good":
					good += 1
				if cat == "blunder":
					blunders += 1
			eng.apply_move(mv)
			ply += 1
	var pct := 100.0 * good / maxi(total, 1)
	check("у мастеров не меньше 60% сильных ходов", pct >= 60.0, "%.0f%% из %d ходов, %d мс" % [pct, total, Time.get_ticks_msec() - t0])
	check("у мастеров зевков не больше 3%", 100.0 * blunders / maxi(total, 1) <= 3.0, "%d зевков" % blunders)
	# верное решение задачи на мат (в том числе мат в 3) не должно читаться как ошибка
	var mate_bad := 0
	var mate_total := 0
	var worst_loss := 0.0
	for p in PuzzleData.all():
		var pe := ChessEngine.new()
		pe.setup_from_fen(p.fen)
		var mv0: String = p.moves[0]
		var pm := find_move(pe, mv0.substr(0, 2), mv0.substr(2, 2))
		if pm.is_empty():
			continue
		mate_total += 1
		var ml: float = ai.move_loss(pe, pm, 3)
		worst_loss = maxf(worst_loss, ml)
		if ChessAI.quality_category(ml) in ["mistake", "blunder"]:
			mate_bad += 1
	check("верный первый ход задач на мат не считается ошибкой", mate_bad == 0, "%d из %d, худшая потеря %.0f" % [mate_bad, mate_total, worst_loss])
	print("=== ИТОГО ошибок: %d ===" % fails)
	get_tree().quit(1 if fails > 0 else 0)
