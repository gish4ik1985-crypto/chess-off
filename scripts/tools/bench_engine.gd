extends Node

# Замер скорости ChessEngine и того, что на нём построено: расчёт ходов, конец партии,
# apply_move, генерация задач всех пяти тем. Запуск: scenes/tools/BenchEngine.tscn

const Generators := {
	"вилка": preload("res://scripts/ForkPuzzleGenerator.gd"),
	"связка": preload("res://scripts/PinPuzzleGenerator.gd"),
	"мат на последней": preload("res://scripts/BackRankPuzzleGenerator.gd"),
	"уничтожение защиты": preload("res://scripts/DefensePuzzleGenerator.gd"),
	"отвлечение": preload("res://scripts/DeflectionPuzzleGenerator.gd"),
}

func _ready() -> void:
	var fens := [
		"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
		"r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
		"r1bq1rk1/pp2bppp/2n1pn2/2pp4/3P1B2/2PBPN2/PP1N1PPP/R2QK2R w KQ - 0 8",
	]
	for fen in fens:
		var e := ChessEngine.new()
		e.setup_from_fen(fen)
		var t := Time.get_ticks_msec()
		var n := 0
		for i in range(300):
			n += e.legal_moves().size()
		var t_legal := Time.get_ticks_msec() - t
		t = Time.get_ticks_msec()
		for i in range(300):
			e._status_cache_valid = false
			e.game_status()
		var t_status := Time.get_ticks_msec() - t
		t = Time.get_ticks_msec()
		var lm = e.legal_moves()
		for i in range(300):
			var c = e.clone()
			c.apply_move(lm[i % lm.size()])
		var t_apply := Time.get_ticks_msec() - t
		t = Time.get_ticks_msec()
		for i in range(300):
			e.legal_moves_for_square(4, 0)
		var t_sq := Time.get_ticks_msec() - t
		print("%s...  legal x300: %d мс (%d ходов) · status x300: %d мс · clone+apply x300: %d мс · ходы одной фигуры x300: %d мс" % [fen.left(14), t_legal, n / 300, t_status, t_apply, t_sq])
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for name in Generators:
		var gen = Generators[name]
		var t0 := Time.get_ticks_msec()
		var made := 0
		for i in range(10):
			var p: Dictionary = gen.generate(rng)
			if not p.is_empty():
				made += 1
		print("задача «%s»: %d из 10 за %d мс (%d мс на задачу)" % [name, made, Time.get_ticks_msec() - t0, (Time.get_ticks_msec() - t0) / 10])
	get_tree().quit()
