# OFFLINE AUTHORING TOOL — not a runtime dependency, nothing in the game
# reads its JSON output. Generates a varied, engine-verified candidate bank
# of mate-in-1/2/3 puzzles; the best ones were hand-picked from a past run
# and copied into PuzzleData.gd's static puzzle array. Re-run this (and the
# curation step) only if that bank ever needs to grow — the JSON it writes
# is scratch output, safe to delete/regenerate, and isn't committed.
# Runs as a scene, not `-s`/SceneTree script mode — that mode skips autoload
# init, and ChessEngine.gd references the Global autoload, so it fails to
# compile there (same issue test_scenes.gd's header documents).
# Run headless:
#   godot --headless --path . res://scenes/tools/GenMatePuzzles.tscn
#
# Variety comes from randomized piece sets (queen / rook pairs / rook+bishop /
# queen+knight / ...), random placement, and a dedupe signature so no two
# puzzles share the same piece set + mating pattern. Every puzzle is verified:
# the solution move is the ONLY first move that forces mate in exactly N,
# and the stored line follows Black's most resistant defense.
extends Node

var rng := RandomNumberGenerator.new()

const WHITE_SETS_1 := [["Q"], ["R"], ["Q", "R"], ["R", "R"], ["Q", "N"], ["Q", "B"], ["R", "B"], ["R", "N"], ["Q", "Q"], ["B", "B"]]
const WHITE_SETS_2 := [["Q"], ["Q", "R"], ["R", "R"], ["Q", "N"], ["Q", "B"], ["R", "B"], ["R", "N"], ["Q", "Q"]]
const WHITE_SETS_3 := [["Q", "R"], ["R", "R"], ["Q", "N"], ["Q", "B"], ["Q", "Q"], ["R", "B"]]
const BLACK_EXTRAS := [[], ["P"], ["P", "P"], ["N"], ["B"], ["P", "N"], ["P", "B"], ["R"], ["P", "P", "P"]]

