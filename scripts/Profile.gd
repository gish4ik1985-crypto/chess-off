extends Node

# Persistent, multi-user player profile: Glicko-2 rating (same system as
# lichess.org), game stats, puzzle progress and achievements. Each user is
# its own save file under user://users/<name>.cfg, so switching users just
# means saving the current one and loading another. No password — this is a
# local "who's playing" name picker, not real authentication.

const USERS_DIR := "user://users/"
const SESSION_PATH := "user://session.cfg"

# ИЗМЕРЕННАЯ сила уровней ИИ (самоигра, scripts/tools/calibrate_levels.gd), пересчитана в шкалу,
# где уровень 20 ≈ 1510, а сильнейший ≈ 1720 (допущение: разницы в самоигре завышены, коэффициент 0,6).
# Раньше здесь стояли угаданные 400–4000. Approximate opponent strength for each AI level, used as
# the "opponent rating" fed into the Glicko-2 formula. Loosely mirrors real
# rating bands from beginner to super-GM (Magnus-level) play.
const LEVEL_RATING := [
	300, 390, 450, 520, 610, 650, 780, 870, 930, 1000,
	1040, 1150, 1170, 1300, 1380, 1400, 1420, 1440, 1480, 1510,
	1515, 1590, 1660, 1690, 1720,
]
const SAVE_VERSION := 1
const SAVE_DELAY := 1.0 # секунд между отложенными записями (request_save)
var _save_pending := false
var _load_failed := false # профиль не прочитался — не перезаписываем его пустым
const MAX_GAME_SWING := 100.0
const FARM_MARGIN := 200.0
const LEVEL_RD := 60.0 # the AI's own strength is considered well-known/stable
# preload, а не class_name: headless-Godot не подхватывает новый class_name
# без пересканирования проекта редактором.
const BotData = preload("res://scripts/BotData.gd")
# Постоянное состояние ботов: id -> {r, rd, v, w, d, l, tw, peak, played_at}.
# Храним только тех, кто уже играл, — остальные берут стартовые значения из BotData.
var bot_state: Dictionary = {}
# Рейтинг бота считается хорошо известным — он много играет между турнирами.
const BOT_RD := 80.0
# Слабые боты растут втрое медленнее (падают как все).
const WEAK_GAIN := 0.35
# Вес партии ботов между собой: вдвое меньше, чем личной встречи с игроком.
const SIM_WEIGHT := 0.5
# Лента изменений в базе игроков: последние события (переходы между лигами,
# заметные скачки рейтинга). Показывается в BotsHub — без неё жизнь мира
# была бы невидимой.
var world_events: Array = []
const MAX_WORLD_EVENTS := 40

# Архив партий ботов: id бота -> массив партий, новые впереди.
# Партия: {white, black, w_name, b_name, moves (массив "e2e4"/"e7e8Q"),
#          result (1/0.5/0 за белых), event, day}.
# Ходы храним КООРДИНАТАМИ, а не нотацией: воспроизведение тогда точное и не
# зависит от разбора текста. Симуляция тура партий сюда не кладёт — там нет
# ходов; сюда попадают только по-настоящему сыгранные партии.
var bot_games: Dictionary = {}
const MAX_GAMES_PER_BOT := 12

var current_user: String = "" # sanitized file key; "" means no user logged in yet
var display_name: String = ""

var rating: float = Glicko2.DEFAULT_RATING
var rd: float = Glicko2.DEFAULT_RD
var volatility: float = Glicko2.DEFAULT_VOLATILITY

var games_played := 0
var wins := 0
var losses := 0
var draws := 0
var win_streak := 0
var best_win_streak := 0
var best_win_level := 0 # highest AI difficulty ever beaten
# Победы над уровнями ИИ БЕЗ помощи (без подсказок, откатов, форы): уровень (String) -> число побед.
# Из них складывается «Ступень» — самый сильный уровень, который игрок стабильно побеждает сам.
var clean_wins: Dictionary = {}
const STEP_WINS_REQUIRED := 2 # чистых побед над уровнем, чтобы он считался пройденным
var last_step_gain := 0 # > 0: последняя партия подняла ступень до этого значения
var last_rating_change := 0.0

var solved_puzzles: Dictionary = {} # puzzle index (String key) -> true
var unlocked_achievements: Dictionary = {} # achievement id -> true
var defeated_characters: Dictionary = {} # MapData character id -> true
var last_played_unix := 0

# Autosave for resuming exactly where the player left off. {} means nothing
# in progress. game_state covers Board.tscn (quick play + map battles);
# puzzle_state covers Puzzle.tscn (static bank, any generated theme, or
# free practice) — each screen resumes independently based on which one
# the player re-enters.
var game_state: Dictionary = {}
var puzzle_state: Dictionary = {}

# Move-quality tracking ("Дневник"): every move the player makes during a
# real game is compared against the engine's own best move at that point
# and bucketed, the same idea lichess/chess.com use for post-game reports.
var move_good := 0
var move_inaccuracy := 0
var move_mistake := 0
var move_blunder := 0
var recent_blunders: Array = [] # last few {fen, move, loss} for the journal, newest first
var recent_best: Array = [] # last few {fen, move, loss} perfect moves (captures/promotions/castles with ~0 loss), newest first
var attention_done := 0 # highest completed level of the «Внимательность» mode (0..50), unlocked strictly in order

signal achievement_unlocked(id: String)
signal rating_changed(new_rating: float, delta: float)
signal user_switched(name: String)

const ACHIEVEMENTS := [
	{"id": "first_win", "name": "Первая победа", "desc": "Выиграйте свою первую партию у ИИ"},
	{"id": "wins_5", "name": "Уверенный старт", "desc": "Одержите 5 побед"},
	{"id": "wins_20", "name": "Опытный боец", "desc": "Одержите 20 побед"},
	{"id": "wins_50", "name": "Ветеран досок", "desc": "Одержите 50 побед"},
	{"id": "streak_3", "name": "Серия побед", "desc": "3 победы подряд"},
	{"id": "streak_5", "name": "Не остановить", "desc": "5 побед подряд"},
	{"id": "beat_level_10", "name": "Повержен Магнус", "desc": "Обыграйте ИИ 10-го уровня сложности"},
	{"id": "rating_1600", "name": "Турнирный рейтинг 1200", "desc": "Достигните турнирного рейтинга 1200"},
	{"id": "rating_2000", "name": "Турнирный рейтинг 1500", "desc": "Достигните турнирного рейтинга 1500"},
	{"id": "rating_2400", "name": "Турнирный рейтинг 1700", "desc": "Достигните турнирного рейтинга 1700"},
	{"id": "puzzle_first", "name": "Первая задача", "desc": "Решите первую задачу на мат"},
	{"id": "puzzle_10", "name": "Тактик", "desc": "Решите 10 задач на мат"},
	{"id": "puzzle_25", "name": "Комбинатор", "desc": "Решите 25 задач на мат"},
	{"id": "puzzle_50", "name": "Мастер матовых финалов", "desc": "Решите все 50 задач на мат"},
	{"id": "puzzle_mate3", "name": "Далеко вперёд", "desc": "Решите задачу на мат в 3 хода"},
	{"id": "map_start", "name": "Начало пути", "desc": "Победите своего первого персонажа на карте"},
	{"id": "map_boss", "name": "Покоритель вершины", "desc": "Победите короля Магнуса — финального соперника карты"},
	{"id": "moves_good_50", "name": "Точная рука", "desc": "Сделайте 50 точных ходов (по мнению дневника)"},
	{"id": "fork_first", "name": "Двойной удар", "desc": "Решите первую задачу на вилку"},
	{"id": "fork_10", "name": "Мастер вилок", "desc": "Решите 10 задач на вилку"},
	{"id": "fork_50", "name": "Гроссмейстер вилок", "desc": "Решите 50 задач на вилку"},
	{"id": "pin_first", "name": "Связал по рукам", "desc": "Решите первую задачу на связку"},
	{"id": "pin_10", "name": "Мастер связок", "desc": "Решите 10 задач на связку"},
	{"id": "pin_50", "name": "Гроссмейстер связок", "desc": "Решите 50 задач на связку"},
	{"id": "backrank_first", "name": "Последняя черта", "desc": "Решите первую задачу на мат на последней горизонтали"},
	{"id": "backrank_10", "name": "Знаток горизонтали", "desc": "Решите 10 задач на мат на последней горизонтали"},
	{"id": "backrank_50", "name": "Гроссмейстер горизонтали", "desc": "Решите 50 задач на мат на последней горизонтали"},
	{"id": "defense_first", "name": "Разрушитель", "desc": "Решите первую задачу на уничтожение защиты"},
	{"id": "defense_10", "name": "Охотник за защитой", "desc": "Решите 10 задач на уничтожение защиты"},
	{"id": "defense_50", "name": "Гроссмейстер разрушения", "desc": "Решите 50 задач на уничтожение защиты"},
	{"id": "deflection_first", "name": "Отвлекающий манёвр", "desc": "Решите первую задачу на отвлечение"},
	{"id": "deflection_10", "name": "Мастер отвлечения", "desc": "Решите 10 задач на отвлечение"},
	{"id": "deflection_50", "name": "Гроссмейстер отвлечения", "desc": "Решите 50 задач на отвлечение"},
	{"id": "daily_streak_3", "name": "Три дня подряд", "desc": "Решайте задачи 3 дня подряд"},
	{"id": "streak_7", "name": "Неделя без перерыва", "desc": "Решайте задачи 7 дней подряд"},
	{"id": "mix_first", "name": "Своя голова", "desc": "Решите первую задачу в режиме «Микс», сами определив нужный приём"},
	{"id": "mix_10", "name": "Настоящий тактик", "desc": "Решите 10 задач в режиме «Микс»"},
	{"id": "act2_champion", "name": "Чемпион турнира", "desc": "Пройдите акт 2 — победите Магнуса в «Турнире мастеров»"},
	{"id": "act3_legend", "name": "Легенда шахматной страны", "desc": "Пройдите акт 3 — выиграйте последнюю партию у Магнуса"},
	{"id": "tourney_first", "name": "Боевое крещение", "desc": "Доиграйте свой первый турнир до конца"},
	{"id": "tourney_win", "name": "Кубок на полке", "desc": "Выиграйте турнир (займите 1-е место)"},
	{"id": "tourney_win_5", "name": "Коллекционер кубков", "desc": "Выиграйте 5 турниров"},
	{"id": "tourney_daily", "name": "Герой дня", "desc": "Выиграйте «Турнир дня»"},
	{"id": "tourney_rating_1800", "name": "Турнирный боец", "desc": "Достигните турнирного рейтинга 1400"},
]

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(USERS_DIR)
	var last = _load_last_user()
	if last != "" and user_exists(last):
		switch_user(last, false)

