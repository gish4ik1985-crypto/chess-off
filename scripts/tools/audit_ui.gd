extends Node

# Глубокий аудит UI. В отличие от test_scenes.gd каждая сцена реально
# добавляется в дерево (срабатывает _ready и все @onready-пути), а затем
# проверяется четырьмя способами:
#   1) ПЕРЕПОЛНЕНИЕ КОНТЕЙНЕРОВ — get_combined_minimum_size() против
#      фактического size. Если содержимому нужно больше места, чем есть,
#      контейнер распирает и дети НЕИЗБЕЖНО наезжают друг на друга. Именно
#      так ломался экран «Партии великих»: длинные названия партий раздували
#      ListScroll с 280 до 483px и сдвигали доску с панелью комментария.
#   2) кнопки без подключённого обработчика;
#   3) пересечение соседних Control-узлов под не-контейнерным родителем;
#   4) выход за пределы экрана 1280x800 (правило «одно окно без прокрутки»).
# Сцены со списками дополнительно прогоняются в заполненном состоянии —
# в пустом состоянии баг не виден.
# Запуск: godot --headless --path . res://scenes/tools/AuditUI.tscn

const SCENES := [
	"res://scenes/Menu.tscn", "res://scenes/RoadHome.tscn", "res://scenes/Board.tscn",
	"res://scenes/Achievements.tscn", "res://scenes/AttentionHub.tscn", "res://scenes/Diary.tscn",
	"res://scenes/HistoricGames.tscn", "res://scenes/Login.tscn", "res://scenes/Map.tscn",
	"res://scenes/Puzzle.tscn", "res://scenes/PuzzleHub.tscn", "res://scenes/School.tscn",
	"res://scenes/Settings.tscn", "res://scenes/TournamentPrep.tscn", "res://scenes/Tournaments.tscn",
	"res://scenes/TrophyRoom.tscn", "res://scenes/BotsHub.tscn", "res://scenes/Admin.tscn", "res://scenes/Homework.tscn", "res://scenes/Notebook.tscn", "res://scenes/ClubTourneys.tscn", "res://scenes/Chat.tscn", "res://scenes/Schedule.tscn", "res://scenes/Announcements.tscn", "res://scenes/Planner.tscn", "res://scenes/OnlineGame.tscn", "res://scenes/Players.tscn", "res://scenes/Appearance.tscn",
]

var problems := 0

# Размер экрана проверки (единицы раскладки). По умолчанию 1280x800; другие размеры — те, что выбирает
# Global под телефоны и планшеты:  ... AuditUI.tscn -- size=800x1067
# Сцены добавляются в SubViewport этого размера, экраны «Партия» и «Задачи» в вертикали получают
# вертикальную раскладку (Global._layout_play_scene).
var W := 1280.0
var H := 800.0
var _vp: SubViewport

func _host() -> Node:
	return _vp if _vp != null else self

# Как в игре: доска/задачи в вертикали — своя раскладка; доска, карта и т.п. в остальных случаях — 1280x800;
# прочие экраны — холст W x H, увеличенный подгонкой под содержимое (Global.content_fit_factor).
func _add(node: Node) -> void:
	var portrait_play := H > W and (node.name in ["Board", "Puzzle"] or node.has_method("apply_portrait"))
	if _vp == null or (node.name in Global.FIXED_LAYOUT_SCENES and not portrait_play):
		add_child(node)
		return
	_vp.size = Vector2i(int(W), int(H))
	_vp.add_child(node)
	if portrait_play and node.has_method("apply_portrait"):
		node.apply_portrait(true, Vector2(W, H))
	elif portrait_play:
		Global._layout_play_scene(node, true, int(H))

# Подгонка холста под содержимое — то же, что делает Global._fit_to_content в игре.
func _fit(node: Node) -> void:
	if _vp == null or node.get_parent() != _vp or node.name in ["Board", "Puzzle"] or node.has_method("apply_portrait"):
		return
	for i in 6:
		await get_tree().process_frame
		await get_tree().process_frame
		var view := Vector2(_vp.size)
		var k := Global.content_fit_factor(node, view)
		if k <= 1.004:
			return
		_vp.size = Vector2i(ceili(view.x * k), ceili(view.y * k))

