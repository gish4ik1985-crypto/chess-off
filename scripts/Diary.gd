extends Control

# «Дневник игрока» — профиль и дневник, объединённые в одно окно.
# Три вкладки:
#   «Обзор»  — инфографика: карточки статов, сильные/слабые стороны,
#              качество ходов, график рейтинга, совет;
#   «Ходы»   — галерея лучших и худших ходов: доска, стрелки сыгранного
#              и лучшего хода, объяснение потери и совет (анализ в фоне);
#   «Партии» — переигрывание партий: оценка позиции после каждого хода
#              (шкала перевеса у доски), пояснение потерь и лучший ход.
# Заменяет старые экраны Journal.tscn и Progress.tscn.

@onready var tab_overview: Button = $TopBar/HBox/TabOverview
@onready var tab_moves: Button = $TopBar/HBox/TabMoves
@onready var tab_games: Button = $TopBar/HBox/TabGames

var page_overview: Control
var page_moves: Control
var page_games: Control
var overview_draw: Node2D

# движки-аналитики (level 9 — сильный «тренерский» поиск, без зевков)
var coach_moves := ChessAI.new(9)
var coach_replay := ChessAI.new(9)

# --- вкладка «Ходы» ---
var moves_list_vbox: VBoxContainer
var moves_board_draw: Node2D
var moves_caption: Label
var moves_engine: ChessEngine = null
var moves_from := Vector2i(-1, -1)
var moves_to := Vector2i(-1, -1)
var moves_best_from := Vector2i(-1, -1)
var moves_best_to := Vector2i(-1, -1)
var moves_flip := false
var _moves_thread: Thread = null
var _moves_request := 0 # id последнего клика: устаревшие результаты анализа отбрасываются

# --- вкладка «Партии» ---
var games_list_vbox: VBoxContainer
var games_button_group: ButtonGroup
var replay_board_draw: Node2D
var replay_comment: Label
var replay_counter: Label
var replay_auto: CheckButton
var replay_states: Array = [] # ChessEngine snapshots, states[0] = start
var replay_base_comments: Array = [] # событийный комментарий хода, ведущего В states[i]
var replay_moves: Array = [] # parsed move dicts (for last-move highlight)
var replay_evals: Array = [] # статическая оценка каждой позиции (сп, + = белые)
var replay_mover: Array = [] # кто сделал ход, ведущий в states[i]: "w"/"b"/""
var replay_loss: Dictionary = {} # ply -> потеря в сп (только ходы игрока)
var replay_better: Dictionary = {} # ply -> текст «сильнее было ...»
var replay_cur := 0
var replay_flip := false
var replay_entry: Dictionary = {}
var _replay_thread: Thread = null
var _replay_request := 0
var _auto_accum := 0.0
const AUTO_STEP := 1.4

# Threads swapped out by a fresh click before they finished — their results
# are already ignored via the request-id check, we just still owe them a
# wait_to_finish() (Godot requires every Thread to be joined) without
# blocking the UI for it. Drained opportunistically in _process() and
# forced closed in _exit_tree().
var _stale_threads: Array[Thread] = []

func _retire_thread(t: Thread) -> void:
	if t == null or not t.is_started():
		return
	if t.is_alive():
		_stale_threads.append(t)
	else:
		t.wait_to_finish()

const SQ := 54.0
const LIGHT_COL := Color(0.32, 0.38, 0.5)
const DARK_COL := Color(0.14, 0.17, 0.26)
const GOOD_COL := Color(0.4, 0.95, 0.5)
const BAD_COL := Color(1.0, 0.45, 0.45)
const PIECE_RU := {"P": "пешку", "N": "коня", "B": "слона", "R": "ладью", "Q": "ферзя", "K": "короля"}
const SCALE_HINT := "Перевес считается в пешках: 1.0 — лишняя пешка · 3.0 — конь или слон · 5.0 — ладья · 9.0 — ферзь. Плюс — впереди вы, минус — соперник."

func _ready() -> void:
	tab_overview.pressed.connect(func(): _show_tab(0))
	tab_moves.pressed.connect(func(): _show_tab(1))
	tab_games.pressed.connect(func(): _show_tab(2))
	_build_overview_page()
	_build_moves_page()
	_build_games_page()
	_show_tab(0)

func _exit_tree() -> void:
	_moves_request += 1
	_replay_request += 1
	if _moves_thread != null and _moves_thread.is_started():
		_moves_thread.wait_to_finish()
	if _replay_thread != null and _replay_thread.is_started():
		_replay_thread.wait_to_finish()
	for t in _stale_threads:
		if t.is_started():
			t.wait_to_finish()
	_stale_threads = []

func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")

func _show_tab(i: int) -> void:
	page_overview.visible = i == 0
	page_moves.visible = i == 1
	page_games.visible = i == 2
	tab_overview.disabled = i == 0
	tab_moves.disabled = i == 1
	tab_games.disabled = i == 2

func _make_page() -> Control:
	var p = Control.new()
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.offset_top = 96.0
	add_child(p)
	return p

# ============================ ОБЗОР ============================

func _build_overview_page() -> void:
	page_overview = _make_page()
	overview_draw = Node2D.new()
	page_overview.add_child(overview_draw)
	overview_draw.draw.connect(_on_overview_draw)
	page_overview.visibility_changed.connect(func():
		if page_overview.visible:
			overview_draw.queue_redraw())

