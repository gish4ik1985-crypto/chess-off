extends Control

# Main menu, restructured to always fit one screen:
#   главный экран — только разделы (Карта / Турниры / Играть / Обучение /
#   Настройки / Выход);
#   "Турниры и соперники" — турниры, подготовка к ним и база игроков
#   (всё три раньше висели по отдельности на главном экране);
#   "Играть" — быстрая игра, папа и сын, товарищеская партия с игроком базы;
#   "Обучение и задачи" — подменю (Дорога домой, задачи, дневник).

@onready var main_panel: PanelContainer = $ContentCenter/MainPanel
@onready var play_panel: PanelContainer = $ContentCenter/PlayPanel
@onready var train_panel: PanelContainer = $ContentCenter/TrainPanel
@onready var tourney_panel: PanelContainer = $ContentCenter/TourneyPanel
@onready var difficulty_slider: HSlider = $ContentCenter/PlayPanel/VBox/DifficultyRow/DifficultySlider
@onready var difficulty_value_label: Label = $ContentCenter/PlayPanel/VBox/DifficultyRow/DifficultyValueLabel
@onready var difficulty_name_label: Label = $ContentCenter/PlayPanel/VBox/DifficultyNameLabel
@onready var white_button: Button = $ContentCenter/PlayPanel/VBox/ColorRow/WhiteButton
@onready var black_button: Button = $ContentCenter/PlayPanel/VBox/ColorRow/BlackButton
@onready var bg: Node2D = $DecorBoard
@onready var rating_label: Label = $ProfileBar/HBox/RatingLabel
@onready var achievements_label: Label = $ProfileBar/HBox/AchievementsSummary
@onready var user_label: Label = $ProfileBar/HBox/UserLabel

var chosen_color := "w"

# Подсказки при наведении: что делает кнопка и что значат термины.
const TOOLTIPS := {
	"ProfileBar/HBox/ProfileButton": "Профиль: рейтинг, ступень и Индекс мастерства — оценка 8 навыков (от 0 до 100) с диапазоном неопределённости.",
	"ProfileBar/HBox/TrophyButton": "Награды: кубки, медали и достижения.",
	"ProfileBar/HBox/JournalButton": "Дневник: качество ходов, партии и разбор ошибок.",
	"ProfileBar/HBox/SwitchUserButton": "Выбрать другого игрока. Прогресс каждого хранится отдельно.",
	"ContentCenter/MainPanel/VBox/MapButton": "Путь по стране: бои с персонажами и задачи. Сложность подстраивается под вас («живая сложность»).",
	"ContentCenter/MainPanel/VBox/TourneyMenuButton": "Турниры со своим рейтингом, подготовка к ним и база игроков.",
	"ContentCenter/MainPanel/VBox/PlayMenuButton": "Быстрая партия против компьютера, командная игра и товарищеские партии.",
	"ContentCenter/MainPanel/VBox/TrainMenuButton": "Задачи, Дорога домой, Внимательность, Школа и разбор партий великих.",
	"ContentCenter/PlayPanel/VBox/PlayButton": "Партия с выбранной сложностью. Подсказки и откаты не идут в ступень и рейтинг.",
	"ContentCenter/TrainPanel/VBox/RoadButton": "Личный путь: остановки появляются там, где вы чаще ошибаетесь.",
	"ContentCenter/TrainPanel/VBox/AttentionButton": "Тренажёр: на доске подсвечены угрозы, подсказки постепенно исчезают.",
	"ContentCenter/TrainPanel/VBox/SchoolButton": "Упражнения «Что изменилось?» и «Школа терпения»: смотреть и не спешить.",
}