# Модальные окна ПО ЗАМЫСЛУ лежат поверх содержимого — их перекрытие с доской
# и панелями не является ошибкой вёрстки. Всё остальное перекрытие — ошибка.
const MODAL_OVERLAYS := [
	"UI/GameOverPanel", "UI/LeavePanel", "UI/PromoPanel", "UI/NudgePanel",
	"UI/SpeechPanel", "UI/DetailPanel",
	"BackButton", # плавающая «← Назад» в углу экрана (Настройки, Школа) — по замыслу поверх содержимого
	"Backdrop", # фирменный фон экрана входа лежит под карточкой
	"VersionLabel", # полупрозрачный номер версии в углу — по замыслу поверх всего
]

func _is_modal(path: String) -> bool:
	for m in MODAL_OVERLAYS:
		if path == m or path.begins_with(m + "/"):
			return true
	return false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("size="):
			var wh := a.substr(5).split("x")
			W = float(wh[0])
			H = float(wh[1])
	if W != 1280.0 or H != 800.0:
		_vp = SubViewport.new()
		_vp.size = Vector2i(int(W), int(H))
		_vp.disable_3d = true
		add_child(_vp)
	print("=== экран проверки: %dx%d ===" % [int(W), int(H)])
	for p in SCENES:
		await _audit_scene(p)
	await _audit_historic_states()
	await _audit_menu_panels()
	await _audit_bot_match()
	await _audit_diary_tabs()
	print("=== ИТОГО проблем: %d ===" % problems)
	get_tree().quit(1 if problems > 0 else 0)

# ---------------------------------------------------------------- проверки

# Главная проверка. Контейнер, которому нужно больше места, чем ему дали, —
# это гарантированное наложение элементов, даже если прямоугольники детей
# формально ещё не пересеклись.
func _scan_container_overflow(root: Node, n: Node, out: Array) -> void:
	if n is Container and n.is_visible_in_tree():
		var need: Vector2 = n.get_combined_minimum_size()
		var have: Vector2 = n.size
		if need.x - have.x > 1.0 or need.y - have.y > 1.0:
			out.append([str(root.get_path_to(n)),
				"нужно %.0fx%.0f, есть %.0fx%.0f" % [need.x, need.y, have.x, have.y]])
	for ch in n.get_children():
		_scan_container_overflow(root, ch, out)

func _scan_buttons(root: Node, n: Node, dead: Array) -> void:
	if n is BaseButton and not (n is OptionButton) and not (n is CheckButton) and not n.disabled:
		if n.pressed.get_connections().is_empty() and n.toggled.get_connections().is_empty():
			dead.append([str(root.get_path_to(n)), str(n.text) if "text" in n else ""])
	for ch in n.get_children():
		_scan_buttons(root, ch, dead)

# Владелец просил, чтобы меню помещались на один экран без прокрутки.
func _scan_spill(root: Node, n: Node, out: Array) -> void:
	if n is ScrollContainer or n is GameBackdrop:
		return # живой фон повторяет размер своей подложки, которая может выходить за экран
	# декоративные фоны намеренно выходят за края экрана — их не считаем
	if n is Control and n.visible and not (n is Label) \
			and not (n is ColorRect) and not (n is TextureRect):
		var r := Rect2(n.global_position, n.size)
		var vs: Vector2 = n.get_viewport().get_visible_rect().size
		if (r.position.x + r.size.x - vs.x > 2.0 or r.position.y + r.size.y - vs.y > 2.0 \
				or r.position.x < -2.0 or r.position.y < -2.0) and r.size.x > 4 and r.size.y > 4:
			out.append([str(root.get_path_to(n)), "rect=%s" % str(r)])
			return # достаточно самого верхнего виновника
	for ch in n.get_children():
		_scan_spill(root, ch, out)

