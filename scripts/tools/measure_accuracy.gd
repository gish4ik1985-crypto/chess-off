extends Node

# Проверка «линейки» точности из Дневника: прогоняет ходы партий гроссмейстеров
# через тот же move_loss и считает, как они попадают в категории. У мастеров
# доля «сильных» ходов должна быть высокой, а зевков — почти нулевой; если это не
# так, линейка врёт и её нельзя применять к игроку. Запуск: scenes/tools/MeasureAccuracy.tscn

const GamesData = preload("res://scripts/HistoricGamesData.gd")
const HG = preload("res://scripts/HistoricGames.gd")

const MAX_PLIES := 70

func _category(loss: float, th: Array) -> String:
	if loss > th[2]:
		return "blunder"
	if loss > th[1]:
		return "mistake"
	if loss > th[0]:
		return "inaccuracy"
	return "good"

func _ready() -> void:
	var configs := [
		{"name": "как сейчас (уровень 9, без поиска взятий), глубина 3", "level": 9, "depth": 3},
		{"name": "с поиском взятий (уровень 12), глубина 3", "level": 12, "depth": 3},
		{"name": "с поиском взятий (уровень 12), глубина 4", "level": 12, "depth": 4},
	]
	var thresholds := [[30.0, 100.0, 300.0], [50.0, 150.0, 350.0], [70.0, 200.0, 400.0]]
	var sample: Array = []
	for p in GamesData.players():
		sample.append(p.games[0])
		if p.games.size() > 5:
			sample.append(p.games[5])
	for cfg in configs:
		var ai := ChessAI.new(cfg.level)
		var losses: Array = []
		var t0 := Time.get_ticks_msec()
		for g in sample:
			var eng := ChessEngine.new()
			if str(g.get("start_fen", "")) != "":
				eng.setup_from_fen(g.start_fen)
			else:
				eng.setup_start_position()
			var ply := 0
			for san in HG.game_moves(g):
				var mv = HG._parse_san(eng, san)
				if mv.is_empty() or ply >= MAX_PLIES:
					break
				if ply >= 8: # дебютную теорию не оцениваем
					losses.append(ai.move_loss(eng, mv, cfg.depth))
				eng.apply_move(mv)
				ply += 1
		print("== %s: ходов %d, %d мс (%.0f мс на ход)" % [cfg.name, losses.size(), Time.get_ticks_msec() - t0, float(Time.get_ticks_msec() - t0) / maxi(losses.size(), 1)])
		for th in thresholds:
			var counts := {"good": 0, "inaccuracy": 0, "mistake": 0, "blunder": 0}
			for l in losses:
				counts[_category(float(l), th)] += 1
			var n := maxi(losses.size(), 1)
			print("   пороги %d/%d/%d: сильных %.0f%%, неточностей %.0f%%, ошибок %.0f%%, зевков %.1f%%" % [th[0], th[1], th[2], 100.0 * counts.good / n, 100.0 * counts.inaccuracy / n, 100.0 * counts.mistake / n, 100.0 * counts.blunder / n])
	get_tree().quit()