# Звание — по ТУРНИРНОМУ рейтингу: он сопоставим с реальным миром (турниры, потом онлайн).
# Внутренняя «рабочая оценка» rating из партий с ИИ игроку больше не показывается —
# она нужна только для подбора сложности («Живая сложность», «Тень»).
func rating_title() -> String:
	return title_for_rating(tournament_rating)

# Ступень: самый сильный уровень ИИ, побеждённый без помощи не менее STEP_WINS_REQUIRED раз.
func clean_step() -> int:
	var best := 0
	for k in clean_wins:
		if int(clean_wins[k]) >= STEP_WINS_REQUIRED:
			best = maxi(best, int(k))
	return best

# Данные для профиля навыков (SkillProfile.compute): всё, что игра уже собирает.
func skill_input() -> Dictionary:
	var themes := {}
	for t in ["mate", "fork", "pin", "backrank", "defense", "deflection"]:
		themes[t] = {"solved": theme_progress(t), "clean": theme_clean_count(t)}
	var cw := 0
	for k in clean_wins:
		cw += int(clean_wins[k])
	return {
		"games": game_log,
		"moves": {"good": move_good, "inaccuracy": move_inaccuracy, "mistake": move_mistake, "blunder": move_blunder},
		"themes": themes,
		"attention_done": attention_done,
		"step": clean_step(),
		"clean_wins_total": cw,
	}

# Сколько чистых побед над следующим уровнем осталось до новой ступени.
func step_wins_left() -> int:
	var nxt := clean_step() + 1
	return maxi(STEP_WINS_REQUIRED - int(clean_wins.get(str(nxt), 0)), 0)

static func title_for_rating(r: float) -> String:
	if r < 500: return "Новичок"
	if r < 800: return "Любитель"
	if r < 1100: return "Клубный игрок"
	if r < 1400: return "Сильный любитель"
	if r < 1800: return "Турнирный боец"
	if r < 1800: return "Турнирный боец"
	if r < 2100: return "Мастер"
	if r < 2400: return "Международный мастер"
	if r < 2600: return "Гроссмейстер"
	return "Супер-гроссмейстер"

func has_user() -> bool:
	return current_user != ""

# --- multi-user management ---

static func sanitize_key(name: String) -> String:
	var s = name.strip_edges()
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "."]:
		s = s.replace(ch, "")
	s = s.to_lower()
	if s == "":
		s = "player"
	return s

func user_exists(name: String) -> bool:
	return FileAccess.file_exists(USERS_DIR + sanitize_key(name) + ".cfg")

func list_users() -> Array:
	var result := []
	var dir = DirAccess.open(USERS_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var f = dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".cfg"):
			var cfg = ConfigFile.new()
			if cfg.load(USERS_DIR + f) == OK:
				var nm = cfg.get_value("meta", "display_name", f.trim_suffix(".cfg"))
				var rt = cfg.get_value("tourney", "rating", Glicko2.DEFAULT_RATING) # турнирный рейтинг
				var games = cfg.get_value("stats", "games_played", 0)
				result.append({"key": f.trim_suffix(".cfg"), "name": nm, "rating": rt, "games": games})
		f = dir.get_next()
	dir.list_dir_end()
	result.sort_custom(func(a, b): return String(a.name).to_lower() < String(b.name).to_lower())
	return result

func delete_user(name: String) -> void:
	var key = sanitize_key(name)
	var path = USERS_DIR + key + ".cfg"
	if FileAccess.file_exists(path):
		# мягкое удаление: файл уходит в _deleted/, а не стирается насовсем
		DirAccess.make_dir_recursive_absolute(USERS_DIR + "_deleted")
		var stamp := Time.get_datetime_string_from_system().replace(":", "-")
		DirAccess.rename_absolute(path, USERS_DIR + "_deleted/" + key + "_" + stamp + ".cfg")
	if current_user == key:
		current_user = ""
		display_name = ""
		_reset_defaults()
		_save_last_user("")

# Switches the active user, saving the previously active one first (unless
# save_current is false, e.g. on first app launch when nothing is loaded yet).
# Creates a fresh profile automatically if this user has never played before.
func switch_user(name: String, save_current: bool = true) -> void:
	if save_current and current_user != "":
		save_profile()
	current_user = sanitize_key(name)
	display_name = name.strip_edges() if name.strip_edges() != "" else current_user
	_reset_defaults()
	load_profile()
	save_profile()
	_save_last_user(current_user)
	emit_signal("user_switched", display_name)

func _reset_defaults() -> void:
	rating = Glicko2.DEFAULT_RATING
	rd = Glicko2.DEFAULT_RD
	volatility = Glicko2.DEFAULT_VOLATILITY
	games_played = 0
	wins = 0
	losses = 0
	draws = 0
	win_streak = 0
	best_win_streak = 0
	best_win_level = 0
	clean_wins = {}
	last_step_gain = 0
	last_rating_change = 0.0
	solved_puzzles = {}
	unlocked_achievements = {}
	defeated_characters = {}
	move_good = 0
	move_inaccuracy = 0
	move_mistake = 0
	move_blunder = 0
	recent_blunders = []
	recent_best = []
	attention_done = 0
	fork_puzzles_solved = 0
	pin_puzzles_solved = 0
	backrank_puzzles_solved = 0
	defense_puzzles_solved = 0
	deflection_puzzles_solved = 0
	theme_clean = {}
	mix_puzzles_solved = 0
	road_stage = 0
	road_blunders_fixed = 0
	blunders_fixed_fens = {}
	solved_generated = {}
	road_focus_done = {}
	real_rating = 0
	tournament_rating = Glicko2.DEFAULT_RATING
	tournament_rd = Glicko2.DEFAULT_RD
	tournament_volatility = Glicko2.DEFAULT_VOLATILITY
	last_tournament_rating_change = 0.0
	tournaments_played = 0
	tournaments_won = 0
	active_tournaments = {}
	tournament_titles = {}
	active_tournament_prep = {}
	bot_state = {}
	world_events = []
	bot_games = {}
	historic_games_viewed = {}
	school_spot_record = 0
	school_wisdom_record = 0
	school_patience_seconds = 10
	daily_history = {}
	game_log = []
	streak_count = 0
	streak_last_day = ""
	game_state = {}
	puzzle_state = {}
	last_played_unix = 0

func _save_last_user(key: String) -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("session", "current_user", key)
	cfg.save(SESSION_PATH)

func _load_last_user() -> String:
	var cfg = ConfigFile.new()
	if cfg.load(SESSION_PATH) != OK:
		return ""
	return cfg.get_value("session", "current_user", "")

# --- game/puzzle recording (operate on whichever user is currently active) ---

# Чистая функция обновления внутреннего рейтинга — её же проверяет TestRatingRealism.
static func rating_after(r: float, d: float, v: float, ai_level: int, score: float) -> Dictionary:
	var opp_rating = float(LEVEL_RATING[clampi(ai_level, 1, LEVEL_RATING.size()) - 1])
	var u: Dictionary = Glicko2.update(r, d, v, opp_rating, LEVEL_RD, score)
	# одна партия не двигает рейтинг больше чем на MAX_GAME_SWING: первая партия новичка
	# (большая неопределённость) иначе давала скачок на сотни очков
	u.rating = r + clampf(float(u.rating) - r, -MAX_GAME_SWING, MAX_GAME_SWING)
	# победы над слабым соперником не разгоняют рейтинг выше его силы + FARM_MARGIN
	if score > 0.5 and float(u.rating) > opp_rating + FARM_MARGIN:
		u.rating = maxf(r, opp_rating + FARM_MARGIN)
	return u

func record_game_result(ai_level: int, score: float) -> void:
	var result = rating_after(rating, rd, volatility, ai_level, score)
	var old_rating = rating
	rating = result.rating
	rd = result.rd
	volatility = result.volatility
	last_rating_change = rating - old_rating
	last_step_gain = 0

	games_played += 1
	if score > 0.75:
		wins += 1
		win_streak += 1
		best_win_streak = max(best_win_streak, win_streak)
		best_win_level = max(best_win_level, ai_level)
		var step_before := clean_step()
		clean_wins[str(ai_level)] = int(clean_wins.get(str(ai_level), 0)) + 1
		if clean_step() > step_before:
			last_step_gain = clean_step()
	elif score < 0.25:
		losses += 1
		win_streak = 0
	else:
		draws += 1
		win_streak = 0

	_check_achievements()
	save_profile()
	emit_signal("rating_changed", rating, last_rating_change)

