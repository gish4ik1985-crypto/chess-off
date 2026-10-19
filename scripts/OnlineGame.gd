extends Control

# Онлайн-партия между учениками (турнир школы): ходы идут через облако, каждые 2 секунды экран
# проверяет, не сходил ли соперник. Часы, сдача, ничья по согласию, запись партии для разбора.
# Документ партии: cgames/{id}. Ходит только тот, чей ход; записывает ход тоже только он.

const POLL := 2.0

var gid := ""
var _doc: Dictionary = {}
var _board: BoardView
var _status: Label
var _top_name: Label
var _top_clock: Label
var _bot_name: Label
var _bot_clock: Label
var _resign_btn: Button
var _draw_btn: Button
var _after_box: VBoxContainer
var _timer := 0.0
var _busy := false
var _my_color := "" # "w", "b" или "" (зритель)
var _synced_moves := -1
var _claim_at := 0

func _ready() -> void:
	gid = Global.online_game_id
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.05)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Global.add_floating_back(self, func(): Global.go_back())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 72.0
	add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	center.add_child(row)
	_board = BoardView.new()
	_board.custom_minimum_size = Vector2(560, 560)
	_board.move_made.connect(_on_move)
	row.add_child(_board)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(330, 0)
	col.add_theme_constant_override("separation", 10)
	row.add_child(col)
	_top_name = _label(col, 20)
	_top_clock = _label(col, 34)
	_status = _label(col, 15)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 70)
	_bot_clock = _label(col, 34)
	_bot_name = _label(col, 20)
	_resign_btn = _btn(col, "🏳 Сдаться", _on_resign)
	_draw_btn = _btn(col, "🤝 Предложить ничью", _on_draw)
	_after_box = VBoxContainer.new()
	_after_box.add_theme_constant_override("separation", 8)
	col.add_child(_after_box)
	var title := Label.new()
	title.text = "ОНЛАЙН-ПАРТИЯ"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.96, 0.76, 0.3))
	title.position = Vector2(24, 16)
	add_child(title)
	if not (Cloud.enabled and Cloud.signed_in) or gid == "":
		_status.text = "Нужен онлайн-вход и выбранная партия."
		return
	_status.text = "Загружаю партию…"
	await _sync()

func _label(parent: Control, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l

func _btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 48)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _process(delta: float) -> void:
	if _doc.is_empty():
		return
	_update_clocks()
	_timer += delta
	if _timer >= POLL and not _busy:
		_timer = 0.0
		_sync()

# ---- часы ----

func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)

func _left_ms(color: String) -> int:
	var t: int = int(_doc.get("wtime" if color == "w" else "btime", 0))
	if String(_doc.get("status", "")) == "play" and int(_doc.get("last", 0)) > 0 and String(_doc.get("turn", "w")) == color:
		t -= _now_ms() - int(_doc.last)
	return maxi(0, t)

func _fmt(ms: int) -> String:
	var s := ms / 1000
	return "%d:%02d" % [s / 60, s % 60]

func _update_clocks() -> void:
	if int(_doc.get("tc", 0)) <= 0:
		_top_clock.text = ""
		_bot_clock.text = ""
		return
	var opp := "b" if _board.perspective == "w" else "w"
	_top_clock.text = _fmt(_left_ms(opp))
	_bot_clock.text = _fmt(_left_ms(_board.perspective))
	# время вышло — победу засчитывает любой из подключённых
	if String(_doc.get("status", "")) == "play" and int(_doc.get("last", 0)) > 0 and not _busy:
		var turn := String(_doc.get("turn", "w"))
		if _left_ms(turn) <= 0 and (_my_color != "" or Roles.can(Profile.role, "open_admin")) and _now_ms() - _claim_at > 5000:
			_claim_at = _now_ms()
			_finish("0-1" if turn == "w" else "1-0", "время вышло")

# ---- синхронизация ----

func _sync() -> void:
	_busy = true
	var r: Dictionary = await Cloud.get_doc("cgames/" + gid)
	_busy = false
	if not is_inside_tree():
		return
	if not r.ok or not r.found:
		_status.text = String(r.error) if not r.ok else "Партия не найдена."
		return
	_doc = r.data
	_my_color = "w" if String(_doc.get("wuid", "")) == Cloud.uid else ("b" if String(_doc.get("buid", "")) == Cloud.uid else "")
	var moves: Array = _doc.get("moves", [])
	if moves.size() != _synced_moves:
		_apply_moves(moves)
	_refresh_ui()

func _apply_moves(moves: Array) -> void:
	_board.perspective = _my_color if _my_color != "" else "w"
	var eng := ChessEngine.new()
	eng.setup_start_position()
	for u in moves:
		var m := BoardView.find_move(eng, String(u))
		if m.is_empty():
			break
		eng.apply_move(m)
	_board.engine = eng
	_board.clear_selection()
	_synced_moves = moves.size()
	_board.queue_redraw()

