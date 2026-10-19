extends Node2D

const SQUARE := 88.0
const BOARD_ORIGIN := Vector2(40, 40)

# Режим «Внимательность»: подсказки-угрозы на доске (см. AttentionHub).
var attention := 0
var attention_flash_ms := 0 # когда соперник сходил (для режима "flash")


@onready var status_label: Label = $UI/SidePanel/Content/StatusLabel
@onready var turn_label: Label = $UI/SidePanel/Content/TurnLabel
@onready var history_label: RichTextLabel = $UI/SidePanel/Content/HistoryLabel
@onready var promo_panel: PanelContainer = $UI/PromoPanel
@onready var gameover_panel: PanelContainer = $UI/GameOverPanel
@onready var gameover_label: Label = $UI/GameOverPanel/VBox/ResultScroll/ResultLabel
@onready var board_draw: Node2D = $BoardDraw
@onready var background_rect: ColorRect = $Background
@onready var board_frame: Panel = $BoardFrame
@onready var music: MusicPlayer = $Music
@onready var sound_fx: SoundFX = $SoundFX
@onready var map_button: Button = $UI/GameOverPanel/VBox/HBox/MapButton
@onready var hint_label: Label = $UI/SidePanel/Content/HintLabel
@onready var hint_button: Button = $UI/SidePanel/Content/HintButton
@onready var nudge_panel: PanelContainer = $UI/NudgePanel
@onready var leave_panel: PanelContainer = $UI/LeavePanel

var pending_leave_target := ""

var engine: ChessEngine
var ai: ChessAI
var selected_square = null # Vector2i or null
var legal_targets: Array = []
var player_color: String = "w"
var ai_thinking := false
var game_over := false
var pending_promotion = null # {"from":..,"to":..}
var move_history: Array = []
# те же ходы координатами ("e2e4", "e7e8Q") — для архива партий ботов:
# воспроизведение по координатам точное и не зависит от разбора нотации
var move_coords: Array = []
var undo_stack: Array = [] # ChessEngine snapshots taken right before each move is applied
@onready var undo_button: Button = $UI/SidePanel/Content/UndoButton
@onready var resign_button: Button = $UI/SidePanel/Content/ResignButton
@onready var menu_button: Button = $UI/SidePanel/Content/MenuButton
@onready var gameover_menu_button: Button = $UI/GameOverPanel/VBox/HBox/MenuButton2

var dragging := false
var drag_from = null # Vector2i
var drag_pos := Vector2.ZERO

# AI move animation: the piece visibly slides from -> to instead of
# teleporting; the engine itself isn't updated until the slide finishes.
var anim_active := false
var anim_from: Vector2i
var anim_to: Vector2i
var anim_piece: Dictionary = {}
var anim_t := 0.0

var map_character: Dictionary = {}

# Co-op battle modes (set from the map node's "coop" field):
# "team" — player + partner AI alternate White moves vs two Black AIs;
# "intervene" — a weak ally AI plays White alone, the player steps in
# whenever the ally is about to blunder.
var coop := ""
# «Помощь» в этой партии: подсказки и откаты ходов. Партия с помощью — не показатель силы игрока,
# поэтому в рейтинг она не идёт (в турнирах подсказок и откатов нет вовсе).
var help_hints := 0
var _leave_defaults: Dictionary = {} # исходные тексты панели подтверждения
var help_undos := 0
var partner_ai: ChessAI
var opp_ai_a: ChessAI
var opp_ai_b: ChessAI
var ally_ai: ChessAI
var intervention_active := false

# "Дорога домой" battle stages (Global.road_mode):
# predict — before the rival replies, the player clicks the square they
#           think it will move TO; correct guesses are counted and praised.
# xray    — after 12s of thinking the pieces hide in fog; move from memory.
# shadow  — the opponent is the player's own "twin" (their rating level and
#           their real blunder rate); shadow_final is the twin plus 2 levels.
var road := ""
var awaiting_prediction := false
var predict_guess = null # Vector2i
var predict_hits := 0
var predict_total := 0
var xray_fog := false
var xray_turn_start := 0

# Rematch review: the player's worst moments this game (loss > ChessAI.LOSS_MISTAKE cp),
# so after a defeat we can show where the game broke and offer a replay
# from right before that move.
var worst_moments: Array = [] # {snapshot: ChessEngine, loss: float, notation: String, move_no: int, hist_len: int}
# FEN the game actually started from (drills/assisted map fights don't start
# from the standard position); "" means standard — recorded in the game log
# so the Diary can replay it instead of assuming setup_start_position().
var initial_fen := ""
var game_quality := {"good": 0, "inaccuracy": 0, "mistake": 0, "blunder": 0} # this game only, for the HTML report
@onready var review_label: Label = get_node_or_null("UI/GameOverPanel/VBox/ReviewLabel")
@onready var replay_button: Button = get_node_or_null("UI/GameOverPanel/VBox/ReplayButton")

# Character speech bubble (map battles): a greeting at the start, a line on
# win/lose appended to the game-over text.
@onready var speech_panel: PanelContainer = get_node_or_null("UI/SpeechPanel")
@onready var speech_label: Label = get_node_or_null("UI/SpeechPanel/SpeechLabel")

# Tournament game (Global.tournament_game): separate rating, chess clocks
# for blitz/rapid formats, no hints/undo (fair play), result reported back
# to the bracket in Profile.active_tournaments.
var tournament: Dictionary = {}
# товарищеская партия с конкретным игроком из «Базы игроков»
var friendly: Dictionary = {}
var clock_white := 0.0
var clock_black := 0.0
var clock_increment := 0.0
var clock_running := false
@onready var clock_label: Label = get_node_or_null("UI/SidePanel/Content/ClockLabel")

var hint_from = null # Vector2i
var hint_to = null # Vector2i
var hint_ai: ChessAI = ChessAI.new(ChessAI.ANALYSIS_LEVEL) # only used for its search, never as an opponent

# «Школа юного шахматиста» (Global.school_mode): режимы против игры наугад.
# "spot": после хода ИИ фигуры на миг исчезают, подсветка хода прячется, и
#         прежде чем ходить самому, ребёнок должен кликнуть клетку, куда
#         сходил соперник (учит СМОТРЕТЬ на чужие ходы).
# "patience": свой ход разрешён только после паузы на обдумывание; ходы,
#         сделанные не сразу, копят серию «очков мудрости», зевок сжигает её.
var school := ""
const SPOT_FLASH_MS := 1200 # сколько миллисекунд фигуры «исчезают» после хода ИИ
const SPOT_TRIES := 2 # попыток угадать клетку, потом показываем ответ
var patience_lock_ms := 10000 # пауза перед ходом (из Profile.school_patience_seconds)
var awaiting_spot := false # ждём клик-ответ «куда сходил соперник?»
var spot_flash_until := 0 # ms; пока не наступило — фигуры скрыты
var spot_tries_left := 0
var spot_hits := 0
var spot_total := 0
var patience_unlock_ms := 0 # ходить можно только после этого момента
var turn_started_ms := 0 # когда начался ход игрока (для очков мудрости)
var wisdom_stars := 0
var wisdom_streak := 0