func _ready() -> void:
	Global.add_version_label(self)
	for path in TOOLTIPS:
		var n = get_node_or_null(path)
		if n != null:
			n.tooltip_text = TOOLTIPS[path]
	$ContentCenter/MainPanel/VBox/QuitButton.visible = not OS.has_feature("web")
	if not Profile.has_user():
		get_tree().change_scene_to_file.call_deferred("res://scenes/Login.tscn")
		return
	Global.back_stack.clear() # главный экран — начало любого пути
	Global.tournament_game = {} # safety: no stale tournament context after returning to menu
	Global.friendly_game = {} # safety: товарищеская партия начинается только из базы игроков
	Global.attention_level = 0 # safety: attention mode only starts from its hub
	Global.school_mode = "" # safety: school modes only start from their hub
	Global.road_mode = "" # safety: road stages only start from RoadHome.tscn
	Global.map_assist = false # safety: assist choice only meant for the map battle it was picked for
	difficulty_slider.max_value = Global.MAX_DIFFICULTY
	difficulty_slider.value = Global.difficulty
	_update_difficulty_label()
	_update_color_buttons()
	_update_profile_bar()
	difficulty_slider.value_changed.connect(_on_difficulty_changed)
	white_button.pressed.connect(func(): chosen_color = "w"; _update_color_buttons())
	black_button.pressed.connect(func(): chosen_color = "b"; _update_color_buttons())
	bg.draw.connect(_on_bg_draw)
	_add_players_button()
	_build_new_layout()
	_apply_compact_layout()
	var want := Global.menu_panel
	Global.menu_panel = ""
	match want:
		"play": _show_panel(play_panel)
		"train": _show_panel(train_panel)
		"tourney": _show_panel(tourney_panel)
		"school": _show_panel(school_panel)
	_equalize_panels.call_deferred()
	_refresh_role.call_deferred()
	_update_hw_button.call_deferred()
	_ask_full_name_if_needed.call_deferred()

# Раздел «Школа»: всё, что связывает учеников и учителя.
func _build_school_panel() -> void:
	school_panel = PanelContainer.new()
	school_panel.visible = false
	$ContentCenter.add_child(school_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.custom_minimum_size = Vector2(420, 0)
	school_panel.add_child(vb)
	var back := Button.new()
	back.text = "← Назад"
	back.custom_minimum_size.y = 44
	back.pressed.connect(func(): _show_panel(main_panel))
	back.name = "BackButton"
	vb.add_child(back)
	var title := Label.new()
	title.text = "ШКОЛА"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.35))
	vb.add_child(title)
	vb.add_child(HSeparator.new())
	_ann_button = _school_item(vb, "📢 Объявления", "res://scenes/Announcements.tscn")
	_school_item(vb, "📅 Расписание и планы", "res://scenes/Schedule.tscn")
	_hw_button = _school_item(vb, "📚 Домашние задания", "res://scenes/Homework.tscn")
	_school_item(vb, "🏫 Турниры школы — онлайн", "res://scenes/ClubTourneys.tscn")
	_chat_button = _school_item(vb, "💬 Чат школы", "res://scenes/Chat.tscn")
	if Roles.can(Profile.role, "open_admin"):
		_school_item(vb, "📒 Задачник учителя", "res://scenes/Planner.tscn")