func save_game_state(state: Dictionary) -> void:
	game_state = state
	request_save()

# Отложенное сохранение для «горячих» мест (каждый ход): не чаще раза в секунду.
# Настоящая запись — save_profile(); принудительно она идёт при выходе и сворачивании.
func request_save() -> void:
	if _save_pending or current_user == "":
		return
	_save_pending = true
	get_tree().create_timer(SAVE_DELAY).timeout.connect(func():
		if _save_pending:
			save_profile())

func _notification(what: int) -> void:
	var leaving: bool = what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT
	if leaving:
		if _save_pending:
			save_profile()

func clear_game_state() -> void:
	if game_state.is_empty():
		return
	game_state = {}
	save_profile()

func save_puzzle_state(state: Dictionary) -> void:
	puzzle_state = state
	save_profile()

func clear_puzzle_state() -> void:
	if puzzle_state.is_empty():
		return
	puzzle_state = {}
	save_profile()

# "Clean" solves per theme: solved with no wrong attempts and no hints.
# Enough of them marks the theme as mastered, which grants a bonus for
# the boss fight of that theme (handicap offered even if the global
# "С форой" setting is off).
# Daily streak: consecutive days with at least one solved puzzle.
var streak_count := 0
var streak_last_day := "" # "YYYY-MM-DD"

func record_daily_activity() -> void:
	var today = Time.get_date_string_from_system()
	if streak_last_day == today:
		return
	var yesterday = Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()) - 86400)
	streak_count = streak_count + 1 if streak_last_day == yesterday else 1
	streak_last_day = today
	if streak_count >= 3: _unlock("daily_streak_3")
	if streak_count >= 7: _unlock("streak_7")
	save_profile()

# 0 if the streak is already broken (no activity today or yesterday).
func current_streak() -> int:
	var today = Time.get_date_string_from_system()
	var yesterday = Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()) - 86400)
	if streak_last_day == today or streak_last_day == yesterday:
		return streak_count
	return 0

const THEME_MASTERY_REQUIRED := 4
var theme_clean := {} # theme -> int

func record_theme_clean(theme: String) -> void:
	theme_clean[theme] = int(theme_clean.get(theme, 0)) + 1
	save_profile()

func theme_clean_count(theme: String) -> int:
	return int(theme_clean.get(theme, 0))

func theme_mastered(theme: String) -> bool:
	return theme != "" and theme_clean_count(theme) >= THEME_MASTERY_REQUIRED

# "Дорога домой": stage progress (0..5 = stages completed in order) and the
# blunder-quest counter for its first stage (fix 3 of your own blunders).
const ROAD_BLUNDERS_REQUIRED := 3
var road_stage := 0
var road_blunders_fixed := 0
var blunders_fixed_fens: Dictionary = {} # позиции исправленных зевков (без повторов)
var solved_generated: Dictionary = {} # "тема|fen" решённых сгенерированных задач

# Dynamic road stages ("дорога растёт"): the road watches EVERY logged game
# (quick play, map battles, road battles) and grows extra remedial stops for
# whatever the player currently gets wrong most — then removes them again
# once the recent games are clean. road_focus_done remembers which of the
# currently-visible stops were beaten (a stop can reappear later if the same
# weakness returns; it will need to be beaten again).
const ROAD_FOCUS_WINDOW := 8 # how many recent games the road looks at
const ROAD_FOCUS_KINDS := {
	"focus_blunders": {
		"name": "Крепость без зевков",
		"blurb": "В последних партиях ты часто зеваешь фигуры (%d зевков за %d партий). Выиграй партию, не зевнув ни разу, — и крепость падёт.",
		"accent": Color(0.95, 0.45, 0.45),
		"icon": "R",
	},
	"focus_opening": {
		"name": "Застава дебюта",
		"blurb": "Твои партии чаще всего ломаются в дебюте — %d ошибок в первых 10 ходах за последние %d партий. Выиграй партию без ошибок в первых 10 ходах.",
		"accent": Color(0.4, 0.9, 0.6),
		"icon": "P",
	},
	"focus_middlegame": {
		"name": "Перевал середины",
		"blurb": "Миттельшпиль — твоё слабое место: %d ошибок на ходах 11–25 за последние %d партий. Выиграй партию, не ошибившись в середине игры.",
		"accent": Color(0.95, 0.7, 0.3),
		"icon": "N",
	},
	"focus_endgame": {
		"name": "Долина эндшпиля",
		"blurb": "После 25-го хода ты часто теряешь нить игры: %d ошибок в эндшпилях за последние %d партий. Выиграй партию без ошибок после 25-го хода.",
		"accent": Color(0.55, 0.75, 0.95),
		"icon": "K",
	},
}
var road_focus_done := {} # kind -> true (for currently active dynamic stops)

# Scans the recent game log and returns the dynamic stages the road should
# show right now: Array of {kind, name, blurb, accent, icon}. A weakness that
# faded from the recent window makes its stage vanish automatically — and its
# "done" mark is dropped so it starts fresh if it ever comes back.
func dynamic_road_stages() -> Array:
	var window: Array = game_log.slice(max(game_log.size() - ROAD_FOCUS_WINDOW, 0))
	var stages := []
	if window.size() >= 3:
		var n = window.size()
		var blunders := 0
		var err_open := 0
		var err_mid := 0
		var err_end := 0
		for g in window:
			blunders += int(g.get("blunder", 0))
			err_open += int(g.get("err_opening", 0))
			err_mid += int(g.get("err_middlegame", 0))
			err_end += int(g.get("err_endgame", 0))
			# older log entries only know the single worst move — still use it
			if not g.has("err_opening") and int(g.get("worst_move_no", 0)) > 0:
				var no = int(g.worst_move_no)
				if no <= 10: err_open += 1
				elif no <= 25: err_mid += 1
				else: err_end += 1
		if blunders >= 4:
			stages.append(_make_focus_stage("focus_blunders", blunders, n))
		if err_open >= 4:
			stages.append(_make_focus_stage("focus_opening", err_open, n))
		if err_mid >= 5:
			stages.append(_make_focus_stage("focus_middlegame", err_mid, n))
		if err_end >= 4:
			stages.append(_make_focus_stage("focus_endgame", err_end, n))
	# слабая тема задач: решено не меньше 5, но меньше половины — без подсказок и ошибок
	var SP = preload("res://scripts/SkillProfile.gd")
	var weak_theme := ""
	var weak_ratio := 0.5
	for t in SP.THEME_NAMES:
		var solved: int = theme_progress(t)
		if solved >= 5:
			var ratio: float = float(theme_clean_count(t)) / float(solved)
			if ratio < weak_ratio:
				weak_ratio = ratio
				weak_theme = t
	if weak_theme != "":
		stages.append({
			"kind": "focus_tactics",
			"theme": weak_theme,
			"name": "Тренажёр: %s" % SP.THEME_NAMES[weak_theme],
			"blurb": "Тема «%s» пока даётся хуже всего: чисто, без подсказок и ошибок, решено %d из %d. Реши несколько задач этой темы — остановка исчезнет, когда доля чистых решений превысит половину." % [SP.THEME_NAMES[weak_theme], theme_clean_count(weak_theme), theme_progress(weak_theme)],
			"accent": Color(0.75, 0.55, 0.95),
			"icon": "T",
		})
	# drop stale "done" marks for stages that are no longer on the road
	var active := {}
	for st in stages:
		active[st.kind] = true
	var changed := false
	for k in road_focus_done.keys():
		if not active.has(k):
			road_focus_done.erase(k)
			changed = true
	if changed:
		save_profile()
	return stages

func _make_focus_stage(kind: String, count: int, games: int) -> Dictionary:
	var def: Dictionary = ROAD_FOCUS_KINDS[kind]
	return {
		"kind": kind,
		"name": def.name,
		"blurb": def.blurb % [count, games],
		"accent": def.accent,
		"icon": def.icon,
	}

func record_focus_stage_done(kind: String) -> void:
	road_focus_done[kind] = true
	save_profile()

# --- tournaments ---
# A completely separate Glicko-2 rating for tournament play. Both standing
# tournaments and the daily one feed it; casual games never touch it (and
# tournament games never touch the main rating). Tournament state itself is
# stored per tournament id in active_tournaments so the player can leave in
# the middle of an event and come back later. A tournament is 8 participants
# (the player + 7 named bots); only the player's games are actually played —
# the other three boards each round are simulated from rating expectation.

# Настоящий рейтинг игрока (федерация, клуб, турнир), 0 — нет. Служит точкой отсчёта:
# турнирный и внутренний рейтинг стартуют с него, а дальше идут по результатам игры.
const REAL_RATING_MIN := 100
const REAL_RATING_MAX := 2800
const REAL_RATING_RD := 150.0 # уверенность ниже, чем в собственных партиях — рейтинг быстро подстроится
var real_rating := 0

func set_real_rating(r: int) -> void:
	if r <= 0:
		real_rating = 0
		save_profile()
		return
	real_rating = clampi(r, REAL_RATING_MIN, REAL_RATING_MAX)
	tournament_rating = float(real_rating)
	tournament_rd = REAL_RATING_RD
	rating = float(real_rating)
	rd = REAL_RATING_RD
	save_profile()

var tournament_rating: float = Glicko2.DEFAULT_RATING
var tournament_rd: float = Glicko2.DEFAULT_RD
var tournament_volatility: float = Glicko2.DEFAULT_VOLATILITY
var last_tournament_rating_change := 0.0
var tournaments_played := 0
var tournaments_won := 0
var active_tournaments: Dictionary = {} # id -> state (see Tournaments.gd _new_state)
# Permanent trophy cabinet: tournament id -> times won (daily wins are
# aggregated under "daily"). Unlike active_tournaments this is never
# overwritten by replays — the trophy room draws its cups from here.
var tournament_titles: Dictionary = {}