func _ready() -> void:
	if not Themes.is_neon():
		$UI/SidePanel/Content.add_theme_constant_override("separation", 10) # кнопки темы выше неоновых
	if Global.small_screen:
		# телефон: поле вписано целиком и уменьшено — боковую панель делаем крупнее
		Global.boost_fonts($UI/SidePanel, 1.6)
	player_color = Global.player_color
	attention = Global.attention_level
	if Global.map_character_id != "":
		map_character = MapData.by_id(Global.map_character_id)
		coop = map_character.get("coop", "")
		match coop:
			"team":
				player_color = "w"
				partner_ai = ChessAI.new(map_character.get("coop_partner", 7))
				opp_ai_a = ChessAI.new(Global.adaptive_level(map_character.get("coop_opp_a", 5)))
				opp_ai_b = ChessAI.new(Global.adaptive_level(map_character.get("coop_opp_b", 8)))
			"intervene":
				player_color = "w"
				ally_ai = ChessAI.new(map_character.get("coop_ally", 3))
				opp_ai_a = ChessAI.new(Global.adaptive_level(map_character.get("coop_opp", 6)))
	elif Global.road_mode != "":
		road = Global.road_mode
		player_color = "w"
	elif Global.school_mode != "":
		school = Global.school_mode
		player_color = "w"
	elif not Global.tournament_game.is_empty():
		tournament = Global.tournament_game
		player_color = tournament.color
	elif not Global.friendly_game.is_empty():
		friendly = Global.friendly_game
		player_color = str(friendly.get("color", "w"))
	elif Global.coop_team:
		# quick-play "папа и сын": TWO HUMANS share the White side and move
		# strictly in turns (Папа → Сын → Папа...), against a rival team of
		# two AIs — the chosen difficulty plus a stronger second player
		coop = "duo"
		player_color = "w"
		opp_ai_a = ChessAI.new(Global.adaptive_level(Global.difficulty))
		opp_ai_b = ChessAI.new(Global.adaptive_level(clampi(Global.difficulty + 2, 1, 25)))

	# The game's true starting FEN, independent of auto-resume below (resuming
	# only changes which mid-game position we load, not what the game began
	# from) — recorded in the log so the Diary can replay non-standard starts.
	if not map_character.is_empty() and Global.map_assist and map_character.has("assist_fen"):
		initial_fen = map_character.assist_fen
	elif not map_character.is_empty() and map_character.has("start_fen"):
		initial_fen = map_character.start_fen

	# Auto-resume: if the saved game matches the context we're entering with
	# (same quick-play vs. same map character + assist choice), continue it
	# exactly where it was left instead of starting over.
	var saved = Profile.game_state
	var resumed = false
	if road == "" and school == "" and attention == 0 and tournament.is_empty() and friendly.is_empty() and not saved.is_empty() and saved.get("map_character_id", "") == Global.map_character_id and saved.get("map_assist", false) == Global.map_assist and saved.get("coop_team", false) == Global.coop_team:
		resumed = _resume_from_saved(saved)

	if not resumed:
		# adaptive difficulty (if enabled) shifts the level toward the player's
		# rating; Global.difficulty is updated so rating math sees the real level
		ai = ChessAI.new(Global.adaptive_level(Global.difficulty))
		Global.difficulty = ai.level
		engine = ChessEngine.new()
		if not map_character.is_empty() and Global.map_assist and map_character.has("assist_fen"):
			engine.setup_from_fen(map_character.assist_fen)
		elif not map_character.is_empty() and map_character.has("start_fen"):
			# endgame drill nodes start from a fixed teaching position
			engine.setup_from_fen(map_character.start_fen)
		else:
			engine.setup_start_position()

	promo_panel.visible = false
	gameover_panel.visible = false
	board_draw.draw.connect(_on_board_draw)
	if not map_character.is_empty():
		var assist_txt = " (с форой)" if Global.map_assist else ""
		turn_label.text = "Соперник: %s — %s%s" % [map_character.name, map_character.region, assist_txt]
		_apply_map_theme()
		music.start_theme(map_character.music)
		if not resumed:
			_show_speech(map_character.get("lines", {}).get("greet", ""))
	elif road != "":
		# training stages always start fresh with their special opponent
		match road:
			"predict":
				ai = ChessAI.new(Global.adaptive_level(5))
				turn_label.text = "Мост предсказаний: после своего хода угадайте ответ соперника!"
			"xray":
				ai = ChessAI.new(Global.adaptive_level(6))
				turn_label.text = "Туманный лес: думайте быстро — через 12 секунд фигуры прячутся в туман!"
			"shadow":
				ai = _make_shadow_ai(0)
				turn_label.text = "Твоя Тень: соперник играет в твою силу и с твоими ошибками"
			"shadow_final":
				ai = _make_shadow_ai(2)
				turn_label.text = "Дом близко! Тень стала сильнее — победи себя завтрашнего"
			"focus_blunders":
				ai = _make_shadow_ai(0)
				turn_label.text = "Крепость без зевков: выиграйте, ни разу не зевнув фигуру!"
			"focus_opening":
				ai = _make_shadow_ai(0)
				turn_label.text = "Застава дебюта: ни одной ошибки в первых 10 ходах — и победа!"
			"focus_middlegame":
				ai = _make_shadow_ai(0)
				turn_label.text = "Перевал середины: без ошибок на ходах 11–25 — и победа!"
			"focus_endgame":
				ai = _make_shadow_ai(0)
				turn_label.text = "Долина эндшпиля: без ошибок после 25-го хода — и победа!"
		Global.difficulty = ai.level
		xray_turn_start = Time.get_ticks_msec()
		map_button.visible = false
	elif school != "":
		# школа играет против мягкого соперника: цель — привычка думать,
		# а не борьба с сильным ИИ
		ai = ChessAI.new(Global.adaptive_level(3))
		Global.difficulty = ai.level
		map_button.visible = false
		if school == "spot":
			turn_label.text = "🔍 Что изменилось? После хода соперника фигуры исчезнут — запомни и покажи, куда он сходил!"
		else:
			patience_lock_ms = clampi(Profile.school_patience_seconds, 3, 60) * 1000
			turn_label.text = "🐢 Школа терпения: ход откроется после паузы %d с. Обдуманные ходы копят ⭐, зевок сжигает серию!" % (patience_lock_ms / 1000)
			patience_unlock_ms = Time.get_ticks_msec() + patience_lock_ms
		turn_started_ms = Time.get_ticks_msec()
	elif not tournament.is_empty():
		ai = ChessAI.new(tournament.level)
		Global.difficulty = tournament.level
		turn_label.text = "%s — тур %d/%d\nСоперник: %s (ур. %d) · Вы играете %s" % [
			tournament.tname, tournament.round, tournament.rounds,
			tournament.opp_name, tournament.level,
			"белыми" if player_color == "w" else "чёрными"]
		map_button.visible = false
		# fair play: no hints, no undo, no mid-game restart in tournaments
		hint_button.visible = false
		undo_button.visible = false
		var restart_btn = get_node_or_null("UI/SidePanel/Content/RestartButton")
		if restart_btn != null:
			restart_btn.visible = false
		var leave_q = get_node_or_null("UI/LeavePanel/VBox/QuestionLabel")
		if leave_q != null:
			leave_q.text = "Это турнирная партия! Выход сейчас = поражение в туре. Точно выйти?"
		if int(tournament.tc) > 0:
			clock_white = float(tournament.tc)
			clock_black = float(tournament.tc)
			clock_increment = float(tournament.inc)
			clock_running = true
			if clock_label != null:
				clock_label.visible = true
				_update_clock_label()
	elif not friendly.is_empty():
		# Товарищеская партия: соперник — конкретный игрок из базы, его сила
		# берётся из его собственного рейтинга. Лига не проверяется: вызвать
		# можно кого угодно, в том числе заведомо сильнее себя.
		ai = ChessAI.new(clampi(int(friendly.get("level", 5)), 1, 25))
		Global.difficulty = ai.level
		turn_label.text = "Товарищеская партия: %s (рейтинг %d) · %s\nВы играете %s" % [
			str(friendly.get("name", "Соперник")), int(friendly.get("rating", 0)),
			str(friendly.get("format_name", "Классика")),
			"белыми" if player_color == "w" else "чёрными"]
		map_button.visible = false
		if int(friendly.get("tc", 0)) > 0:
			clock_white = float(friendly.tc)
			clock_black = float(friendly.tc)
			clock_increment = float(friendly.get("inc", 0))
			clock_running = true
			if clock_label != null:
				clock_label.visible = true
				_update_clock_label()
	elif Global.coop_team:
		turn_label.text = "Папа и сын против ИИ ур. %d и %d — ходите по очереди!" % [
			Global.difficulty, clampi(Global.difficulty + 2, 1, 25)]
		map_button.visible = false
	else:
		turn_label.text = "Сложность: " + Global.difficulty_label(Global.difficulty)
		map_button.visible = false
		if attention > 0:
			var hint_txt: String = {
				"both": "🔴 свои под боем · 🟢 чужие под ударом",
				"red": "🔴 только свои фигуры под боем",
				"green": "🟢 только фигуры соперника под ударом",
				"flash": "подсказки гаснут через 5 секунд",
				"none": "ЭКЗАМЕН: без подсказок и без зевков!",
			}[Global.attention_hint_mode(attention)]
			turn_label.text = "Внимательность %d/50 · %s" % [attention, hint_txt]
	_update_status()
	_update_undo_button()
	_update_exit_labels()
	_autosave_game()
	_maybe_ai_move()

# Restores engine + move history from a saved state; returns false (and
# leaves everything untouched) if the save turns out to be unusable.
func _resume_from_saved(saved: Dictionary) -> bool:
	var fen: String = saved.get("fen", "")
	if fen == "":
		return false
	# Сохранённая позиция уже закончена (мат/пат/ничья) — продолжать нечего. Раньше такая
	# партия открывалась снова и результат записывался в профиль повторно.
	var probe := ChessEngine.new()
	probe.setup_from_fen(fen)
	if probe.game_status() != "playing":
		Profile.clear_game_state()
		return false
	Global.difficulty = saved.get("difficulty", Global.difficulty)
	player_color = saved.get("player_color", player_color)
	Global.player_color = player_color
	ai = ChessAI.new(Global.difficulty)
	engine = ChessEngine.new()
	engine.setup_from_fen(fen)
	move_history = saved.get("move_history", []).duplicate()
	_refresh_history_label()
	return true

func _current_game_state() -> Dictionary:
	return {
		"fen": engine.to_fen(),
		"player_color": player_color,
		"difficulty": Global.difficulty,
		"map_character_id": map_character.get("id", "") if not map_character.is_empty() else "",
		"map_assist": Global.map_assist,
		"coop_team": Global.coop_team,
		"move_history": move_history,
	}

func _autosave_game() -> void:
	if game_over:
		return # законченную партию не сохраняем: иначе она «воскресает» при следующем запуске и засчитывается второй раз
	if road != "" or school != "" or attention > 0 or not tournament.is_empty() or not friendly.is_empty():
		return # training/tournament games always restart fresh; don't clobber the real save
	Profile.save_game_state(_current_game_state())

func _apply_map_theme() -> void:
	var palette: Dictionary = map_character.palette
	background_rect.color = palette.bg_b
	var sb: StyleBoxFlat = board_frame.get_theme_stylebox("panel").duplicate()
	sb.bg_color = palette.bg_a.lerp(Color.BLACK, 0.6)
	sb.border_color = palette.accent
	sb.shadow_color = Color(palette.accent.r, palette.accent.g, palette.accent.b, 0.25)
	board_frame.add_theme_stylebox_override("panel", sb)

func _update_status() -> void:
	var status = engine.game_status()
	var side_txt = "Белые" if engine.side_to_move == "w" else "Чёрные"
	match status:
		"checkmate":
			var winner = "Чёрные" if engine.side_to_move == "w" else "Белые"
			status_label.text = "Мат! Победили: " + winner
			var score = 1.0 if winner == _player_color_name() else 0.0
			_show_game_over(winner + " победили матом!", score)
		"stalemate":
			status_label.text = "Пат — ничья"
			_show_game_over("Пат. Ничья.", 0.5)
		"draw50":
			status_label.text = "Ничья (правило 50 ходов)"
			_show_game_over("Ничья по правилу 50 ходов.", 0.5)
		"insufficient":
			status_label.text = "Ничья (недостаточно материала)"
			_show_game_over("Ничья — недостаточно материала.", 0.5)
		"repetition":
			status_label.text = "Ничья (троекратное повторение)"
			_show_game_over("Ничья — позиция повторилась трижды.", 0.5)
		_:
			var check_txt = " — Шах!" if engine.is_in_check(engine.side_to_move) else ""
			if coop == "team" and engine.side_to_move == "w":
				side_txt = "Белые (ваш)" if _white_moves_made() % 2 == 0 else "Белые (напарник)"
			elif coop == "duo" and engine.side_to_move == "w":
				side_txt = "ПАПА 👨" if _white_moves_made() % 2 == 0 else "СЫН 👦"
			status_label.text = "Ход: " + side_txt + check_txt
	board_draw.queue_redraw()