func _accuracy() -> float:
	var total = Profile.move_good + Profile.move_inaccuracy + Profile.move_mistake + Profile.move_blunder
	if total == 0:
		return 0.0
	return 100.0 * float(Profile.move_good) / float(total)

func _phase_stats() -> Dictionary:
	# average errors per game over the last 15 logged games
	var window = Profile.game_log.slice(max(Profile.game_log.size() - 15, 0))
	var out = {"Дебют": 0.0, "Миттельшпиль": 0.0, "Эндшпиль": 0.0, "games": window.size()}
	for g in window:
		out["Дебют"] += float(g.get("err_opening", 0))
		out["Миттельшпиль"] += float(g.get("err_middlegame", 0))
		out["Эндшпиль"] += float(g.get("err_endgame", 0))
	if window.size() > 0:
		for k in ["Дебют", "Миттельшпиль", "Эндшпиль"]:
			out[k] /= float(window.size())
	return out

func _panel(rect: Rect2, title: String, font: Font) -> void:
	overview_draw.draw_rect(rect, Color(0.05, 0.05, 0.09, 0.92), true)
	overview_draw.draw_rect(rect, Color(0.11, 0.85, 0.95, 0.4), false, 2.0)
	overview_draw.draw_string(font, rect.position + Vector2(18, 28), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36, 14, Color(1, 0.65, 0.95, 0.9))

func _stat_card(rect: Rect2, title: String, value: String, sub: String, val_col: Color, font: Font) -> void:
	overview_draw.draw_rect(rect, Color(0.05, 0.05, 0.09, 0.92), true)
	overview_draw.draw_rect(rect, Color(0.11, 0.85, 0.95, 0.4), false, 2.0)
	overview_draw.draw_string(font, rect.position + Vector2(16, 24), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 32, 12, Color(0.55, 0.6, 0.7))
	overview_draw.draw_string(font, rect.position + Vector2(16, 56), value, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 32, 24, val_col)
	overview_draw.draw_string(font, rect.position + Vector2(16, 78), sub, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 32, 11, Color(0.55, 0.6, 0.7))

func _on_overview_draw() -> void:
	var font = ThemeDB.fallback_font
	var w = get_viewport_rect().size.x
	var left = maxf((w - 1200.0) / 2.0, 24.0)

	# --- карточки статов ---
	var card_w = (1200.0 - 3 * 16.0) / 4.0
	var delta = Profile.last_rating_change
	var delta_txt = "%+d за последнюю партию" % int(delta) if delta != 0.0 else "сыграйте партию!"
	_stat_card(Rect2(left, 8, card_w, 92), "РЕЙТИНГ", str(int(Profile.rating)),
		delta_txt, Color(0.1, 0.95, 1), font)
	_stat_card(Rect2(left + card_w + 16, 8, card_w, 92), "ПАРТИИ",
		str(Profile.games_played), "побед %d · ничьих %d · поражений %d" % [Profile.wins, Profile.draws, Profile.losses],
		Color(0.9, 0.95, 1), font)
	var acc = _accuracy()
	var acc_col = GOOD_COL if acc >= 70.0 else (Color(0.95, 0.8, 0.35) if acc >= 50.0 else BAD_COL)
	_stat_card(Rect2(left + 2 * (card_w + 16), 8, card_w, 92), "ТОЧНОСТЬ ХОДОВ",
		"%.0f%%" % acc, "доля сильных ходов", acc_col, font)
	_stat_card(Rect2(left + 3 * (card_w + 16), 8, card_w, 92), "СЕРИЯ ПОБЕД",
		str(Profile.win_streak), "рекорд: %d" % Profile.best_win_streak, Color(0.95, 0.8, 0.35), font)

	# --- сильные и слабые стороны ---
	var pr = Rect2(left, 116, 590, 240)
	_panel(pr, "СИЛЬНОЕ И СЛАБОЕ МЕСТО (последние партии)", font)
	var ph = _phase_stats()
	if ph.games == 0:
		overview_draw.draw_string(font, pr.position + Vector2(18, 70), "Сыграйте несколько партий — здесь появится разбор по фазам.", HORIZONTAL_ALIGNMENT_LEFT, pr.size.x - 36, 13, Color(0.55, 0.6, 0.7))
	else:
		var keys = ["Дебют", "Миттельшпиль", "Эндшпиль"]
		var best_k = keys[0]
		var worst_k = keys[0]
		for k in keys:
			if ph[k] < ph[best_k]: best_k = k
			if ph[k] > ph[worst_k]: worst_k = k
		overview_draw.draw_string(font, pr.position + Vector2(18, 56), "✔ Сила: %s — меньше всего ошибок" % best_k.to_lower(), HORIZONTAL_ALIGNMENT_LEFT, pr.size.x - 36, 14, GOOD_COL)
		overview_draw.draw_string(font, pr.position + Vector2(18, 80), "✘ Слабость: %s — тренируйте в «Дороге домой»" % worst_k.to_lower(), HORIZONTAL_ALIGNMENT_LEFT, pr.size.x - 36, 14, BAD_COL)
		var max_v = 0.01
		for k in keys:
			max_v = maxf(max_v, ph[k])
		var by = pr.position.y + 108
		for k in keys:
			overview_draw.draw_string(font, Vector2(pr.position.x + 18, by + 14), k, HORIZONTAL_ALIGNMENT_LEFT, 150, 13, Color(0.82, 0.88, 0.95))
			var bx = pr.position.x + 180
			var bw = pr.size.x - 200
			var frac = ph[k] / max_v
			var col = BAD_COL if k == worst_k else (GOOD_COL if k == best_k else Color(0.35, 0.75, 0.95))
			overview_draw.draw_rect(Rect2(bx, by, bw, 18), Color(1, 1, 1, 0.08), true)
			overview_draw.draw_rect(Rect2(bx, by, bw * frac, 18), col, true)
			overview_draw.draw_string(font, Vector2(bx + bw * frac + 8, by + 14), "%.1f ош./партию" % ph[k], HORIZONTAL_ALIGNMENT_LEFT, 130, 11, Color(0.55, 0.6, 0.7))
			by += 38

	# --- качество ходов ---
	var qr = Rect2(left + 610, 116, 590, 240)
	_panel(qr, "КАЧЕСТВО ХОДОВ (за всё время)", font)
	var rows = [
		["Сильные", Profile.move_good, GOOD_COL],
		["Неточности", Profile.move_inaccuracy, Color(0.95, 0.8, 0.35)],
		["Ошибки", Profile.move_mistake, Color(0.95, 0.6, 0.3)],
		["Зевки", Profile.move_blunder, BAD_COL],
	]
	var q_total = maxi(Profile.move_good + Profile.move_inaccuracy + Profile.move_mistake + Profile.move_blunder, 1)
	var qy = qr.position.y + 52
	for row in rows:
		overview_draw.draw_string(font, Vector2(qr.position.x + 18, qy + 14), row[0], HORIZONTAL_ALIGNMENT_LEFT, 120, 13, Color(0.82, 0.88, 0.95))
		var bx = qr.position.x + 150
		var bw = qr.size.x - 270
		var frac = float(row[1]) / float(q_total)
		overview_draw.draw_rect(Rect2(bx, qy, bw, 18), Color(1, 1, 1, 0.08), true)
		overview_draw.draw_rect(Rect2(bx, qy, bw * frac, 18), row[2], true)
		overview_draw.draw_string(font, Vector2(bx + bw + 10, qy + 14), "%d (%.0f%%)" % [row[1], 100.0 * frac], HORIZONTAL_ALIGNMENT_LEFT, 100, 12, row[2])
		qy += 40
	overview_draw.draw_string(font, Vector2(qr.position.x + 18, qy + 16), "Зевков меньше — рейтинг выше. Худшие ходы ждут на вкладке «Ходы».", HORIZONTAL_ALIGNMENT_LEFT, qr.size.x - 36, 11, Color(0.55, 0.6, 0.7))

	# --- график рейтинга ---
	var gr = Rect2(left, 372, 1200, 230)
	_panel(gr, "РЕЙТИНГ ПО ДНЯМ", font)
	_draw_rating_chart(gr, font)

	# --- совет ---
	var advice = Profile.journal_advice()
	if advice.size() > 0:
		overview_draw.draw_string(font, Vector2(left, 632), "💡 Совет: %s" % advice[0], HORIZONTAL_ALIGNMENT_LEFT, 1200, 14, Color(0.95, 0.8, 0.35))

