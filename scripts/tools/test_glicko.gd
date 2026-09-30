extends Node

# Проверка рейтинговой системы Glicko-2: направление изменений, разумные величины,
# рост неопределённости без игры. Запуск: scenes/tools/TestGlicko.tscn

var fails := 0

func check(name: String, ok: bool, info: String = "") -> void:
	print(("OK   " if ok else "FAIL ") + name + (" " + info if info != "" else ""))
	if not ok:
		fails += 1

func _ready() -> void:
	var eq_win: Dictionary = Glicko2.update(1200.0, 100.0, 0.06, 1200.0, 100.0, 1.0)
	var eq_loss: Dictionary = Glicko2.update(1200.0, 100.0, 0.06, 1200.0, 100.0, 0.0)
	var eq_draw: Dictionary = Glicko2.update(1200.0, 100.0, 0.06, 1200.0, 100.0, 0.5)
	check("победа над равным поднимает рейтинг", eq_win.rating > 1200.0, "%.1f" % eq_win.rating)
	check("поражение от равного опускает рейтинг", eq_loss.rating < 1200.0, "%.1f" % eq_loss.rating)
	check("ничья с равным почти не меняет рейтинг", absf(eq_draw.rating - 1200.0) < 1.0, "%.2f" % eq_draw.rating)
	check("выигрыш и проигрыш симметричны", absf((eq_win.rating - 1200.0) + (eq_loss.rating - 1200.0)) < 0.5)
	check("после партии неопределённость (RD) уменьшается", eq_win.rd < 100.0, "%.1f" % eq_win.rd)
	var strong_win: Dictionary = Glicko2.update(1200.0, 100.0, 0.06, 1800.0, 100.0, 1.0)
	check("победа над сильным даёт больше, чем над равным", strong_win.rating - 1200.0 > eq_win.rating - 1200.0)
	var weak_win: Dictionary = Glicko2.update(1200.0, 100.0, 0.06, 800.0, 100.0, 1.0)
	check("победа над слабым даёт меньше, чем над равным", weak_win.rating >= 1200.0 and weak_win.rating - 1200.0 < eq_win.rating - 1200.0)
	var weak_loss: Dictionary = Glicko2.update(1200.0, 100.0, 0.06, 800.0, 100.0, 0.0)
	check("поражение от слабого бьёт по рейтингу сильнее", 1200.0 - weak_loss.rating > 1200.0 - eq_loss.rating)
	var new_player: Dictionary = Glicko2.update(Glicko2.DEFAULT_RATING, Glicko2.DEFAULT_RD, Glicko2.DEFAULT_VOLATILITY, 1000.0, 100.0, 1.0)
	check("у новичка (RD 350) рейтинг двигается сильнее, чем у опытного", new_player.rating - 1000.0 > eq_win.rating - 1200.0, "%.0f" % (new_player.rating - 1000.0))
	var r := 1000.0
	var rd := 350.0
	var vol := 0.06
	for i in range(30):
		var u: Dictionary = Glicko2.update(r, rd, vol, 1000.0, 100.0, 1.0)
		r = u.rating
		rd = u.rd
		vol = u.volatility
	check("30 побед подряд: рейтинг растёт и остаётся конечным", r > 1300.0 and r < 4000.0 and is_finite(r), "%.0f" % r)
	check("RD не падает ниже разумного", rd > 20.0, "%.1f" % rd)
	check("RD растёт, пока игрок не играет", Glicko2.decay_rd(60.0, 10.0) > 60.0)
	check("RD не превышает исходную неопределённость", Glicko2.decay_rd(300.0, 10000.0) <= Glicko2.DEFAULT_RD)
	check("при нуле прошедших периодов RD не меняется", Glicko2.decay_rd(60.0, 0.0) == 60.0)
	print("=== ИТОГО ошибок: %d ===" % fails)
	get_tree().quit(1 if fails > 0 else 0)
