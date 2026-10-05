extends Node

var difficulty: int = 5
var player_color: String = "w"
var sound_on: bool = true
var puzzle_start_index: int = 0
var puzzle_jump: int = -1 # >=0: открыть именно эту задачу банка, игнорируя автопродолжение (выбор из хаба задач)
var puzzle_theme: String = "" # set before entering Puzzle.tscn to jump straight into a theme (map task nodes)
var map_character_id: String = "" # set before entering Board.tscn for a map battle; "" = free play
var map_assist: bool = false # true = start the map battle from an advantaged position instead of scratch
var coop_team: bool = false # quick-play "папа и сын": player + partner AI vs two AIs, difficulty from the menu slider

# "Дорога домой" — personalised training journey. road_mode is set before
# entering Board.tscn for its battle stages: "predict" (guess the rival's
# reply before it moves), "xray" (pieces vanish into fog after 12s — move
# from memory), "shadow" / "shadow_final" (an AI twin built from the
# player's own rating and blunder rate).
var road_mode: String = ""
var road_stage_playing: int = -1

# Режим «Внимательность»: 0 = выключен, 1..50 = номер уровня. Во время партии
# на доске подсвечиваются угрозы (свои фигуры под боем / фигуры соперника под
# ударом); чем выше уровень, тем меньше подсказок и сильнее ИИ.
var attention_level: int = 0

# Tournament context: non-empty while a tournament game is being played.
# Set by Tournaments.gd before entering Board.tscn:
# {tid, tname, opp_idx, opp_name, level, tc, inc, round, color}
# tc = seconds per side (0 = no clock), inc = increment seconds per move.
var tournament_game: Dictionary = {}

# Товарищеская партия с конкретным игроком из «Базы игроков» (BotsHub.gd).
# В отличие от турнира лига не важна: вызвать можно кого угодно, хоть легенду.
# {id, name, level, rating, tc, inc, format} — tc/inc как у турнира.
# Влияет на обычный рейтинг игрока и на постоянный рейтинг самого бота, но
# не на турнирный рейтинг и не на турнирные таблицы.
var friendly_game: Dictionary = {}

# Просмотр партии двух ботов (BotMatch.tscn): {white, black} — id из BotData.
# Партия играется по-настоящему в момент просмотра: заранее ничего не хранится.
var bot_match: Dictionary = {}

# «Школа юного шахматиста» (School.tscn) — режимы против спешки:
# "spot" — «Что изменилось?»: после хода ИИ фигуры на миг исчезают, и надо
#          кликнуть клетку, куда сходил соперник, прежде чем ходить самому;
# "patience" — «Школа терпения»: ход разрешён только после паузы на
#          обдумывание, обдуманные ходы копят очки мудрости.
var school_mode: String = ""

var handicap_enabled: bool = false # setting: whether "С форой" is offered anywhere in the game
# setting: adaptive difficulty — when on, every AI opponent's level is pulled
# toward the level matching the player's current rating (see adaptive_level());
# when off, levels are exactly as chosen/authored (slider, map nodes, drills).
var adaptive_difficulty: bool = false
# setting: whether the FIDE 50-move rule (no capture/pawn move in 50 moves =
# automatic draw) applies; off by default so games can run as long as the
# player wants, can be turned on for the standard rule.
var fifty_move_rule_enabled: bool = false
var music_volume: float = 0.7 # 0..1, background music loudness
var sfx_volume: float = 0.8 # 0..1, move/capture/result sounds loudness
var move_sound_style: int = 0 # index into SoundFX.MOVE_STYLES

var fullscreen_enabled: bool = false
var window_resolution_index: int = 1 # index into WINDOW_RESOLUTIONS, used only when windowed
const WINDOW_RESOLUTIONS := [
	Vector2i(1024, 640),
	Vector2i(1280, 800),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]

# Названия не обещают шахматных званий: сила уровней измерена самоигрой, см. CalibrateLevels.
const DIFFICULTY_NAMES := [
	"1 — Пешка", "2 — Новичок", "3 — Любитель", "4 — Стажёр", "5 — Клубный игрок",
	"6 — Разрядник", "7 — Боец", "8 — Тактик", "9 — Стратег", "10 — Наставник",
	"11 — Расчётливый", "12 — Машина", "13 — Провидец", "14 — Титан", "15 — Немезида",
	"16 — Оракул", "17 — Легенда", "18 — Бессмертный", "19 — Абсолют", "20 — Квант",
	"21 — Нейрон", "22 — Комета", "23 — Сверхновая", "24 — Горизонт", "25 — Бесконечность"
]
const MAX_DIFFICULTY := 25

const SETTINGS_PATH := "user://settings.cfg"

func _ready() -> void:
	load_settings()
	apply_display_settings()