func _draw_rating_chart(gr: Rect2, font: Font) -> void:
	var days = Profile.daily_history.keys()
	days.sort()
	if days.size() > 30:
		days = days.slice(days.size() - 30)
	if days.size() < 2:
		overview_draw.draw_string(font, gr.position + Vector2(18, 70), "Играйте несколько дней подряд — тут вырастет график вашего рейтинга.", HORIZONTAL_ALIGNMENT_LEFT, gr.size.x - 36, 13, Color(0.55, 0.6, 0.7))
		return
	var vals := []
	for d in days:
		vals.append(float(Profile.daily_history[d].get("rating", Profile.rating)))
	var vmin = vals.min() - 30.0
	var vmax = vals.max() + 30.0
	var plot = Rect2(gr.position + Vector2(70, 44), gr.size - Vector2(100, 80))
	overview_draw.draw_rect(plot, Color(1, 1, 1, 0.04), true)
	for t in [0.0, 0.5, 1.0]:
		var yy = plot.position.y + plot.size.y * (1.0 - t)
		overview_draw.draw_line(Vector2(plot.position.x, yy), Vector2(plot.end.x, yy), Color(1, 1, 1, 0.1), 1.0)
		overview_draw.draw_string(font, Vector2(gr.position.x + 14, yy + 5), str(int(vmin + (vmax - vmin) * t)), HORIZONTAL_ALIGNMENT_LEFT, 52, 11, Color(0.55, 0.6, 0.7))
	var pts := PackedVector2Array()
	for i in range(vals.size()):
		var x = plot.position.x + plot.size.x * float(i) / float(vals.size() - 1)
		var y = plot.position.y + plot.size.y * (1.0 - (vals[i] - vmin) / (vmax - vmin))
		pts.append(Vector2(x, y))
	overview_draw.draw_polyline(pts, Color(0.1, 0.95, 1), 3.0, true)
	for p in pts:
		overview_draw.draw_circle(p, 4.0, Color(0.1, 0.95, 1))
	overview_draw.draw_string(font, Vector2(plot.position.x, plot.end.y + 22), days[0], HORIZONTAL_ALIGNMENT_LEFT, 120, 11, Color(0.55, 0.6, 0.7))
	overview_draw.draw_string(font, Vector2(plot.end.x - 90, plot.end.y + 22), days[-1], HORIZONTAL_ALIGNMENT_LEFT, 120, 11, Color(0.55, 0.6, 0.7))

