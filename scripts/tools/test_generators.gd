# Quick offline check: how often each themed generator fails after the
# stricter clean-puzzle constraints.
# Runs as a scene, not `-s`/SceneTree script mode — that mode skips autoload
# init, and ChessEngine.gd references the Global autoload, so it fails to
# compile there (same issue test_scenes.gd's header documents).
# godot --headless --path . res://scenes/tools/TestGenerators.tscn
extends Node

func _ready() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 12345
	var gens = {
		"fork": func(): return ForkPuzzleGenerator.generate(rng),
		"pin": func(): return PinPuzzleGenerator.generate(rng),
		"backrank": func(): return BackRankPuzzleGenerator.generate(rng),
		"defense": func(): return DefensePuzzleGenerator.generate(rng),
		"deflection": func(): return DeflectionPuzzleGenerator.generate(rng),
	}
	for name in gens:
		var fails = 0
		for i in range(30):
			if gens[name].call().is_empty():
				fails += 1
		print("%s: %d/30 failed" % [name, fails])
	get_tree().quit()
