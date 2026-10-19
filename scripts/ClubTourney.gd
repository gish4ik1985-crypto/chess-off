class_name ClubTourney
extends RefCounted

# Турниры школы, которые проводит учитель онлайн: жеребьёвка (круговая и швейцарская), турнирная таблица.
# Данные в облаке: ctourneys (турнир), centries (заявки), cgames (партии). Здесь — только расчёты.

const KINDS := {"round_robin": "Круговой (каждый с каждым)", "swiss": "Швейцарская система"}

# Игрок: {uid, name}. Пара: {w, b} — игроки; b == null — «пропуск тура» (очко без партии).

# Круговая система методом «круга»: список туров, в каждом — пары. Нечётное число игроков — пропуск тура.
static func round_robin(players: Array) -> Array:
	var ps := players.duplicate()
	if ps.size() % 2 == 1:
		ps.append(null)
	var n := ps.size()
	var rounds := []
	for r in range(n - 1):
		var pairs := []
		for i in range(n / 2):
			var a = ps[i]
			var b = ps[n - 1 - i]
			if a == null or b == null:
				pairs.append({"w": a if a != null else b, "b": null})
			else:
				# цвета чередуем по туру и по столу, чтобы у всех было примерно поровну белых
				pairs.append({"w": a, "b": b} if (r + i) % 2 == 0 else {"w": b, "b": a})
		rounds.append(pairs)
		# поворот: первый стоит, остальные сдвигаются
		var last = ps.pop_back()
		ps.insert(1, last)
	return rounds

# Один тур швейцарской системы. scores: имя → очки; played: набор «имя1|имя2»; whites: имя → сколько раз белыми;
# had_bye: имена, уже получавшие пропуск. Возвращает список пар.
static func swiss_round(players: Array, scores: Dictionary, played: Dictionary, whites: Dictionary, had_bye: Array) -> Array:
	var ps := players.duplicate()
	ps.sort_custom(func(a, b):
		var sa: float = float(scores.get(a.uid, 0.0))
		var sb: float = float(scores.get(b.uid, 0.0))
		if sa != sb:
			return sa > sb
		return String(a.name) < String(b.name))
	var pairs := []
	var bye_player = null
	if ps.size() % 2 == 1:
		# пропуск тура — слабейшему из тех, кто его ещё не имел
		for i in range(ps.size() - 1, -1, -1):
			if not (ps[i].uid in had_bye):
				bye_player = ps[i]
				ps.remove_at(i)
				break
		if bye_player == null:
			bye_player = ps.pop_back()
	var used := {}
	for i in range(ps.size()):
		var a = ps[i]
		if used.has(a.uid):
			continue
		used[a.uid] = true
		var partner = null
		for j in range(i + 1, ps.size()):
			var b = ps[j]
			if used.has(b.uid):
				continue
			if not played.has(_key(a.uid, b.uid)):
				partner = b
				break
		if partner == null: # все подходящие уже играли — допускаем повтор
			for j in range(i + 1, ps.size()):
				if not used.has(ps[j].uid):
					partner = ps[j]
					break
		if partner == null:
			continue
		used[partner.uid] = true
		# белыми — тот, у кого их было меньше
		var wa: int = int(whites.get(a.uid, 0))
		var wb: int = int(whites.get(partner.uid, 0))
		pairs.append({"w": a, "b": partner} if wa <= wb else {"w": partner, "b": a})
	if bye_player != null:
		pairs.append({"w": bye_player, "b": null})
	return pairs

static func _key(a: String, b: String) -> String:
	return (a + "|" + b) if a < b else (b + "|" + a)

# Из списка партий турнира: очки, кто с кем играл, сколько раз белыми, кто имел пропуск.
static func summarize(games: Array) -> Dictionary:
	var scores := {}
	var played := {}
	var whites := {}
	var had_bye := []
	for g in games:
		if String(g.get("status", "")) != "done":
			continue
		var w := String(g.get("wuid", ""))
		var b := String(g.get("buid", ""))
		var res := String(g.get("result", ""))
		if b == "":
			if w != "":
				had_bye.append(w)
				scores[w] = float(scores.get(w, 0.0)) + 1.0
			continue
		played[_key(w, b)] = true
		whites[w] = int(whites.get(w, 0)) + 1
		match res:
			"1-0":
				scores[w] = float(scores.get(w, 0.0)) + 1.0
			"0-1":
				scores[b] = float(scores.get(b, 0.0)) + 1.0
			"1/2-1/2":
				scores[w] = float(scores.get(w, 0.0)) + 0.5
				scores[b] = float(scores.get(b, 0.0)) + 0.5
	return {"scores": scores, "played": played, "whites": whites, "had_bye": had_bye}

# Турнирная таблица по именам (работает и для турниров, записанных вручную): строки {name, pts, games, w, d, l}.
static func standings(games: Array) -> Array:
	var rows := {}
	for g in games:
		if String(g.get("status", "")) != "done":
			continue
		var wn := String(g.get("wname", ""))
		var bn := String(g.get("bname", ""))
		var res := String(g.get("result", ""))
		if wn == "":
			continue
		if not rows.has(wn):
			rows[wn] = {"name": wn, "pts": 0.0, "games": 0, "w": 0, "d": 0, "l": 0}
		if String(g.get("buid", "")) == "" and bn.begins_with("—"):
			rows[wn].pts += 1.0 # пропуск тура
			continue
		if bn == "":
			continue
		if not rows.has(bn):
			rows[bn] = {"name": bn, "pts": 0.0, "games": 0, "w": 0, "d": 0, "l": 0}
		rows[wn].games += 1
		rows[bn].games += 1
		match res:
			"1-0":
				rows[wn].pts += 1.0
				rows[wn].w += 1
				rows[bn].l += 1
			"0-1":
				rows[bn].pts += 1.0
				rows[bn].w += 1
				rows[wn].l += 1
			"1/2-1/2":
				rows[wn].pts += 0.5
				rows[bn].pts += 0.5
				rows[wn].d += 1
				rows[bn].d += 1
	var out: Array = rows.values()
	out.sort_custom(func(a, b):
		if a.pts != b.pts:
			return a.pts > b.pts
		if a.w != b.w:
			return a.w > b.w
		return String(a.name) < String(b.name))
	return out

static func pts_text(p: float) -> String:
	return str(int(p)) if is_equal_approx(p, floor(p)) else "%d½" % int(floor(p)) if p >= 1.0 else "½"

# ---- кеш для главного экрана: мои партии, ждущие хода ----
static var my_turn_games: Array = []

static func load_mine() -> void:
	my_turn_games = []
	if not (Cloud.enabled and Cloud.signed_in):
		return
	var g: Dictionary = await Cloud.query_top("cgames", "at", 800)
	if not g.ok:
		return
	for d in g.docs:
		if String(d.get("status", "")) != "play":
			continue
		var turn := String(d.get("turn", "w"))
		if (turn == "w" and String(d.get("wuid", "")) == Cloud.uid) or (turn == "b" and String(d.get("buid", "")) == Cloud.uid):
			my_turn_games.append(d)