# ============================ ХОДЫ ============================

func _build_moves_page() -> void:
	page_moves = _make_page()
	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	scroll.offset_left = 24
	scroll.offset_right = 444
	scroll.offset_top = 8
	scroll.offset_bottom = -16
	scroll.anchor_bottom = 1.0
	page_moves.add_child(scroll)
	moves_list_vbox = VBoxContainer.new()
	moves_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	moves_list_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(moves_list_vbox)

	moves_board_draw = Node2D.new()
	moves_board_draw.position = Vector2(500, 24)
	page_moves.add_child(moves_board_draw)
	moves_board_draw.draw.connect(func(): _draw_board(moves_board_draw, moves_engine, moves_from, moves_to, moves_flip, moves_best_from, moves_best_to))

	moves_caption = Label.new()
	moves_caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	moves_caption.offset_left = 500
	moves_caption.offset_right = -24
	moves_caption.offset_top = -210
	moves_caption.offset_bottom = -12
	moves_caption.autowrap_mode = TextServer.AUTOWRAP_WORD
	moves_caption.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	moves_caption.add_theme_font_size_override("font_size", 14)
	page_moves.add_child(moves_caption)
	moves_caption.text = "Выберите ход слева. Красная стрелка — как было сыграно, зелёная — как советует тренер."

	_fill_moves_list()

func _fill_moves_list() -> void:
	var sec_bad = Label.new()
	sec_bad.text = "ХУДШИЕ ХОДЫ (зевки)"
	sec_bad.add_theme_color_override("font_color", BAD_COL)
	sec_bad.add_theme_font_size_override("font_size", 13)
	moves_list_vbox.add_child(sec_bad)
	if Profile.recent_blunders.is_empty():
		_moves_list_note("Пока пусто — и это отлично! Зевки из партий появятся здесь.")
	for e in Profile.recent_blunders:
		_moves_list_button(e, false)
	var sec_good = Label.new()
	sec_good.text = "ЛУЧШИЕ ХОДЫ"
	sec_good.add_theme_color_override("font_color", GOOD_COL)
	sec_good.add_theme_font_size_override("font_size", 13)
	moves_list_vbox.add_child(sec_good)
	if Profile.recent_best.is_empty():
		_moves_list_note("Сыграйте красивый точный ход (взятие, превращение) — он попадёт сюда.")
	for e in Profile.recent_best:
		_moves_list_button(e, true)

func _moves_list_note(txt: String) -> void:
	var l = Label.new()
	l.text = txt
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	moves_list_vbox.add_child(l)

func _moves_list_button(e: Dictionary, is_best: bool) -> void:
	var b = Button.new()
	b.custom_minimum_size = Vector2(0, 40)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if is_best:
		b.text = "★ %s — идеальный ход" % e.move
	else:
		b.text = "✘ %s — потеряно ≈%d очков" % [e.move, int(e.loss)]
	b.pressed.connect(func(): _show_move_entry(e, is_best))
	moves_list_vbox.add_child(b)

func _show_move_entry(e: Dictionary, is_best: bool) -> void:
	moves_engine = ChessEngine.new()
	moves_engine.setup_from_fen(e.fen)
	moves_flip = str(e.fen).contains(" b ")
	var sq = _squares_from_notation(str(e.move))
	moves_from = sq[0]
	moves_to = sq[1]
	moves_best_from = Vector2i(-1, -1)
	moves_best_to = Vector2i(-1, -1)
	moves_board_draw.queue_redraw()
	moves_caption.remove_theme_color_override("font_color")
	moves_caption.text = "⏳ Тренер анализирует позицию..."
	# фоновый анализ: лучший ход + объяснение
	_moves_request += 1
	var req = _moves_request
	_retire_thread(_moves_thread)
	if Global.can_thread:
		_moves_thread = Thread.new()
		_moves_thread.start(_analyze_move_entry.bind(e.duplicate(), is_best, req))
	else:
		_analyze_move_entry.bind(e.duplicate(), is_best, req).call_deferred()

