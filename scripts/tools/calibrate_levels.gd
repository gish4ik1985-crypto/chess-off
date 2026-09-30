extends Node

# Замер реальной разницы в силе между уровнями ИИ (партиями друг с другом) и расчёт таблицы
# Profile.LEVEL_RATING. Долгий (десятки минут): запускать вручную, сцена
# scenes/tools/CalibrateLevels.tscn. Результат печатается строкой «LADDER».
#
# Абсолютную силу самоигра измерить не может — только разницу между уровнями. Поэтому
# верхний уровень привязывается к внешнему ориентиру ANCHOR_TOP (см. ниже).

const LevelMatch = preload("res://scripts/tools/LevelMatch.gd")

# Ориентир: простой движок TSCP 1.81 (материал + таблицы клеток, поиск 6–8 полуходов) имеет в
# списке CCRL около 1720. У нашего ИИ фиксированная глубина 4 (плюс взятия), это заметно слабее:
# каждый потерянный полуход стоит порядка 100–150 очков, значит верх шкалы ≈ 1500 ± 250.
const ANCHOR_TOP := 1500.0

# цепочка сравниваемых уровней: пары, число партий
const CHAIN := [
	[1, 2, 40], [2, 3, 40], [3, 4, 40], [4, 5, 40], [5, 6, 40], [6, 7, 40], [7, 8, 40], [8, 9, 40], [9, 10, 40],
	[10, 11, 24], [11, 12, 24], [12, 14, 20], [14, 18, 12], [18, 25, 12],
]

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var steps: Array = [] # [уровень, прирост относительно предыдущего звена]
	var var_sum := 0.0
	for c in CHAIN:
		var r: Dictionary = LevelMatch.match_levels(c[1], c[0], c[2])
		# elo — сила старшего уровня c[1] относительно младшего c[0]
		print("уровень %2d против %2d: %d партий, очков старшего %.2f (+%d =%d -%d) → %+.0f ± %.0f   [%d с]" % [
			c[1], c[0], c[2], r.score, r.wins, r.draws, r.losses, r.elo, r.err, (Time.get_ticks_msec() - t0) / 1000])
		steps.append([c[0], c[1], r.elo])
		var_sum += r.err * r.err
	# накопленная лестница относительно уровня 1, дыры между звеньями — линейная интерполяция
	var ladder := {1: 0.0}
	for s in steps:
		var lo: int = s[0]
		var hi: int = s[1]
		var base: float = ladder[lo]
		var gain: float = maxf(float(s[2]), 0.0) # разницу не считаем отрицательной: уровень выше не слабее
		for l in range(lo + 1, hi + 1):
			ladder[l] = base + gain * float(l - lo) / float(hi - lo)
	var top: float = ladder[25]
	var table: Array = []
	for l in range(1, 26):
		table.append(int(round((ladder[l] - top + ANCHOR_TOP) / 10.0) * 10.0))
	print("суммарная разница уровней 1 → 25: %.0f очков (погрешность ± %.0f)" % [top, sqrt(var_sum)])
	print("LADDER (верх привязан к %d): %s" % [int(ANCHOR_TOP), str(table)])
	print("всего %d с" % ((Time.get_ticks_msec() - t0) / 1000))
	get_tree().quit()