func _player_color_name() -> String:
	return "Белые" if player_color == "w" else "Чёрные"

# captured: whether the just-applied move captured a piece. Skips the
# regular tone entirely when the game just ended — _show_game_over plays
# its own win/lose jingle instead so the two don't overlap.
func _play_move_sfx(captured: bool) -> void:
	if sound_fx == null:
		return
	if engine.game_status() != "playing":
		return
	if engine.is_in_check(engine.side_to_move):
		sound_fx.play_check()
	elif captured:
		sound_fx.play_capture()
	else:
		sound_fx.play_move()

# Every finished game goes into the profile's game log; Profile regenerates
# the HTML analysis report right after.
# Почему эта партия не должна менять рейтинг (пустая строка — должна).
func _rating_skip_reason() -> String:
	var reasons: Array = []
	if coop != "":
		reasons.append("командная партия")
	if Global.map_assist:
		reasons.append("партия с форой")
	if help_hints > 0:
		reasons.append("были подсказки (%d)" % help_hints)
	if help_undos > 0:
		reasons.append("был откат хода")
	# маркеры угроз «Внимательности» — подсказка сильнее кнопки: работает всю партию
	if attention > 0 and Global.attention_hint_mode(attention) != "none":
		reasons.append("подсказки угроз на доске")
	# уроки с готовой позицией (мат двумя ладьями и т.п.) учат приёму, а не меряют силу
	if str(map_character.get("id", "")).begins_with("drill_"):
		reasons.append("учебная позиция")
	return ", ".join(reasons)

func _log_finished_game(score: float) -> void:
	var worst_no := 0
	var worst_notation := ""
	var worst_loss := 0.0
	var err_open := 0
	var err_mid := 0
	var err_end := 0
	for m in worst_moments:
		if m.loss > worst_loss:
			worst_loss = m.loss
			worst_no = m.move_no
			worst_notation = m.notation
		if m.move_no <= 10: err_open += 1
		elif m.move_no <= 25: err_mid += 1
		else: err_end += 1
	Profile.record_game_log({
		"err_opening": err_open,
		"err_middlegame": err_mid,
		"err_endgame": err_end,
		"date": Time.get_datetime_string_from_system(false, true),
		"opponent": _opponent_label(),
		"level": Global.difficulty,
		"result": "победа" if score >= 1.0 else ("поражение" if score < 0.5 else "ничья"),
		"color": player_color,
		"moves": move_history.duplicate(),
		"good": game_quality.good,
		"inaccuracy": game_quality.inaccuracy,
		"mistake": game_quality.mistake,
		"blunder": game_quality.blunder,
		"worst_move_no": worst_no,
		"worst_notation": worst_notation,
		"start_fen": initial_fen,
		"help_hints": help_hints,
		"help_undos": help_undos,
		"assist": Global.map_assist,
		"coop": coop,
		"tournament": not tournament.is_empty(),
	})

# Dynamic road stages ("focus_*"): winning is not enough — the stage also
# demands clean play in the phase the player has been fumbling lately.
func _focus_condition_met() -> bool:
	for m in worst_moments:
		match road:
			"focus_blunders":
				if m.loss > ChessAI.LOSS_BLUNDER: return false
			"focus_opening":
				if m.move_no <= 10: return false
			"focus_middlegame":
				if m.move_no >= 11 and m.move_no <= 25: return false
			"focus_endgame":
				if m.move_no > 25: return false
	return true

func _focus_condition_text() -> String:
	match road:
		"focus_blunders": return "были зевки"
		"focus_opening": return "были ошибки в первых 10 ходах"
		"focus_middlegame": return "были ошибки на ходах 11–25"
		"focus_endgame": return "были ошибки после 25-го хода"
	return ""

func _opponent_label() -> String:
	if not map_character.is_empty():
		return map_character.get("name", "ИИ")
	match road:
		"shadow": return "Твоя Тень"
		"shadow_final": return "Тень (финал)"
		"predict": return "ИИ (мост предсказаний)"
		"xray": return "ИИ (туманный лес)"
		"focus_blunders": return "Страж крепости"
		"focus_opening": return "Страж заставы"
		"focus_middlegame": return "Страж перевала"
		"focus_endgame": return "Страж долины"
	if not tournament.is_empty():
		return "%s (турнир)" % tournament.opp_name
	if coop in ["team", "duo"]:
		return "Команда ИИ"
	return "ИИ"

# Shows the character's line in a bubble above the board for a few seconds,
# coloured in the character's accent. No-op for empty lines / non-map games.
func _show_speech(line: String, sticky: bool = false) -> void:
	if speech_panel == null or line == "":
		return
	if sticky:
		speech_label.text = line
	else:
		speech_label.text = "%s: «%s»" % [map_character.name, line]
	if map_character.has("palette"):
		speech_label.add_theme_color_override("font_color", map_character.palette.accent)
	speech_panel.visible = true
	speech_panel.modulate.a = 1.0
	if sticky:
		return # stays until hidden explicitly (co-op intervention prompt)
	var tw = create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(speech_panel, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func(): speech_panel.visible = false)

func _show_game_over(text: String, score: float = -1.0) -> void:
	if game_over:
		return
	game_over = true
	# партия могла закончиться, пока открыт вопрос «Выйти из партии?» (соперник
	# додумал ход или упал флаг) — иначе панель выхода осталась бы висеть
	# поверх итогов партии
	leave_panel.visible = false
	pending_leave_target = ""
	# school drills (deliberately random-ish opponents) would flood the
	# ROAD_FOCUS_WINDOW used by dynamic_road_stages() and drown out the player's
	# real mistakes. Tournament games are the fairest mode (no hints, no undo), so
	# they DO feed the learning stats; the road window is normalised by opponent level.
	if score >= 0.0 and school == "":
		_log_finished_game(score)
	if speech_panel != null:
		speech_panel.visible = false
	if not map_character.is_empty() and score >= 0.0:
		var key = "win" if score >= 1.0 else ("lose" if score < 0.5 else "")
		var line: String = map_character.get("lines", {}).get(key, "") if key != "" else ""
		if line != "":
			text = "%s: «%s»\n\n%s" % [map_character.name, line, text]
	Profile.clear_game_state()
	if sound_fx != null:
		if score >= 1.0:
			sound_fx.play_result(true)
		elif score >= 0.0 and score < 0.5:
			sound_fx.play_result(false)
	clock_running = false
	# архив соперника — до турнирной ветки: она возвращается раньше, а состояние
	# турнира (кто соперник) после finish_*_round может уже не найтись
	if score >= 0.0:
		_archive_bot_game(score)
	if score >= 0.0 and not tournament.is_empty():
		var practice = tournament.get("practice", false)
		var state: Dictionary
		if practice:
			# preparation tournaments never touch the real tournament rating
			state = Profile.finish_prep_round(tournament.tid, tournament.opp_idx, score)
		else:
			# tournaments live on their own rating and report back to the bracket
			Profile.record_tournament_game(tournament.level, score)
			var tdelta = Profile.last_tournament_rating_change
			var tsign = "+" if tdelta >= 0 else ""
			text += "\nТурнирный рейтинг: %d (%s%d)" % [round(Profile.tournament_rating), tsign, round(tdelta)]
			state = Profile.finish_tournament_round(tournament.tid, tournament.opp_idx, score)
		if not state.is_empty():
			if state.get("done", false):
				var place = Profile.tournament_place(state)
				if state.get("won", false):
					text += "\n\n🏆 Турнир «%s» ВЫИГРАН! Ваши очки: %.1f" % [tournament.tname, float(state.my_score)]
				elif state.get("tied_first", false):
					text += "\n\nТурнир «%s» завершён: ничья за 1-е место (очки: %.1f)." % [tournament.tname, float(state.my_score)]
				else:
					text += "\n\nТурнир «%s» завершён: %d-е место (очки: %.1f)." % [tournament.tname, place, float(state.my_score)]
			else:
				text += "\n\nТур %d сыгран. Очки: %.1f — впереди тур %d из %d." % [
					tournament.round, float(state.my_score), int(state.round) + 1, int(state.rounds)]
		# выход из турнирной партии ведёт в турнирный хаб — это уже делает
		# кнопка выхода (см. _update_exit_labels), второй такой же не нужно
		map_button.visible = false
		var restart2 = get_node_or_null("UI/GameOverPanel/VBox/HBox/RestartButton2")
		if restart2 != null:
			restart2.visible = false
		gameover_label.text = text
		gameover_panel.visible = true
		_show_game_review(score)
		if replay_button != null:
			replay_button.visible = false # the round is already scored — no replays
		return
	if score >= 0.0:
		# road (incl. replayed stops) and school are training modes with
		# controlled/repeatable opponents — they must not feed the main
		# rating, same as tournaments already don't.
		# партия с форой (материальный перевес игроку) показывает не силу игрока, а силу форы —
		# в рейтинг она не идёт, иначе победы над «ослабленным» соперником завышали бы его
		if road == "" and school == "":
			var no_count := _rating_skip_reason()
			if no_count != "":
				text += "\nНе идёт в ступень и статистику: " + no_count + "."
			else:
				var lvl: int = clampi(Global.difficulty, 1, Profile.LEVEL_RATING.size())
				Profile.record_game_result(Global.difficulty, score) # внутренняя оценка для подбора сложности
				text += "\nСоперник: %s. За партию: ошибок %d, зевков %d." % [Global.difficulty_label(lvl), int(game_quality.get("mistake", 0)), int(game_quality.get("blunder", 0))]
				if Profile.last_step_gain > 0:
					text += "\n🎖 Новая ступень: %d — %s!" % [Profile.last_step_gain, Global.difficulty_label(Profile.last_step_gain)]
				elif score >= 1.0:
					text += "\nЧистая победа над уровнем %d засчитана. Ступень: %d, до следующей — %d чист. побед над уровнем %d." % [lvl, Profile.clean_step(), Profile.step_wins_left(), Profile.clean_step() + 1]
				else:
					text += "\nСтупень: %d (растёт от чистых побед без подсказок и откатов)." % Profile.clean_step()
		if not friendly.is_empty():
			# Товарищеская партия — тоже партия с живым игроком базы, поэтому
			# двигает и его постоянный рейтинг (турнирный рейтинг не трогаем).
			var moved = Profile.record_friendly_game(str(friendly.get("id", "")), score)
			if not moved.is_empty():
				var bsign = "+" if float(moved.delta) >= 0 else ""
				text += "\nРейтинг соперника (%s): %d (%s%d)" % [
					str(friendly.get("name", "")), round(float(moved.rating)), bsign, round(float(moved.delta))]
				if bool(moved.get("league_changed", false)):
					text += "\n%s перешёл в лигу «%s»!" % [str(friendly.get("name", "")), str(moved.league_name)]
		if attention > 0 and score >= 1.0:
			# экзаменационные уровни (41-50) требуют победы без единого зевка
			if attention <= 40 or game_quality.get("blunder", 0) == 0:
				var was = Profile.attention_done
				Profile.complete_attention_level(attention)
				if Profile.attention_done > was:
					text += "\n\n👁 Уровень внимательности %d пройден! Открыт уровень %d." % [attention, mini(attention + 1, 50)]
					if Profile.attention_done >= 50:
						text += "\nВСЕ 50 УРОВНЕЙ ПРОЙДЕНЫ — у вас глаз-алмаз!"
				else:
					text += "\n\n👁 Уровень внимательности %d пройден (повторно)." % attention
			else:
				text += "\n\n👁 Победа, но на экзамене нельзя зевать (зевков: %d). Уровень не засчитан — ещё раз!" % game_quality.get("blunder", 0)
		if road.begins_with("focus_") and score >= 1.0:
			if _focus_condition_met():
				Profile.record_focus_stage_done(road)
				text += "\n\nОстановка «Дороги домой» пройдена! Ты справился со своей слабостью."
			else:
				text += "\n\nПобеда, но условие остановки не выполнено (%s). Попробуйте ещё раз!" % _focus_condition_text()
		elif road != "" and score >= 1.0:
			Profile.advance_road(Global.road_stage_playing)
			text += "\n\nЭтап «Дороги домой» пройден! Дорога зовёт дальше."
			if road == "predict" and predict_total > 0:
				text += "\nПредсказано ходов: %d из %d." % [predict_hits, predict_total]
		if not map_character.is_empty():
			if score >= 1.0:
				Profile.mark_character_defeated(map_character.id)
				if map_character.get("is_drill", false):
					text += "\n\nУрок пройден! Карта открыта дальше."
				else:
					text += "\n\n%s повержен(а)! Карта открыта дальше." % map_character.name
				gameover_label.text = text
				gameover_panel.visible = true
				_celebrate_character_defeat()
				_show_game_review(score)
				return
			elif map_character.get("is_drill", false):
				text += "\n\nНе получилось — попробуйте урок ещё раз!"
			else:
				text += "\n\nПопробуйте снова, чтобы победить %s." % map_character.name
	if school != "":
		text += _school_summary()
		map_button.visible = false
	gameover_label.text = text
	gameover_panel.visible = true
	_show_game_review(score)