func _school_item(vb: VBoxContainer, text: String, scene: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 46
	b.pressed.connect(func(): _open(scene))
	vb.add_child(b)
	return b

func _update_school_badges() -> void:
	if _ann_button != null:
		var n := SchoolData.unread_announcements().size() if SchoolData.loaded else 0
		_ann_button.text = "📢 Объявления" + ("  · новых: %d" % n if n > 0 else "")
	if _chat_button != null:
		_chat_button.text = "💬 Чат школы" + ("  · новые сообщения" if ChatScreen.has_unread() else "")
	if _lobby != null:
		var total := (SchoolData.unread_announcements().size() if SchoolData.loaded else 0) + (Homework.pending().size() if Homework.loaded else 0)
		_lobby.set_school_badge(total)

# Новое объявление показываем всплывающим окном сразу после входа (один раз, пока не прочитано).
static var _ann_popup_shown_for := 0

func _show_announcement_popup() -> void:
	if not SchoolData.loaded:
		return
	var fresh := SchoolData.unread_announcements()
	if fresh.is_empty():
		return
	var newest := 0
	for a in fresh:
		newest = maxi(newest, int(a.get("at", 0)))
	if _ann_popup_shown_for >= newest:
		return
	_ann_popup_shown_for = newest
	var dlg := AcceptDialog.new()
	dlg.title = "📢 Объявление" if fresh.size() == 1 else "📢 Новые объявления: %d" % fresh.size()
	var text := ""
	for a in fresh.slice(0, 3):
		text += "%s\n%s\n\n" % [String(a.get("title", "")), String(a.get("text", ""))]
	dlg.dialog_text = text.strip_edges()
	dlg.ok_button_text = "Понятно"
	dlg.confirmed.connect(func():
		SchoolData.mark_announcements_seen()
		_update_school_badges()
		dlg.queue_free())
	dlg.canceled.connect(func():
		SchoolData.mark_announcements_seen()
		_update_school_badges()
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered(Vector2i(520, 260))

# Все четыре панели (главная и три раздела) одного размера — при переходах рамка не «прыгает»,
# а «Назад» в подменю всегда на одном и том же месте.
func _equalize_panels() -> void:
	await get_tree().process_frame
	var panels := [play_panel, train_panel, tourney_panel, school_panel] # лобби — своего размера
	var need := Vector2.ZERO
	for p in panels:
		var m: Vector2 = (p as Control).get_combined_minimum_size()
		need = Vector2(maxf(need.x, m.x), maxf(need.y, m.y))
	need.y = minf(need.y, get_viewport_rect().size.y - 140.0)
	for p in panels:
		(p as Control).custom_minimum_size = need

# После онлайн-входа без ФИО (старые аккаунты) один раз за сеанс просим его вписать.
static var _role_checked_uid := ""

# Роль (ученик / тренер / администратор) подтягивается из облака один раз за сеанс.
func _refresh_role() -> void:
	if _role_checked_uid == Cloud.uid or not (Cloud.enabled and Cloud.signed_in):
		return
	_role_checked_uid = Cloud.uid
	await Cloud.refresh_role()
	await Homework.load_all()
	await Homework.auto_submit_done()
	await ClubTourney.load_mine()
	await ChatScreen.check_unread()
	await SchoolData.load_all()
	if is_inside_tree():
		_update_profile_bar()
		_update_bell()
		_update_hw_button()
		_update_school_badges()
		_show_announcement_popup()

func _update_hw_button() -> void:
	if _hw_button == null:
		return
	var n := Homework.pending().size() if Homework.loaded else 0
	_hw_button.text = "📚 Домашние задания" + ("  · новых: %d" % n if n > 0 else "")

static var _fio_asked := false

func _ask_full_name_if_needed() -> void:
	if _fio_asked or Profile.full_name.strip_edges() != "" or not (Cloud.enabled and Cloud.signed_in):
		return
	_fio_asked = true
	var dlg := ConfirmationDialog.new()
	dlg.title = "Как вас зовут?"
	dlg.dialog_text = "Впишите ФИО — оно будет показано в игре."
	dlg.ok_button_text = "Сохранить"
	dlg.cancel_button_text = "Позже"
	var edit := LineEdit.new()
	edit.placeholder_text = "Фамилия Имя Отчество"
	edit.max_length = 60
	dlg.add_child(edit)
	dlg.register_text_enter(edit)
	dlg.confirmed.connect(func():
		var t := edit.text.strip_edges()
		if t.length() >= 3:
			Profile.full_name = t
			Profile.save_profile()
			_update_profile_bar()
			Cloud.push_profile())
	dlg.canceled.connect(dlg.queue_free)
	dlg.confirmed.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered(Vector2i(460, 150))
	edit.grab_focus()

# Низкий экран (телефон в альбомной ориентации): верхняя панель ужимается до одной строки,
# а меню получает освободившееся место, чтобы панели не налезали друг на друга.
func _apply_compact_layout() -> void:
	if get_viewport_rect().size.y >= 700.0:
		return
	achievements_label.visible = false
	var bar: Control = $ProfileBar
	# высота полосы — по её содержимому (карточка игрока выше прежней строки текста)
	var h := bar.get_combined_minimum_size().y
	bar.offset_top = 8
	bar.offset_bottom = 8 + h
	$ContentCenter.offset_top = 16 + h
	for panel in [main_panel, play_panel, train_panel, tourney_panel, school_panel]:
		var vb := panel.get_child(0) as VBoxContainer
		if vb != null:
			vb.add_theme_constant_override("separation", 6)

# --- новая структура меню ---------------------------------------------------------------------
# Главный экран: «Продолжить» + три раздела (Играть / Учиться / Соревнования). Профиль, уведомления и
# настройки — в верхней полосе. Остальные пункты разложены по смыслу: карта — в «Учиться»,
# подготовка к турниру — внутри «Турниров», дневник и награды — в «Моём профиле».
var _bell_button: Button
var _hw_button: Button
var _chat_button: Button
var _school_btn: Button
var _ann_button: Button
var school_panel: PanelContainer
var _lobby: Node

# Главная панель — игровое лобби: старые пункты прячутся, вместо них плитки и большая кнопка «Играть».
func _build_lobby() -> void:
	var main_vb: VBoxContainer = $ContentCenter/MainPanel/VBox
	for ch in main_vb.get_children():
		(ch as CanvasItem).visible = false
	main_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	main_panel.set_meta("themed", true)
	_lobby = preload("res://scripts/Lobby.gd").new()
	main_vb.add_child(_lobby)
	_lobby.build(self)
var _notice_layer: Control

func _build_new_layout() -> void:
	var main_vb: VBoxContainer = $ContentCenter/MainPanel/VBox
	($ContentCenter/MainPanel/VBox/TitleLabel as Label).text = "ИРБИС"
	($ContentCenter/MainPanel/VBox/SubtitleLabel as Label).text = "Шахматный клуб · 25 уровней сложности"
	var seal := TextureRect.new()
	seal.texture = load("res://assets/brand/seal_512.png")
	seal.custom_minimum_size = Vector2(64, 64)
	seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vb.add_child(seal)
	main_vb.move_child(seal, 0)
	$ContentCenter/MainPanel/VBox/MapButton.visible = false
	$ContentCenter/MainPanel/VBox/SettingsButton.visible = false
	var play_b: Button = $ContentCenter/MainPanel/VBox/PlayMenuButton
	var train_b: Button = $ContentCenter/MainPanel/VBox/TrainMenuButton
	var tourney_b: Button = $ContentCenter/MainPanel/VBox/TourneyMenuButton
	play_b.text = "Играть  →"
	train_b.text = "Учиться  →"
	tourney_b.text = "Соревнования  →"
	for b in [play_b, train_b, tourney_b]:
		(b as Button).custom_minimum_size.y = 52
	_add_continue_block(main_vb)
	# порядок: заголовок, подзаголовок, черта, «Продолжить» + подписи, затем Играть / Учиться / Соревнования
	var base := play_b.get_index()
	main_vb.move_child(play_b, main_vb.get_child_count() - 1)
	main_vb.move_child(train_b, main_vb.get_child_count() - 1)
	main_vb.move_child(tourney_b, main_vb.get_child_count() - 1)
	main_vb.move_child($ContentCenter/MainPanel/VBox/QuitButton, main_vb.get_child_count() - 1)
	_school_btn = Button.new()
	_school_btn.text = "Школа  →"
	_school_btn.tooltip_text = "Объявления, расписание, домашние задания, турниры школы и чат."
	_school_btn.custom_minimum_size.y = 52
	_school_btn.pressed.connect(func(): _show_panel(school_panel))
	main_vb.add_child(_school_btn)
	main_vb.move_child(_school_btn, main_vb.get_child_count() - 2)
	_build_school_panel()
	_build_lobby()

	# «Назад» — первой строкой подменю, а не в самом низу
	for panel in [play_panel, train_panel, tourney_panel]:
		var vb := panel.get_child(0) as VBoxContainer
		var back_b: Button = vb.get_node("BackButton")
		vb.move_child(back_b, 0)
		back_b.custom_minimum_size.y = 44

	# «Играть»
	$ContentCenter/PlayPanel/VBox/FriendlyButton.text = "Сыграть с ботом — выбрать соперника"
	# «Учиться»: карта стала частью обучения; дневник переехал в профиль
	var tv: VBoxContainer = $ContentCenter/TrainPanel/VBox
	tv.get_node("TitleLabel").text = "УЧИТЬСЯ"
	tv.get_node("ProgressButton").visible = false
	var map_b := Button.new()
	map_b.text = "Карта шахматной страны — основной путь"
	map_b.tooltip_text = "Путь по стране: бои с персонажами и задачи. Сложность подстраивается под вас."
	map_b.pressed.connect(func(): _open("res://scenes/Map.tscn"))
	tv.add_child(map_b)
	tv.move_child(map_b, 2)
	var nb := Button.new()
	nb.text = "📓 Записная книжка партий — записать, разобрать, сыграть"
	nb.pressed.connect(func(): _open("res://scenes/Notebook.tscn"))
	tv.add_child(nb)
	tv.move_child(nb, 3)
	tv.get_node("RoadHint").visible = false # смысл «Дороги» теперь в подсказке кнопки и на главном экране
	var road_b: Button = tv.get_node("RoadButton")
	road_b.tooltip_text = "Дорога растёт из твоих партий: новые остановки для твоих слабых мест."
	var new_stops := _new_road_stops()
	if new_stops > 0:
		road_b.text = "Дорога домой · новых остановок: %d" % new_stops
	# «Соревнования»
	var cv: VBoxContainer = $ContentCenter/TourneyPanel/VBox
	cv.get_node("TitleLabel").text = "СОРЕВНОВАНИЯ"
	cv.get_node("TournamentPrepButton").visible = false
	var running := _running_tournaments()
	var tb: Button = cv.get_node("TournamentsButton")
	tb.text = "Турниры (рейтинг, турнир дня, подготовка)" + ("  · идёт: %d" % running if running > 0 else "")
	cv.get_node("BotsButton").text = "Лига ботов — рейтинги и карточки соперников"

	# верхняя полоса: профиль, уведомления, настройки
	var hb: HBoxContainer = $ProfileBar/HBox
	achievements_label.visible = false
	for n in ["TrophyButton", "JournalButton", "SwitchUserButton"]:
		hb.get_node(n).visible = false
	var prof: Button = hb.get_node("ProfileButton")
	prof.text = "Мой профиль"
	prof.custom_minimum_size.x = 150
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)
	hb.move_child(spacer, prof.get_index())
	_bell_button = Button.new()
	_bell_button.custom_minimum_size = Vector2(70, 0)
	_bell_button.tooltip_text = "Уведомления: турниры, новые остановки дороги, серия дней."
	_bell_button.pressed.connect(_show_notifications)
	hb.add_child(_bell_button)
	hb.move_child(_bell_button, prof.get_index() + 1)
	var gear := Button.new()
	gear.text = "⚙"
	gear.custom_minimum_size = Vector2(52, 0)
	gear.tooltip_text = "Настройки: звук, оформление, игра «с форой», профиль в файл."
	gear.pressed.connect(func(): _open("res://scenes/Settings.tscn"))
	hb.add_child(gear)
	hb.move_child(gear, prof.get_index() + 2)
	# карточка игрока и «ресурсы» вместо строки с текстом; «Мой профиль» — нажатием на карточку
	user_label.visible = false
	rating_label.visible = false
	prof.visible = false
	preload("res://scripts/Lobby.gd").build_hud(self, hb)
	_update_bell()
	Global.update_ready.connect(_update_bell)

func _running_tournaments() -> int:
	Profile.expire_daily()
	var n := 0
	for id in Profile.active_tournaments:
		var st: Dictionary = Profile.active_tournaments[id]
		if not st.get("done", false):
			n += 1
	return n

# Остановки «Дороги домой», выросшие из ошибок игрока и ещё не пройденные.
func _new_road_stops() -> int:
	var n := 0
	for st in Profile.dynamic_road_stages():
		if not Profile.road_focus_done.has(st.kind):
			n += 1
	return n

# Что продолжить: незаконченная партия → идущий турнир → следующий шаг на карте.
func _continue_info() -> Dictionary:
	Profile.expire_daily()
	var gs: Dictionary = Profile.game_state
	if not gs.is_empty():
		var mv := int((gs.get("move_history", []) as Array).size())
		var who := "партия против компьютера"
		if String(gs.get("map_character_id", "")) != "":
			var ch = MapData.by_id(String(gs.map_character_id))
			who = "бой на карте: %s" % String(ch.get("name", "соперник"))
		return {"title": "Продолжить партию", "sub": "%s, сыграно ходов: %d" % [who, mv], "kind": "game"}
	for id in Profile.active_tournaments:
		var st: Dictionary = Profile.active_tournaments[id]
		if not st.get("done", false):
			return {"title": "Продолжить турнир", "sub": "«%s»: тур %d из %d" % [st.name, int(st.round) + 1, int(st.rounds)], "kind": "tourney"}
	return {"title": "Играть дальше", "sub": "Следующий шаг на карте шахматной страны", "kind": "map"}

func _add_continue_block(main_vb: VBoxContainer) -> void:
	var info := _continue_info()
	var b := Button.new()
	b.name = "ContinueButton"
	b.text = String(info.title)
	b.custom_minimum_size = Vector2(0, 62)
	b.theme_type_variation = "PrimaryButton"
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(_on_continue_pressed.bind(String(info.kind)))
	main_vb.add_child(b)
	var sub := Label.new()
	sub.text = String(info.sub)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	main_vb.add_child(sub)
	var hint := _road_hint()
	if hint != "":
		var l := Label.new()
		l.text = hint
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", Color(0.95, 0.8, 0.35))
		main_vb.add_child(l)

func _road_hint() -> String:
	for st in Profile.dynamic_road_stages():
		if not Profile.road_focus_done.has(st.kind):
			return "Дорога домой: новая остановка — «%s»" % st.name
	return ""

func _on_continue_pressed(kind: String) -> void:
	match kind:
		"game":
			var gs: Dictionary = Profile.game_state
			Global.difficulty = int(gs.get("difficulty", Global.difficulty))
			Global.player_color = String(gs.get("player_color", "w"))
			Global.map_character_id = String(gs.get("map_character_id", ""))
			Global.map_assist = bool(gs.get("map_assist", false))
			Global.coop_team = bool(gs.get("coop_team", false))
			Global.open("res://scenes/Board.tscn")
		"tourney":
			Global.open("res://scenes/Tournaments.tscn", Global.MENU_SCENE)
		_:
			Global.open("res://scenes/Map.tscn", Global.MENU_SCENE)

# --- уведомления --------------------------------------------------------------------------------
# Напоминания, собранные из профиля. Системные уведомления на телефон появятся вместе с облаком:
# тогда сюда же придут приглашения в турниры от других игроков.
func _notifications() -> Array:
	Profile.expire_daily() # меню могло простоять открытым через полночь
	var out := []
	if Global.update_available:
		out.append({"text": "Вышла новая версия игры. Нажмите, чтобы обновиться (прогресс сохранится).", "go": "update"})
	if not Profile.game_state.is_empty():
		out.append({"text": "Партия не закончена — можно продолжить.", "go": "continue"})
	for id in Profile.active_tournaments:
		var st: Dictionary = Profile.active_tournaments[id]
		if not st.get("done", false):
			out.append({"text": "Турнир «%s»: ждёт тур %d из %d." % [st.name, int(st.round) + 1, int(st.rounds)], "go": "res://scenes/Tournaments.tscn"})
	var daily_id := "daily_" + Time.get_date_string_from_system()
	var dst: Dictionary = Profile.active_tournaments.get(daily_id, {})
	if dst.is_empty():
		out.append({"text": "Сегодня новый «Турнир дня» — можно записаться.", "go": "res://scenes/Tournaments.tscn"})
	for st in Profile.dynamic_road_stages():
		if not Profile.road_focus_done.has(st.kind):
			out.append({"text": "На «Дороге домой» новая остановка: «%s»." % st.name, "go": "res://scenes/RoadHome.tscn"})
	if SchoolData.loaded:
		for a in SchoolData.unread_announcements().slice(0, 2):
			out.append({"text": "Объявление: «%s»." % String(a.get("title", "")), "go": "res://scenes/Announcements.tscn"})
		for ev in SchoolData.upcoming(3).slice(0, 3):
			out.append({"text": "Скоро: %s — %s%s." % [SchoolData.fmt_date(String(ev.get("date", ""))), String(ev.get("title", "")), (", " + String(ev.get("place", ""))) if String(ev.get("place", "")) != "" else ""], "go": "res://scenes/Schedule.tscn"})
	if ChatScreen.has_unread():
		out.append({"text": "Новые сообщения в чате школы.", "go": "res://scenes/Chat.tscn"})
	if ClubTourney.my_turn_games.size() > 0:
		out.append({"text": "Ваш ход в турнирной партии (%d)." % ClubTourney.my_turn_games.size(), "go": "res://scenes/ClubTourneys.tscn"})
	if Homework.loaded and Homework.pending().size() > 0:
		out.append({"text": "Новых домашних заданий: %d." % Homework.pending().size(), "go": "res://scenes/Homework.tscn"})
	var streak := Profile.current_streak()
	if streak > 0 and Profile.streak_last_day != Time.get_date_string_from_system():
		out.append({"text": "Серия %d дн. прервётся: решите сегодня одну задачу." % streak, "go": "res://scenes/PuzzleHub.tscn"})
	return out

func _update_bell() -> void:
	var n := _notifications().size()
	_bell_button.text = "🔔 %d" % n if n > 0 else "🔔"

func _show_notifications() -> void:
	if _notice_layer != null:
		return
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.custom_minimum_size = Vector2(460, 0)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "Уведомления"
	title.add_theme_font_size_override("font_size", 22)
	vb.add_child(title)
	var items := _notifications()
	if items.is_empty():
		var l := Label.new()
		l.text = "Пока всё спокойно. Новые напоминания появятся здесь."
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
		vb.add_child(l)
	for it in items:
		var b := Button.new()
		b.text = String(it.text)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0, 48)
		b.pressed.connect(func():
			if it.go == "continue":
				_on_continue_pressed("game")
			elif it.go == "update":
				b.text = "Обновляю… сохраняю прогресс"
				b.disabled = true
				Global.app_update.apply()
			else:
				Global.open(String(it.go), Global.MENU_SCENE))
		vb.add_child(b)
	var close := Button.new()
	close.name = "CloseButton"
	close.text = "Закрыть"
	close.custom_minimum_size = Vector2(0, 46)
	close.pressed.connect(func():
		layer.queue_free()
		_notice_layer = null)
	vb.add_child(close)
	add_child(layer)
	_notice_layer = layer

