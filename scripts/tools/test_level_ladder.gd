extends Node

# Лестница уровней ИИ монотонна: уровень на 3 ступени выше набирает больше половины очков.
# Быстрая проверка нижней и средней части (верх измеряет CalibrateLevels — он слишком долгий для теста).
# Запуск: scenes/tools/TestLevelLadder.tscn

const LevelMatch = preload("res://scripts/tools/LevelMatch.gd")

const PAIRS := [[1, 4], [4, 7], [7, 10]] # [младший, старший]

func _ready() -> void:
	var fails := 0
	for p in PAIRS:
		var r: Dictionary = LevelMatch.match_levels(p[1], p[0], 8, 60)
		var ok: bool = r.score >= 0.6
		print(("OK   " if ok else "FAIL ") + "уровень %d сильнее уровня %d: %.2f очка (+%d =%d -%d)" % [p[1], p[0], r.score, r.wins, r.draws, r.losses])
		if not ok:
			fails += 1
	print("=== ИТОГО ошибок: %d ===" % fails)
	get_tree().quit(1 if fails > 0 else 0)