# After any finished game, point at the single worst moment (biggest eval
# drop) and offer to replay from right before that move — a concrete lesson
# instead of a statistic. The wording adapts to the result.
func _show_game_review(score: float) -> void:
	if review_label == null or replay_button == null:
		return
	if score < 0.0 or worst_moments.is_empty():
		review_label.visible = false
		replay_button.visible = false
		return
	var worst = worst_moments[0]
	for m in worst_moments:
		if m.loss > worst.loss:
			worst = m
	var where: String
	if worst.loss >= 800.0:
		# losses this big are "missed a decisive tactic", counting pawns is silly
		where = "на ходу %d (%s) — он резко изменил оценку партии" % [worst.move_no, ChessEngine.ru_notation(str(worst.notation))]
	else:
		where = "на ходу %d (%s) — он потерял примерно %.1f пешки" % [worst.move_no, ChessEngine.ru_notation(str(worst.notation)), worst.loss / 100.0]
	if score < 0.5:
		review_label.text = "Разбор: партия сломалась %s. Попробуйте сыграть его иначе!" % where
	elif score < 1.0:
		review_label.text = "Разбор: ничья могла стать победой — самый слабый ход был %s. Посмотрите, как сыграть сильнее." % where
	else:
		review_label.text = "Разбор: победа! Но был шаткий момент %s. Хотите поизучать, как выиграть ещё чище?" % where
	review_label.visible = true
	replay_button.visible = true
	_append_better_move(worst)

# К разбору добавляем сам урок: какой ход был сильнее (считается в фоне, текст дописывается позже).
func _append_better_move(worst: Dictionary) -> void:
	if not worst.has("snapshot"):
		return
	var snap: ChessEngine = worst.snapshot.clone()
	var result := {"m": null}
	await Global.run_bg(func(): result.m = hint_ai.best_move_clean(snap, 3))
	if result.m == null or not is_instance_valid(review_label) or not review_label.visible:
		return
	var best_txt: String = ChessEngine.ru_notation(move_notation(snap, result.m))
	if best_txt == ChessEngine.ru_notation(str(worst.notation)):
		return
	review_label.text += "
Сильнее было: %s." % best_txt

func _on_replay_worst_pressed() -> void:
	if worst_moments.is_empty():
		return
	var worst = worst_moments[0]
	for m in worst_moments:
		if m.loss > worst.loss:
			worst = m
	engine = worst.snapshot.clone()
	move_history = move_history.slice(0, worst.hist_len)
	_refresh_history_label()
	# only moments from before the replay point are still relevant
	var kept: Array = []
	for m in worst_moments:
		if m.hist_len < worst.hist_len:
			kept.append(m)
	worst_moments = kept
	undo_stack = []
	selected_square = null
	legal_targets = []
	dragging = false
	pending_promotion = null
	game_over = false
	gameover_panel.visible = false
	review_label.visible = false
	replay_button.visible = false
	_clear_hint()
	if nudge_panel != null:
		nudge_panel.visible = false
	_update_undo_button()
	_update_status()
	_autosave_game()

# a bit of extra flourish when a map character is defeated: the panel border
# glows in the character's own region colour and the result text pulses,
# instead of the plain neutral game-over panel used for regular games.
func _celebrate_character_defeat() -> void:
	var accent: Color = map_character.palette.accent
	var sb: StyleBoxFlat = gameover_panel.get_theme_stylebox("panel").duplicate()
	sb.border_color = accent
	sb.border_width_left = 4
	sb.border_width_top = 4
	sb.border_width_right = 4
	sb.border_width_bottom = 4
	sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.5)
	sb.shadow_size = 22
	gameover_panel.add_theme_stylebox_override("panel", sb)
	gameover_label.add_theme_color_override("font_color", accent)
	gameover_label.pivot_offset = gameover_label.size / 2.0
	var tw = create_tween()
	tw.set_loops(3)
	tw.tween_property(gameover_label, "scale", Vector2(1.08, 1.08), 0.25).from(Vector2.ONE)
	tw.tween_property(gameover_label, "scale", Vector2.ONE, 0.25)

func _maybe_ai_move() -> void:
	if game_over:
		return
	match coop:
		"team":
			await _team_step()
		"duo":
			await _duo_step()
		"intervene":
			await _intervene_step()
		_:
			if engine.side_to_move != player_color:
				# predict stage: ask for the guess first, move only after it
				if road == "predict" and predict_guess == null and not awaiting_prediction:
					awaiting_prediction = true
					_show_speech("Куда пойдёт соперник? Кликните клетку с вашим предсказанием!", true)
					return
				await _ai_take_turn(ai)
				if school != "" and not game_over:
					_school_after_ai_move()
				if road == "predict" and predict_guess != null:
					predict_total += 1
					if engine.last_move != null and engine.last_move.to == predict_guess:
						predict_hits += 1
						_show_speech("🎯 Угадал! Предсказано %d из %d" % [predict_hits, predict_total], true)
					else:
						_show_speech("Он пошёл иначе. Предсказано %d из %d" % [predict_hits, predict_total], true)
					predict_guess = null
				if road == "xray":
					xray_turn_start = Time.get_ticks_msec()
				_maybe_show_nudge()

# One full AI move: think on a worker thread (UI never freezes), then animate
# and apply. Shared by the normal opponent, co-op partners and co-op rivals.
func _ai_take_turn(ai_inst: ChessAI, thinking_text: String = "ИИ думает...") -> void:
	ai_thinking = true
	status_label.text = thinking_text
	await get_tree().create_timer(0.25).timeout
	var engine_snapshot = engine.clone()
	var result := {"move": null}
	await Global.run_bg(func(): result.move = ai_inst.choose_move(engine_snapshot))
	await _apply_ai_move(result.move)

func _apply_ai_move(m) -> void:
	if game_over:
		# the clock (or another async path) already ended the game while this
		# move was being thought out on the worker thread — applying it now
		# would mutate the finished position and re-trigger the autosave
		# Profile.clear_game_state() already cleared in _show_game_over.
		ai_thinking = false
		return
	if m != null:
		var captured = engine.board[m.to.y][m.to.x] != null or m.get("is_ep", false)
		await _animate_move(m)
		if game_over:
			# the clock could still flag mid-animation (the tween itself awaits
			# real frames) — bail before touching engine state a second time
			ai_thinking = false
			return
		undo_stack.append(engine.clone())
		_record_move(m)
		var mover = engine.side_to_move
		engine.apply_move(m)
		_add_clock_increment(mover)
		_play_move_sfx(captured)
		attention_flash_ms = Time.get_ticks_msec()
	ai_thinking = false
	_update_undo_button()
	_update_status()
	_autosave_game()

# --- co-op: "папа и сын" — the player and an AI partner alternate White's
# moves against a team of two Black AIs that also alternate. Move parity is
# derived from move_history, so resuming a saved game keeps the rotation.
func _white_moves_made() -> int:
	return (move_history.size() + 1) / 2

