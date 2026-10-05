extends Node

# «Живая сложность»: новичок не получает утяжелённый старт, сдвиг ограничен ±2.
# Запуск: scenes/tools/TestAdaptive.tscn

var fails := 0

func check(name: String, ok: bool, info: String = "") -> void:
	print(("OK   " if ok else "FAIL ") + name + (" " + info if info != "" else ""))
	if not ok:
		fails += 1

func _ready() -> void:
	var old_a: bool = Global.adaptive_difficulty
	var old_g: int = Profile.games_played
	var old_r: float = Profile.rating
	Global.adaptive_difficulty = true
	Profile.games_played = 0
	Profile.rating = 600.0
	check("новичок: авторский уровень 1 остаётся 1", Global.adaptive_level(1) == 1, str(Global.adaptive_level(1)))
	Profile.games_played = Global.ADAPTIVE_MIN_GAMES
	var lvl: int = Global.adaptive_level(1)
	check("после разминки сдвиг вверх не больше +2", lvl >= 1 and lvl <= 1 + Global.ADAPTIVE_MAX_SHIFT, str(lvl))
	Profile.rating = 3000.0
	check("сильный игрок: сдвиг не больше +2", Global.adaptive_level(10) == 12, str(Global.adaptive_level(10)))
	Profile.rating = 100.0
	check("слабый игрок: сдвиг вниз не больше -2", Global.adaptive_level(10) == 8, str(Global.adaptive_level(10)))
	# соседние авторские уровни не сливаются в один
	Profile.rating = 1000.0
	var distinct := {}
	for b in range(1, 26):
		distinct[Global.adaptive_level(b)] = true
	check("авторская шкала не схлопывается (различимых уровней >= 18)", distinct.size() >= 20, str(distinct.size()))
	Global.adaptive_difficulty = false
	check("настройка выключена — уровень не меняется", Global.adaptive_level(7) == 7)
	Global.adaptive_difficulty = old_a
	Profile.games_played = old_g
	Profile.rating = old_r
	print("=== ИТОГО ошибок: %d ===" % fails)
	get_tree().quit(1 if fails > 0 else 0)
