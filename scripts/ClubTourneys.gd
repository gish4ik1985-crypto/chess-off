extends Control

# «Турниры школы»: онлайн-турниры, которые проводит учитель, и записанные офлайн-турниры.
# Ученик записывается и играет свои партии (OnlineGame), все смотрят таблицу и разбирают партии в записной книжке.
# Учитель создаёт турнир, запускает его (жеребьёвка), открывает следующий тур, добавляет партии вручную.

var _root: VBoxContainer
var _status: Label
var _view: VBoxContainer
var _tourneys: Array = []
var _entries: Array = []
var _games: Array = []
var _open_id := ""

func _ready() -> void:
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.02, 0.02, 0.05)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 72.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_root = VBoxContainer.new()
	_root.custom_minimum_size = Vector2(780, 0)
	_root.add_theme_constant_override("separation", 12)
	center.add_child(_root)
	Global.add_floating_back(self, _on_back)
	var title := Label.new()
	title.text = "ТУРНИРЫ ШКОЛЫ"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.96, 0.76, 0.3))
	title.position = Vector2(24, 16)
	add_child(title)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 13)
	_root.add_child(_status)
	_view = VBoxContainer.new()
	_view.add_theme_constant_override("separation", 10)
	_root.add_child(_view)
	if not (Cloud.enabled and Cloud.signed_in):
		_status.text = "Турниры школы идут через облако: войдите онлайн."
		return
	_reload()

func _on_back() -> void:
	if _open_id != "":
		_open_id = ""
		_show_list()
		return
	Global.go_back()

func _is_teacher() -> bool:
	return Roles.can(Profile.role, "open_admin")

func _reload() -> void:
	_status.text = "Загружаю…"
	var t: Dictionary = await Cloud.query_top("ctourneys", "created", 60)
	var e: Dictionary = await Cloud.query_top("centries", "at", 800)
	var g: Dictionary = await Cloud.query_top("cgames", "at", 1500)
	if not is_inside_tree():
		return
	if not t.ok:
		_status.text = String(t.error)
		return
	_tourneys = t.docs
	_entries = e.docs if e.ok else []
	_games = g.docs if g.ok else []
	_status.text = ""
	if _open_id != "" and _find(_open_id).is_empty():
		_open_id = ""
	if _open_id != "":
		_show_detail(_find(_open_id))
	else:
		_show_list()

func _find(id: String) -> Dictionary:
	for t in _tourneys:
		if String(t.get("_id", "")) == id:
			return t
	return {}

func _clear() -> void:
	for ch in _view.get_children():
		ch.queue_free()

func _lbl(text: String, size := 14, color := Color(1, 1, 1, 0.92)) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	if color != Color(1, 1, 1, 0.92):
		l.add_theme_color_override("font_color", color)
	return l