# Кнопка «Игроки школы» — только когда облако настроено.
func _add_players_button() -> void:
	if not Cloud.enabled:
		return
	var vb := tourney_panel.get_child(0) as VBoxContainer
	var b := Button.new()
	b.text = "Игроки школы — общий рейтинг"
	b.custom_minimum_size = Vector2(0, 48)
	b.tooltip_text = "Таблица игроков школы с турнирными рейтингами (нужен онлайн-вход)."
	b.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Players.tscn"))
	vb.add_child(b)
	vb.move_child(b, vb.get_child_count() - 2) # перед «← Назад»

func _show_panel(panel: PanelContainer) -> void:
	main_panel.visible = panel == main_panel
	play_panel.visible = panel == play_panel
	train_panel.visible = panel == train_panel
	tourney_panel.visible = panel == tourney_panel
	if school_panel != null:
		school_panel.visible = panel == school_panel

func _on_play_menu_pressed() -> void:
	_show_panel(play_panel)

func _on_train_menu_pressed() -> void:
	_show_panel(train_panel)

func _on_tourney_menu_pressed() -> void:
	_show_panel(tourney_panel)

func _on_back_pressed() -> void:
	_show_panel(main_panel)

func _update_profile_bar() -> void:
	user_label.text = (Profile.avatar + " " if Profile.avatar != "" else "") + Profile.shown_name() + ("  " + Roles.icon_for(Profile.role) if Roles.icon_for(Profile.role) != "" else "")
	rating_label.text = "Турнирный рейтинг: %d (%s) · Ступень %d" % [round(Profile.tournament_rating), Profile.rating_title(), Profile.clean_step()]
	rating_label.tooltip_text = "Турнирный рейтинг растёт от турниров. Ступень — сильнейший уровень компьютера, побеждённый без помощи."
	rating_label.mouse_filter = Control.MOUSE_FILTER_STOP
	achievements_label.text = "Достижения: %d/%d" % [Profile.achievement_count(), Profile.total_achievement_count()]
	var streak = Profile.current_streak()
	if streak > 0 and Profile.streak_last_day == Time.get_date_string_from_system():
		achievements_label.text += "   🔥 Серия: %d дн." % streak
	elif streak > 0:
		achievements_label.text += "   🔥 Серия: %d дн. — решите задачу сегодня, чтобы не прервать!" % streak
	else:
		achievements_label.text += "   Решите задачу — начнётся серия дней!"

