extends Node

# Валидатор базы знаменитых партий: прогоняет каждую партию каждого шахматиста
# через движок и проверяет, что все ходы читаются и партия доигрывается.
# Запуск: открыть сцену res://scenes/tools/HistoricValidator.tscn.

const GamesData = preload("res://scripts/HistoricGamesData.gd")
const HG = preload("res://scripts/HistoricGames.gd")

func _ready() -> void:
	var players: Array = GamesData.players()
	var total := 0
	var fails := 0
	print("=== HISTORIC GAMES VALIDATION ===")
	for p in players:
		var pfails := 0
		for g in p.games:
			total += 1
			var eng := ChessEngine.new()
			if str(g.get("start_fen", "")) != "":
				eng.setup_from_fen(g.start_fen)
			else:
				eng.setup_start_position()
			var sans = HG.game_moves(g)
			var ply := 0
			for san in sans:
				var mv = HG._parse_san(eng, san)
				if mv.is_empty():
					print("  FAIL %s: ход #%d '%s' не читается" % [g.id, ply + 1, san])
					fails += 1
					pfails += 1
					break
				eng.apply_move(mv)
				ply += 1
		var mark = "OK" if pfails == 0 else ("FAILS=%d" % pfails)
		var warn = "  <10!" if p.games.size() < 10 else ""
		print("%s — %d партий [%s]%s" % [p.name, p.games.size(), mark, warn])
	print("=== ИТОГО: партий %d, ошибок %d ===" % [total, fails])
	get_tree().quit(1 if fails > 0 else 0)