# Выполняется в фоне: считает лучший ход, ответ соперника и собирает объяснение.
func _analyze_move_entry(e: Dictionary, is_best: bool, req: int) -> void:
	var eng = ChessEngine.new()
	eng.setup_from_fen(str(e.fen))
	var played = _parse_move(eng, str(e.move))
	var best = coach_moves.best_move_clean(eng, 3)
	var out := {"req": req, "is_best": is_best, "loss": float(e.get("loss", 0.0)), "move": str(e.move)}
	out["best_from"] = Vector2i(-1, -1)
	out["best_to"] = Vector2i(-1, -1)
	# почему сыгранный ход теряет очки: показываем лучший ответ соперника
	if not played.is_empty() and not is_best:
		var after = eng.clone()
		after.apply_move(played)
		var reply = coach_moves.best_move_clean(after, 2)
		if reply != null:
			var victim = after.board[reply.to.y][reply.to.x]
			var reply_txt = _notation(after, reply)
			if victim != null:
				out["punish"] = "Соперник ответит %s и заберёт %s — вот откуда потеря." % [reply_txt, PIECE_RU.get(victim.type, "фигуру")]
			else:
				var after2 = after.clone()
				after2.apply_move(reply)
				if after2.game_status() == "checkmate":
					out["punish"] = "После этого хода соперник ставит мат ходом %s!" % reply_txt
				elif after2.is_in_check(after2.side_to_move):
					out["punish"] = "Соперник ответит %s с шахом и перехватит инициативу." % reply_txt
				else:
					out["punish"] = "Лучший ответ соперника — %s: позиция постепенно портится (фигуры теряют хорошие поля)." % reply_txt
	# лучший ход и почему он хорош
	if best != null:
		out["best_from"] = best.from
		out["best_to"] = best.to
		out["best_txt"] = _notation(eng, best)
		var after_b = eng.clone()
		var victim_b = eng.board[best.to.y][best.to.x]
		after_b.apply_move(best)
		var st = after_b.game_status()
		if st == "checkmate":
			out["best_why"] = "ставит мат!"
		elif victim_b != null:
			out["best_why"] = "забирает %s" % PIECE_RU.get(victim_b.type, "фигуру")
		elif after_b.is_in_check(after_b.side_to_move):
			out["best_why"] = "даёт шах и захватывает инициативу"
		elif best.get("is_castle", "") != "":
			out["best_why"] = "рокировка — король уходит в безопасность"
		else:
			out["best_why"] = "самый крепкий ход: ничего не отдаёт и улучшает позицию"
	call_deferred("_apply_move_analysis", out)

func _apply_move_analysis(out: Dictionary) -> void:
	if out.get("req", -1) != _moves_request:
		return # пользователь уже кликнул на другой ход
	moves_best_from = out.get("best_from", Vector2i(-1, -1))
	moves_best_to = out.get("best_to", Vector2i(-1, -1))
	var lines := []
	if out.is_best:
		lines.append("★ Отличный ход %s! Тренер сыграл бы так же — запомните этот приём." % out.move)
		moves_caption.add_theme_color_override("font_color", GOOD_COL)
	else:
		var loss = int(out.loss)
		var loss_txt = "%.1f пешки" % (loss / 100.0) if loss < 1500 else "решающее преимущество"
		lines.append("✘ Сыграно %s (красная стрелка) — потеряно %s." % [out.move, loss_txt])
		if out.has("punish"):
			lines.append("Почему: %s" % out.punish)
		if out.has("best_txt"):
			lines.append("✔ Сильнее было %s (зелёная стрелка) — %s." % [out.best_txt, out.best_why])
		lines.append(SCALE_HINT)
		moves_caption.remove_theme_color_override("font_color")
	if out.is_best and out.has("best_txt") and moves_best_from != moves_from:
		lines.append("Тренер бы предпочёл %s — %s. Оба хода хороши!" % [out.best_txt, out.best_why])
	moves_caption.text = "\n".join(lines)
	moves_board_draw.queue_redraw()

# «Ng1-f3» / «e2xd3» / «e7-e8=Q» (журнал ходов) или plain «e2e4» без разделителя
# (так Board.gd записывает ходы для лучших/худших ходов дневника) → пара
# клеток; «O-O» → (-1,-1) (рокировку рисуем без стрелки)
func _squares_from_notation(txt: String) -> Array:
	if txt.begins_with("O-O"):
		return [Vector2i(-1, -1), Vector2i(-1, -1)]
	var s = txt
	var eq = s.find("=")
	if eq >= 0:
		s = s.substr(0, eq)
	if s.length() > 0 and s[0] in "NBRQK":
		s = s.substr(1)
	if s.length() == 4:
		return [_square(s.substr(0, 2)), _square(s.substr(2, 2))]
	if s.length() < 5:
		return [Vector2i(-1, -1), Vector2i(-1, -1)]
	return [_square(s.substr(0, 2)), _square(s.substr(3, 2))]

func _square(name: String) -> Vector2i:
	return Vector2i(name.unicode_at(0) - 97, name.unicode_at(1) - 49)

# move dict → запись в стиле журнала: "Ng1-f3", "e2xd3", "O-O", "e7-e8=Q"
func _notation(eng: ChessEngine, m: Dictionary) -> String:
	if m.get("is_castle", "") == "K":
		return "O-O"
	if m.get("is_castle", "") == "Q":
		return "O-O-O"
	var p = eng.board[m.from.y][m.from.x]
	var names = {"P": "", "N": "N", "B": "B", "R": "R", "Q": "Q", "K": "K"}
	var cap = eng.board[m.to.y][m.to.x] != null or m.get("is_ep", false)
	var txt = str(names.get(p.type if p != null else "P", "")) + ChessEngine.square_name(m.from.x, m.from.y) + ("x" if cap else "-") + ChessEngine.square_name(m.to.x, m.to.y)
	if str(m.get("promo", "")) != "":
		txt += "=" + str(m.promo)
	return txt

# ============================ ПАРТИИ ============================