func _black_moves_made() -> int:
	return move_history.size() / 2

func _team_step() -> void:
	if engine.side_to_move == "w":
		if _white_moves_made() % 2 == 1:
			await _ai_take_turn(partner_ai, "Напарник думает...")
			if not game_over:
				_maybe_ai_move()
		# even parity = the player's own move: wait for input
	else:
		var second = _black_moves_made() % 2 == 1
		var rival = opp_ai_b if second else opp_ai_a
		await _ai_take_turn(rival, "Соперник %d думает..." % (2 if second else 1))
		if not game_over:
			_maybe_ai_move()

# --- co-op: "папа и сын" (свободный матч) — both White moves are made by
# humans taking turns; only the Black AI pair is automated.
func _duo_step() -> void:
	if engine.side_to_move == "b":
		var second = _black_moves_made() % 2 == 1
		var rival = opp_ai_b if second else opp_ai_a
		await _ai_take_turn(rival, "Соперник %d думает..." % (2 if second else 1))
		# after the rivals' move it's always the humans' turn — nothing to chain

# --- co-op: "помощь другу" — a weak ally AI plays White on its own, but
# when its intended move loses serious material the game pauses and the
# player must step in and find a better move themselves.
func _intervene_step() -> void:
	if engine.side_to_move == "b":
		await _ai_take_turn(opp_ai_a, "Соперник думает...")
		if not game_over:
			_maybe_ai_move()
		return
	if intervention_active:
		return # waiting for the player's rescue move
	ai_thinking = true
	status_label.text = "Ваш друг думает..."
	var engine_snapshot = engine.clone()
	var result := {"move": null, "loss": 0.0}
	await Global.run_bg(func():
		result.move = ally_ai.choose_move(engine_snapshot)
		if result.move != null:
			result.loss = hint_ai.move_loss(engine_snapshot, result.move, 3))
	if result.move == null:
		ai_thinking = false
		_update_status()
		return
	if result.loss > 150.0:
		ai_thinking = false
		intervention_active = true
		_update_status()
		_show_speech("Ваш друг растерялся и чуть не зевнул! Найдите за него сильный ход.", true)
		return
	await _apply_ai_move(result.move)
	if not game_over:
		_maybe_ai_move()

# "Тень": an AI twin of the player — level picked from their Glicko rating,
# blunder chance taken from their real journal stats (bonus levels for the
# final stage). Beating your own shadow is the honest exam.
func _make_shadow_ai(bonus: int) -> ChessAI:
	var shadow = ChessAI.new(clampi(Global.rating_level() + bonus, 1, 25))
	var total = Profile.move_good + Profile.move_inaccuracy + Profile.move_mistake + Profile.move_blunder
	if total >= 20 and bonus == 0:
		# the twin blunders exactly as often as its human original
		shadow.custom_blunder = clampf(float(Profile.move_blunder) / float(total), 0.0, 0.35)
	return shadow

# ======================= ШКОЛА ЮНОГО ШАХМАТИСТА =======================

# Вызывается сразу после хода ИИ. "spot": прячем фигуры на мгновение и ждём
# клик-ответ. "patience": запираем ход на паузу для обдумывания.
func _school_after_ai_move() -> void:
	turn_started_ms = Time.get_ticks_msec()
	if school == "spot":
		awaiting_spot = true
		spot_total += 1
		spot_tries_left = SPOT_TRIES
		spot_flash_until = Time.get_ticks_msec() + SPOT_FLASH_MS
		_show_speech("✨ Фигуры спрятались! Куда сходил соперник? Нажми на клетку.", true)
		board_draw.queue_redraw()
	elif school == "patience":
		patience_unlock_ms = Time.get_ticks_msec() + patience_lock_ms

func _spot_flash_active() -> bool:
	return school == "spot" and Time.get_ticks_msec() < spot_flash_until

# Пока идёт вопрос «куда сходил соперник?», подсветку и стрелку последнего
# хода рисовать нельзя — иначе ответ виден на доске.
func _spot_hide_last_move() -> bool:
	return school == "spot" and awaiting_spot

func _school_process() -> void:
	if school == "" or game_over:
		return
	# вспышка «исчезающих фигур»: перерисовываем, пока она идёт (+1 кадр после)
	if school == "spot" and spot_flash_until > 0 and Time.get_ticks_msec() < spot_flash_until + 100:
		board_draw.queue_redraw()
	# обратный отсчёт паузы в «Школе терпения»
	if school == "patience" and not ai_thinking and engine != null and engine.side_to_move == player_color and pending_promotion == null:
		var left = patience_unlock_ms - Time.get_ticks_msec()
		if left > 0:
			status_label.text = "🐢 Думаем… ход откроется через %d с. Что грозит? Кто под боем?" % ceili(left / 1000.0)
		elif left > -300:
			_update_status()
			if wisdom_streak > 0:
				status_label.text += "  · серия мудрости: ⭐×%d" % wisdom_streak

# Клик в режиме «Что изменилось?»: проверяем, угадал ли ребёнок клетку,
# куда сходил соперник. Возвращает true, если клик обработан здесь.
func _spot_handle_click(sq) -> void:
	if sq == null or engine.last_move == null:
		return
	if Time.get_ticks_msec() < spot_flash_until:
		return # фигуры ещё спрятаны — ждём конца вспышки
	if sq == engine.last_move.to:
		spot_hits += 1
		awaiting_spot = false
		_show_speech("🎯 Точно! Найдено ходов: %d из %d. Теперь твой ход." % [spot_hits, spot_total], true)
		board_draw.queue_redraw()
		return
	spot_tries_left -= 1
	if spot_tries_left > 0:
		_show_speech("Не тут. Посмотри ещё раз — куда сходил соперник? (осталась %d попытка)" % spot_tries_left, true)
	else:
		awaiting_spot = false
		_show_speech("Вот его ход — смотри на стрелку! Найдено: %d из %d. Твой ход." % [spot_hits, spot_total], true)
		board_draw.queue_redraw()

# Начисление «очков мудрости» при собственном ходе в «Школе терпения».
func _school_on_player_move() -> void:
	if school != "patience":
		return
	var thought_s = (Time.get_ticks_msec() - turn_started_ms) / 1000.0
	if thought_s >= patience_lock_ms / 1000.0 + 3.0:
		wisdom_streak += 1
		wisdom_stars += wisdom_streak # длинная серия даёт всё больше очков
		_show_speech("⭐ Обдуманный ход! Серия ×%d, очков мудрости: %d" % [wisdom_streak, wisdom_stars], true)

# Шёпот тренера + сгорание серии на зевке (вызывается из анализа качества).
func _school_on_move_quality(category: String) -> void:
	if school != "patience":
		return
	# движок проверяет ход поиском всего на несколько ходов вперёд, поэтому
	# может ошибаться — формулировка честно это отражает, а не заявляет
	# зевок как доказанный факт
	if category == "blunder":
		if wisdom_streak > 0:
			_show_speech("💥 Похоже на серьёзную неточность — движок нашёл ход заметно сильнее. Серия мудрости сгорела (было ⭐×%d). Не факт, что это правда ошибка — но стоит перепроверить: можно нажать «Отменить ход»." % wisdom_streak, true)
		else:
			_show_speech("💥 Похоже на серьёзную неточность — движок думает, что был ход заметно сильнее. Проверь: не подвисла ли фигура? Если хочешь — нажми «Отменить ход» и попробуй ещё раз.", true)
		wisdom_streak = 0
	elif category == "mistake":
		_show_speech("⚠ Возможно, ход не лучший — движок видит вариант получше. Посмотри ещё раз, кто под боем.", true)

# Итоговая строка школы для экрана окончания партии + сохранение рекордов.
func _school_summary() -> String:
	if school == "spot":
		var txt = "\n\n🔍 Найдено ходов соперника: %d из %d." % [spot_hits, spot_total]
		if spot_hits > Profile.school_spot_record:
			Profile.school_spot_record = spot_hits
			Profile.save_profile()
			txt += " 🏆 Новый рекорд!"
		return txt
	if school == "patience":
		var txt = "\n\n🐢 Очков мудрости: %d." % wisdom_stars
		if wisdom_stars > Profile.school_wisdom_record:
			Profile.school_wisdom_record = wisdom_stars
			Profile.save_profile()
			txt += " 🏆 Новый рекорд!"
		return txt
	return ""

func _process(_delta: float) -> void:
	_tick_clock(_delta)
	# режим "flash": маркеры угроз гаснут через 5 секунд — перерисовываем,
	# пока окно подсказки открыто (и один кадр после, чтобы их спрятать)
	if attention > 0 and Global.attention_hint_mode(attention) == "flash":
		if Time.get_ticks_msec() - attention_flash_ms < 5600:
			board_draw.queue_redraw()
	_school_process()
	# xray stage: hide the pieces in fog once the player thinks too long
	if road != "xray" or game_over or ai_thinking or xray_fog:
		return
	if engine == null or engine.side_to_move != player_color or pending_promotion != null:
		return
	if Time.get_ticks_msec() - xray_turn_start > 12000:
		xray_fog = true
		_show_speech("Туман опустился! Сделайте ход по памяти.", true)
		board_draw.queue_redraw()

# --- tournament chess clock ---

func _tick_clock(delta: float) -> void:
	if not clock_running or game_over or pending_promotion != null:
		return
	if engine.side_to_move == "w":
		clock_white -= delta
	else:
		clock_black -= delta
	_update_clock_label()
	if clock_white <= 0.0 or clock_black <= 0.0:
		clock_running = false
		var flagged_white = clock_white <= 0.0
		var winner = "Чёрные" if flagged_white else "Белые"
		var score = 1.0 if winner == _player_color_name() else 0.0
		status_label.text = "Время вышло! Победили: " + winner
		_show_game_over("Флаг упал — время вышло! %s победили по времени." % winner, score)