# Декоративная подложка: ColorRect/TextureRect/Panel во всю площадь родителя.
func _is_backdrop(c: Control) -> bool:
	if c is Container or c is Label or c is BaseButton:
		return false
	if not (c is ColorRect or c is TextureRect or c is Panel):
		return false
	var p = c.get_parent()
	if p is Control:
		return c.size.x >= p.size.x * 0.95 and c.size.y >= p.size.y * 0.95
	return c.size.x >= 1200 and c.size.y >= 700

func _scan_overlaps(root: Node, parent: Node, out: Array) -> void:
	# Скрытое поддерево контейнер не раскладывает, у детей остаются мусорные
	# прямоугольники — сравнивать их бессмысленно (давало ложное пересечение
	# InfoPanel/Controls в «Партиях великих», пока партия не открыта).
	if parent is Control and not parent.is_visible_in_tree():
		return
	var kids := []
	for ch in parent.get_children():
		if ch is Control and ch.visible and not _is_backdrop(ch):
			kids.append(ch)
	if not (parent is Container):
		for i in range(kids.size()):
			for j in range(i + 1, kids.size()):
				var a: Control = kids[i]
				var b: Control = kids[j]
				if a.mouse_filter == Control.MOUSE_FILTER_IGNORE and b.mouse_filter == Control.MOUSE_FILTER_IGNORE:
					continue
				var ra := Rect2(a.global_position, a.size)
				var rb := Rect2(b.global_position, b.size)
				if ra.size.x <= 4 or ra.size.y <= 4 or rb.size.x <= 4 or rb.size.y <= 4:
					continue
				# Порог по ДОЛЕ ПЛОЩАДИ был ошибкой: шапка, налезающая на
				# содержимое полоской в 8px, — это 1% площади, но именно она
				# и портит картинку. Считаем наложением любое перекрытие
				# толще 2px по обеим осям.
				var pa := str(root.get_path_to(a))
				var pb := str(root.get_path_to(b))
				if _is_modal(pa) or _is_modal(pb):
					continue
				var inter := ra.intersection(rb)
				if inter.size.x > 2.0 and inter.size.y > 2.0:
					out.append([pa, pb, "%.0fx%.0fpx" % [inter.size.x, inter.size.y]])
	for ch in parent.get_children():
		_scan_overlaps(root, ch, out)

# Проверка соседей ловит не всё: шапка и кнопка «свернуть список» лежат в
# РАЗНЫХ ветках дерева (TopBar и Main/BoardArea), соседями не являются, а
# налезают друг на друга. Поэтому отдельно сравниваем все видимые «рисующие»
# узлы по всему дереву, пропуская пары предок-потомок.
func _collect_ink(n: Node, out: Array) -> void:
	if n is Control and n.is_visible_in_tree():
		if (n is Label or n is BaseButton or n is Panel or n is PanelContainer) \
				and not _is_backdrop(n) and n.size.x > 4 and n.size.y > 4:
			out.append(n)
	for ch in n.get_children():
		_collect_ink(ch, out)

func _scan_global_overlaps(root: Node, out: Array) -> void:
	var ink := []
	_collect_ink(root, ink)
	for i in range(ink.size()):
		for j in range(i + 1, ink.size()):
			var a: Control = ink[i]
			var b: Control = ink[j]
			if a.is_ancestor_of(b) or b.is_ancestor_of(a):
				continue
			var pa := str(root.get_path_to(a))
			var pb := str(root.get_path_to(b))
			if _is_modal(pa) or _is_modal(pb):
				continue
			var inter := Rect2(a.global_position, a.size).intersection(Rect2(b.global_position, b.size))
			if inter.size.x > 2.0 and inter.size.y > 2.0:
				out.append([pa, pb, "%.0fx%.0fpx" % [inter.size.x, inter.size.y]])

# Все символы интерфейса должны быть в шрифте проекта (с его fallback-цепочкой), а не только в системном:
# в веб-сборке системных шрифтов нет, и недостающий символ превращается в пустой квадрат.
var _ui_font: Font = null

