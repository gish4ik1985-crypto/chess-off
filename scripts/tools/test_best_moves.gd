extends Node

# Проверяет, что «лучшие ходы» в дневнике вообще могут попасть в галерею.
# Раньше Board.gd строил нотацию как "e2e4", а Profile.record_move_quality
# отбирает в recent_best взятия/превращения/рокировки по символам "x", "=",
# "O-O" — совпадений не было никогда, и вкладка «Ходы» показывала только
# худшие ходы.
# Запуск: godot --headless --path . res://scenes/tools/TestBestMoves.tscn

const Board = preload("res://scripts/Board.gd")

func _ready() -> void:
	var fails := 0

	# 1. Нотация должна помечать взятие, превращение и рокировку
	var eng := ChessEngine.new()
	eng.setup_start_position()
	# 1.e4 d5 2.exd5 — взятие пешкой
	eng.apply_move(_find(eng, "e2", "e4"))
	eng.apply_move(_find(eng, "d7", "d5"))
	var capture = _find(eng, "e4", "d5")
	var n_cap = Board.move_notation(eng, capture)
	fails += _check("взятие", n_cap, n_cap.contains("x"))

	var quiet := ChessEngine.new()
	quiet.setup_start_position()
	var n_quiet = Board.move_notation(quiet, _find(quiet, "g1", "f3"))
	fails += _check("тихий ход", n_quiet, n_quiet == "Ng1-f3")

	# рокировка
	var cst := ChessEngine.new()
	cst.setup_from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	var n_cst = Board.move_notation(cst, _find(cst, "e1", "g1"))
	fails += _check("рокировка", n_cst, n_cst == "O-O")

	# превращение
	var pro := ChessEngine.new()
	pro.setup_from_fen("8/P6k/8/8/8/8/7K/8 w - - 0 1")
	var pm = _find(pro, "a7", "a8")
	var n_pro = Board.move_notation(pro, pm)
	fails += _check("превращение", n_pro, n_pro.contains("="))

	# 2. Сквозная проверка: такой ход реально попадает в recent_best
	Profile.recent_best = []
	Profile.record_move_quality("good", 0.0, eng.to_fen(), n_cap)
	fails += _check("recent_best пополнился", str(Profile.recent_best.size()),
		Profile.recent_best.size() == 1)

	# тихий ход в галерею лучших не идёт — так и задумано
	Profile.recent_best = []
	Profile.record_move_quality("good", 0.0, quiet.to_fen(), n_quiet)
	fails += _check("тихий ход в галерею не идёт", str(Profile.recent_best.size()),
		Profile.recent_best.size() == 0)

	print("=== ИТОГО ошибок: %d ===" % fails)
	get_tree().quit(1 if fails > 0 else 0)

func _check(what: String, got: String, ok: bool) -> int:
	print("%s %s -> %s" % ["OK  " if ok else "FAIL", what, got])
	return 0 if ok else 1

func _find(eng: ChessEngine, from_sq: String, to_sq: String) -> Dictionary:
	var f = _sq(from_sq)
	var t = _sq(to_sq)
	for m in eng.legal_moves(eng.side_to_move):
		if m.from == f and m.to == t:
			return m
	return {}

func _sq(s: String) -> Vector2i:
	return Vector2i(s.unicode_at(0) - 97, s.unicode_at(1) - 49)
