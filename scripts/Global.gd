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

# Esc на любом экране: закрывает открытое окошко («Остаться», «Закрыть») или нажимает «Назад»/«В меню».
# Кнопки ищем по имени среди видимых и включённых, в порядке важности.
const ESC_BUTTONS := ["StayButton", "CloseButton", "BackButton", "MenuButton"]

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	for want in ESC_BUTTONS:
		var btn := _find_visible_button(scene, want)
		if btn != null:
			btn.pressed.emit()
			get_viewport().set_input_as_handled()
			return

func _find_visible_button(node: Node, want: String) -> Button:
	if node is Button and node.name == want and node.is_visible_in_tree() and not node.disabled:
		return node
	for c in node.get_children():
		var r := _find_visible_button(c, want)
		if r != null:
			return r
	return null

func _ready() -> void:
	load_settings()
	apply_display_settings()
	_setup_small_screen_scaling()

# --- телефоны и маленькие окна -----------------------------------------------
# Раскладка рассчитана на 1280×800. На телефоне в альбомной ориентации (≈800×360 CSS-пикселей)
# такой холст ужимается до 0,45 и всё становится мелким. Поэтому на низких экранах опорный размер
# уменьшаем: интерфейс остаётся тем же, но масштаб не падает ниже ~0,75. Режим «expand» растягивает
# поле по ширине, так что чёрных полос по бокам нет.
const MIN_LAYOUT_HEIGHT := 600
const FULL_LAYOUT_HEIGHT := 800
const TARGET_UI_SCALE := 0.75
var _rotate_layer: CanvasLayer
var _rotate_label: Label

func _css_screen_size() -> Vector2:
	if OS.has_feature("web"):
		var w = JavaScriptBridge.eval("window.innerWidth", true)
		var h = JavaScriptBridge.eval("window.innerHeight", true)
		if w != null and h != null and float(w) > 0.0 and float(h) > 0.0:
			return Vector2(float(w), float(h))
	return Vector2(DisplayServer.window_get_size())

# Сцены с жёсткой раскладкой 1280×800 (доска, задачи, карта): их поле не растягивается, а
# целиком вписывается в экран, как раньше. Остальные экраны построены на контейнерах и
# перестраиваются под низкий экран.
const FIXED_LAYOUT_SCENES := ["Board", "Puzzle", "Map", "BotMatch", "RoadHome"]
var small_screen := false # низкий экран (телефон в альбомной ориентации): стоит укрупнить шрифты

func _setup_small_screen_scaling() -> void:
	var win := get_window()
	win.size_changed.connect(_apply_small_screen_scaling)
	get_tree().node_added.connect(_on_node_added)
	_apply_small_screen_scaling()

# Новая сцена — узел прямо под корнем: выбираем для неё режим масштабирования.
func _on_node_added(node: Node) -> void:
	if node.get_parent() == get_tree().root and node != self and node.scene_file_path != "":
		_apply_small_screen_scaling.call_deferred()

func _current_scene_is_fixed() -> bool:
	var sc := get_tree().current_scene
	if sc == null:
		# сцена ещё не стала текущей — смотрим на последнего ребёнка корня
		var root := get_tree().root
		sc = root.get_child(root.get_child_count() - 1)
	return sc != null and sc.name in FIXED_LAYOUT_SCENES

func _apply_small_screen_scaling() -> void:
	if DisplayServer.get_name() == "headless":
		return # проверки без окна меряют вёрстку на штатных 1280×800
	var css := _css_screen_size()
	small_screen = css.y < 700.0
	var win := get_window()
	if _current_scene_is_fixed():
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		win.content_scale_size = Vector2i(1280, 800)
	else:
		# высота опорного холста: чем ниже экран, тем меньше, но не ниже MIN_LAYOUT_HEIGHT
		var layout_h := clampi(roundi(css.y / TARGET_UI_SCALE), MIN_LAYOUT_HEIGHT, FULL_LAYOUT_HEIGHT)
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		win.content_scale_size = Vector2i(roundi(layout_h * 1.6), layout_h)
	_update_rotate_hint(css)

# Укрупняет шрифты и кнопки внутри node (боковые панели на телефоне). Размер читаем с учётом темы.
func boost_fonts(node: Node, factor: float) -> void:
	if node is Control:
		var c := node as Control
		for kind in ["font_size", "normal_font_size"]:
			if c.has_theme_font_size(kind):
				c.add_theme_font_size_override(kind, roundi(c.get_theme_font_size(kind) * factor))
		if c is Button:
			c.custom_minimum_size.y = maxf(c.custom_minimum_size.y, 52.0)
	for ch in node.get_children():
		boost_fonts(ch, factor)

# Узкий телефон в портрете: поле не помещается, просим повернуть устройство.
func _update_rotate_hint(css: Vector2) -> void:
	var need := css.x < 600.0 and css.y > css.x
	if need and _rotate_layer == null:
		_rotate_layer = CanvasLayer.new()
		_rotate_layer.layer = 100
		var bg := ColorRect.new()
		bg.color = Color(0.02, 0.02, 0.05, 0.96)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		_rotate_layer.add_child(bg)
		_rotate_label = Label.new()
		_rotate_label.text = "Поверните телефон горизонтально\nИгра рассчитана на широкий экран"
		_rotate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rotate_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_rotate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_rotate_label.add_theme_font_size_override("font_size", 28)
		_rotate_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.add_child(_rotate_label)
		add_child(_rotate_layer)
	if _rotate_layer != null:
		_rotate_layer.visible = need

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
	cfg.set_value("settings", Themes.SETTINGS_KEY, Themes.current_id)
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