# --- tournament preparation mode ---
# Practice tournaments (TournamentPrep.gd): three levels of a Swiss bracket
# growing from 4 to 8 rounds, meant to rehearse real-tournament etiquette
# (no undo, no hints, play it out) without touching the real tournament
# rating — a beaten "Разминка" just unlocks the next, harder level.
var active_tournament_prep: Dictionary = {} # id -> state (same shape as active_tournaments)

# --- historic games (HistoricGames.gd) ---
# Which famous annotated games the player has opened at least once, so the
# list can show a checkmark — id (HistoricGamesData) -> 1.
var historic_games_viewed: Dictionary = {}

# --- school (School.gd / Board.gd «Школа юного шахматиста») ---
# Лучшие результаты за одну партию: найдено ходов соперника («Что
# изменилось?») и очков мудрости («Школа терпения»).
var school_spot_record := 0
var school_wisdom_record := 0
var school_patience_seconds := 10 # длительность паузы в «Школе терпения»: 5 / 10 / 15

# ------------------------------------------------------------ база ботов
# Постоянные соперники (BotData): у каждого свой рейтинг Glicko-2, который
# живёт между турнирами. Игрок встречает только ботов своей лиги — тот, кто
# перерос игрока, уходит наверх и не попадается, пока игрок не подтянется.

# Уровень ИИ, примерно соответствующий рейтингу бота.
func bot_level(r: float) -> int:
	var lvl := 1
	for i in range(LEVEL_RATING.size()):
		if r >= float(LEVEL_RATING[i]) - 100.0:
			lvl = i + 1
	return lvl

# Карточка бота: постоянные данные из BotData + накопленная статистика.
func bot_record(id: String) -> Dictionary:
	var d: Dictionary = BotData.def_by_id(id)
	if d.is_empty():
		return {}
	var st: Dictionary = bot_state.get(id, {})
	var r := float(st.get("r", d.base_rating))
	var rec := d.duplicate(true)
	rec["rating"] = r
	rec["rd"] = float(st.get("rd", BOT_RD))
	rec["volatility"] = float(st.get("v", Glicko2.DEFAULT_VOLATILITY))
	rec["wins"] = int(st.get("w", 0))
	rec["draws"] = int(st.get("d", 0))
	rec["losses"] = int(st.get("l", 0))
	rec["tourneys_won"] = int(st.get("tw", 0))
	rec["peak"] = float(st.get("peak", r))
	# личные встречи с игроком, с точки зрения БОТА
	rec["p_wins"] = int(st.get("pw", 0))
	rec["p_draws"] = int(st.get("pd", 0))
	rec["p_losses"] = int(st.get("pl", 0))
	rec["league_idx"] = BotData.league_idx_for_rating(r)
	rec["league_def"] = BotData.LEAGUES[int(rec.league_idx)]
	rec["level"] = bot_level(r)
	rec["promoted"] = int(rec.league_idx) > int(d.home_league_idx)
	rec["relegated"] = int(rec.league_idx) < int(d.home_league_idx)
	return rec

func all_bot_records() -> Array:
	var out := []
	for i in range(BotData.count()):
		out.append(bot_record("bot_%03d" % i))
	return out

# Лига игрока определяется его ТУРНИРНЫМ рейтингом.
func player_league_idx() -> int:
	return BotData.league_idx_for_rating(tournament_rating)

# Соперники для турнира: берём из лиги игрока, а если там не набралось —
# расширяемся на соседние лиги (иначе турнир просто нельзя было бы собрать).
func pick_tournament_field(need: int, player_league: int = -1) -> Array:
	var target = player_league if player_league >= 0 else player_league_idx()
	var by_league := {}
	for rec in all_bot_records():
		var li = int(rec.league_idx)
		if not by_league.has(li):
			by_league[li] = []
		by_league[li].append(rec)
	var picked := []
	# радиус 0 — своя лига, потом всё дальше от неё
	for radius in range(BotData.LEAGUES.size()):
		for li in [target - radius, target + radius] if radius > 0 else [target]:
			if not by_league.has(li):
				continue
			var pool: Array = by_league[li].duplicate()
			pool.shuffle()
			for rec in pool:
				if picked.size() >= need:
					break
				picked.append(rec)
		if picked.size() >= need:
			break
	return picked

# Обновляет постоянный рейтинг бота после одной партии.
# score — результат С ТОЧКИ ЗРЕНИЯ БОТА (1 победа, 0.5 ничья, 0 поражение).
# weight — вес партии. Партии ботов между собой идут с половинным весом
# (SIM_WEIGHT): личные встречи с игроком должны двигать рейтинг соперника
# сильнее, чем симуляция, иначе мир убегает вперёд от того, кто играет
# размеренно.
func apply_bot_result(id: String, opp_rating: float, score: float, vs_player: bool = false, weight: float = 1.0) -> void:
	var d: Dictionary = BotData.def_by_id(id)
	if d.is_empty():
		return
	var st: Dictionary = bot_state.get(id, {})
	var r := float(st.get("r", d.base_rating))
	var rd := float(st.get("rd", BOT_RD))
	var v := float(st.get("v", Glicko2.DEFAULT_VOLATILITY))
	var res := Glicko2.update(r, rd, v, opp_rating, BOT_RD, score)
	var new_r := r + (float(res.rating) - r) * weight
	if not bool(d.weak):
		# обычный бот не уходит дальше двух лиг от родной — иначе состав
		# расползается по краям и средние лиги пустеют
		var db := BotData.drift_bounds(int(d.home_league_idx))
		new_r = clampf(new_r, float(db.lo), float(db.hi))
	if bool(d.weak):
		# Слабые растут втрое медленнее и НИКОГДА не поднимаются выше нижней
		# половины родной лиги. Благодаря этому в каждой лиге навсегда есть
		# соперники, которых игрок способен обыграть, — даже если весь
		# остальной состав вырос вместе с ним.
		if new_r > r:
			new_r = r + (new_r - r) * WEAK_GAIN
		var band := BotData.league_band(int(d.home_league_idx))
		new_r = clampf(new_r, float(band.lo), BotData.weak_ceiling(int(d.home_league_idx)))
	st["r"] = new_r
	# нижний порог RD: без него рейтинг бота после серии партий «замерзает»
	# и он перестаёт заметно расти или падать
	st["rd"] = maxf(float(res.rd), 45.0)
	st["v"] = res.volatility
	st["peak"] = maxf(float(st.get("peak", new_r)), new_r)
	if score >= 1.0:
		st["w"] = int(st.get("w", 0)) + 1
	elif score <= 0.0:
		st["l"] = int(st.get("l", 0)) + 1
	else:
		st["d"] = int(st.get("d", 0)) + 1
	if vs_player:
		if score >= 1.0:
			st["pw"] = int(st.get("pw", 0)) + 1
		elif score <= 0.0:
			st["pl"] = int(st.get("pl", 0)) + 1
		else:
			st["pd"] = int(st.get("pd", 0)) + 1
	bot_state[id] = st

# Товарищеская партия игрока с ботом. score — результат ИГРОКА.
# Возвращает {rating, delta, league_changed, league_name} для показа в итогах,
# или {} если бот неизвестен.
func record_friendly_game(id: String, score: float) -> Dictionary:
	var before := bot_record(id)
	if before.is_empty():
		return {}
	# соперником для бота выступает ОБЫЧНЫЙ рейтинг игрока: товарищеские
	# партии не имеют отношения к турнирному зачёту
	apply_bot_result(id, rating, 1.0 - score, true)
	var after := bot_record(id)
	save_profile()
	return {
		"rating": after.rating,
		"delta": float(after.rating) - float(before.rating),
		"league_changed": int(after.league_idx) != int(before.league_idx),
		"league_name": str(after.league_def.name),
	}

# Тик мира: по одному туру в КАЖДОЙ лиге. Без него живой была бы только лига
# игрока, а остальные семь стояли бы замороженными — и база снова выглядела
# бы мёртвой, просто в другом месте. Вызывается в момент, когда игрок
# доигрывает свой турнир, то есть мир идёт вперёд только вместе с игроком.
func simulate_world_round() -> void:
	var before := {}
	for i in range(BotData.count()):
		var id := "bot_%03d" % i
		var rec := bot_record(id)
		before[id] = {"r": float(rec.rating), "league": int(rec.league_idx)}
	# группируем по текущим лигам и играем внутри каждой
	var by_league := {}
	for i in range(BotData.count()):
		var id := "bot_%03d" % i
		var li := int(before[id].league)
		if not by_league.has(li):
			by_league[li] = []
		by_league[li].append(id)
	for li in by_league.keys():
		var pool: Array = by_league[li]
		pool.shuffle()
		for p in range(0, pool.size() - 1, 2):
			var ida: String = pool[p]
			var idb: String = pool[p + 1]
			var ra: float = before[ida].r
			var rb: float = before[idb].r
			var expected = 1.0 / (1.0 + pow(10.0, (rb - ra) / 400.0))
			var sa := 0.5
			if randf() < 0.18:
				sa = 0.5
			elif randf() < expected:
				sa = 1.0
			else:
				sa = 0.0
			apply_bot_result(ida, rb, sa, false, SIM_WEIGHT)
			apply_bot_result(idb, ra, 1.0 - sa, false, SIM_WEIGHT)
	_collect_world_events(before)

