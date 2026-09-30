extends Node

# Замер «живости» комментариев к партиям великих: доля ручных заметок, число
# разных автоматических фраз (после маскирования клеток и цифр), самые частые
# повторы, а также проверка, что ход, названный в ручной заметке, действительно
# стоит на её полуходе. Запуск: scenes/tools/CommentStats.tscn

const GamesData = preload("res://scripts/HistoricGamesData.gd")
const HG = preload("res://scripts/HistoricGames.gd")

func _ready() -> void:
	var hg = HG.new()
	var B := char(92)
	var rx := RegEx.new()
	rx.compile("(" + B + "d+)(" + B + ".{3}|" + B + ".)" + B + "s?([NBRQK]?[a-h]?[1-8]?x?[a-h][1-8](?:=[QRBN])?|O-O-O|O-O)")
	var mask := RegEx.new()
	mask.compile("[a-h][1-8]|" + B + "d+")
	var plies := 0
	var hand := 0
	var auto := 0
	var bodies := {}
	var checked := 0
	var bad := []
	var empty_or_bad := 0
	for p in GamesData.players():
		for g in p.games:
			hg.current_game = g
			var eng := ChessEngine.new()
			if str(g.get("start_fen", "")) != "":
				eng.setup_from_fen(g.start_fen)
			else:
				eng.setup_start_position()
			var notes: Dictionary = g.get("notes", {})
			var ply := 0
			for san in HG.game_moves(g):
				var before = eng.clone()
				var mv = HG._parse_san(eng, san)
				if mv.is_empty():
					break
				eng.apply_move(mv)
				ply += 1
				plies += 1
				if notes.has(ply):
					hand += 1
					for m in rx.search_all(str(notes[ply])):
						var n := int(m.get_string(1))
						var want := 2 * n - (1 if m.get_string(2) == "." else 0)
						if want == ply:
							checked += 1
							if m.get_string(3).replace("x", "").split("=")[0] != san.replace("+", "").replace("#", "").replace("x", "").split("=")[0]:
								bad.append("%s ply %d: в ходе %s, в заметке %s" % [g.id, ply, san, m.get_string(3)])
							break
				else:
					auto += 1
					var c: String = hg._auto_comment(before, eng, mv, san, ply)
					if c.strip_edges() == "" or c.find("%s") >= 0 or c.find("%d") >= 0:
						empty_or_bad += 1
					var body: String = mask.sub(c.substr(c.find("): ") + 3), "#", true)
					body = body.split("\n")[0]
					bodies[body] = int(bodies.get(body, 0)) + 1
	print("полуходов: %d, ручных: %d (%.1f%%), автоматических: %d" % [plies, hand, 100.0 * hand / plies, auto])
	print("РАЗНЫХ автоматических фраз: %d (после маскирования клеток и цифр)" % bodies.size())
	var arr: Array = bodies.keys()
	arr.sort_custom(func(a, b): return bodies[a] > bodies[b])
	var top5 := 0
	for i in range(mini(5, arr.size())):
		top5 += int(bodies[arr[i]])
	print("пять самых частых фраз покрывают %d ходов (%.1f%%)" % [top5, 100.0 * top5 / maxi(auto, 1)])
	for i in range(mini(10, arr.size())):
		print("%5dx  %s" % [bodies[arr[i]], str(arr[i]).left(120)])
	print("ручные заметки, проверено ходов: %d, расхождений: %d" % [checked, bad.size()])
	for b in bad:
		print("  ", b)
	print("пустых или с нераскрытым шаблоном: %d" % empty_or_bad)
	get_tree().quit()