# Applies the current fullscreen/resolution choice to the actual OS window.
# Windowed mode gets re-centered on the screen after resizing so the game
# never ends up half off-screen after switching resolutions.
func apply_display_settings() -> void:
	if OS.has_feature("web"):
		# в браузере размером окна управляет страница; работает только полный экран
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen_enabled else DisplayServer.WINDOW_MODE_WINDOWED)
		return
	if fullscreen_enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var idx = clampi(window_resolution_index, 0, WINDOW_RESOLUTIONS.size() - 1)
	var size: Vector2i = WINDOW_RESOLUTIONS[idx]
	DisplayServer.window_set_size(size)
	var screen_size = DisplayServer.screen_get_size()
	DisplayServer.window_set_position((screen_size - size) / 2)

func difficulty_label(lvl: int) -> String:
	var idx = clampi(lvl, 1, MAX_DIFFICULTY) - 1
	return DIFFICULTY_NAMES[idx]

# The AI level whose rating band matches the player's current rating
# (same rule as the Road Home "shadow" opponent uses).
func rating_level() -> int:
	var lvl := 1
	for i in range(Profile.LEVEL_RATING.size()):
		if Profile.rating >= float(Profile.LEVEL_RATING[i]) - 100.0:
			lvl = i + 1
	return lvl

# ИИ-уровень для уровня внимательности n (1..50): плавный рост от 1 до 17.
func attention_ai_level(n: int) -> int:
	return clampi(1 + roundi((n - 1) * 16.0 / 49.0), 1, MAX_DIFFICULTY)

# Какие подсказки-угрозы показывать на уровне n:
# "both" — свои под боем (красным) и чужие под ударом (зелёным);
# "red" — только свои под боем; "green" — только чужие под ударом;
# "flash" — обе, но лишь 5 секунд после хода соперника; "none" — экзамен.
func attention_hint_mode(n: int) -> String:
	if n <= 10: return "both"
	if n <= 20: return "red"
	if n <= 30: return "green"
	if n <= 40: return "flash"
	return "none"

# Adaptive difficulty: nudge the authored level toward the player's rating level,
# by at most ADAPTIVE_MAX_SHIFT either way. Until the player has ADAPTIVE_MIN_GAMES
# rated games the rating is only a guess, so the authored level passes through
# (the old "average with rating_level()" made the very first battle level 4).
# With the setting off, the base level passes through as well.
const ADAPTIVE_MIN_GAMES := 5
const ADAPTIVE_MAX_SHIFT := 2

func adaptive_level(base: int) -> int:
	if not adaptive_difficulty or Profile.games_played < ADAPTIVE_MIN_GAMES:
		return clampi(base, 1, MAX_DIFFICULTY)
	var shift := clampi(rating_level() - base, -ADAPTIVE_MAX_SHIFT, ADAPTIVE_MAX_SHIFT)
	return clampi(base + shift, 1, MAX_DIFFICULTY)

func save_settings() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("settings", "handicap_enabled", handicap_enabled)
	cfg.set_value("settings", "adaptive_difficulty", adaptive_difficulty)
	cfg.set_value("settings", "fifty_move_rule_enabled", fifty_move_rule_enabled)
	cfg.set_value("settings", "music_volume", music_volume)
	cfg.set_value("settings", "sfx_volume", sfx_volume)
	cfg.set_value("settings", "move_sound_style", move_sound_style)
	cfg.set_value("settings", "fullscreen_enabled", fullscreen_enabled)
	cfg.set_value("settings", "window_resolution_index", window_resolution_index)
	cfg.save(SETTINGS_PATH)

func load_settings() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	handicap_enabled = cfg.get_value("settings", "handicap_enabled", false)
	adaptive_difficulty = cfg.get_value("settings", "adaptive_difficulty", false)
	fifty_move_rule_enabled = cfg.get_value("settings", "fifty_move_rule_enabled", false)
	music_volume = cfg.get_value("settings", "music_volume", 0.7)
	sfx_volume = cfg.get_value("settings", "sfx_volume", 0.8)
	move_sound_style = cfg.get_value("settings", "move_sound_style", 0)
	fullscreen_enabled = cfg.get_value("settings", "fullscreen_enabled", false)
	window_resolution_index = cfg.get_value("settings", "window_resolution_index", 1)

# --- фоновые вычисления -----------------------------------------------------
# В браузере (Web-экспорт без потоков — GitHub Pages не умеет отдавать заголовки
# для многопоточности) Thread недоступен. Тяжёлый поиск ИИ теперь занимает
# доли секунды, поэтому там он просто выполняется в основном потоке — после двух
# кадров, чтобы успела прорисоваться надпись «ИИ думает...».
var can_thread: bool = not OS.has_feature("web")

# Выполняет fn в фоне (потоке) и ждёт результата, не замораживая кадры.
# Использовать так: await Global.run_bg(func(): result.move = ai.choose_move(pos))
func run_bg(fn: Callable) -> void:
	if not can_thread:
		await get_tree().process_frame
		await get_tree().process_frame
		fn.call()
		return
	var thread := Thread.new()
	thread.start(fn)
	while thread.is_alive():
		await get_tree().process_frame
	thread.wait_to_finish()