# Сравнивает состояние до и после тика и складывает заметное в ленту.
func _collect_world_events(before: Dictionary) -> void:
	var moves := []
	var jumps := []
	for id in before.keys():
		var rec := bot_record(id)
		var was: Dictionary = before[id]
		var d := float(rec.rating) - float(was.r)
		if int(rec.league_idx) != int(was.league):
			moves.append({
				"kind": "league",
				"name": str(rec.name),
				"up": int(rec.league_idx) > int(was.league),
				"league": str(BotData.LEAGUES[int(rec.league_idx)].name),
				"icon": str(BotData.LEAGUES[int(rec.league_idx)].icon),
				"rating": int(round(float(rec.rating))),
			})
		elif absf(d) >= 25.0:
			jumps.append({"kind": "jump", "name": str(rec.name), "delta": int(round(d)),
				"rating": int(round(float(rec.rating)))})
	# переходы между лигами — главная новость, их берём все; скачки рейтинга
	# только самые крупные, иначе лента превратится в простыню цифр
	jumps.sort_custom(func(a, b): return absi(int(a.delta)) > absi(int(b.delta)))
	var batch: Array = moves
	batch.append_array(jumps.slice(0, 5))
	if batch.is_empty():
		return
	var stamp := Time.get_date_string_from_system()
	for e in batch:
		e["day"] = stamp
		world_events.push_front(e)
	if world_events.size() > MAX_WORLD_EVENTS:
		world_events.resize(MAX_WORLD_EVENTS)

# Кладёт сыгранную партию в архив обоих участников. white/black — id бота
# или "" для живого игрока. result — очки БЕЛЫХ (1 / 0.5 / 0).
func record_bot_game(white: String, black: String, w_name: String, b_name: String,
		move_coords: Array, result: float, event: String) -> void:
	if move_coords.is_empty():
		return
	var game := {
		"white": white, "black": black, "w_name": w_name, "b_name": b_name,
		"moves": move_coords.duplicate(), "result": result, "event": event,
		"day": Time.get_date_string_from_system(),
	}
	for id in [white, black]:
		if str(id) == "":
			continue # партии живого игрока хранит его собственный дневник
		var arr: Array = bot_games.get(id, [])
		arr.push_front(game)
		if arr.size() > MAX_GAMES_PER_BOT:
			arr.resize(MAX_GAMES_PER_BOT)
		bot_games[id] = arr

func games_of_bot(id: String) -> Array:
	return bot_games.get(id, [])

func record_bot_tournament_win(id: String) -> void:
	if BotData.def_by_id(id).is_empty():
		return
	var st: Dictionary = bot_state.get(id, {})
	st["tw"] = int(st.get("tw", 0)) + 1
	bot_state[id] = st

# Рейтинг бота, участвующего в турнире (для расчёта ожиданий в симуляции).
func bot_rating_in_state(bt: Dictionary) -> float:
	var id := str(bt.get("id", ""))
	if id != "":
		var rec := bot_record(id)
		if not rec.is_empty():
			return float(rec.rating)
	# старые сохранения без id — оцениваем по уровню ИИ, как раньше
	return float(LEVEL_RATING[clampi(int(bt.get("level", 5)), 1, LEVEL_RATING.size()) - 1])

# Simulates the three boards not involving the player: pairs the remaining
# six bots (preferring pairings that haven't already met this tournament, so
# the same two don't keep replaying each other while others never meet) and
# rolls each result from rating-based win expectation. Mutates bots' scores
# and state.bot_pairs in place.
# Остальные доски тура. Мир живой: эти партии меняют постоянные рейтинги —
# но с половинным весом и ТОЛЬКО в тот момент, когда за доской сидит игрок.
# Фонового роста нет: ушли на месяц — вернулись в тот же самый мир.
# rated=false для тренировочных турниров (TournamentPrep).
func _simulate_bot_round(bots: Array, opp_idx: int, state: Dictionary, rated: bool = true) -> void:
	var others := []
	for i in range(bots.size()):
		if i != opp_idx:
			others.append(i)
	var bot_pairs: Dictionary = state.get("bot_pairs", {})
	others = _pair_bots_avoiding_repeats(others, bot_pairs)
	for p in range(0, others.size() - 1, 2):
		var a: Dictionary = bots[others[p]]
		var b: Dictionary = bots[others[p + 1]]
		# ожидание считаем по ПОСТОЯННЫМ рейтингам ботов, а не по уровню ИИ:
		# так выросший бот действительно начинает чаще обыгрывать соседей
		var ra := bot_rating_in_state(a)
		var rb := bot_rating_in_state(b)
		var expected = 1.0 / (1.0 + pow(10.0, (rb - ra) / 400.0))
		var sa := 0.5
		if randf() < 0.18:
			a.score = float(a.score) + 0.5
			b.score = float(b.score) + 0.5
		elif randf() < expected:
			a.score = float(a.score) + 1.0
			sa = 1.0
		else:
			b.score = float(b.score) + 1.0
			sa = 0.0
		if rated:
			apply_bot_result(str(a.get("id", "")), rb, sa, false, SIM_WEIGHT)
			apply_bot_result(str(b.get("id", "")), ra, 1.0 - sa, false, SIM_WEIGHT)
		var key = _pair_key(others[p], others[p + 1])
		bot_pairs[key] = int(bot_pairs.get(key, 0)) + 1
	state.bot_pairs = bot_pairs

func _pair_key(a: int, b: int) -> String:
	return "%d-%d" % [mini(a, b), maxi(a, b)]

# Tries a handful of random shuffles and keeps the one with fewest pairings
# already present in bot_pairs — cheap stand-in for real Swiss pairing given
# only 3 pairs to place; falls back to a partial repeat once fresh pairs run out.
func _pair_bots_avoiding_repeats(others: Array, bot_pairs: Dictionary) -> Array:
	var best: Array = others.duplicate()
	best.shuffle()
	var best_repeats := _count_repeat_pairs(best, bot_pairs)
	for attempt in range(19):
		if best_repeats == 0:
			break
		var candidate: Array = others.duplicate()
		candidate.shuffle()
		var repeats = _count_repeat_pairs(candidate, bot_pairs)
		if repeats < best_repeats:
			best = candidate
			best_repeats = repeats
	return best

func _count_repeat_pairs(order: Array, bot_pairs: Dictionary) -> int:
	var n := 0
	for p in range(0, order.size() - 1, 2):
		if bot_pairs.has(_pair_key(order[p], order[p + 1])):
			n += 1
	return n

func finish_prep_round(tid: String, opp_idx: int, score: float) -> Dictionary:
	if not active_tournament_prep.has(tid):
		return {}
	var state: Dictionary = active_tournament_prep[tid]
	if state.get("done", false):
		return state
	var bots: Array = state.bots
	state.my_score = float(state.my_score) + score
	bots[opp_idx].score = float(bots[opp_idx].score) + (1.0 - score)
	state.my_played.append(opp_idx)
	# тренировка не трогает ни рейтинг игрока, ни постоянные рейтинги ботов
	_simulate_bot_round(bots, opp_idx, state, false)
	state.round = int(state.round) + 1
	if state.round >= int(state.rounds):
		state.done = true
		var best_bot := 0.0
		for bt in bots:
			best_bot = maxf(best_bot, float(bt.score))
		# tied for first isn't a clean win — no tiebreak system here, so
		# don't claim "won" (and its trophy/achievement) for a shared score
		state.won = float(state.my_score) > best_bot
		state.tied_first = float(state.my_score) == best_bot
	active_tournament_prep[tid] = state
	save_profile()
	return state

func record_tournament_game(ai_level: int, score: float) -> void:
	var result = rating_after(tournament_rating, tournament_rd, tournament_volatility, ai_level, score)
	last_tournament_rating_change = result.rating - tournament_rating
	tournament_rating = result.rating
	tournament_rd = result.rd
	tournament_volatility = result.volatility
	if tournament_rating >= 1400:
		_unlock("tourney_rating_1800")
	save_profile()

# Applies the player's game result to the bracket, simulates the other three
# boards of this round and advances/finishes the event. Returns the updated
# state (or {} if the tournament is unknown).
func finish_tournament_round(tid: String, opp_idx: int, score: float) -> Dictionary:
	if not active_tournaments.has(tid):
		return {}
	var state: Dictionary = active_tournaments[tid]
	if state.get("done", false):
		return state
	var bots: Array = state.bots
	state.my_score = float(state.my_score) + score
	bots[opp_idx].score = float(bots[opp_idx].score) + (1.0 - score)
	state.my_played.append(opp_idx)
	# личная встреча с игроком меняет постоянный рейтинг бота: счёт передаём
	# с точки зрения БОТА, а рейтингом соперника для него служит турнирный
	# рейтинг игрока (берём ДО его собственного пересчёта — record_tournament_
	# game уже отработал, так что это свежее значение)
	apply_bot_result(str(bots[opp_idx].get("id", "")), tournament_rating, 1.0 - score, true)
	_simulate_bot_round(bots, opp_idx, state)
	state.round = int(state.round) + 1
	if state.round >= int(state.rounds):
		state.done = true
		var best_bot := 0.0
		for bt in bots:
			best_bot = maxf(best_bot, float(bt.score))
		# tied for first isn't a clean win — no tiebreak system here, so
		# don't claim "won" (and its trophy/achievement) for a shared score
		state.won = float(state.my_score) > best_bot
		state.tied_first = float(state.my_score) == best_bot
		# кубок победившему боту — попадёт в его карточку в «Базе игроков»
		if not state.won:
			for bt in bots:
				if float(bt.score) == best_bot:
					record_bot_tournament_win(str(bt.get("id", "")))
					break
		tournaments_played += 1
		_unlock("tourney_first")
		if state.won:
			tournaments_won += 1
			var title_key = "daily" if tid.begins_with("daily_") else tid
			tournament_titles[title_key] = int(tournament_titles.get(title_key, 0)) + 1
			_unlock("tourney_win")
			if tournaments_won >= 5:
				_unlock("tourney_win_5")
			if tid.begins_with("daily_"):
				_unlock("tourney_daily")
		# турнир доигран — остальные лиги тоже сыграли свой тур
		simulate_world_round()
	active_tournaments[tid] = state
	save_profile()
	return state