func _refresh_ui() -> void:
	var opp := "b" if _board.perspective == "w" else "w"
	_top_name.text = "%s %s" % ["⚫" if opp == "b" else "⚪", String(_doc.get("bname" if opp == "b" else "wname", ""))]
	_bot_name.text = "%s %s" % ["⚫" if _board.perspective == "b" else "⚪", String(_doc.get("bname" if _board.perspective == "b" else "wname", ""))]
	var done := String(_doc.get("status", "")) == "done"
	var turn := String(_doc.get("turn", "w"))
	_board.turn_color = _my_color
	_board.interactive = (not done) and _my_color != "" and turn == _my_color
	_resign_btn.visible = (not done) and _my_color != ""
	_draw_btn.visible = (not done) and _my_color != ""
	var offer := String(_doc.get("draw", ""))
	if offer != "" and offer != _my_color:
		_draw_btn.text = "🤝 Принять ничью"
	elif offer == _my_color:
		_draw_btn.text = "Ничья предложена…"
	else:
		_draw_btn.text = "🤝 Предложить ничью"
	if done:
		_status.text = "Партия окончена: %s (%s)." % [String(_doc.get("result", "")), String(_doc.get("reason", ""))]
		_show_after()
	elif _my_color == "":
		_status.text = "Вы наблюдаете за партией."
	elif turn == _my_color:
		_status.text = "Ваш ход."
	else:
		_status.text = "Ход соперника…"
	if String(_doc.get("draw", "")) != "" and not done and offer != _my_color and _my_color != "":
		_status.text += "  Соперник предлагает ничью."

func _show_after() -> void:
	if _after_box.get_child_count() > 0:
		return
	var b := Button.new()
	b.text = "🔍 Разобрать партию"
	b.custom_minimum_size = Vector2(0, 48)
	b.pressed.connect(func():
		Global.pending_pgn = _pgn()
		Global.open("res://scenes/Notebook.tscn", "res://scenes/OnlineGame.tscn"))
	_after_box.add_child(b)

func _pgn() -> String:
	var eng := ChessEngine.new()
	eng.setup_start_position()
	var sans: Array = []
	for u in _doc.get("moves", []):
		var m := BoardView.find_move(eng, String(u))
		if m.is_empty():
			break
		sans.append(GameRecord.san(eng, m))
		eng.apply_move(m)
	return GameRecord.build_pgn({"Event": "Турнир школы", "White": String(_doc.get("wname", "")), "Black": String(_doc.get("bname", "")),
		"Date": Time.get_date_string_from_system().replace("-", ".")}, sans, [], String(_doc.get("result", "*")))

# ---- ходы и результат ----

func _on_move(_m: Dictionary, uci: String) -> void:
	if _busy or _my_color == "" or String(_doc.get("status", "")) != "play":
		_board.set_fen(_board.engine.to_fen())
		return
	_busy = true
	var moves: Array = (_doc.get("moves", []) as Array).duplicate()
	moves.append(uci)
	var now := _now_ms()
	var d := _doc.duplicate()
	if int(d.get("last", 0)) > 0 and int(d.get("tc", 0)) > 0:
		var key := "wtime" if _my_color == "w" else "btime"
		d[key] = maxi(0, int(d[key]) - (now - int(d.last)))
	d["moves"] = moves
	d["fen"] = _board.engine.to_fen()
	d["turn"] = _board.engine.side_to_move
	d["last"] = now
	d["draw"] = ""
	var status := _board.engine.game_status()
	if status != "playing":
		d["status"] = "done"
		d["last"] = 0
		if status == "checkmate":
			d["result"] = "1-0" if _my_color == "w" else "0-1"
			d["reason"] = "мат"
		else:
			d["result"] = "1/2-1/2"
			d["reason"] = {"stalemate": "пат", "draw50": "правило 50 ходов", "insufficient": "нет материала", "repetition": "троекратное повторение"}.get(status, "ничья")
		d["pgn"] = _pgn_for(d)
	d["at"] = int(Time.get_unix_time_from_system())
	var r: Dictionary = await Cloud.set_doc("cgames/" + gid, d)
	_busy = false
	if not r.ok:
		_status.text = "Ход не отправился: %s" % String(r.error)
		_synced_moves = -1 # вернём позицию из облака при ближайшей проверке
		return
	_doc = d
	_synced_moves = moves.size()
	_refresh_ui()

func _pgn_for(d: Dictionary) -> String:
	var keep := _doc
	_doc = d
	var p := _pgn()
	_doc = keep
	return p

func _finish(result: String, reason: String) -> void:
	if _busy:
		return
	_busy = true
	var r0: Dictionary = await Cloud.get_doc("cgames/" + gid)
	if not r0.ok or not r0.found or String(r0.data.get("status", "")) == "done":
		_busy = false
		return
	var d: Dictionary = r0.data
	d["status"] = "done"
	d["result"] = result
	d["reason"] = reason
	d["last"] = 0
	d["draw"] = ""
	d["pgn"] = _pgn_for(d)
	d["at"] = int(Time.get_unix_time_from_system())
	var r: Dictionary = await Cloud.set_doc("cgames/" + gid, d)
	_busy = false
	if r.ok and is_inside_tree():
		_doc = d
		_refresh_ui()

func _on_resign() -> void:
	if _my_color == "":
		return
	_finish("0-1" if _my_color == "w" else "1-0", "сдача")

func _on_draw() -> void:
	if _my_color == "" or _busy:
		return
	var offer := String(_doc.get("draw", ""))
	if offer != "" and offer != _my_color:
		_finish("1/2-1/2", "ничья по согласию")
		return
	if offer == _my_color:
		return
	_busy = true
	var d := _doc.duplicate()
	d["draw"] = _my_color
	var r: Dictionary = await Cloud.set_doc("cgames/" + gid, d)
	_busy = false
	if r.ok:
		_doc = d
		_refresh_ui()
