extends Node

# Темы оформления. Все экраны проекта нарисованы в «неоновой» палитре (theme/NeonTheme.tres и
# цвета, прописанные в сценах и коде). Чтобы не переписывать сотни мест, тема = палитра ролей,
# а старые цвета перекрашиваются по роли: тёмный фон, панель, светлый текст, приглушённый текст,
# акцент (бывший голубой), второй акцент (бывший розовый). Цвета-смыслы (золото, зелёный, красный)
# не трогаются. Тема «Неон» ничего не перекрашивает — это исходный вид.
# Выбор темы хранится в настройках; применяется при загрузке следующего экрана.

const NEON_THEME_PATH := "res://theme/NeonTheme.tres"
const DEFAULT_ID := "neon"

# bg — фон экрана, panel — панели и кнопки, text/muted — текст, accent/accent2 — рамки, заголовки,
# наведение; light/dark — клетки доски.
const PALETTES := [
	{"id": "neon", "name": "Неон (по умолчанию)"},
	{"id": "wood", "name": "Дерево — шахматный клуб",
		"bg": Color(0.10, 0.07, 0.04), "panel": Color(0.21, 0.14, 0.08), "text": Color(0.96, 0.90, 0.77),
		"muted": Color(0.72, 0.62, 0.46), "accent": Color(0.87, 0.62, 0.30), "accent2": Color(0.96, 0.82, 0.52),
		"light": Color(0.94, 0.83, 0.62), "dark": Color(0.58, 0.38, 0.22)},
	{"id": "classic", "name": "Классика — зелёная доска",
		"bg": Color(0.15, 0.15, 0.13), "panel": Color(0.22, 0.22, 0.20), "text": Color(0.86, 0.86, 0.83),
		"muted": Color(0.62, 0.62, 0.58), "accent": Color(0.55, 0.70, 0.32), "accent2": Color(0.88, 0.78, 0.42),
		"light": Color(0.93, 0.93, 0.82), "dark": Color(0.46, 0.59, 0.34)},
	{"id": "ocean", "name": "Океан",
		"bg": Color(0.02, 0.07, 0.12), "panel": Color(0.05, 0.14, 0.22), "text": Color(0.86, 0.94, 0.99),
		"muted": Color(0.52, 0.67, 0.80), "accent": Color(0.30, 0.72, 0.92), "accent2": Color(0.96, 0.68, 0.46),
		"light": Color(0.82, 0.90, 0.95), "dark": Color(0.35, 0.55, 0.72)},
	{"id": "forest", "name": "Лес",
		"bg": Color(0.04, 0.09, 0.06), "panel": Color(0.08, 0.17, 0.10), "text": Color(0.89, 0.94, 0.83),
		"muted": Color(0.56, 0.69, 0.51), "accent": Color(0.52, 0.82, 0.42), "accent2": Color(0.92, 0.77, 0.36),
		"light": Color(0.85, 0.90, 0.70), "dark": Color(0.40, 0.55, 0.30)},
	{"id": "sunset", "name": "Закат",
		"bg": Color(0.12, 0.05, 0.08), "panel": Color(0.23, 0.10, 0.14), "text": Color(1.0, 0.93, 0.87),
		"muted": Color(0.80, 0.57, 0.56), "accent": Color(1.0, 0.56, 0.31), "accent2": Color(1.0, 0.82, 0.42),
		"light": Color(0.98, 0.86, 0.72), "dark": Color(0.78, 0.40, 0.35)},
	{"id": "lavender", "name": "Лаванда",
		"bg": Color(0.10, 0.08, 0.16), "panel": Color(0.17, 0.14, 0.27), "text": Color(0.94, 0.91, 1.0),
		"muted": Color(0.66, 0.61, 0.81), "accent": Color(0.72, 0.57, 1.0), "accent2": Color(1.0, 0.72, 0.86),
		"light": Color(0.91, 0.87, 0.97), "dark": Color(0.55, 0.45, 0.75)},
	{"id": "day", "name": "День (светлая)",
		"bg": Color(0.92, 0.93, 0.95), "panel": Color(1.0, 1.0, 1.0), "text": Color(0.11, 0.13, 0.19),
		"muted": Color(0.38, 0.43, 0.53), "accent": Color(0.08, 0.42, 0.82), "accent2": Color(0.82, 0.25, 0.42),
		"light": Color(0.95, 0.92, 0.84), "dark": Color(0.52, 0.60, 0.71)},
	{"id": "graphite", "name": "Графит — строгая",
		"bg": Color(0.07, 0.07, 0.08), "panel": Color(0.14, 0.14, 0.16), "text": Color(0.95, 0.95, 0.95),
		"muted": Color(0.62, 0.62, 0.67), "accent": Color(0.88, 0.88, 0.94), "accent2": Color(1.0, 0.80, 0.22),
		"light": Color(0.86, 0.86, 0.86), "dark": Color(0.40, 0.40, 0.45)},
	{"id": "mint", "name": "Мята",
		"bg": Color(0.05, 0.12, 0.12), "panel": Color(0.09, 0.21, 0.20), "text": Color(0.91, 1.0, 0.98),
		"muted": Color(0.56, 0.76, 0.73), "accent": Color(0.40, 0.95, 0.80), "accent2": Color(1.0, 0.72, 0.62),
		"light": Color(0.88, 0.97, 0.93), "dark": Color(0.30, 0.60, 0.55)},
	{"id": "royal", "name": "Королевская",
		"bg": Color(0.10, 0.03, 0.05), "panel": Color(0.21, 0.07, 0.11), "text": Color(0.98, 0.93, 0.81),
		"muted": Color(0.76, 0.61, 0.56), "accent": Color(0.95, 0.76, 0.31), "accent2": Color(0.92, 0.42, 0.47),
		"light": Color(0.95, 0.88, 0.72), "dark": Color(0.60, 0.20, 0.25)},
	{"id": "kids", "name": "Детская — яркая",
		"bg": Color(0.12, 0.16, 0.36), "panel": Color(0.20, 0.27, 0.52), "text": Color(1.0, 1.0, 1.0),
		"muted": Color(0.76, 0.81, 0.96), "accent": Color(1.0, 0.85, 0.22), "accent2": Color(0.42, 1.0, 0.62),
		"light": Color(1.0, 0.95, 0.80), "dark": Color(0.30, 0.70, 0.95)},
]