# increment is added to the clock of the side that just completed a move
func _add_clock_increment(mover: String) -> void:
	if not clock_running or clock_increment <= 0.0:
		return
	if mover == "w":
		clock_white += clock_increment
	else:
		clock_black += clock_increment
	_update_clock_label()

func _update_clock_label() -> void:
	if clock_label == null:
		return
	var mine = clock_white if player_color == "w" else clock_black
	var theirs = clock_black if player_color == "w" else clock_white
	clock_label.text = "⏱ Вы: %s   ·   Соперник: %s" % [_fmt_clock(mine), _fmt_clock(theirs)]
	# turn red when the player is under 30 seconds
	clock_label.add_theme_color_override("font_color",
		Color(1.0, 0.35, 0.35) if mine < 30.0 else Color(0.95, 0.8, 0.35))

func _fmt_clock(t: float) -> String:
	var s = maxi(int(ceil(t)), 0)
	return "%d:%02d" % [s / 60, s % 60]

# true when a click on the board should be treated as the player's move
func _player_turn_now() -> bool:
	if engine.side_to_move != player_color:
		return false
	match coop:
		"team":
			return _white_moves_made() % 2 == 0
		"duo":
			return true # both White moves are human moves
		"intervene":
			return intervention_active
		_:
			return true

# After the AI moves, if the player's position looks notably worse than a
# pawn's worth, offer a dismissible nudge suggesting they use a hint —
# so the player doesn't get stuck grinding a lost position unnoticed.
func _maybe_show_nudge() -> void:
	if game_over or nudge_panel == null or coop != "" or not tournament.is_empty():
		return
	var eval_white = hint_ai.evaluate_position(engine)
	var player_eval = eval_white if player_color == "w" else -eval_white
	nudge_panel.visible = player_eval < -220.0

func _animate_move(m: Dictionary) -> void:
	var piece = engine.board[m.from.y][m.from.x]
	if piece == null:
		return
	anim_piece = piece
	anim_from = m.from
	anim_to = m.to
	anim_t = 0.0
	anim_active = true
	var tw = create_tween()
	tw.tween_method(func(t): anim_t = t; board_draw.queue_redraw(), 0.0, 1.0, 0.18)
	await tw.finished
	anim_active = false

func _clear_hint() -> void:
	hint_from = null
	hint_to = null
	hint_label.text = ""
	board_draw.queue_redraw()

func _on_hint_pressed() -> void:
	if game_over or ai_thinking or engine.side_to_move != player_color:
		return
	nudge_panel.visible = false
	ai_thinking = true
	hint_button.disabled = true
	var result := {"move": null}
	var hint_snapshot = engine.clone() # поток не должен трогать живую позицию
	await Global.run_bg(func(): result.move = hint_ai.best_move_clean(hint_snapshot, 3))
	ai_thinking = false
	hint_button.disabled = false
	var m = result.move
	if m == null:
		return
	help_hints += 1
	hint_from = m.from
	hint_to = m.to
	var piece_names = {"P": "Пешкой", "N": "Конём", "B": "Слоном", "R": "Ладьёй", "Q": "Ферзём", "K": "Королём"}
	var p = engine.board[m.from.y][m.from.x]
	hint_label.text = "Подсказка: %s %s → %s" % [piece_names.get(p.type, ""), ChessEngine.square_name(m.from.x, m.from.y), ChessEngine.square_name(m.to.x, m.to.y)]
	board_draw.queue_redraw()

func _update_undo_button() -> void:
	# undo would break the move rotation in co-op modes, so it's off there
	undo_button.disabled = undo_stack.size() < 2 or ai_thinking or pending_promotion != null or coop != ""
	# Resign/Menu would pop LeavePanel/GameOverPanel on top of the still-open
	# PromoPanel otherwise — greyed out until the player picks a piece.
	resign_button.disabled = pending_promotion != null
	menu_button.disabled = pending_promotion != null

func _on_undo_pressed() -> void:
	if ai_thinking or pending_promotion != null or undo_stack.size() < 2:
		return
	if awaiting_spot:
		# откат хода снимает вопрос «куда сходил соперник?» — ход исчез
		awaiting_spot = false
		spot_total = maxi(spot_total - 1, 0)
		if speech_panel != null:
			speech_panel.visible = false
	help_undos += 1
	undo_stack.pop_back() # discard the AI's pre-move snapshot
	engine = undo_stack.pop_back() # restore to right before the player's own move
	if move_history.size() > 0:
		move_history.pop_back()
	if move_history.size() > 0:
		move_history.pop_back()
	_refresh_history_label()
	# drop review moments that point past the undone move
	var kept: Array = []
	for m in worst_moments:
		if m.hist_len < move_history.size():
			kept.append(m)
	worst_moments = kept
	selected_square = null
	legal_targets = []
	dragging = false
	game_over = false
	gameover_panel.visible = false
	_clear_hint()
	nudge_panel.visible = false
	_update_undo_button()
	_update_status()
	_autosave_game()

func _on_nudge_dismiss_pressed() -> void:
	nudge_panel.visible = false

func _on_nudge_hint_pressed() -> void:
	_on_hint_pressed()

# Псевдо-SAN из позиции ДО хода: "Ng1-f3", "e2xd3", "O-O", "e7-e8=Q".
# Раньше эта логика жила только внутри _record_move, а разбор качества
# хода строил свою, голую нотацию вида "e2e4" — без "x", "=" и "O-O".
# Из-за этого галерея лучших ходов в дневнике никогда не пополнялась:
# Profile.record_move_quality отбирает туда именно взятия/превращения/рокировки
# по этим самым символам. Теперь оба места зовут одну функцию.
static func move_notation(state: ChessEngine, m: Dictionary) -> String:
	if m.get("is_castle", "") == "K":
		return "O-O"
	if m.get("is_castle", "") == "Q":
		return "O-O-O"
	var from: Vector2i = m.from
	var to: Vector2i = m.to
	var p = state.board[from.y][from.x]
	if p == null:
		return ChessEngine.square_name(from.x, from.y) + "-" + ChessEngine.square_name(to.x, to.y)
	var names = {"P":"", "N":"N", "B":"B", "R":"R", "Q":"Q", "K":"K"}
	var cap = state.board[to.y][to.x] != null or m.get("is_ep", false)
	var txt = names[p.type] + ChessEngine.square_name(from.x, from.y) + ("x" if cap else "-") + ChessEngine.square_name(to.x, to.y)
	if m.get("promo", "") != "":
		txt += "=" + m.promo
	return txt

# Координатная запись хода: "e2e4", с буквой фигуры при превращении ("e7e8Q").
static func move_coord(m: Dictionary) -> String:
	var txt = ChessEngine.square_name(m.from.x, m.from.y) + ChessEngine.square_name(m.to.x, m.to.y)
	if str(m.get("promo", "")) != "":
		txt += str(m.promo)
	return txt

func _record_move(m: Dictionary) -> void:
	move_history.append(move_notation(engine, m))
	move_coords.append(move_coord(m))
	_refresh_history_label()

func _refresh_history_label() -> void:
	var lines := []
	var i = 0
	while i < move_history.size():
		var num = i / 2 + 1
		var white_m = ChessEngine.ru_notation(move_history[i])
		var black_m = ChessEngine.ru_notation(move_history[i + 1]) if i + 1 < move_history.size() else ""
		lines.append(str(num) + ". " + white_m + "  " + black_m)
		i += 2
	history_label.text = "\n".join(lines)
	history_label.scroll_to_line(max(0, lines.size() - 1))

func _unhandled_input(event: InputEvent) -> void:
	if game_over or ai_thinking:
		return
	if awaiting_prediction:
		# predict stage: this click is the guess, not a move
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var glocal = board_draw.get_global_transform().affine_inverse() * event.position
			var gsq = _pixel_to_square(glocal)
			if gsq != null:
				predict_guess = gsq
				awaiting_prediction = false
				if speech_panel != null:
					speech_panel.visible = false
				_maybe_ai_move()
		return
	if awaiting_spot:
		# «Что изменилось?»: клик — это ответ на вопрос, а не ход
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var slocal = board_draw.get_global_transform().affine_inverse() * event.position
			_spot_handle_click(_pixel_to_square(slocal))
		return
	if school == "patience" and Time.get_ticks_msec() < patience_unlock_ms:
		return # «Школа терпения»: пауза ещё идёт — фигуры пока заперты
	if not _player_turn_now():
		return
	if pending_promotion != null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var local = board_draw.get_global_transform().affine_inverse() * event.position
		if event.pressed:
			var sq = _pixel_to_square(local)
			if sq == null:
				return
			_handle_press(sq, local)
		else:
			if dragging:
				var sq = _pixel_to_square(local)
				_handle_release(sq)
	elif event is InputEventMouseMotion and dragging:
		var local = board_draw.get_global_transform().affine_inverse() * event.position
		drag_pos = local
		board_draw.queue_redraw()

func _pixel_to_square(pos: Vector2):
	var rel = pos - BOARD_ORIGIN
	if rel.x < 0 or rel.y < 0:
		return null
	var f = int(rel.x / SQUARE)
	var r_disp = int(rel.y / SQUARE)
	if f < 0 or f > 7 or r_disp < 0 or r_disp > 7:
		return null
	var r = 7 - r_disp if player_color == "w" else r_disp
	var ff = f if player_color == "w" else 7 - f
	return Vector2i(ff, r)

func _handle_press(sq: Vector2i, local: Vector2) -> void:
	var p = engine.board[sq.y][sq.x]
	if selected_square != null:
		var move = _find_move(selected_square, sq)
		if move != null:
			dragging = false
			_apply_move_maybe_promotion(move)
			board_draw.queue_redraw()
			return
		if p != null and p.color == engine.side_to_move:
			selected_square = sq
			legal_targets = engine.legal_moves_for_square(sq.x, sq.y)
			dragging = true
			drag_from = sq
			drag_pos = local
		else:
			selected_square = null
			legal_targets = []
			dragging = false
	else:
		if p != null and p.color == engine.side_to_move:
			selected_square = sq
			legal_targets = engine.legal_moves_for_square(sq.x, sq.y)
			dragging = true
			drag_from = sq
			drag_pos = local
	board_draw.queue_redraw()