func _build_games_page() -> void:
	page_games = _make_page()
	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	scroll.offset_left = 24
	scroll.offset_right = 444
	scroll.offset_top = 8
	scroll.offset_bottom = -16
	scroll.anchor_bottom = 1.0
	page_games.add_child(scroll)
	games_list_vbox = VBoxContainer.new()
	games_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	games_list_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(games_list_vbox)

	replay_board_draw = Node2D.new()
	replay_board_draw.position = Vector2(500, 24)
	page_games.add_child(replay_board_draw)
	replay_board_draw.draw.connect(_on_replay_board_draw)

	var controls = HBoxContainer.new()
	controls.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	controls.offset_left = 500
	controls.offset_right = -24
	controls.offset_top = -196
	controls.offset_bottom = -156
	controls.add_theme_constant_override("separation", 10)
	page_games.add_child(controls)
	for pair in [["⏮", func(): _replay_seek(0)], ["◀", func(): _replay_seek(replay_cur - 1)],
			["▶", func(): _replay_seek(replay_cur + 1)], ["⏭", func(): _replay_seek(replay_states.size() - 1)]]:
		var b = Button.new()
		b.custom_minimum_size = Vector2(64, 40)
		b.text = pair[0]
		b.pressed.connect(pair[1])
		controls.add_child(b)
	replay_auto = CheckButton.new()
	replay_auto.text = "Авто"
	controls.add_child(replay_auto)
	replay_counter = Label.new()
	replay_counter.add_theme_font_size_override("font_size", 14)
	controls.add_child(replay_counter)

	replay_comment = Label.new()
	replay_comment.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	replay_comment.offset_left = 500
	replay_comment.offset_right = -24
	replay_comment.offset_top = -148
	replay_comment.offset_bottom = -10
	replay_comment.autowrap_mode = TextServer.AUTOWRAP_WORD
	replay_comment.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	replay_comment.add_theme_font_size_override("font_size", 13)
	page_games.add_child(replay_comment)
	replay_comment.text = "Выберите партию слева, чтобы пересмотреть её с разбором."

	_fill_games_list()

func _fill_games_list() -> void:
	var log = Profile.game_log
	if log.is_empty():
		var l = Label.new()
		l.text = "Сыграйте партию — она появится здесь для разбора."
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
		games_list_vbox.add_child(l)
		return
	var count = mini(log.size(), 40)
	games_button_group = ButtonGroup.new()
	for i in range(log.size() - 1, log.size() - 1 - count, -1):
		var g = log[i]
		var b = Button.new()
		b.custom_minimum_size = Vector2(0, 48)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var res = str(g.get("result", ""))
		var mark = "✔" if res == "победа" else ("=" if res == "ничья" else "✘")
		b.text = "%s %s · %s\n%s · ходов: %d" % [mark, res, str(g.get("opponent", "Соперник")), str(g.get("date", "")), g.get("moves", []).size()]
		# toggle group so the game currently being reviewed stays highlighted
		# in the list — otherwise there's no visual link between the board
		# on the right and which entry on the left it came from
		b.toggle_mode = true
		b.button_group = games_button_group
		b.pressed.connect(_load_replay.bind(g))
		games_list_vbox.add_child(b)

func _load_replay(g: Dictionary) -> void:
	# _retire_thread() doesn't block: the previous game's background thread
	# gets its own snapshots of the replay_* arrays (see _analyze_replay),
	# so it's safe to let it keep running in the background while we
	# reassign these below — it just quietly finishes and gets joined later
	# instead of freezing the UI on a synchronous wait_to_finish().
	_replay_request += 1
	_retire_thread(_replay_thread)
	replay_entry = g
	replay_flip = str(g.get("color", "w")) == "b"
	replay_states = []
	replay_base_comments = [""]
	replay_moves = [null]
	replay_evals = []
	replay_mover = [""]
	replay_loss = {}
	replay_better = {}
	var eng = ChessEngine.new()
	var start_fen: String = g.get("start_fen", "")
	if start_fen != "":
		eng.setup_from_fen(start_fen)
	else:
		eng.setup_start_position()
	replay_states.append(eng.clone())
	replay_evals.append(coach_replay.evaluate_position(eng))
	var my_color = str(g.get("color", "w"))
	var ply = 0
	for txt in g.get("moves", []):
		var mv = _parse_move(eng, str(txt))
		if mv.is_empty():
			replay_base_comments[replay_base_comments.size() - 1] += "\n(дальше запись партии не читается)"
			break
		var mover = eng.side_to_move
		var is_capture = str(txt).contains("x")
		eng.apply_move(mv)
		ply += 1
		var who = "Вы" if mover == my_color else "Соперник"
		var c = "%d. %s: %s" % [(ply + 1) / 2, who, txt]
		if str(txt).begins_with("O-O"):
			c += " — рокировка, король в безопасности"
		elif str(txt).contains("="):
			c += " — пешка превратилась в новую фигуру!"
		elif is_capture:
			c += " — взятие"
		var status = eng.game_status()
		if status != "playing":
			c += " · партия окончена"
		elif eng.is_in_check(eng.side_to_move):
			c += " — шах!"
		if mover == my_color and int(g.get("worst_move_no", -1)) >= 0 and str(g.get("worst_notation", "")) == str(txt):
			c += "\n⚠ Худший ход партии."
		if ply == 1:
			c += "\nДебют: выводите фигуры и прячьте короля."
		elif ply == 21:
			c += "\nМиттельшпиль: время планов и комбинаций."
		elif ply == 51:
			c += "\nЭндшпиль: король становится бойцом."
		replay_base_comments.append(c)
		replay_moves.append(mv)
		replay_mover.append(mover)
		replay_states.append(eng.clone())
		replay_evals.append(coach_replay.evaluate_position(eng))
	# фоновый разбор ходов игрока: точная цена ошибок + лучший ход
	# (предыдущий поток уже остановлен в начале этой функции)
	var req = _replay_request
	# Snapshots (duplicate()), not live references — the arrays below get
	# reassigned wholesale the moment the player opens another game, and
	# this thread must keep reading the game it was actually asked to
	# analyze instead of racing that reassignment.
	var analysis := _analyze_replay.bind(my_color, req, replay_states.duplicate(), replay_moves.duplicate(), replay_mover.duplicate())
	if Global.can_thread:
		_replay_thread = Thread.new()
		_replay_thread.start(analysis)
	else:
		analysis.call_deferred() # в браузере потоков нет — считаем в основном
	_replay_seek(0)

