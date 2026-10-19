extends Node

# Smoke test: loads and instantiates every top-level scene, checking each
# attached script actually compiles. Must run as a normal scene (not via
# `godot -s`, which is SceneTree script mode and skips autoload init —
# Global/Profile wouldn't exist there, so every script referencing them
# would silently fail to compile while the scene still "loaded").
# Run: godot --headless --path . res://scenes/tools/TestScenes.tscn

const SCENES := [
	"res://scenes/Menu.tscn", "res://scenes/RoadHome.tscn", "res://scenes/Board.tscn",
	"res://scenes/Achievements.tscn", "res://scenes/AttentionHub.tscn", "res://scenes/Diary.tscn",
	"res://scenes/HistoricGames.tscn", "res://scenes/Login.tscn", "res://scenes/Map.tscn",
	"res://scenes/Puzzle.tscn", "res://scenes/PuzzleHub.tscn", "res://scenes/School.tscn",
	"res://scenes/Settings.tscn", "res://scenes/TournamentPrep.tscn", "res://scenes/Tournaments.tscn",
	"res://scenes/TrophyRoom.tscn", "res://scenes/BotsHub.tscn", "res://scenes/Admin.tscn", "res://scenes/Homework.tscn", "res://scenes/Notebook.tscn",
]

func _ready() -> void:
	var fails := 0
	for p in SCENES:
		var ps = load(p)
		if ps == null:
			print("FAIL ", p, " — failed to load")
			fails += 1
			continue
		var node = ps.instantiate()
		if node == null:
			print("FAIL ", p, " — failed to instantiate")
			fails += 1
			continue
		# Сломанный скрипт НЕ делает load() неуспешным: сцена грузится, а
		# скрипт молча отваливается с parse error. Проверяем явно.
		if node.get_script() == null:
			print("FAIL ", p, " — скрипт корня не скомпилировался")
			fails += 1
			node.free()
			continue
		node.free()
		print("OK ", p)
	print("=== ИТОГО: сцен %d, ошибок %d ===" % [SCENES.size(), fails])
	get_tree().quit(1 if fails > 0 else 0)