func _on_profile_pressed() -> void:
	_open("res://scenes/Diary.tscn")

func _on_journal_pressed() -> void:
	_open("res://scenes/Diary.tscn")

func _on_switch_user_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Login.tscn")

func _on_difficulty_changed(v: float) -> void:
	Global.difficulty = int(v)
	_update_difficulty_label()

func _update_difficulty_label() -> void:
	difficulty_value_label.text = str(int(difficulty_slider.value))
	difficulty_name_label.text = Global.difficulty_label(int(difficulty_slider.value))

func _update_color_buttons() -> void:
	white_button.button_pressed = chosen_color == "w"
	black_button.button_pressed = chosen_color == "b"

func _on_play_pressed() -> void:
	Global.difficulty = int(difficulty_slider.value)
	Global.player_color = chosen_color
	Global.map_character_id = ""
	Global.coop_team = false
	get_tree().change_scene_to_file("res://scenes/Board.tscn")

# quick-play team match: opponent strength follows the difficulty slider
func _on_team_pressed() -> void:
	Global.difficulty = int(difficulty_slider.value)
	Global.player_color = "w"
	Global.map_character_id = ""
	Global.coop_team = true
	get_tree().change_scene_to_file("res://scenes/Board.tscn")

func _on_settings_pressed() -> void:
	_open("res://scenes/Settings.tscn")