func _scan_glyphs(root: Node, n: Node, out: Array) -> void:
	if _ui_font == null:
		_ui_font = load("res://theme/NeonTheme.tres").default_font
	if (n is Label or n is BaseButton or n is RichTextLabel) and n.is_visible_in_tree():
		var txt := ""
		if n is RichTextLabel:
			txt = n.get_parsed_text()
		elif "text" in n:
			txt = str(n.text)
		var missing := ""
		for i in txt.length():
			var c := txt.unicode_at(i)
			if c > 127 and not (c >= 0x400 and c <= 0x4FF) and c != 0xFE0F and c != 0x200D and c != 0xA0 					and not _ui_font.has_char(c) and missing.find(txt[i]) < 0:
				missing += txt[i]
		if missing != "":
			out.append([str(root.get_path_to(n)), "нет в шрифте: " + missing])
	for ch in n.get_children():
		_scan_glyphs(root, ch, out)

func _report(label: String, node: Node) -> void:
	if _vp != null and node.get_parent() == _vp:
		label += "  [холст %dx%d]" % [_vp.size.x, _vp.size.y]
	var over := []
	_scan_container_overflow(node, node, over)
	var dead := []
	_scan_buttons(node, node, dead)
	var overlaps := []
	_scan_overlaps(node, node, overlaps)
	_scan_global_overlaps(node, overlaps)
	var spill := []
	_scan_spill(node, node, spill)
	var glyphs := []
	_scan_glyphs(node, node, glyphs)
	var bad = over.size() + dead.size() + overlaps.size() + spill.size() + glyphs.size()
	print("--- %s%s" % [label, "" if bad > 0 else "  [OK]"])
	for o in over:
		print("    ⚠ КОНТЕЙНЕР ПЕРЕПОЛНЕН: %s (%s)" % o)
	for d in dead:
		print("    ⚠ кнопка без обработчика: %s (%s)" % d)
	for o in overlaps:
		print("    ⚠ пересечение: %s <-> %s (%s)" % o)
	for s in spill:
		print("    ⚠ не влезает в экран: %s (%s)" % s)
	for g in glyphs:
		print("    ⚠ символы вне шрифта проекта: %s (%s)" % g)
	problems += bad

# ---------------------------------------------------------------- прогоны

func _audit_scene(path: String) -> void:
	var ps = load(path)
	if ps == null:
		print("FAIL %s — не загрузилась" % path)
		problems += 1
		return
	var node = ps.instantiate()
	_add(node)
	await get_tree().process_frame
	await get_tree().process_frame
	await _fit(node)
	_report(path, node)
	node.queue_free()
	await get_tree().process_frame

# «Партии великих»: список шахматистов -> список партий КАЖДОГО из них
# (названия партий разной длины) -> загруженная партия, со списком и без.
func _audit_historic_states() -> void:
	var node = load("res://scenes/HistoricGames.tscn").instantiate()
	_add(node)
	await get_tree().process_frame
	for p in node.players:
		node._show_games(p)
		await get_tree().process_frame
		await get_tree().process_frame
		await _fit(node)
		_report("HistoricGames · список партий: %s" % p.name, node)
	var first = node.players[0]
	node._show_games(first)
	await get_tree().process_frame
	node._load_game(first.games[0])
	await get_tree().process_frame
	await get_tree().process_frame
	await _fit(node)
	_report("HistoricGames · партия открыта, список развёрнут", node)
	_check_board_vs_panels(node)
	node._on_list_toggle_pressed()
	await get_tree().process_frame
	await get_tree().process_frame
	await _fit(node)
	_report("HistoricGames · партия открыта, список свёрнут", node)
	_check_board_vs_panels(node)
	node.queue_free()
	await get_tree().process_frame