const NEON_LIGHT := Color(0.93, 0.86, 0.72)
const NEON_DARK := Color(0.55, 0.38, 0.26)

var current_id := DEFAULT_ID
var _pal: Dictionary = {}
var _theme: Theme = null
const SETTINGS_KEY := "theme_id"

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(Global.SETTINGS_PATH) == OK:
		current_id = String(cfg.get_value("settings", SETTINGS_KEY, DEFAULT_ID))
	_select(current_id)
	get_tree().node_added.connect(_on_node_added)
	# сцена входа могла появиться раньше этого автозагрузчика — красим всё, что уже в дереве
	_apply_tree.call_deferred(get_tree().root)

func _apply_tree(node: Node) -> void:
	if node == self:
		return
	_on_node_added(node)
	for ch in node.get_children():
		_apply_tree(ch)

func palette_by_id(id: String) -> Dictionary:
	for p in PALETTES:
		if p.id == id:
			return p
	return PALETTES[0]

func _select(id: String) -> void:
	_pal = palette_by_id(id)
	current_id = _pal.id
	_theme = null
	if is_neon():
		return
	var base: Theme = load(NEON_THEME_PATH)
	_theme = base.duplicate(true)
	for type in _theme.get_color_type_list():
		for nm in _theme.get_color_list(type):
			_theme.set_color(nm, type, recolor(_theme.get_color(nm, type)))
	var seen := {} # один и тот же стиль бывает у нескольких состояний (hover/focus) — красим раз
	for type in _theme.get_stylebox_type_list():
		for nm in _theme.get_stylebox_list(type):
			var sb := _theme.get_stylebox(nm, type)
			if sb is StyleBoxFlat and not seen.has(sb.get_instance_id()):
				seen[sb.get_instance_id()] = true
				_remap_stylebox(sb as StyleBoxFlat)