func _handle_release(sq) -> void:
	dragging = false
	if sq == null or drag_from == null or sq == drag_from:
		board_draw.queue_redraw()
		return
	var move = _find_move(drag_from, sq)
	if move != null:
		_apply_move_maybe_promotion(move)
	board_draw.queue_redraw()

func _apply_move_maybe_promotion(move: Dictionary) -> void:
	_clear_hint()
	if nudge_panel != null:
		nudge_panel.visible = false
	if coop == "intervene" and intervention_active:
		intervention_active = false
		if speech_panel != null:
			speech_panel.visible = false
	if road == "xray" and xray_fog:
		xray_fog = false
		if speech_panel != null:
			speech_panel.visible = false
	if _is_promotion_move(move):
		pending_promotion = move
		selected_square = null
		legal_targets = []
		_show_promotion_panel()
		return
	var pre_move_state = engine.clone()
	undo_stack.append(pre_move_state)
	var captured = engine.board[move.to.y][move.to.x] != null or move.get("is_ep", false)
	_record_move(move)
	var mover = engine.side_to_move
	engine.apply_move(move)
	_add_clock_increment(mover)
	selected_square = null
	legal_targets = []
	_update_undo_button()
	_update_status()
	_play_move_sfx(captured)
	_autosave_game()
	_school_on_player_move()
	_analyze_move_quality(pre_move_state, move)
	_maybe_ai_move()

# Compares the player's chosen move against the engine's own best move in
# this position and logs it for the Дневник (Journal). Best-effort coaching
# signal, not a strict correctness check.
func _analyze_move_quality(pre_move_state: ChessEngine, move: Dictionary) -> void:
	# Snapshot move_history's length NOW, synchronously — the analysis below
	# awaits a frame and then a background thread, and by the time it
	# finishes the AI (or the player, or another _analyze_move_quality call)
	# may well have appended further moves. Reading move_history.size() only
	# after the await would then record the wrong ply for this move.
	var hist_len := maxi(move_history.size() - 1, 0)
	# waits a frame so the board redraws (the piece visibly lands), then runs
	# the heavy search on a worker thread so it never freezes the UI.
	await get_tree().process_frame
	# «Школа терпения» показывает "Зевок!" прямо в лицо ребёнку, поэтому там
	# оправдан более глубокий (и более надёжный) поиск, чем для фонового
	# журналирования обычной игры — здесь это не замедляет саму партию: ход
	# уже применён, а анализ работает в фоновом потоке независимо от неё.
	var depth = 5 if school == "patience" else 3
	var result := {"loss": 0.0}
	await Global.run_bg(func(): result.loss = hint_ai.move_loss(pre_move_state, move, depth))
	var loss = result.loss
	var category = ChessAI.quality_category(loss)
	var fen = pre_move_state.to_fen()
	var notation = move_notation(pre_move_state, move)
	Profile.record_move_quality(category, loss, fen, notation)
	game_quality[category] = int(game_quality.get(category, 0)) + 1
	_school_on_move_quality(category)
	if loss > ChessAI.LOSS_MISTAKE:
		worst_moments.append({
			"snapshot": pre_move_state.clone(),
			"loss": loss,
			"notation": notation,
			"move_no": pre_move_state.fullmove_number,
			"hist_len": hist_len,
		})

func _is_promotion_move(move: Dictionary) -> bool:
	return move.get("promo", "") != ""

func _find_move(from: Vector2i, to: Vector2i):
	for m in legal_targets:
		if m.from == from and m.to == to:
			return m
	return null

func _show_promotion_panel() -> void:
	promo_panel.visible = true
	_update_undo_button()

func _on_promotion_chosen(piece_type: String) -> void:
	if pending_promotion == null:
		return
	pending_promotion["promo"] = piece_type
	var pre_move_state = engine.clone()
	undo_stack.append(pre_move_state)
	var captured = engine.board[pending_promotion.to.y][pending_promotion.to.x] != null
	_record_move(pending_promotion)
	var mover = engine.side_to_move
	engine.apply_move(pending_promotion)
	_add_clock_increment(mover)
	_analyze_move_quality(pre_move_state, pending_promotion)
	pending_promotion = null
	selected_square = null
	legal_targets = []
	promo_panel.visible = false
	_update_undo_button()
	_update_status()
	_play_move_sfx(captured)
	_autosave_game()
	_maybe_ai_move()

func _on_board_draw() -> void:
	# squares
	for r in range(8):
		for f in range(8):
			var disp_f = f if player_color == "w" else 7 - f
			var disp_r = 7 - r if player_color == "w" else r
			var pos = BOARD_ORIGIN + Vector2(disp_f * SQUARE, disp_r * SQUARE)
			Themes.draw_square(board_draw, Rect2(pos, Vector2(SQUARE, SQUARE)), (f + r) % 2 == 1, r * 8 + f)

	# last move highlight (спрятана, пока в «Что изменилось?» идёт вопрос —
	# иначе ответ виден прямо на доске)
	if engine.last_move != null and not _spot_hide_last_move():
		for sqv in [engine.last_move.from, engine.last_move.to]:
			var pos = _square_to_pixel(sqv)
			board_draw.draw_rect(Rect2(pos, Vector2(SQUARE, SQUARE)), Themes.hl_last(), true)
		# an arrow makes the AI's move easier to spot at a glance than the
		# highlight alone, especially for kids scanning the board quickly
		if engine.last_move.piece.color != player_color:
			_draw_last_move_arrow(engine.last_move.from, engine.last_move.to)

	# check highlight
	if engine.is_in_check(engine.side_to_move):
		var k = engine.find_king(engine.side_to_move)
		if k.x >= 0:
			var pos = _square_to_pixel(k)
			board_draw.draw_rect(Rect2(pos, Vector2(SQUARE, SQUARE)), Themes.hl_check(), true)

	# hint highlight
	if hint_from != null and hint_to != null:
		board_draw.draw_rect(Rect2(_square_to_pixel(hint_from), Vector2(SQUARE, SQUARE)), Themes.hl_hint(), true)
		board_draw.draw_rect(Rect2(_square_to_pixel(hint_to), Vector2(SQUARE, SQUARE)), Themes.hl_hint(), true)

	# selection + legal targets
	if selected_square != null:
		var pos = _square_to_pixel(selected_square)
		board_draw.draw_rect(Rect2(pos, Vector2(SQUARE, SQUARE)), Themes.hl_select(), true)
		for m in legal_targets:
			var tpos = _square_to_pixel(m.to)
			var center = tpos + Vector2(SQUARE, SQUARE) / 2
			var is_capture = engine.board[m.to.y][m.to.x] != null or m.get("is_ep", false)
			if is_capture:
				board_draw.draw_arc(center, SQUARE * 0.42, 0, TAU, 24, Themes.capture_ring(), 5.0, true)
			else:
				board_draw.draw_circle(center, SQUARE * 0.15, Themes.move_dot())

	# coordinates
	# буквы — в нижнем ряду справа, цифры — в левом столбце сверху; цвет — противоположной клетки
	var font = Themes.font_bold()
	for i in range(8):
		var file_char = "abcdefgh"[i if player_color == "w" else 7 - i]
		var fp = BOARD_ORIGIN + Vector2(i * SQUARE + SQUARE - 13, 8 * SQUARE - 5)
		board_draw.draw_string(font, fp, file_char, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Themes.coord_color(i % 2 == 1))
		var rank_char = str(8 - i if player_color == "w" else i + 1)
		var rp = BOARD_ORIGIN + Vector2(4, i * SQUARE + 16)
		board_draw.draw_string(font, rp, rank_char, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Themes.coord_color(i % 2 == 0))

	# pieces — hidden entirely while the xray fog is down (move from memory!)
	# or during the «Что изменилось?» vanish-flash right after the AI's move
	var spot_flash = _spot_flash_active()
	if xray_fog:
		var fog_font = ThemeDB.fallback_font
		board_draw.draw_string(fog_font, BOARD_ORIGIN + Vector2(60, 4 * SQUARE), "☁  ТУМАН — ходите по памяти!  ☁", HORIZONTAL_ALIGNMENT_CENTER, int(8 * SQUARE - 120), 26, Themes.ink(Color(0.85, 0.92, 1.0, 0.9)))
	elif spot_flash:
		var flash_font = ThemeDB.fallback_font
		board_draw.draw_string(flash_font, BOARD_ORIGIN + Vector2(60, 4 * SQUARE), "✨  Куда сходил соперник?  ✨", HORIZONTAL_ALIGNMENT_CENTER, int(8 * SQUARE - 120), 26, Themes.ink(Color(1.0, 0.9, 0.5, 0.95)))
	for r in range(8):
		for f in range(8):
			if xray_fog or spot_flash:
				continue
			var p = engine.board[r][f]
			if p == null:
				continue
			if dragging and drag_from != null and drag_from.x == f and drag_from.y == r:
				continue
			if anim_active and anim_from.x == f and anim_from.y == r:
				continue
			var pos = _square_to_pixel(Vector2i(f, r))
			var center = pos + Vector2(SQUARE, SQUARE) / 2
			PieceTextures.draw(board_draw, p.type, p.color, center, SQUARE * 0.92)

	# «Внимательность»: маркеры угроз — маленькие точки в углу клетки,
	# чтобы не заслонять фигуры. Красная — ваша фигура под боем, зелёная —
	# фигура соперника под вашим ударом.
	if attention > 0 and not xray_fog and not game_over:
		var mode = Global.attention_hint_mode(attention)
		if mode == "flash" and Time.get_ticks_msec() - attention_flash_ms > 5000:
			mode = "none"
		if mode != "none":
			var show_red = mode == "both" or mode == "red" or mode == "flash"
			var show_green = mode == "both" or mode == "green" or mode == "flash"
			var opp = "b" if player_color == "w" else "w"
			for r in range(8):
				for f in range(8):
					var p = engine.board[r][f]
					if p == null:
						continue
					var pos = _square_to_pixel(Vector2i(f, r))
					if p.color == player_color and show_red and engine.is_square_attacked(f, r, opp):
						var c = pos + Vector2(SQUARE - 12, 12)
						# красный ТРЕУГОЛЬНИК: форма отличается от зелёного ромба — не только цветом (дальтонизм)
						var tri := PackedVector2Array([c + Vector2(0, -10), c + Vector2(9.5, 7), c + Vector2(-9.5, 7)])
						board_draw.draw_colored_polygon(tri, Themes.ink(Color(1.0, 0.25, 0.25, 0.95)))
						board_draw.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Themes.ink(Color(1, 1, 1, 0.85)), 1.5)
					elif p.color == opp and show_green and engine.is_square_attacked(f, r, player_color):
						var c = pos + Vector2(SQUARE - 12, 12)
						# зелёный РОМБ
						var dia := PackedVector2Array([c + Vector2(0, -9), c + Vector2(9, 0), c + Vector2(0, 9), c + Vector2(-9, 0)])
						board_draw.draw_colored_polygon(dia, Themes.ink(Color(0.25, 0.95, 0.4, 0.95)))
						board_draw.draw_polyline(PackedVector2Array([dia[0], dia[1], dia[2], dia[3], dia[0]]), Themes.ink(Color(1, 1, 1, 0.85)), 1.5)

	# dragged piece follows the cursor, drawn on top
	if dragging and drag_from != null and not xray_fog:
		var dp = engine.board[drag_from.y][drag_from.x]
		if dp != null:
			PieceTextures.draw(board_draw, dp.type, dp.color, drag_pos, SQUARE * 1.0)

	# AI's move slides visibly from -> to instead of teleporting
	if anim_active:
		var from_px = _square_to_pixel(anim_from) + Vector2(SQUARE, SQUARE) / 2
		var to_px = _square_to_pixel(anim_to) + Vector2(SQUARE, SQUARE) / 2
		var anim_pos = from_px.lerp(to_px, anim_t)
		PieceTextures.draw(board_draw, anim_piece.type, anim_piece.color, anim_pos, SQUARE * 0.92)