# Final place of the player in a (finished or running) tournament: 1..8.
func tournament_place(state: Dictionary) -> int:
	var place := 1
	for bt in state.bots:
		if float(bt.score) > float(state.my_score):
			place += 1
	return place

# Drops stale daily-tournament states (yesterday's event is gone forever).
func prune_daily_tournaments(today_id: String) -> void:
	var changed := false
	for k in active_tournaments.keys():
		if String(k).begins_with("daily_") and k != today_id:
			active_tournaments.erase(k)
			changed = true
	if changed:
		save_profile()

func advance_road(stage_idx: int) -> void:
	if road_stage == stage_idx:
		road_stage += 1
		save_profile()

# fen — позиция исправленного зевка: один и тот же зевок второй раз в зачёт не идёт
# (раньше этап «Овраг зевков» проходился трёхкратным исправлением одного момента).
func record_road_blunder_fix(fen: String = "") -> bool:
	if fen != "":
		if blunders_fixed_fens.has(fen):
			return false
		blunders_fixed_fens[fen] = true
	road_blunders_fixed += 1
	if road_blunders_fixed >= ROAD_BLUNDERS_REQUIRED:
		advance_road(0)
	save_profile()
	return true

# Сгенерированные задачи (вилка, связка, ...): true, если эту позицию игрок решает впервые.
# Только такая победа увеличивает счётчик темы; мат-задачи считаются отдельно (solved_puzzles).
func mark_solved_once(theme: String, fen: String) -> bool:
	var key := theme + "|" + fen
	if solved_generated.has(key):
		return false
	solved_generated[key] = true
	return true

# Pathway Этап 3 — "Микс": puzzles mixing mate/fork/pin at random, without
# revealing which trick applies, so the player must recognise it themselves.
var mix_puzzles_solved := 0

func record_mix_puzzle_solved() -> void:
	mix_puzzles_solved += 1
	if mix_puzzles_solved >= 1: _unlock("mix_first")
	if mix_puzzles_solved >= 10: _unlock("mix_10")
	save_profile()

func theme_progress(theme: String) -> int:
	match theme:
		"mate": return solved_puzzles.size()
		"fork": return fork_puzzles_solved
		"pin": return pin_puzzles_solved
		"backrank": return backrank_puzzles_solved
		"defense": return defense_puzzles_solved
		"deflection": return deflection_puzzles_solved
	return 0

func is_character_unlocked(id: String) -> bool:
	var idx = MapData.index_of(id)
	if idx <= 0:
		return true # first node is always open
	if not is_character_defeated(MapData.CHARACTERS[idx - 1].id):
		return false
	var c = MapData.CHARACTERS[idx]
	var required = c.get("theme_required", 0)
	if required <= 0:
		return true
	return theme_progress(c.get("theme", "")) >= required

func is_character_defeated(id: String) -> bool:
	var c = MapData.by_id(id)
	# task nodes pass automatically once enough theme puzzles are solved;
	# the mix node (Pathway Этап 3) uses its own separate counter. But that
	# quota is a lifetime counter shared by every act, so it can already be
	# satisfied long before the player actually reaches this stop — without
	# the unlocked check, a not-yet-reached task node would silently count
	# as "passed" and unlock everything after it, skipping real battles the
	# player never played (is_character_unlocked calls back into this
	# function for the previous node, so this recursion always terminates
	# at index 0).
	if c.get("node", "") == "task":
		return is_character_unlocked(id) and theme_progress(c.get("theme", "")) >= int(c.get("required", 0))
	if c.get("node", "") == "mix":
		return is_character_unlocked(id) and mix_puzzles_solved >= int(c.get("required", 0))
	return defeated_characters.has(id)

func mark_character_defeated(id: String) -> void:
	var is_new = not defeated_characters.has(id)
	defeated_characters[id] = true
	if is_new:
		if id == "pawn_timofey":
			_unlock("map_start")
		if id == "king_magnus_2":
			_unlock("act2_champion")
		if id == "king_magnus_3":
			_unlock("act3_legend")
		var ch = MapData.by_id(id)
		if ch.get("is_boss", false):
			_unlock("map_boss")
	_check_achievements()
	save_profile()

const MOVE_QUALITY_ACHIEVEMENTS := {
	"good_50": {"threshold": 50, "id": "moves_good_50"},
}

# Уровень внимательности пройден: открывается следующий (строго по порядку).
func complete_attention_level(n: int) -> void:
	if n == attention_done + 1:
		attention_done = n
		save_profile()

# category: "good" | "inaccuracy" | "mistake" | "blunder"
# loss_cp: how many centipawns worse the played move was than the best one
func record_move_quality(category: String, loss_cp: float, fen: String, move_notation: String) -> void:
	match category:
		"good":
			move_good += 1
			# a spectacular perfect move (capture/promotion/castle with ~zero
			# loss) goes to the "best moves" gallery in the diary
			if loss_cp <= 5.0 and (move_notation.contains("x") or move_notation.contains("=") or move_notation.begins_with("O-O")):
				recent_best.push_front({"fen": fen, "move": move_notation, "loss": loss_cp})
				if recent_best.size() > 8:
					recent_best.resize(8)
		"inaccuracy": move_inaccuracy += 1
		"mistake": move_mistake += 1
		"blunder":
			move_blunder += 1
			recent_blunders.push_front({"fen": fen, "move": move_notation, "loss": loss_cp})
			if recent_blunders.size() > 8:
				recent_blunders.resize(8)
	if move_good >= 50:
		_unlock("moves_good_50")
	_check_achievements()
	request_save()

func move_quality_total() -> int:
	return move_good + move_inaccuracy + move_mistake + move_blunder

# Simple heuristic coaching notes for the Дневник (Journal) screen — no
# ambition to be a real chess coach, just enough signal to point the player
# (or the parent watching over their shoulder) at what to practice next.
func journal_advice() -> Array:
	var total = move_quality_total()
	var notes := []
	if total < 12:
		notes.append("Сыграйте побольше партий — дневник начнёт давать более точные советы примерно после десятка-другого ходов.")
		return notes
	var blunder_rate = float(move_blunder) / float(total)
	var mistake_rate = float(move_mistake) / float(total)
	var good_rate = float(move_good) / float(total)
	if blunder_rate > 0.15:
		notes.append("Многовато зевков фигур (%.0f%% ходов) — перед каждым ходом проверяйте, не бьёт ли соперник фигуру, которую вы подставляете." % (blunder_rate * 100.0))
	if mistake_rate > 0.2:
		notes.append("Часто встречаются неточные ходы — попробуйте перед ходом задать себе вопрос «а что мне ответят?» хотя бы на один ход вперёд.")
	if solved_puzzles.size() < 10:
		notes.append("Порешайте задачи на мат в разделе «Задачи» — это быстро прокачивает умение видеть короткие комбинации.")
	if best_win_streak == 0 and games_played >= 3:
		notes.append("Пока нет ни одной победы подряд — попробуйте уровень попроще или начните партию «с форой» на карте.")
	if good_rate > 0.75 and total >= 20:
		notes.append("Отличная точность ходов! Можно попробовать соперника посложнее — рост будет быстрее.")
	if notes.is_empty():
		notes.append("Стабильная игра без явных провалов — продолжайте в том же духе и пробуйте более сильных соперников.")
	return notes

func record_puzzle_solved(puzzle_index: int, mate_in: int) -> void:
	var key = str(puzzle_index)
	if not solved_puzzles.has(key):
		solved_puzzles[key] = true
	if mate_in >= 3:
		_unlock("puzzle_mate3")
	_check_achievements()
	save_profile()

var fork_puzzles_solved := 0

func record_fork_puzzle_solved() -> void:
	fork_puzzles_solved += 1
	if fork_puzzles_solved >= 1: _unlock("fork_first")
	if fork_puzzles_solved >= 10: _unlock("fork_10")
	if fork_puzzles_solved >= 50: _unlock("fork_50")
	_check_achievements()
	save_profile()

var pin_puzzles_solved := 0

func record_pin_puzzle_solved() -> void:
	pin_puzzles_solved += 1
	if pin_puzzles_solved >= 1: _unlock("pin_first")
	if pin_puzzles_solved >= 10: _unlock("pin_10")
	if pin_puzzles_solved >= 50: _unlock("pin_50")
	_check_achievements()
	save_profile()

var backrank_puzzles_solved := 0

func record_backrank_puzzle_solved() -> void:
	backrank_puzzles_solved += 1
	if backrank_puzzles_solved >= 1: _unlock("backrank_first")
	if backrank_puzzles_solved >= 10: _unlock("backrank_10")
	if backrank_puzzles_solved >= 50: _unlock("backrank_50")
	_check_achievements()
	save_profile()

var defense_puzzles_solved := 0

func record_defense_puzzle_solved() -> void:
	defense_puzzles_solved += 1
	if defense_puzzles_solved >= 1: _unlock("defense_first")
	if defense_puzzles_solved >= 10: _unlock("defense_10")
	if defense_puzzles_solved >= 50: _unlock("defense_50")
	_check_achievements()
	save_profile()