func _on_map_pressed() -> void:
	_open("res://scenes/Map.tscn")

func _on_tournaments_pressed() -> void:
	_open("res://scenes/Tournaments.tscn")

func _on_tournament_prep_pressed() -> void:
	_open("res://scenes/TournamentPrep.tscn")

func _on_bots_pressed() -> void:
	_open("res://scenes/BotsHub.tscn")

func _on_historic_games_pressed() -> void:
	_open("res://scenes/HistoricGames.tscn")

func _on_school_pressed() -> void:
	_open("res://scenes/School.tscn")

func _on_trophy_pressed() -> void:
	_open("res://scenes/TrophyRoom.tscn")

func _on_progress_pressed() -> void:
	_open("res://scenes/Diary.tscn")

func _on_road_pressed() -> void:
	_open("res://scenes/RoadHome.tscn")

func _on_puzzles_pressed() -> void:
	_open("res://scenes/PuzzleHub.tscn")

func _on_attention_pressed() -> void:
	_open("res://scenes/AttentionHub.tscn")

# Открыть раздел и запомнить, из какого подменю пришли, — «Назад» вернёт туда же.
func _open(scene: String) -> void:
	var panel := ""
	if play_panel.visible: panel = "play"
	elif train_panel.visible: panel = "train"
	elif tourney_panel.visible: panel = "tourney"
	elif school_panel != null and school_panel.visible: panel = "school"
	Global.open(scene, Global.MENU_SCENE, panel)

func _on_quit_pressed() -> void:
	if OS.has_feature("web"):
		return # вкладку браузера закрывает сам игрок
	get_tree().quit()

func _on_bg_draw() -> void:
	# прежний узор-шахматка — только для темы «Неон»; в остальных темах фон живой (GameBackdrop)
	if not Themes.is_neon():
		return
	var sq = 64.0
	# на весь экран 1280×800 (раньше рисовалось только в левом верхнем углу)
	for r in range(13):
		for f in range(20):
			if (r + f) % 2 == 0:
				continue
			var pos = Vector2(f * sq, r * sq)
			bg.draw_rect(Rect2(pos, Vector2(sq, sq)), Themes.ink(Color(1, 1, 1, 0.035)), true)

# Для снимков экрана (инструмент Shots).
func _show_school_for_shot() -> void:
	_show_panel(school_panel)