# Доска рисуется через Node2D фиксированного размера (SQ=62 -> 496px плюс
# шкала оценки), поэтому система контейнеров про её размер НЕ знает и при
# нехватке места молча сжимает панель комментария вместо доски. Проверяем
# геометрию вручную.
func _check_board_vs_panels(node: Node) -> void:
	var area: Control = node.get_node("Main/BoardArea")
	var info: Control = node.get_node("Main/BoardArea/InfoPanel")
	var ctrl: Control = node.get_node("Main/BoardArea/Controls")
	var board := Rect2(area.global_position + Vector2(10, 46), Vector2(62.0 * 8 + 28, 62.0 * 8))
	var ri := Rect2(info.global_position, info.size)
	var rc := Rect2(ctrl.global_position, ctrl.size)
	print("      доска=%s InfoPanel=%s (ширина %.0f) Controls=%s" % [str(board), str(ri), ri.size.x, str(rc)])
	if board.intersects(ri):
		print("    ⚠ доска налезает на панель комментария")
		problems += 1
	if board.intersects(rc):
		print("    ⚠ доска налезает на кнопки перемотки")
		problems += 1
	if ri.size.x < 220.0:
		print("    ⚠ панель комментария сжата до %.0fpx — текст будет нечитаем" % ri.size.x)
		problems += 1

# Разбор партии бота требует контекста в Global.bot_match — без него сцена
# сразу уходит обратно в базу, поэтому в общем списке её проверять нельзя.
# Кладём в архив настоящую партию и открываем её.
func _audit_bot_match() -> void:
	var eng := ChessEngine.new()
	eng.setup_start_position()
	var ai := ChessAI.new(1)
	var coords := []
	for i in range(12):
		var mv = ai.choose_move(eng)
		if mv == null:
			break
		coords.append(load("res://scripts/Board.gd").move_coord(mv))
		eng.apply_move(mv)
	Profile.bot_games = {}
	Profile.record_bot_game("bot_001", "bot_002", "Соня", "Гоша", coords, 1.0, "Проверка")
	Global.bot_match = {"mode": "replay", "bot": "bot_001", "index": 0}
	var node = load("res://scenes/BotMatch.tscn").instantiate()
	_add(node)
	await get_tree().process_frame
	await get_tree().process_frame
	await _fit(node)
	_report("BotMatch · разбор партии", node)
	node.queue_free()
	await get_tree().process_frame
	Global.bot_match = {}
	Profile.bot_games = {}

# Главное меню — это четыре панели, из которых видна одна. Скрытые панели
# контейнер не раскладывает, поэтому в состоянии «по умолчанию» проверяется
# только главная. Открываем каждую и меряем по-настоящему.
func _audit_menu_panels() -> void:
	var node = load("res://scenes/Menu.tscn").instantiate()
	_add(node)
	await get_tree().process_frame
	for pair in [["MainPanel", "главная"], ["PlayPanel", "Играть"],
			["TourneyPanel", "Турниры и соперники"], ["TrainPanel", "Обучение"]]:
		var panel: Control = node.get_node_or_null("ContentCenter/" + str(pair[0]))
		if panel == null:
			print("--- Menu · панель %s ОТСУТСТВУЕТ" % pair[0])
			problems += 1
			continue
		node._show_panel(panel)
		await get_tree().process_frame
		await get_tree().process_frame
		await _fit(node)
		_report("Menu · панель «%s»" % pair[1], node)
	node.queue_free()
	await get_tree().process_frame

# «Дневник игрока»: вкладки строятся кодом, проверяем каждую.
func _audit_diary_tabs() -> void:
	var node = load("res://scenes/Diary.tscn").instantiate()
	_add(node)
	await get_tree().process_frame
	await get_tree().process_frame
	var tabs = node.find_children("*", "TabContainer", true, false)
	if tabs.is_empty():
		await _fit(node)
		_report("Diary · вкладок TabContainer нет, проверено как есть", node)
	else:
		var tc: TabContainer = tabs[0]
		for i in range(tc.get_tab_count()):
			tc.current_tab = i
			await get_tree().process_frame
			await get_tree().process_frame
			await _fit(node)
			_report("Diary · вкладка «%s»" % tc.get_tab_title(i), node)
	node.queue_free()
	await get_tree().process_frame