var deflection_puzzles_solved := 0

func record_deflection_puzzle_solved() -> void:
	deflection_puzzles_solved += 1
	if deflection_puzzles_solved >= 1: _unlock("deflection_first")
	if deflection_puzzles_solved >= 10: _unlock("deflection_10")
	if deflection_puzzles_solved >= 50: _unlock("deflection_50")
	_check_achievements()
	save_profile()

func _check_achievements() -> void:
	if wins >= 1: _unlock("first_win")
	if wins >= 5: _unlock("wins_5")
	if wins >= 20: _unlock("wins_20")
	if wins >= 50: _unlock("wins_50")
	if best_win_streak >= 3: _unlock("streak_3")
	if best_win_streak >= 5: _unlock("streak_5")
	if best_win_level >= 10: _unlock("beat_level_10")
	if tournament_rating >= 1200: _unlock("rating_1600")
	if tournament_rating >= 1500: _unlock("rating_2000")
	if tournament_rating >= 1700: _unlock("rating_2400")
	var solved_count = solved_puzzles.size()
	if solved_count >= 1: _unlock("puzzle_first")
	if solved_count >= 10: _unlock("puzzle_10")
	if solved_count >= 25: _unlock("puzzle_25")
	if solved_count >= 50: _unlock("puzzle_50")

func _unlock(id: String) -> void:
	if not unlocked_achievements.has(id):
		unlocked_achievements[id] = true
		emit_signal("achievement_unlocked", id)

func achievement_count() -> int:
	return unlocked_achievements.size()

func total_achievement_count() -> int:
	return ACHIEVEMENTS.size()

# --- daily progress history ---
# One snapshot per calendar day the player actually played (updated on every
# save, so the entry always holds the end-of-day state). The Progress screen
# turns these into rating charts and better/worse trends over time.
const DAILY_HISTORY_LIMIT := 400
var daily_history: Dictionary = {} # "YYYY-MM-DD" -> snapshot

func _update_daily_snapshot() -> void:
	var d = Time.get_date_string_from_system()
	daily_history[d] = {
		"rating": rating,
		"trating": tournament_rating,
		"games": games_played,
		"wins": wins,
		"losses": losses,
		"good": move_good,
		"inaccuracy": move_inaccuracy,
		"mistake": move_mistake,
		"blunder": move_blunder,
		"puzzles": total_puzzles_solved(),
		"ach": achievement_count(),
	}
	if daily_history.size() > DAILY_HISTORY_LIMIT:
		var keys = daily_history.keys()
		keys.sort()
		daily_history.erase(keys[0])

func total_puzzles_solved() -> int:
	return solved_puzzles.size() + fork_puzzles_solved + pin_puzzles_solved \
		+ backrank_puzzles_solved + defense_puzzles_solved + deflection_puzzles_solved \
		+ mix_puzzles_solved

func history_days() -> Array:
	var keys = daily_history.keys()
	keys.sort()
	return keys

# --- persistence for the currently active user ---

# Every finished game is logged (opponent, result, move list, move-quality
# counts, the worst moment) and an HTML analysis report is regenerated after
# each game at user://game_analysis.html — the raw material for spotting the
# player's strengths and weaknesses and tuning the game around them.
const GAME_LOG_LIMIT := 300
var game_log: Array = []

func record_game_log(entry: Dictionary) -> void:
	game_log.append(entry)
	while game_log.size() > GAME_LOG_LIMIT:
		game_log.pop_front()
	save_profile()
	write_game_report()

func report_path() -> String:
	return ProjectSettings.globalize_path("user://game_analysis.html")