func _btn(text: String, w := 0.0, h := 44.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	return b

func _games_of(tid: String) -> Array:
	var out := []
	for g in _games:
		if String(g.get("tid", "")) == tid:
			out.append(g)
	return out

func _entries_of(tid: String) -> Array:
	var out := []
	for e in _entries:
		if String(e.get("tid", "")) == tid:
			out.append(e)
	return out

func _status_text(t: Dictionary) -> String:
	match String(t.get("status", "")):
		"reg": return "🟢 идёт запись"
		"run": return "🔵 идёт турнир" + (" · тур %d из %d" % [int(t.get("round", 0)), int(t.get("rounds", 0))] if String(t.get("kind", "")) == "swiss" else "")
		"done": return "🏁 завершён"
	return ""

# ------------------------------------------------------------------ список

func _show_list() -> void:
	_clear()
	if _is_teacher():
		var add := _btn("+ Новый турнир", 0, 50)
		add.pressed.connect(_show_builder)
		_view.add_child(add)
	# мои партии, ждущие хода
	var mine := _my_games()
	if not mine.is_empty():
		_view.add_child(_lbl("Мои партии", 15, Color(0.96, 0.76, 0.3)))
		for g in mine:
			_view.add_child(_game_row(g, true))
	if _tourneys.is_empty():
		_view.add_child(_lbl("Турниров пока нет. Когда учитель создаст турнир, здесь можно будет записаться."))
	for t in _tourneys:
		_view.add_child(_tourney_card(t))

func _my_games() -> Array:
	var out := []
	for g in _games:
		if String(g.get("status", "")) == "play" and (String(g.get("wuid", "")) == Cloud.uid or String(g.get("buid", "")) == Cloud.uid):
			out.append(g)
	return out

func _tourney_card(t: Dictionary) -> Control:
	var tid := String(t.get("_id", ""))
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(_lbl(String(t.get("name", "Турнир")), 18))
	var kind := String(t.get("kind", ""))
	var tc := int(t.get("tc", 0))
	col.add_child(_lbl("%s · %s%s · участников: %d" % [_status_text(t), String(ClubTourney.KINDS.get(kind, "Записанный турнир")), (" · %d мин" % tc) if tc > 0 and kind != "recorded" else "", _entries_of(tid).size() if String(t.get("status", "")) == "reg" else int(t.get("nplayers", 0))], 12, Color(0.55, 0.6, 0.7)))
	var open := _btn("Открыть", 120)
	open.pressed.connect(func():
		_open_id = tid
		_show_detail(t))
	row.add_child(open)
	return panel

# ------------------------------------------------------------------ турнир

func _show_detail(t: Dictionary) -> void:
	_clear()
	_open_id = String(t.get("_id", ""))
	var tid := _open_id
	var kind := String(t.get("kind", ""))
	var st := String(t.get("status", ""))
	var back := _btn("← К списку турниров", 0, 44)
	back.pressed.connect(func():
		_open_id = ""
		_show_list())
	_view.add_child(back)
	_view.add_child(_lbl(String(t.get("name", "")), 22))
	_view.add_child(_lbl("%s · %s" % [_status_text(t), String(ClubTourney.KINDS.get(kind, "Записанный турнир"))], 13, Color(0.55, 0.6, 0.7)))
	var games := _games_of(tid)
	# запись
	if st == "reg":
		var me := _my_entry(tid)
		var b := _btn("✋ Записаться на турнир" if me.is_empty() else "Выписаться", 0, 50)
		b.pressed.connect(func():
			b.disabled = true
			var eid := tid + "_" + Cloud.uid
			var r: Dictionary
			if me.is_empty():
				r = await Cloud.set_doc("centries/" + eid, {"tid": tid, "uid": Cloud.uid, "name": Profile.shown_name(), "at": int(Time.get_unix_time_from_system())})
			else:
				r = await Cloud.del_doc("centries/" + eid)
			_status.text = "" if r.ok else String(r.error)
			_reload())
		_view.add_child(b)
		_view.add_child(_lbl("Записались:", 14, Color(0.96, 0.76, 0.3)))
		for e in _entries_of(tid):
			_view.add_child(_lbl("• " + String(e.get("name", "")), 14))
	# таблица
	var rows := ClubTourney.standings(games)
	if not rows.is_empty():
		_view.add_child(_lbl("Турнирная таблица", 15, Color(0.96, 0.76, 0.3)))
		var place := 0
		for r in rows:
			place += 1
			_view.add_child(_lbl("%d.  %s — %s  (партий %d: +%d =%d −%d)" % [place, r.name, ClubTourney.pts_text(r.pts), r.games, r.w, r.d, r.l], 15))
	# партии
	if not games.is_empty():
		_view.add_child(_lbl("Партии", 15, Color(0.96, 0.76, 0.3)))
		var sorted := games.duplicate()
		sorted.sort_custom(func(a, b): return int(a.get("round", 0)) < int(b.get("round", 0)))
		for g in sorted:
			_view.add_child(_game_row(g, false))
	if _is_teacher():
		_build_teacher_controls(t, games)

func _my_entry(tid: String) -> Dictionary:
	for e in _entries_of(tid):
		if String(e.get("uid", "")) == Cloud.uid:
			return e
	return {}

func _game_row(g: Dictionary, with_tourney: bool) -> Control:
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var done := String(g.get("status", "")) == "done"
	var res := String(g.get("result", ""))
	var txt := "%s — %s" % [String(g.get("wname", "")), String(g.get("bname", ""))]
	if int(g.get("round", 0)) > 0:
		txt = "Тур %d · %s" % [int(g.get("round", 0)), txt]
	if with_tourney:
		var tt := _find(String(g.get("tid", "")))
		txt = "%s · %s" % [String(tt.get("name", "")), txt]
	row.add_child(_lbl(txt + ("   " + res if done else ""), 15))
	row.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mine := String(g.get("wuid", "")) == Cloud.uid or String(g.get("buid", "")) == Cloud.uid
	if not done:
		var turn_mine := (String(g.get("turn", "w")) == "w" and String(g.get("wuid", "")) == Cloud.uid) or (String(g.get("turn", "w")) == "b" and String(g.get("buid", "")) == Cloud.uid)
		var b := _btn("▶ Играть — ваш ход" if turn_mine else ("▶ Открыть" if mine else "👁 Смотреть"), 190)
		var gid := String(g.get("_id", ""))
		b.pressed.connect(func():
			Global.online_game_id = gid
			Global.open("res://scenes/OnlineGame.tscn", "res://scenes/ClubTourneys.tscn"))
		row.add_child(b)
	elif String(g.get("pgn", "")) != "":
		var b2 := _btn("🔍 Разбор", 120)
		var pgn := String(g.get("pgn", ""))
		b2.pressed.connect(func():
			Global.pending_pgn = pgn
			Global.open("res://scenes/Notebook.tscn", "res://scenes/ClubTourneys.tscn"))
		row.add_child(b2)
	return panel

# ------------------------------------------------------------------ управление учителя

func _build_teacher_controls(t: Dictionary, games: Array) -> void:
	var tid := String(t.get("_id", ""))
	var kind := String(t.get("kind", ""))
	var st := String(t.get("status", ""))
	_view.add_child(_lbl("Управление турниром", 15, Color(0.96, 0.76, 0.3)))
	if st == "reg":
		var go := _btn("▶ Начать турнир (жеребьёвка)", 0, 50)
		go.pressed.connect(func(): _start(t))
		_view.add_child(go)
	elif st == "run" and kind == "swiss":
		var all_done := true
		for g in games:
			if int(g.get("round", 0)) == int(t.get("round", 0)) and String(g.get("status", "")) != "done":
				all_done = false
		var nxt := _btn("➡ Следующий тур" if int(t.get("round", 0)) < int(t.get("rounds", 0)) else "🏁 Завершить турнир", 0, 50)
		nxt.disabled = not all_done
		nxt.pressed.connect(func(): _next_round(t, games))
		_view.add_child(nxt)
		if not all_done:
			_view.add_child(_lbl("Следующий тур откроется, когда закончатся все партии текущего.", 12, Color(0.55, 0.6, 0.7)))
	if st != "done":
		var fin := _btn("🏁 Завершить турнир сейчас", 0, 44)
		fin.pressed.connect(func():
			t["status"] = "done"
			await _save_t(t)
			_reload())
		_view.add_child(fin)
	_view.add_child(_lbl("Добавить сыгранную партию вручную (запись офлайн-турнира)", 13, Color(0.55, 0.6, 0.7)))
	_view.add_child(_manual_form(tid, int(t.get("round", 0))))
	var del := _btn("🗑 Удалить турнир", 0, 44)
	del.pressed.connect(func():
		for g in games:
			await Cloud.del_doc("cgames/" + String(g.get("_id", "")))
		for e in _entries_of(tid):
			await Cloud.del_doc("centries/" + String(e.get("_id", "")))
		await Cloud.del_doc("ctourneys/" + tid)
		_open_id = ""
		_reload())
	_view.add_child(del)

func _save_t(t: Dictionary) -> Dictionary:
	var d := t.duplicate()
	var id := String(d.get("_id", ""))
	d.erase("_id")
	return await Cloud.set_doc("ctourneys/" + id, d)

func _manual_form(tid: String, round_no: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var names := HBoxContainer.new()
	names.add_theme_constant_override("separation", 6)
	box.add_child(names)
	var w := LineEdit.new()
	w.placeholder_text = "Белые (имя)"
	w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w.custom_minimum_size = Vector2(0, 42)
	names.add_child(w)
	var b := LineEdit.new()
	b.placeholder_text = "Чёрные (имя)"
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 42)
	names.add_child(b)
	var res := OptionButton.new()
	for r in ["1-0", "0-1", "1/2-1/2"]:
		res.add_item("Результат: " + r)
	res.custom_minimum_size = Vector2(0, 42)
	names.add_child(res)
	var pgn := TextEdit.new()
	pgn.placeholder_text = "Запись партии (PGN или ходы) — необязательно, нужна для разбора"
	pgn.custom_minimum_size = Vector2(0, 90)
	pgn.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(pgn)
	var add := _btn("+ Добавить партию в турнир", 0, 44)
	add.pressed.connect(func():
		var wn := Cloud.normalize_name(w.text)
		var bn := Cloud.normalize_name(b.text)
		if wn == "" or bn == "":
			_status.text = "Впишите имена обоих игроков."
			return
		var text := pgn.text.strip_edges()
		var record := ""
		if text != "":
			var p := GameRecord.parse_pgn(text)
			var rp := GameRecord.replay(p.sans)
			if not rp.ok:
				_status.text = "Ход № %d в записи не удалось разобрать." % (int(rp.bad) + 1)
				return
			record = GameRecord.build_pgn({"Event": "Турнир школы", "White": wn, "Black": bn, "Date": Time.get_date_string_from_system().replace("-", ".")}, rp.sans, p.comments, ["1-0", "0-1", "1/2-1/2"][res.selected])
		var gid := "m%d%03d" % [int(Time.get_unix_time_from_system()), randi() % 1000]
		var doc := _new_game_doc(tid, round_no, {"uid": "", "name": wn}, {"uid": "", "name": bn}, 0)
		doc["status"] = "done"
		doc["result"] = ["1-0", "0-1", "1/2-1/2"][res.selected]
		doc["reason"] = "записано учителем"
		doc["pgn"] = record
		var r: Dictionary = await Cloud.set_doc("cgames/" + gid, doc)
		_status.text = "✔ Партия добавлена." if r.ok else String(r.error)
		_reload())
	box.add_child(add)
	return box

func _new_game_doc(tid: String, round_no: int, w: Dictionary, b: Dictionary, tc: int) -> Dictionary:
	return {
		"tid": tid, "round": round_no, "wuid": w.uid, "wname": w.name, "buid": b.uid, "bname": b.name,
		"fen": GameRecord.START_FEN, "moves": [], "turn": "w", "status": "play", "result": "", "reason": "",
		"wtime": tc * 60000, "btime": tc * 60000, "last": 0, "tc": tc, "draw": "", "pgn": "",
		"at": int(Time.get_unix_time_from_system()),
	}

func _make_games(t: Dictionary, round_no: int, pairs: Array) -> void:
	var tid := String(t.get("_id", ""))
	var tc := int(t.get("tc", 0))
	var i := 0
	for p in pairs:
		i += 1
		var gid := "g%s_%d_%d" % [tid, round_no, i]
		var doc: Dictionary
		if p.b == null:
			doc = _new_game_doc(tid, round_no, p.w, {"uid": "", "name": "— пропуск тура"}, tc)
			doc["status"] = "done"
			doc["result"] = "1-0"
			doc["reason"] = "пропуск тура"
		else:
			doc = _new_game_doc(tid, round_no, p.w, p.b, tc)
		await Cloud.set_doc("cgames/" + gid, doc)

func _start(t: Dictionary) -> void:
	var tid := String(t.get("_id", ""))
	var players := []
	for e in _entries_of(tid):
		players.append({"uid": String(e.get("uid", "")), "name": String(e.get("name", ""))})
	if players.size() < 2:
		_status.text = "Для турнира нужно хотя бы два участника."
		return
	_status.text = "Провожу жеребьёвку…"
	if String(t.get("kind", "")) == "round_robin":
		var rounds := ClubTourney.round_robin(players)
		t["rounds"] = rounds.size()
		t["round"] = 1
		for r in range(rounds.size()):
			await _make_games(t, r + 1, rounds[r])
	else:
		t["round"] = 1
		await _make_games(t, 1, ClubTourney.swiss_round(players, {}, {}, {}, []))
	t["status"] = "run"
	t["nplayers"] = players.size()
	t["players"] = players
	var r: Dictionary = await _save_t(t)
	_status.text = "Турнир начался: партии разосланы участникам." if r.ok else String(r.error)
	_reload()

func _next_round(t: Dictionary, games: Array) -> void:
	if int(t.get("round", 0)) >= int(t.get("rounds", 0)):
		t["status"] = "done"
		await _save_t(t)
		_reload()
		return
	var sm := ClubTourney.summarize(games)
	var next_no: int = int(t.get("round", 0)) + 1
	_status.text = "Жеребьёвка тура %d…" % next_no
	await _make_games(t, next_no, ClubTourney.swiss_round(t.get("players", []), sm.scores, sm.played, sm.whites, sm.had_bye))
	t["round"] = next_no
	await _save_t(t)
	_reload()

# ------------------------------------------------------------------ новый турнир

func _show_builder() -> void:
	_clear()
	var back := _btn("← К списку турниров", 0, 44)
	back.pressed.connect(_show_list)
	_view.add_child(back)
	_view.add_child(_lbl("НОВЫЙ ТУРНИР", 20, Color(0.96, 0.76, 0.3)))
	var name := LineEdit.new()
	name.placeholder_text = "Название (например: «Кубок школы, осень»)"
	name.max_length = 60
	name.custom_minimum_size = Vector2(0, 44)
	_view.add_child(name)
	var kind := OptionButton.new()
	var keys := ["round_robin", "swiss", "recorded"]
	kind.add_item("Круговой: каждый с каждым (онлайн)")
	kind.add_item("Швейцарская система (онлайн)")
	kind.add_item("Записать прошедший турнир (вручную)")
	kind.custom_minimum_size = Vector2(0, 44)
	_view.add_child(kind)
	var rrow := HBoxContainer.new()
	var rl := Label.new()
	rl.text = "Туров (для швейцарской):  "
	rrow.add_child(rl)
	var rounds := SpinBox.new()
	rounds.min_value = 1
	rounds.max_value = 12
	rounds.value = 5
	rrow.add_child(rounds)
	var tl := Label.new()
	tl.text = "     Минут на партию каждому:  "
	rrow.add_child(tl)
	var tc := SpinBox.new()
	tc.min_value = 0
	tc.max_value = 90
	tc.value = 10
	rrow.add_child(tc)
	_view.add_child(rrow)
	_view.add_child(_lbl("0 минут — без часов.", 12, Color(0.55, 0.6, 0.7)))
	var create := _btn("Создать турнир", 0, 54)
	create.pressed.connect(func():
		if name.text.strip_edges() == "":
			_status.text = "Впишите название турнира."
			return
		var k: String = keys[kind.selected]
		var id := "t%d%03d" % [int(Time.get_unix_time_from_system()), randi() % 1000]
		var doc := {
			"name": name.text.strip_edges(), "kind": k, "rounds": int(rounds.value) if k == "swiss" else 0,
			"tc": int(tc.value) if k != "recorded" else 0, "status": "reg" if k != "recorded" else "run",
			"round": 0, "nplayers": 0, "by": Cloud.uid, "by_name": Profile.shown_name(),
			"created": int(Time.get_unix_time_from_system()),
		}
		var r: Dictionary = await Cloud.set_doc("ctourneys/" + id, doc)
		if r.ok:
			_open_id = id
		_status.text = "✔ Турнир создан." if r.ok else String(r.error)
		_reload())
	_view.add_child(create)