# Сохраняет выбор и записывает его в настройки (тот же файл, что и у Global).
func set_theme_id(id: String) -> void:
	_select(id)
	var cfg := ConfigFile.new()
	cfg.load(Global.SETTINGS_PATH)
	cfg.set_value("settings", SETTINGS_KEY, current_id)
	cfg.save(Global.SETTINGS_PATH)

func is_neon() -> bool:
	return current_id == DEFAULT_ID

func board_light() -> Color:
	return NEON_LIGHT if is_neon() else _pal.light

func board_dark() -> Color:
	return NEON_DARK if is_neon() else _pal.dark

# --- перекраска ---------------------------------------------------------------------------------

func _lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b

# Определяет роль старого неонового цвета и возвращает цвет текущей темы (прозрачность сохраняется).
func recolor(c: Color) -> Color:
	if is_neon():
		return c
	var out := c
	var mx := maxf(c.r, maxf(c.g, c.b))
	var mn := minf(c.r, minf(c.g, c.b))
	var l := _lum(c)
	var pure_white := c.r >= 0.99 and c.g >= 0.99 and c.b >= 0.99
	if pure_white:
		return c
	if c.r < 0.7 and c.g > 0.85 and c.b > 0.95 and c.r > 0.5:
		out = (_pal.accent as Color).lerp(_pal.text, 0.35) # светло-голубой текст кнопок
	elif c.r < 0.3 and c.g > 0.7 and c.b > 0.8:
		out = _pal.accent
	elif c.r > 0.8 and c.b > 0.75 and c.g < 0.75:
		out = _pal.accent2
	elif l > 0.7 and c.b >= c.r and (mx - mn) < 0.25:
		out = _pal.text
	elif (mx - mn) < 0.25 and c.b > c.r and l >= 0.45 and l <= 0.75:
		out = _pal.muted
	elif mx < 0.2 and c.b >= c.r - 0.02:
		if l < 0.035:
			out = _pal.bg
		else:
			out = (_pal.panel as Color).lerp(_pal.accent, clampf((l - 0.06) * 2.0, 0.0, 0.2))
	else:
		return c
	out.a = c.a
	return out

func _remap_stylebox(sb: StyleBoxFlat) -> void:
	sb.bg_color = recolor(sb.bg_color)
	sb.border_color = recolor(sb.border_color)
	sb.shadow_color = recolor(sb.shadow_color)

const COLOR_NAMES := ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
	"font_disabled_color", "font_shadow_color", "default_color", "font_placeholder_color", "caret_color", "font_outline_color"]
const STYLE_NAMES := ["panel", "normal", "hover", "pressed", "focus", "disabled", "background", "fill"]

# Каждый новый элемент интерфейса перекрашивается один раз, в конце кадра — после того как
# сцена или код успели выставить свои цвета.
func _on_node_added(node: Node) -> void:
	if is_neon() or not (node is Control or node is ColorRect):
		return
	if node.has_meta("themed"):
		return
	node.set_meta("themed", true)
	_apply_to.call_deferred(node)

func _apply_to(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node is ColorRect:
		(node as ColorRect).color = recolor((node as ColorRect).color)
	if not (node is Control):
		return
	var c := node as Control
	if c.theme != null and c.theme.resource_path == NEON_THEME_PATH:
		c.theme = _theme
	for nm in COLOR_NAMES:
		if c.has_theme_color_override(nm):
			c.add_theme_color_override(nm, recolor(c.get_theme_color(nm)))
	for nm in STYLE_NAMES:
		if c.has_theme_stylebox_override(nm):
			var sb := c.get_theme_stylebox(nm)
			if sb is StyleBoxFlat:
				var copy := sb.duplicate() as StyleBoxFlat
				_remap_stylebox(copy)
				c.add_theme_stylebox_override(nm, copy)