# Выполняется в фоне: для каждого хода игрока считает потерю (move_loss) и,
# если ход был неточным, лучший ход с объяснением. Результаты подкладываются
# в replay_loss/replay_better по мере готовности. states/moves/movers — снимки
# replay_* массивов на момент запуска, не живые ссылки на поля Diary.
func _analyze_replay(my_color: String, req: int, states: Array, moves: Array, movers: Array) -> void:
	for i in range(1, states.size()):
		if req != _replay_request:
			return # открыли другую партию — бросаем расчёт
		if movers[i] != my_color or moves[i] == null:
			continue
		var before: ChessEngine = states[i - 1]
		var loss = coach_replay.move_loss(before, moves[i], 2)
		var better_txt := ""
		if loss > 30.0:
			var best = coach_replay.best_move_clean(before, 2)
			if best != null and not (best.from == moves[i].from and best.to == moves[i].to):
				var victim = before.board[best.to.y][best.to.x]
				var why = "забирает %s" % PIECE_RU.get(victim.type, "фигуру") if victim != null else "держит позицию без потерь"
				better_txt = "Сильнее было %s — %s." % [_notation(before, best), why]
		call_deferred("_apply_replay_analysis", i, loss, better_txt, req)

func _apply_replay_analysis(i: int, loss: float, better_txt: String, req: int) -> void:
	if req != _replay_request:
		return
	replay_loss[i] = loss
	if better_txt != "":
		replay_better[i] = better_txt
	if replay_cur == i:
		_replay_seek(replay_cur) # обновить комментарий, если стоим на этом ходе

func _parse_move(eng: ChessEngine, txt: String) -> Dictionary:
	var legal = eng.legal_moves(eng.side_to_move)
	if txt.begins_with("O-O-O"):
		for m in legal:
			if m.get("is_castle", "") == "Q":
				return m
		return {}
	if txt.begins_with("O-O"):
		for m in legal:
			if m.get("is_castle", "") == "K":
				return m
		return {}
	var promo = ""
	var s = txt
	var eq = s.find("=")
	if eq >= 0:
		promo = s.substr(eq + 1, 1)
		s = s.substr(0, eq)
	if s.length() > 0 and s[0] in "NBRQK":
		s = s.substr(1)
	if s.length() < 5:
		return {}
	var from = _square(s.substr(0, 2))
	var to = _square(s.substr(3, 2))
	for m in legal:
		if m.from == from and m.to == to and str(m.get("promo", "")) == promo:
			return m
	# underpromotion: the generator only offers "Q", so re-tag the move
	for m in legal:
		if m.from == from and m.to == to:
			var d = m.duplicate()
			if promo != "":
				d["promo"] = promo
			return d
	return {}

func _replay_seek(i: int) -> void:
	if replay_states.is_empty():
		return
	replay_cur = clampi(i, 0, replay_states.size() - 1)
	var my_color = str(replay_entry.get("color", "w"))
	var sign = 1.0 if my_color == "w" else -1.0
	if replay_cur == 0:
		replay_comment.text = "Начальная позиция. «▶» — следующий ход, «Авто» — партия проиграется сама.\nСоперник: %s · результат: %s\nШкала у доски показывает, чей перевес. %s" % [str(replay_entry.get("opponent", "")), str(replay_entry.get("result", "")), SCALE_HINT]
	else:
		var lines := [replay_base_comments[replay_cur]]
		# влияние хода на перевес (с точки зрения игрока, в пешках)
		var ev_now = sign * replay_evals[replay_cur] / 100.0
		var ev_prev = sign * replay_evals[replay_cur - 1] / 100.0
		var d = ev_now - ev_prev
		var trend = "→ перевес не изменился"
		if d > 0.3:
			trend = "→ ваш перевес вырос на %.1f пешки" % d
		elif d < -0.3:
			trend = "→ ваше положение ухудшилось на %.1f пешки" % absf(d)
		lines.append("Перевес: %+.1f пешки (было %+.1f) %s" % [ev_now, ev_prev, trend])
		# точный разбор хода игрока (из фонового анализа)
		if replay_mover[replay_cur] == my_color:
			if replay_loss.has(replay_cur):
				var loss = replay_loss[replay_cur]
				if loss <= 15.0:
					lines.append("✔ Отличный ход — лучший или почти лучший в позиции.")
				else:
					var cat = "неточность" if loss <= 100 else ("ошибка" if loss <= 300 else "зевок")
					lines.append("▼ Это %s: потеряно %.1f пешки. %s" % [cat, loss / 100.0, str(replay_better.get(replay_cur, ""))])
			elif _replay_thread != null and _replay_thread.is_alive():
				lines.append("⏳ Тренер ещё считает этот ход...")
		replay_comment.text = "\n".join(lines)
	replay_counter.text = "%d / %d" % [replay_cur, replay_states.size() - 1]
	replay_board_draw.queue_redraw()