func write_game_report() -> void:
	var f = FileAccess.open("user://game_analysis.html", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(_build_report_html())
	f.close()

func _build_report_html() -> String:
	var wins := 0
	var losses := 0
	var draws := 0
	var total_moves := 0
	var total_good := 0
	var total_mist := 0
	var total_blun := 0
	var worst_plies: Array = []
	for g in game_log:
		match g.get("result", ""):
			"победа": wins += 1
			"поражение": losses += 1
			_: draws += 1
		total_moves += int(g.get("good", 0)) + int(g.get("inaccuracy", 0)) + int(g.get("mistake", 0)) + int(g.get("blunder", 0))
		total_good += int(g.get("good", 0))
		total_mist += int(g.get("mistake", 0))
		total_blun += int(g.get("blunder", 0))
		if g.get("worst_move_no", 0) > 0:
			worst_plies.append(int(g.worst_move_no))
	var n = game_log.size()
	var acc = (100.0 * total_good / total_moves) if total_moves > 0 else 0.0
	var html := "<!doctype html><html lang=\"ru\"><head><meta charset=\"utf-8\">"
	html += "<title>Анализ партий — %s</title><style>" % display_name
	html += "body{background:#0a0a12;color:#cdd6e0;font-family:'Segoe UI',sans-serif;max-width:900px;margin:0 auto;padding:30px;}"
	html += "h1{color:#1aeaff;}h2{color:#ff33d6;}table{border-collapse:collapse;width:100%;margin:14px 0;}"
	html += "td,th{border:1px solid #2a3040;padding:6px 10px;font-size:14px;text-align:left;}th{color:#1aeaff;}"
	html += ".win{color:#6bf2a0;}.loss{color:#ff6b6b;}.draw{color:#d9bf59;}details{margin:4px 0;}summary{cursor:pointer;color:#7a8698;}"
	html += "</style></head><body><h1>Анализ партий — %s</h1>" % display_name
	html += "<p>Партий записано: <b>%d</b> · Победы: <b class=\"win\">%d</b> · Поражения: <b class=\"loss\">%d</b> · Ничьи: <b class=\"draw\">%d</b></p>" % [n, wins, losses, draws]
	if total_moves > 0:
		html += "<p>Точность за всё время: <b>%.0f%%</b> (точных ходов %d из %d) · Ошибок: %d · Зевков: %d (в среднем %.1f за партию)</p>" % [acc, total_good, total_moves, total_mist, total_blun, (float(total_blun) / max(n, 1))]
	if worst_plies.size() > 0:
		var avg_ply := 0.0
		for w in worst_plies:
			avg_ply += w
		avg_ply /= worst_plies.size()
		var phase = "в дебюте (первые 10 ходов)" if avg_ply <= 10 else ("в миттельшпиле (ходы 11-25)" if avg_ply <= 25 else "в эндшпиле (после 25-го хода)")
		html += "<h2>Слабые места</h2><p>Худший ход партии в среднем случается на <b>%d-м ходу</b> — чаще всего партии ломаются %s. На это стоит направить тренировки.</p>" % [int(avg_ply), phase]
	html += "<h2>Партии</h2><table><tr><th>Дата</th><th>Соперник</th><th>Результат</th><th>Точность</th><th>Зевки</th><th>Худший ход</th></tr>"
	for i in range(game_log.size() - 1, -1, -1):
		var g = game_log[i]
		var gm = int(g.get("good", 0)) + int(g.get("inaccuracy", 0)) + int(g.get("mistake", 0)) + int(g.get("blunder", 0))
		var ga = (100.0 * int(g.get("good", 0)) / gm) if gm > 0 else 0.0
		var cls = "win" if g.get("result", "") == "победа" else ("loss" if g.get("result", "") == "поражение" else "draw")
		var worst_txt = ("ход %d (%s)" % [g.get("worst_move_no", 0), g.get("worst_notation", "")]) if g.get("worst_move_no", 0) > 0 else "—"
		html += "<tr><td>%s</td><td>%s (ур. %d)</td><td class=\"%s\">%s</td><td>%.0f%%</td><td>%d</td><td>%s</td></tr>" % [
			g.get("date", ""), g.get("opponent", ""), g.get("level", 0), cls, g.get("result", ""), ga, int(g.get("blunder", 0)), worst_txt]
		var moves: Array = g.get("moves", [])
		if not moves.is_empty():
			var txt := ""
			for j in range(moves.size()):
				if j % 2 == 0:
					txt += "%d. " % (j / 2 + 1)
				txt += str(moves[j]) + " "
			html += "<tr><td colspan=\"6\"><details><summary>ходы партии</summary>%s</details></td></tr>" % txt
	html += "</table><p style=\"color:#7a8698;font-size:12px;\">Файл обновляется автоматически после каждой партии.</p></body></html>"
	return html

# Backup: profiles live only in user:// (no password, no cloud), so give the
# player a way to save the raw .cfg anywhere and restore it later.
func export_profile(dest_path: String) -> bool:
	if current_user == "":
		return false
	save_profile()
	var src = ProjectSettings.globalize_path(USERS_DIR + current_user + ".cfg")
	return DirAccess.copy_absolute(src, dest_path) == OK

# Содержимое файла профиля (для скачивания из браузера, где нет файловых диалогов).
func export_profile_bytes() -> PackedByteArray:
	if current_user == "":
		return PackedByteArray()
	save_profile()
	return FileAccess.get_file_as_bytes(USERS_DIR + current_user + ".cfg")

# Returns the imported display name, or "" on failure. If the file belongs
# to the currently active user, their state is reloaded from the backup.
func import_profile(src_path: String) -> String:
	var cfg = ConfigFile.new()
	if cfg.load(src_path) != OK:
		return ""
	var nm: String = cfg.get_value("meta", "display_name", "")
	if nm == "":
		return ""
	var key = sanitize_key(nm)
	DirAccess.make_dir_recursive_absolute(USERS_DIR)
	if DirAccess.copy_absolute(src_path, USERS_DIR + key + ".cfg") != OK:
		return ""
	if key == current_user:
		load_profile() # don't switch_user: it would first save over the import
	else:
		switch_user(nm, current_user != "")
	return nm

func save_profile() -> void:
	_save_pending = false
	if current_user == "" or _load_failed:
		return # не затираем профиль, который не удалось прочитать
	_update_daily_snapshot()
	var cfg = ConfigFile.new()
	cfg.set_value("meta", "display_name", display_name)
	cfg.set_value("rating", "value", rating)
	cfg.set_value("rating", "rd", rd)
	cfg.set_value("rating", "volatility", volatility)
	cfg.set_value("stats", "games_played", games_played)
	cfg.set_value("stats", "wins", wins)
	cfg.set_value("stats", "losses", losses)
	cfg.set_value("stats", "draws", draws)
	cfg.set_value("stats", "win_streak", win_streak)
	cfg.set_value("stats", "best_win_streak", best_win_streak)
	cfg.set_value("stats", "best_win_level", best_win_level)
	cfg.set_value("stats", "clean_wins", clean_wins)
	cfg.set_value("puzzles", "solved", solved_puzzles)
	cfg.set_value("achievements", "unlocked", unlocked_achievements)
	cfg.set_value("map", "defeated", defeated_characters)
	cfg.set_value("journal", "move_good", move_good)
	cfg.set_value("journal", "move_inaccuracy", move_inaccuracy)
	cfg.set_value("journal", "move_mistake", move_mistake)
	cfg.set_value("journal", "move_blunder", move_blunder)
	cfg.set_value("journal", "recent_blunders", recent_blunders)
	cfg.set_value("journal", "recent_best", recent_best)
	cfg.set_value("attention", "done", attention_done)
	cfg.set_value("puzzles", "fork_solved", fork_puzzles_solved)
	cfg.set_value("puzzles", "pin_solved", pin_puzzles_solved)
	cfg.set_value("puzzles", "backrank_solved", backrank_puzzles_solved)
	cfg.set_value("puzzles", "defense_solved", defense_puzzles_solved)
	cfg.set_value("puzzles", "deflection_solved", deflection_puzzles_solved)
	cfg.set_value("puzzles", "theme_clean", theme_clean)
	cfg.set_value("puzzles", "mix_puzzles_solved", mix_puzzles_solved)
	cfg.set_value("games", "log", game_log)
	cfg.set_value("road", "stage", road_stage)
	cfg.set_value("road", "blunders_fixed", road_blunders_fixed)
	cfg.set_value("road", "blunders_fixed_fens", blunders_fixed_fens)
	cfg.set_value("puzzles", "generated_solved", solved_generated)
	cfg.set_value("road", "focus_done", road_focus_done)
	cfg.set_value("tourney", "rating", tournament_rating)
	cfg.set_value("tourney", "real_rating", real_rating)
	cfg.set_value("tourney", "rd", tournament_rd)
	cfg.set_value("tourney", "volatility", tournament_volatility)
	cfg.set_value("tourney", "played", tournaments_played)
	cfg.set_value("tourney", "won", tournaments_won)
	cfg.set_value("tourney", "active", active_tournaments)
	cfg.set_value("tourney", "titles", tournament_titles)
	cfg.set_value("tourney", "prep", active_tournament_prep)
	cfg.set_value("tourney", "bots", bot_state)
	cfg.set_value("tourney", "world_events", world_events)
	cfg.set_value("tourney", "bot_games", bot_games)
	cfg.set_value("historic_games", "viewed", historic_games_viewed)
	cfg.set_value("school", "spot_record", school_spot_record)
	cfg.set_value("school", "wisdom_record", school_wisdom_record)
	cfg.set_value("school", "patience_seconds", school_patience_seconds)
	cfg.set_value("history", "daily", daily_history)
	cfg.set_value("puzzles", "streak_count", streak_count)
	cfg.set_value("puzzles", "streak_last_day", streak_last_day)
	cfg.set_value("session", "game_state", game_state)
	cfg.set_value("session", "puzzle_state", puzzle_state)
	cfg.set_value("meta", "last_played_unix", Time.get_unix_time_from_system())
	cfg.set_value("meta", "save_version", SAVE_VERSION)
	var path := USERS_DIR + current_user + ".cfg"
	var tmp := path + ".tmp"
	# пишем во временный файл и подменяем только после успеха: обрыв записи
	# не должен оставить половину профиля
	if cfg.save(tmp) != OK:
		push_error("Не удалось записать профиль: " + tmp)
		return
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")
	if DirAccess.rename_absolute(tmp, path) != OK:
		push_error("Не удалось заменить профиль: " + path)

func load_profile() -> void:
	if current_user == "":
		return
	var cfg = ConfigFile.new()
	var path := USERS_DIR + current_user + ".cfg"
	_load_failed = false
	var err = cfg.load(path)
	if err != OK:
		if not FileAccess.file_exists(path):
			return # новый игрок — читать нечего
		# файл есть, но не читается: пробуем предыдущую копию
		cfg = ConfigFile.new()
		if cfg.load(path + ".bak") != OK:
			_load_failed = true
			push_error("Профиль повреждён и копии нет: " + path)
			return
		push_warning("Профиль повреждён, восстановлен из .bak: " + path)
	display_name = cfg.get_value("meta", "display_name", display_name)
	rating = cfg.get_value("rating", "value", Glicko2.DEFAULT_RATING)
	rd = cfg.get_value("rating", "rd", Glicko2.DEFAULT_RD)
	volatility = cfg.get_value("rating", "volatility", Glicko2.DEFAULT_VOLATILITY)
	games_played = cfg.get_value("stats", "games_played", 0)
	wins = cfg.get_value("stats", "wins", 0)
	losses = cfg.get_value("stats", "losses", 0)
	draws = cfg.get_value("stats", "draws", 0)
	win_streak = cfg.get_value("stats", "win_streak", 0)
	best_win_streak = cfg.get_value("stats", "best_win_streak", 0)
	best_win_level = cfg.get_value("stats", "best_win_level", 0)
	clean_wins = cfg.get_value("stats", "clean_wins", {})
	solved_puzzles = cfg.get_value("puzzles", "solved", {})
	fork_puzzles_solved = cfg.get_value("puzzles", "fork_solved", 0)
	pin_puzzles_solved = cfg.get_value("puzzles", "pin_solved", 0)
	backrank_puzzles_solved = cfg.get_value("puzzles", "backrank_solved", 0)
	defense_puzzles_solved = cfg.get_value("puzzles", "defense_solved", 0)
	deflection_puzzles_solved = cfg.get_value("puzzles", "deflection_solved", 0)
	theme_clean = cfg.get_value("puzzles", "theme_clean", {})
	mix_puzzles_solved = cfg.get_value("puzzles", "mix_puzzles_solved", 0)
	game_log = cfg.get_value("games", "log", [])
	road_stage = cfg.get_value("road", "stage", 0)
	road_blunders_fixed = cfg.get_value("road", "blunders_fixed", 0)
	blunders_fixed_fens = cfg.get_value("road", "blunders_fixed_fens", {})
	solved_generated = cfg.get_value("puzzles", "generated_solved", {})
	road_focus_done = cfg.get_value("road", "focus_done", {})
	tournament_rating = cfg.get_value("tourney", "rating", Glicko2.DEFAULT_RATING)
	real_rating = int(cfg.get_value("tourney", "real_rating", 0))
	tournament_rd = cfg.get_value("tourney", "rd", Glicko2.DEFAULT_RD)
	tournament_volatility = cfg.get_value("tourney", "volatility", Glicko2.DEFAULT_VOLATILITY)
	tournaments_played = cfg.get_value("tourney", "played", 0)
	tournaments_won = cfg.get_value("tourney", "won", 0)
	active_tournaments = cfg.get_value("tourney", "active", {})
	tournament_titles = cfg.get_value("tourney", "titles", {})
	active_tournament_prep = cfg.get_value("tourney", "prep", {})
	bot_state = cfg.get_value("tourney", "bots", {})
	world_events = cfg.get_value("tourney", "world_events", [])
	bot_games = cfg.get_value("tourney", "bot_games", {})
	historic_games_viewed = cfg.get_value("historic_games", "viewed", {})
	school_spot_record = cfg.get_value("school", "spot_record", 0)
	school_wisdom_record = cfg.get_value("school", "wisdom_record", 0)
	school_patience_seconds = cfg.get_value("school", "patience_seconds", 10)
	daily_history = cfg.get_value("history", "daily", {})
	streak_count = cfg.get_value("puzzles", "streak_count", 0)
	streak_last_day = cfg.get_value("puzzles", "streak_last_day", "")
	game_state = cfg.get_value("session", "game_state", {})
	puzzle_state = cfg.get_value("session", "puzzle_state", {})
	unlocked_achievements = cfg.get_value("achievements", "unlocked", {})
	defeated_characters = cfg.get_value("map", "defeated", {})
	move_good = cfg.get_value("journal", "move_good", 0)
	move_inaccuracy = cfg.get_value("journal", "move_inaccuracy", 0)
	move_mistake = cfg.get_value("journal", "move_mistake", 0)
	move_blunder = cfg.get_value("journal", "move_blunder", 0)
	recent_blunders = cfg.get_value("journal", "recent_blunders", [])
	recent_best = cfg.get_value("journal", "recent_best", [])
	attention_done = cfg.get_value("attention", "done", 0)
	last_played_unix = cfg.get_value("meta", "last_played_unix", 0)

	var last = last_played_unix
	if last > 0:
		var now = Time.get_unix_time_from_system()
		var days_elapsed = float(now - last) / 86400.0
		rd = Glicko2.decay_rd(rd, days_elapsed)
		tournament_rd = Glicko2.decay_rd(tournament_rd, days_elapsed)
