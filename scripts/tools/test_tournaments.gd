extends SceneTree

# Headless sanity test for the tournament system:
#   godot --headless -s res://scripts/tools/test_tournaments.gd

func _init() -> void:
	var profile = load("res://scripts/Profile.gd").new()

	# separate tournament rating moves independently of the main one
	var main_before = profile.rating
	var t_before = profile.tournament_rating
	profile.record_tournament_game(5, 1.0)
	assert(profile.tournament_rating > t_before, "tournament rating must rise after a win")
	assert(profile.rating == main_before, "main rating must NOT change from tournament games")
	assert(profile.last_tournament_rating_change > 0.0, "delta must be positive")

	# play a full 3-round tournament winning every game
	var bots := []
	for i in range(7):
		bots.append({"name": "Бот %d" % i, "level": 3 + (i % 3), "score": 0.0})
	profile.active_tournaments["test_cup"] = {
		"id": "test_cup", "name": "Тестовый кубок", "format": "Классика",
		"tc": 0, "inc": 0, "rounds": 3,
		"round": 0, "my_score": 0.0, "my_played": [], "bots": bots,
		"done": false, "won": false,
	}
	var state = {}
	for r in range(3):
		state = profile.finish_tournament_round("test_cup", r, 1.0)
		assert(not state.is_empty(), "state must be returned")
	assert(state.done, "tournament must finish after 3 rounds")
	assert(state.my_score == 3.0, "player must have 3 points")
	# with 3/3 the player can at worst share first (bots max 3 too)
	assert(profile.tournament_place(state) <= 2, "3/3 must be near the top")
	assert(profile.tournaments_played == 1, "played counter")
	assert(profile.unlocked_achievements.has("tourney_first"), "first-tournament achievement")
	if state.won:
		assert(profile.tournaments_won == 1, "won counter must match state.won")
		assert(profile.unlocked_achievements.has("tourney_win"), "win achievement")
	# every bot got a result in every round: total points = 4 games * 3 rounds
	var total = float(state.my_score)
	for bt in state.bots:
		total += float(bt.score)
	assert(absf(total - 12.0) < 0.001, "each round must distribute exactly 4 points, got %f" % total)

	# a finished tournament ignores further results
	var again = profile.finish_tournament_round("test_cup", 0, 1.0)
	assert(again.done and float(again.my_score) == 3.0, "finished tournament must be immutable")

	# daily pruning keeps today, drops older
	profile.active_tournaments["daily_2020-01-01"] = {"done": true}
	profile.active_tournaments["daily_today"] = {"done": false}
	profile.prune_daily_tournaments("daily_today")
	assert(not profile.active_tournaments.has("daily_2020-01-01"), "old daily must be pruned")
	assert(profile.active_tournaments.has("daily_today"), "today's daily must survive")
	assert(profile.active_tournaments.has("test_cup"), "standing tournaments must survive pruning")

	print("ALL TOURNAMENT TESTS PASSED")
	quit(0)