func _on_replay_board_draw() -> void:
	if replay_states.is_empty():
		_draw_board(replay_board_draw, null, Vector2i(-1, -1), Vector2i(-1, -1), false)
		return
	var eng: ChessEngine = replay_states[replay_cur]
	var from = Vector2i(-1, -1)
	var to = Vector2i(-1, -1)
	if replay_cur > 0 and replay_moves[replay_cur] != null:
		from = replay_moves[replay_cur].from
		to = replay_moves[replay_cur].to
	_draw_board(replay_board_draw, eng, from, to, replay_flip)
	# шкала перевеса: белая доля снизу, чёрная сверху
	var ev = replay_evals[replay_cur]
	var white_frac = clampf(0.5 + ev / 1200.0, 0.05, 0.95)
	var bar = Rect2(Vector2(SQ * 8 + 14, 0), Vector2(20, SQ * 8))
	replay_board_draw.draw_rect(bar, Color(0.12, 0.12, 0.16), true)
	replay_board_draw.draw_rect(Rect2(bar.position + Vector2(0, bar.size.y * (1.0 - white_frac)), Vector2(bar.size.x, bar.size.y * white_frac)), Color(0.9, 0.92, 0.95), true)
	replay_board_draw.draw_rect(bar, Color(0.11, 0.85, 0.95, 0.5), false, 1.5)
	replay_board_draw.draw_line(bar.position + Vector2(-3, bar.size.y / 2), bar.position + Vector2(bar.size.x + 3, bar.size.y / 2), Color(1, 0.65, 0.95, 0.6), 1.5)

func _process(delta: float) -> void:
	if not _stale_threads.is_empty():
		var still_alive: Array[Thread] = []
		for t in _stale_threads:
			if t.is_alive():
				still_alive.append(t)
			else:
				t.wait_to_finish()
		_stale_threads = still_alive
	if page_games != null and page_games.visible and replay_auto != null and replay_auto.button_pressed and not replay_states.is_empty():
		if replay_cur >= replay_states.size() - 1:
			replay_auto.button_pressed = false
			return
		_auto_accum += delta
		if _auto_accum >= AUTO_STEP:
			_auto_accum = 0.0
			_replay_seek(replay_cur + 1)

# ============================ ДОСКА ============================

func _draw_board(cr: Node2D, eng: ChessEngine, from: Vector2i, to: Vector2i, flip: bool, best_from := Vector2i(-1, -1), best_to := Vector2i(-1, -1)) -> void:
	var font = ThemeDB.fallback_font
	for r in range(8):
		for f in range(8):
			var sx = (7 - f) if flip else f
			var sy = r if flip else (7 - r)
			var pos = Vector2(sx * SQ, sy * SQ)
			var col = LIGHT_COL if (f + r) % 2 == 1 else DARK_COL
			cr.draw_rect(Rect2(pos, Vector2(SQ, SQ)), col, true)
			if Vector2i(f, r) == from:
				cr.draw_rect(Rect2(pos, Vector2(SQ, SQ)), Color(0.95, 0.8, 0.35, 0.35), true)
			if Vector2i(f, r) == to:
				cr.draw_rect(Rect2(pos, Vector2(SQ, SQ)), Color(0.95, 0.8, 0.35, 0.55), true)
	cr.draw_rect(Rect2(Vector2.ZERO, Vector2(SQ * 8, SQ * 8)), Color(0.11, 0.85, 0.95, 0.5), false, 2.0)
	# координаты
	for f in range(8):
		var sx = (7 - f) if flip else f
		cr.draw_string(font, Vector2(sx * SQ + SQ - 14, SQ * 8 - 5), char(97 + f), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.45))
	for r in range(8):
		var sy = r if flip else (7 - r)
		cr.draw_string(font, Vector2(4, sy * SQ + 14), str(r + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.45))
	if eng == null:
		return
	for r in range(8):
		for f in range(8):
			var p = eng.board[r][f]
			if p == null:
				continue
			var sx = (7 - f) if flip else f
			var sy = r if flip else (7 - r)
			var center = Vector2(sx * SQ + SQ / 2, sy * SQ + SQ / 2)
			PieceTextures.draw(cr, p.type, p.color, center, SQ * 0.92)
	# стрелки: красная — сыгранный ход, зелёная — совет тренера
	if from.x >= 0 and to.x >= 0:
		_draw_arrow(cr, from, to, flip, Color(1.0, 0.35, 0.35, 0.9))
	if best_from.x >= 0 and best_to.x >= 0 and (best_from != from or best_to != to):
		_draw_arrow(cr, best_from, best_to, flip, Color(0.35, 0.95, 0.45, 0.9))

func _draw_arrow(cr: Node2D, from: Vector2i, to: Vector2i, flip: bool, col: Color) -> void:
	var a = _square_center(from, flip)
	var b = _square_center(to, flip)
	var dir = (b - a).normalized()
	var tip = b - dir * SQ * 0.18
	cr.draw_line(a, tip - dir * 10.0, col, 5.0)
	var side = Vector2(-dir.y, dir.x) * 9.0
	cr.draw_colored_polygon(PackedVector2Array([tip, tip - dir * 18.0 + side, tip - dir * 18.0 - side]), col)

func _square_center(sq: Vector2i, flip: bool) -> Vector2:
	var sx = (7 - sq.x) if flip else sq.x
	var sy = sq.y if flip else (7 - sq.y)
	return Vector2(sx * SQ + SQ / 2, sy * SQ + SQ / 2)