func _draw_last_move_arrow(from: Vector2i, to: Vector2i) -> void:
	var a = _square_to_pixel(from) + Vector2(SQUARE, SQUARE) / 2
	var b = _square_to_pixel(to) + Vector2(SQUARE, SQUARE) / 2
	var dir = (b - a).normalized()
	if dir == Vector2.ZERO:
		return
	var head_len = SQUARE * 0.28
	var shaft_end = b - dir * head_len * 0.7
	var col = Themes.ink(Color(1.0, 0.7, 0.15, 0.75))
	board_draw.draw_line(a, shaft_end, col, 5.0, true)
	var perp = Vector2(-dir.y, dir.x)
	var p1 = b - dir * head_len + perp * head_len * 0.5
	var p2 = b - dir * head_len - perp * head_len * 0.5
	board_draw.draw_colored_polygon(PackedVector2Array([b, p1, p2]), col)

func _square_to_pixel(sq: Vector2i) -> Vector2:
	var disp_f = sq.x if player_color == "w" else 7 - sq.x
	var disp_r = 7 - sq.y if player_color == "w" else sq.y
	return BOARD_ORIGIN + Vector2(disp_f * SQUARE, disp_r * SQUARE)

func _on_resign_pressed() -> void:
	if game_over or pending_promotion != null:
		return
	_ask_confirm("resign", "Сдаться?", "Партия будет засчитана как поражение. Сдаться?", "Сдаться")

func _on_restart_pressed() -> void:
	# пустую партию стирать не жалко — спрашиваем, только если уже были ходы
	if game_over or move_coords.is_empty():
		_do_restart()
		return
	_ask_confirm("restart", "Начать заново?", "Текущая партия будет потеряна без результата. Начать заново?", "Начать заново")

func _do_restart() -> void:
	Profile.clear_game_state()
	get_tree().reload_current_scene()

func _on_menu_pressed() -> void:
	_leave_or_confirm("menu")

func _on_map_pressed() -> void:
	_leave_or_confirm("map")

# Кнопка выхода ведёт не в главное меню, а в тот хаб, откуда пришли
# (дорога/школа/турнир/внимательность). Раньше она во всех режимах была
# подписана «В меню» и обманывала — теперь надпись совпадает с назначением.
func _exit_destination_label() -> String:
	if not tournament.is_empty():
		return "К подготовке" if tournament.get("practice", false) else "К турниру"
	if road != "":
		return "К дороге"
	if school != "":
		return "К школе"
	if attention > 0:
		return "К уровням"
	if not friendly.is_empty():
		return "К базе игроков"
	return "В меню"

func _update_exit_labels() -> void:
	var txt = _exit_destination_label()
	menu_button.text = txt
	gameover_menu_button.text = txt

func _leave_or_confirm(target: String) -> void:
	if pending_promotion != null:
		return
	if game_over:
		_do_leave(target)
		return
	_ask_confirm(target)

# Одна панель подтверждения на все опасные действия (выход, «Сдаться», «Заново»).
# Тексты по умолчанию запоминаем при первом показе — турнирный режим подменяет вопрос заранее.
func _ask_confirm(target: String, title: String = "", question: String = "", yes_text: String = "") -> void:
	var t_lbl = get_node_or_null("UI/LeavePanel/VBox/TitleLabel")
	var q_lbl = get_node_or_null("UI/LeavePanel/VBox/QuestionLabel")
	var y_btn = get_node_or_null("UI/LeavePanel/VBox/HBox/LeaveButton")
	if _leave_defaults.is_empty():
		_leave_defaults = {
			"title": t_lbl.text if t_lbl != null else "",
			"question": q_lbl.text if q_lbl != null else "",
			"yes": y_btn.text if y_btn != null else "",
		}
	if t_lbl != null:
		t_lbl.text = title if title != "" else _leave_defaults.title
	if q_lbl != null:
		q_lbl.text = question if question != "" else _leave_defaults.question
	if y_btn != null:
		y_btn.text = yes_text if yes_text != "" else _leave_defaults.yes
	pending_leave_target = target
	leave_panel.visible = true

func _on_leave_confirmed() -> void:
	match pending_leave_target:
		"resign":
			leave_panel.visible = false
			if not game_over:
				_show_game_over("Вы сдались.", 0.0)
		"restart":
			_do_restart()
		_:
			_do_leave(pending_leave_target)

func _on_leave_cancel() -> void:
	leave_panel.visible = false

func _do_leave(target: String) -> void:
	if not tournament.is_empty():
		# leaving an unfinished tournament game counts as losing the round —
		# otherwise quitting bad positions would be free rating protection
		var practice = tournament.get("practice", false)
		if not game_over:
			if practice:
				Profile.finish_prep_round(tournament.tid, tournament.opp_idx, 0.0)
			else:
				Profile.record_tournament_game(tournament.level, 0.0)
				Profile.finish_tournament_round(tournament.tid, tournament.opp_idx, 0.0)
		Global.tournament_game = {}
		var target_scene = "res://scenes/TournamentPrep.tscn" if practice else "res://scenes/Tournaments.tscn"
		get_tree().change_scene_to_file(target_scene)
		return
	Global.map_character_id = ""
	Global.map_assist = false
	Global.coop_team = false
	var was_road = Global.road_mode != ""
	Global.road_mode = ""
	Global.road_stage_playing = -1
	if was_road:
		get_tree().change_scene_to_file("res://scenes/RoadHome.tscn")
		return
	if Global.school_mode != "":
		Global.school_mode = ""
		get_tree().change_scene_to_file("res://scenes/School.tscn")
		return
	if attention > 0:
		# уровни внимательности проходятся подряд — возвращаемся к списку
		# уровней, а не в главное меню (как это делают дорога и школа)
		Global.attention_level = 0
		get_tree().change_scene_to_file("res://scenes/AttentionHub.tscn")
		return
	if not friendly.is_empty():
		Global.friendly_game = {}
		get_tree().change_scene_to_file("res://scenes/BotsHub.tscn")
		return
	var scene = "res://scenes/Map.tscn" if target == "map" else "res://scenes/Menu.tscn"
	if scene.ends_with("Menu.tscn"):
		Global.menu_panel = "play" # быстрая партия закончилась — возвращаем в подменю «Играть»
	get_tree().change_scene_to_file(scene)

# Партии игрока против бота — ЕДИНСТВЕННЫЕ партии с ботами, которые уже
# сыграны по-настоящему и имеют ходы (симуляция тура ходов не даёт).
# Кладём их в архив соперника, чтобы к нему можно было готовиться.
func _archive_bot_game(score: float) -> void:
	var bot_id := ""
	var bot_name := ""
	var event := ""
	if not tournament.is_empty():
		var idx = int(tournament.get("opp_idx", -1))
		var st: Dictionary = Profile.active_tournament_prep.get(tournament.tid, {}) if tournament.get("practice", false) else Profile.active_tournaments.get(tournament.tid, {})
		if not st.is_empty() and idx >= 0 and idx < st.bots.size():
			bot_id = str(st.bots[idx].get("id", ""))
		bot_name = str(tournament.get("opp_name", ""))
		event = str(tournament.get("tname", "Турнир"))
	elif not friendly.is_empty():
		bot_id = str(friendly.get("id", ""))
		bot_name = str(friendly.get("name", ""))
		event = "Товарищеская партия"
	if bot_id == "" or move_coords.is_empty():
		return
	# result в архиве — всегда очки БЕЛЫХ
	var player_white = player_color == "w"
	var white_score = score if player_white else 1.0 - score
	Profile.record_bot_game(
		"" if player_white else bot_id,
		bot_id if player_white else "",
		Profile.display_name if player_white else bot_name,
		bot_name if player_white else Profile.display_name,
		move_coords, white_score, event)

func _on_promo_queen_pressed() -> void: _on_promotion_chosen("Q")
func _on_promo_rook_pressed() -> void: _on_promotion_chosen("R")
func _on_promo_bishop_pressed() -> void: _on_promotion_chosen("B")
func _on_promo_knight_pressed() -> void: _on_promotion_chosen("N")