func _ready() -> void:
	rng.seed = 20260708
	var bank := {"mate1": [], "mate2": [], "mate3": []}
	var sigs := {}
	_collect(bank.mate1, sigs, 1, 10, 20000)
	print("mate1 done: ", bank.mate1.size())
	_collect(bank.mate2, sigs, 2, 30, 60000)
	print("mate2 done: ", bank.mate2.size())
	_collect(bank.mate3, sigs, 3, 10, 60000)
	print("mate3 done: ", bank.mate3.size())
	var f = FileAccess.open("res://scripts/tools/generated_puzzles.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(bank, "\t"))
	f.close()
	print("WROTE ", bank.mate1.size(), "/", bank.mate2.size(), "/", bank.mate3.size())
	get_tree().quit()

func _collect(out: Array, sigs: Dictionary, n: int, want: int, max_tries: int) -> void:
	var sets: Array = [WHITE_SETS_1, WHITE_SETS_2, WHITE_SETS_3][n - 1]
	var set_idx := 0
	var tries := 0
	while out.size() < want and tries < max_tries:
		tries += 1
		# cycle piece sets so variety is forced, not left to chance
		var wset: Array = sets[set_idx % sets.size()]
		var bextra: Array = BLACK_EXTRAS[rng.randi_range(0, BLACK_EXTRAS.size() - 1)]
		var e = _random_position(wset, bextra)
		if e == null:
			continue
		var sols = _mate_solutions(e, n)
		if sols.size() != 1:
			continue
		if n >= 2 and not _mate_solutions(e, n - 1).is_empty():
			continue
		if n >= 3 and not _mate_solutions(e, 1).is_empty():
			continue
		var line = _extract_line(e, sols[0], n)
		if line.is_empty():
			continue
		var sig = _signature(e, line)
		if sigs.has(sig):
			continue
		sigs[sig] = true
		out.append({"fen": e.to_fen(), "moves": line, "mate_in": n})
		set_idx += 1
		print("  found %d/%d (n=%d, try %d): %s" % [out.size(), want, n, tries, e.to_fen()])

func _random_position(wset: Array, bextra: Array):
	var e = ChessEngine.new()
	e.board = []
	for r in range(8):
		var row := []
		for f in range(8):
			row.append(null)
		e.board.append(row)
	var used := {}
	var bk = _rand_sq(used)
	# bias the black king toward edges/corners — that's where real mates live
	if rng.randf() < 0.7:
		var edge_choice = rng.randi_range(0, 3)
		match edge_choice:
			0: bk = Vector2i(rng.randi_range(0, 7), 7)
			1: bk = Vector2i(rng.randi_range(0, 7), 0)
			2: bk = Vector2i(0, rng.randi_range(0, 7))
			3: bk = Vector2i(7, rng.randi_range(0, 7))
		used.clear()
		used[bk] = true
	var wk = _rand_sq(used)
	if max(abs(wk.x - bk.x), abs(wk.y - bk.y)) < 2:
		return null
	e.board[bk.y][bk.x] = {"type": "K", "color": "b"}
	e.board[wk.y][wk.x] = {"type": "K", "color": "w"}
	for t in wset:
		var s = _rand_sq(used)
		if t == "P" and (s.y == 0 or s.y == 7):
			return null
		e.board[s.y][s.x] = {"type": t, "color": "w"}
	for t in bextra:
		var s = _rand_sq(used)
		if t == "P" and (s.y < 4 or s.y == 7):
			return null # keep black pawns far from promotion
		e.board[s.y][s.x] = {"type": t, "color": "b"}
	e.side_to_move = "w"
	e.castling = {"wk": false, "wq": false, "bk": false, "bq": false}
	e.en_passant_target = null
	e.halfmove_clock = 0
	e.fullmove_number = 1
	if e.is_in_check("b") or e.is_in_check("w"):
		return null
	if e.game_status() != "playing":
		return null
	return e

func _rand_sq(used: Dictionary) -> Vector2i:
	while true:
		var s = Vector2i(rng.randi_range(0, 7), rng.randi_range(0, 7))
		if not used.has(s):
			used[s] = true
			return s
	return Vector2i.ZERO

# First white moves that force mate in <= n. For n >= 2 only checking moves
# are considered (kid-level forced mates are check sequences; also fast).
func _mate_solutions(e, n: int) -> Array:
	var res := []
	for m in e.legal_moves("w"):
		var c = e.clone()
		c.apply_move(m)
		if c.game_status() == "checkmate":
			res.append(m)
			continue
		if n < 2:
			continue
		if not c.is_in_check("b"):
			continue
		var replies = c.legal_moves("b")
		if replies.is_empty():
			continue # stalemate
		var all_forced := true
		for r in replies:
			var c2 = c.clone()
			c2.apply_move(r)
			if _mate_solutions(c2, n - 1).is_empty():
				all_forced = false
				break
		if all_forced:
			res.append(m)
	return res

# Full move line following Black's most resistant defense.
func _extract_line(e, first_move, n: int) -> Array:
	var line := []
	var cur = e.clone()
	var m = first_move
	var depth = n
	while true:
		line.append(_coord(m))
		cur.apply_move(m)
		if cur.game_status() == "checkmate":
			return line
		if depth <= 1:
			return [] # should not happen
		# pick Black's reply that survives the longest
		var best_r = null
		var best_d := -1
		for r in cur.legal_moves("b"):
			var c2 = cur.clone()
			c2.apply_move(r)
			var d = 1
			while d < depth and _mate_solutions(c2, d).is_empty():
				d += 1
			if d > best_d:
				best_d = d
				best_r = r
		if best_r == null:
			return []
		line.append(_coord(best_r))
		cur.apply_move(best_r)
		depth -= 1
		var sols = _mate_solutions(cur, depth)
		if sols.is_empty():
			return []
		m = sols[0]
	return line

func _coord(m: Dictionary) -> String:
	return ChessEngine.square_name(m.from.x, m.from.y) + ChessEngine.square_name(m.to.x, m.to.y)

# Dedupe: same piece material + same mating piece + same mate corner quadrant
# counts as "the same kind of puzzle".
func _signature(e, line: Array) -> String:
	var mat := []
	for r in range(8):
		for f in range(8):
			var p = e.board[r][f]
			if p != null:
				mat.append(p.color + p.type)
	mat.sort()
	var last: String = line[-1]
	var quad = str(int(last[2] >= "e")) + str(int(int(last[3]) >= 5))
	return ",".join(mat) + "|" + last.substr(0, 1) + "|" + quad + "|" + str(line.size())
