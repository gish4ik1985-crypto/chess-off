extends Node

# Темы оформления.
#
# Экраны проекта когда-то рисовались в одной «неоновой» теме (theme/NeonTheme.tres плюс цвета,
# прописанные прямо в сценах и коде). Новая система делает две вещи:
#   1) строит из палитры настоящую тему Godot со своим стилем — плоские карточки с мягкой тенью,
#      заметная главная кнопка с объёмным краем, полужирные заголовки, свои переключатели и ползунки;
#   2) каждый элемент интерфейса при появлении один раз «переводится» в новую тему: старые неоновые
#      цвета узнаются по роли (фон, карточка, текст, акцент, золото, успех, ошибка) и заменяются
#      цветами палитры, светящиеся рамки и тени — спокойным стилем, крупные надписи становятся
#      полужирными, главные кнопки («Играть», «Войти»…) — акцентными.
# Код, который рисует сам (доски, карта, дневник), берёт цвета через ink() и функции доски ниже.
# Тема «Неон» — исходный вид без изменений.

const NEON_THEME_PATH := "res://theme/NeonTheme.tres"
const DEFAULT_ID := "irbis"
const SETTINGS_KEY := "ui_theme2" # новая фирменная тема по умолчанию для всех; прежний ключ theme_id относился к старым темам — их больше нет

# Палитры. Цвета — строки #rrggbb[aa], разбираются при выборе темы.
#   bg/bg2 — фон экрана (верх/низ градиента), surface — карточки, raised — кнопки и вложенные панели,
#   border — тонкие линии, text/dim/heading — текст, accent — главный цвет (кнопки, рамки выбора),
#   on_accent — текст на акцентной кнопке, ink — акцент для текста, accent2 — второй акцент
#   (подзаголовки, статусы), good/bad/gold — смысловые цвета.
#   light/darksq/frame — доска; last/select — подсветка хода; texture — flat/wood/marble.
#   radius — скругление, edge — толщина «объёмного» края кнопок, border_w — рамки карточек,
#   shadow — плотность тени.
const PALETTES := [
	{"id": "irbis", "name": "ИРБИС", "desc": "Фирменная: ночное небо, золото, объёмные кнопки",
		"dark": true, "bg": "#1a2150", "bg2": "#0b0e26", "surface": "#1f2a5c", "raised": "#2d3b7c",
		"border": "#3f4f9c", "text": "#eef1ff", "dim": "#a9b2df", "heading": "#ffe3a1",
		"accent": "#f2b632", "on_accent": "#2b1700", "ink": "#ffcf5c", "accent2": "#62d0ff",
		"good": "#6ee08a", "bad": "#ff6b7d", "gold": "#ffcf5c",
		"light": "#f0d9b5", "darksq": "#b58863", "frame": "#2d3b7c", "last": "#ffcf5c66", "select": "#62d0ff66",
		"texture": "wood", "radius": 14, "edge": 5, "border_w": 1, "shadow": 0.55},
	{"id": "classic", "name": "Классика", "desc": "Спокойная тёмная, коричневая доска",
		"dark": true, "bg": "#22201d", "bg2": "#171614", "surface": "#2c2a27", "raised": "#3b3835",
		"border": "#46423d", "text": "#e9e6e1", "dim": "#a39e97", "heading": "#ffffff",
		"accent": "#3d8fe0", "on_accent": "#ffffff", "ink": "#6db0f2", "accent2": "#e0b25a",
		"good": "#86c060", "bad": "#e9675a", "gold": "#e8b84a",
		"light": "#f0d9b5", "darksq": "#b58863", "frame": "#3b3835", "last": "#9bc70069", "select": "#14551e80",
		"texture": "flat", "radius": 10, "edge": 3, "border_w": 1, "shadow": 0.45},
	{"id": "classic_light", "name": "Классика светлая", "desc": "Светлая и чистая, для дня",
		"dark": false, "bg": "#efeeeb", "bg2": "#e2e0db", "surface": "#ffffff", "raised": "#eceae6",
		"border": "#d8d4cd", "text": "#2c2a27", "dim": "#6f6a63", "heading": "#1b1a18",
		"accent": "#2f7fd1", "on_accent": "#ffffff", "ink": "#2468ad", "accent2": "#a8661b",
		"good": "#4f8f22", "bad": "#c4402f", "gold": "#a67608",
		"light": "#f0d9b5", "darksq": "#b58863", "frame": "#d8d4cd", "last": "#9bc70069", "select": "#14551e66",
		"texture": "flat", "radius": 10, "edge": 3, "border_w": 1, "shadow": 0.12},
	{"id": "wood", "name": "Дерево", "desc": "Шахматный клуб: орех, клён, янтарь",
		"dark": true, "bg": "#2b1e15", "bg2": "#1b120c", "surface": "#3a2a1e", "raised": "#4e3828",
		"border": "#5e4633", "text": "#f4e7d4", "dim": "#c4ab8d", "heading": "#ffe8c4",
		"accent": "#cf8f3e", "on_accent": "#24170c", "ink": "#e8ad5e", "accent2": "#ecc57d",
		"good": "#a3c75f", "bad": "#e47a62", "gold": "#f1c45f",
		"light": "#e9cb9c", "darksq": "#a36d3f", "frame": "#5b3b22", "last": "#ffd36a5c", "select": "#4a7a2a80",
		"texture": "wood", "radius": 8, "edge": 3, "border_w": 1, "shadow": 0.5},
	{"id": "tournament", "name": "Турнир", "desc": "Зелёная турнирная доска",
		"dark": true, "bg": "#302e2b", "bg2": "#252320", "surface": "#272522", "raised": "#3e3b37",
		"border": "#4a4743", "text": "#f2f1ef", "dim": "#b0aea9", "heading": "#ffffff",
		"accent": "#7fb24a", "on_accent": "#ffffff", "ink": "#9dcc63", "accent2": "#f0c45c",
		"good": "#86c060", "bad": "#f0614e", "gold": "#f4c047",
		"light": "#ebecd0", "darksq": "#779556", "frame": "#272522", "last": "#f6f66980", "select": "#bbcb2b99",
		"texture": "flat", "radius": 8, "edge": 4, "border_w": 0, "shadow": 0.45},
	{"id": "ice", "name": "Лёд", "desc": "Холодный синий и мраморная доска",
		"dark": true, "bg": "#101c2b", "bg2": "#0a131e", "surface": "#17283c", "raised": "#213853",
		"border": "#2d4a69", "text": "#e7f0fa", "dim": "#97adc5", "heading": "#ffffff",
		"accent": "#4aa9f0", "on_accent": "#04121f", "ink": "#7cc4ff", "accent2": "#a8dcff",
		"good": "#62d18e", "bad": "#ff7070", "gold": "#ffd36b",
		"light": "#dfe6ea", "darksq": "#8aa1ae", "frame": "#213853", "last": "#7fd3ff66", "select": "#2a6fb080",
		"texture": "marble", "radius": 12, "edge": 3, "border_w": 1, "shadow": 0.5},
	{"id": "emerald", "name": "Изумруд", "desc": "Глубокий зелёный, мягкое золото",
		"dark": true, "bg": "#0f211b", "bg2": "#091612", "surface": "#15302a", "raised": "#1e4237",
		"border": "#2b5647", "text": "#e8f6f0", "dim": "#9dc4b4", "heading": "#ffffff",
		"accent": "#2fbf8a", "on_accent": "#04221a", "ink": "#5edcaa", "accent2": "#f2c97b",
		"good": "#5edcaa", "bad": "#ff7f6e", "gold": "#f2c97b",
		"light": "#f4f4dc", "darksq": "#7ea66f", "frame": "#1e4237", "last": "#f2c97b66", "select": "#0e6b4a80",
		"texture": "flat", "radius": 12, "edge": 3, "border_w": 1, "shadow": 0.5},
	{"id": "royal", "name": "Королевская", "desc": "Бордо и золото, торжественно",
		"dark": true, "bg": "#24090f", "bg2": "#160509", "surface": "#341019", "raised": "#4a1924",
		"border": "#5f2632", "text": "#f9ebd8", "dim": "#d2ac9c", "heading": "#ffe4a6",
		"accent": "#d6a53b", "on_accent": "#2a0d00", "ink": "#ecc361", "accent2": "#f3cb7f",
		"good": "#a3c86e", "bad": "#ff8080", "gold": "#f3cb7f",
		"light": "#f3e3c3", "darksq": "#a14552", "frame": "#5a1d29", "last": "#f3cb7f73", "select": "#6b1a2a99",
		"texture": "marble", "radius": 8, "edge": 3, "border_w": 1, "shadow": 0.55},
	{"id": "lavender", "name": "Лаванда", "desc": "Мягкая фиолетовая",
		"dark": true, "bg": "#1d1929", "bg2": "#14111d", "surface": "#282339", "raised": "#362f4e",
		"border": "#473e65", "text": "#f0ebff", "dim": "#b5abd7", "heading": "#ffffff",
		"accent": "#9a7bff", "on_accent": "#ffffff", "ink": "#b9a3ff", "accent2": "#ffb4da",
		"good": "#80d8a2", "bad": "#ff7d92", "gold": "#ffd47c",
		"light": "#e2d8f0", "darksq": "#9077b8", "frame": "#362f4e", "last": "#ffb4da66", "select": "#5b3fb080",
		"texture": "flat", "radius": 14, "edge": 3, "border_w": 1, "shadow": 0.5},
	{"id": "sand", "name": "Песок", "desc": "Тёплая светлая, как старая книга",
		"dark": false, "bg": "#f6eee2", "bg2": "#eadfcd", "surface": "#fffaf3", "raised": "#f1e5d3",
		"border": "#e1d2bc", "text": "#3b2f25", "dim": "#85735f", "heading": "#2a1f17",
		"accent": "#d9733a", "on_accent": "#ffffff", "ink": "#b3561f", "accent2": "#9c5a2a",
		"good": "#4f8f22", "bad": "#c4402f", "gold": "#a8780c",
		"light": "#f3dfbf", "darksq": "#c48c58", "frame": "#d8c09c", "last": "#e8a33d59", "select": "#9a5a1a59",
		"texture": "wood", "radius": 12, "edge": 3, "border_w": 1, "shadow": 0.12},
	{"id": "kids", "name": "Детская", "desc": "Яркая и дружелюбная, крупные кнопки",
		"dark": false, "bg": "#dcf2ff", "bg2": "#bfe5fb", "surface": "#ffffff", "raised": "#eef7ff",
		"border": "#b7daf1", "text": "#23364b", "dim": "#5a7690", "heading": "#1b5f9e",
		"accent": "#ff8a1f", "on_accent": "#ffffff", "ink": "#d96a00", "accent2": "#1f9e63",
		"good": "#1f9e63", "bad": "#e23d63", "gold": "#d18a00",
		"light": "#fff4d8", "darksq": "#66bdee", "frame": "#7cc6ee", "last": "#ffd16699", "select": "#ff8a1f66",
		"texture": "flat", "radius": 16, "edge": 4, "border_w": 2, "shadow": 0.1},
	{"id": "contrast", "name": "Контраст", "desc": "Максимально чётко — для слабого зрения",
		"dark": true, "bg": "#000000", "bg2": "#000000", "surface": "#0b0b0b", "raised": "#1c1c1c",
		"border": "#ffffff", "text": "#ffffff", "dim": "#dedede", "heading": "#ffee00",
		"accent": "#ffd400", "on_accent": "#000000", "ink": "#ffe24d", "accent2": "#33e6ff",
		"good": "#3dff8f", "bad": "#ff5c5c", "gold": "#ffd400",
		"light": "#f2f2f2", "darksq": "#557a99", "frame": "#ffffff", "last": "#ffee0080", "select": "#33e6ff80",
		"texture": "flat", "radius": 6, "edge": 0, "border_w": 2, "shadow": 0.0},
	{"id": "neon", "name": "Неон", "desc": "Прежний вид игры со светящимися рамками",
		"neon": true, "dark": true, "bg": "#050510", "surface": "#0d0d17", "raised": "#0f121f",
		"text": "#d1e0f2", "accent": "#1cd9f2", "accent2": "#ff4dd9", "light": "#edd9b8", "darksq": "#8c6142"},
]

# Исходные цвета доски и подсветок — для темы «Неон».
const NEON_LIGHT := Color(0.93, 0.86, 0.72)
const NEON_DARK := Color(0.55, 0.38, 0.26)

var current_id := DEFAULT_ID
var _pal: Dictionary = {}
var _c: Dictionary = {} # разобранные цвета текущей палитры
var _theme: Theme = null
var _font_regular: Font
var _font_bold: Font
var _font_semi: Font
var _grain: Texture2D = null # текстура клеток доски (дерево/мрамор) или null

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(Global.SETTINGS_PATH) == OK:
		current_id = String(cfg.get_value("settings", SETTINGS_KEY, DEFAULT_ID))
	_select(current_id)
	get_tree().node_added.connect(_on_node_added)
	# сцена входа могла появиться раньше этого автозагрузчика — переводим всё, что уже в дереве
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

# Разобранные цвета любой палитры (для превью в выборе темы).
func colors_of(id: String) -> Dictionary:
	var out := {}
	var p := palette_by_id(id)
	for k in p:
		if typeof(p[k]) == TYPE_STRING and String(p[k]).begins_with("#"):
			out[k] = Color.html(p[k])
	return out

func _select(id: String) -> void:
	_pal = palette_by_id(id)
	current_id = _pal.id
	_c = colors_of(current_id)
	var neon_theme: Theme = load(NEON_THEME_PATH)
	_font_regular = neon_theme.default_font
	_font_semi = _make_bold(_font_regular, 0.32)
	_font_bold = _make_bold(_font_regular, 0.62)
	_grain = null
	_card_cache = null
	if is_neon():
		_theme = neon_theme
		return
	_theme = _build_theme()
	if String(_pal.get("texture", "flat")) != "flat":
		_grain = _make_grain(String(_pal.texture))

func set_theme_id(id: String) -> void:
	_select(id)
	var cfg := ConfigFile.new()
	cfg.load(Global.SETTINGS_PATH)
	cfg.set_value("settings", SETTINGS_KEY, current_id)
	cfg.save(Global.SETTINGS_PATH)

func is_neon() -> bool:
	return bool(_pal.get("neon", false))

func is_dark() -> bool:
	return bool(_pal.get("dark", true))

func current_name() -> String:
	return String(_pal.get("name", ""))

func color(key: String) -> Color:
	return _c.get(key, Color.MAGENTA)

func font_bold() -> Font:
	return _font_bold

func font_regular() -> Font:
	return _font_regular

# Карточка, нарисованная кодом (дневник): та же, что у PanelContainer в теме.
var _card_cache: StyleBox = null
func draw_card(ci: CanvasItem, rect: Rect2) -> void:
	if is_neon():
		ci.draw_rect(rect, Color(0.05, 0.05, 0.09, 0.92), true)
		ci.draw_rect(rect, Color(0.11, 0.85, 0.95, 0.4), false, 2.0)
		return
	if _card_cache == null:
		_card_cache = _theme.get_stylebox("panel", "PanelContainer")
	_card_cache.draw(ci.get_canvas_item(), rect)

# Копия плоского стиля карточки текущей темы — чтобы подкрасить рамку (например, у полученной награды).
var _flat_card: StyleBoxFlat = null
func card_box() -> StyleBoxFlat:
	if _flat_card != null:
		return _flat_card.duplicate() as StyleBoxFlat
	return _box(Color(0.1, 0.1, 0.12), 10)

# --- доска -----------------------------------------------------------------------------------

func board_light() -> Color:
	return NEON_LIGHT if is_neon() else _c.light

func board_dark() -> Color:
	return NEON_DARK if is_neon() else _c.darksq

func hl_last() -> Color:
	return Color(0.9, 0.65, 0.15, 0.35) if is_neon() else _c.last

func hl_select() -> Color:
	return Color(0.95, 0.85, 0.25, 0.55) if is_neon() else _c.select

func hl_hint() -> Color:
	return Color(0.25, 0.65, 0.95, 0.6) if is_neon() else Color(_c.accent, 0.5)

func hl_check() -> Color:
	return Color(0.85, 0.1, 0.1, 0.55) if is_neon() else Color(0.9, 0.12, 0.1, 0.6)

func move_dot() -> Color:
	return Color(0.15, 0.55, 0.2, 0.55) if is_neon() else Color(0.08, 0.1, 0.06, 0.26)

func capture_ring() -> Color:
	return Color(0.8, 0.15, 0.15, 0.55) if is_neon() else Color(0.08, 0.1, 0.06, 0.3)

# Цвет подписи координаты на клетке: в стиле lichess — цвет противоположной клетки.
func coord_color(on_light_square: bool) -> Color:
	if is_neon():
		return Color(0, 0, 0, 0.5)
	return board_dark() if on_light_square else board_light()

# Рисует одну клетку: ровный цвет или текстура дерева/мрамора, своя для каждой клетки.
func draw_square(ci: CanvasItem, rect: Rect2, light: bool, index: int) -> void:
	var col := board_light() if light else board_dark()
	if _grain == null:
		ci.draw_rect(rect, col, true)
		return
	var k := 1.0 / 0.91 # текстура темнит в среднем на ~9 %, компенсируем
	var mod := Color(minf(col.r * k, 1.0), minf(col.g * k, 1.0), minf(col.b * k, 1.0))
	var off := Vector2(float((index * 137) % 384), float((index * 71 + (0 if light else 191)) % 384))
	ci.draw_texture_rect_region(_grain, rect, Rect2(off, Vector2(128, 128)), mod)

# Серая текстура 512×512 со значениями 0.8–1.0: волокна дерева или прожилки мрамора.
func _make_grain(kind: String) -> Texture2D:
	var n := FastNoiseLite.new()
	n.seed = 7
	var img: Image
	var lo := 205
	if kind == "wood":
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.035
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 4
		img = n.get_image(24, 512)
		img.resize(512, 512, Image.INTERPOLATE_BILINEAR) # растянули по горизонтали — получились волокна
	else:
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX
		n.frequency = 0.006
		n.fractal_type = FastNoiseLite.FRACTAL_RIDGED
		n.fractal_octaves = 5
		n.domain_warp_enabled = true
		n.domain_warp_amplitude = 40.0
		img = n.get_image(512, 512)
		lo = 214
	img.convert(Image.FORMAT_L8)
	var data := img.get_data()
	var span := 255 - lo
	for i in data.size():
		data[i] = lo + (data[i] * span) / 255
	return ImageTexture.create_from_image(Image.create_from_data(512, 512, false, Image.FORMAT_L8, data))

# --- построение темы -------------------------------------------------------------------------

func _make_bold(base: Font, strength: float) -> Font:
	var fv := FontVariation.new()
	if base is FontVariation:
		var b := base as FontVariation
		fv.base_font = b.base_font
		fv.fallbacks = b.fallbacks
		fv.spacing_top = b.spacing_top
		fv.spacing_bottom = b.spacing_bottom
	else:
		fv.base_font = base
	fv.variation_embolden = strength
	return fv

func _box(bg: Color, radius: int, margins := Vector4(16, 9, 16, 9)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margins.x
	sb.content_margin_top = margins.y
	sb.content_margin_right = margins.z
	sb.content_margin_bottom = margins.w
	sb.anti_aliasing = true
	return sb

func _shade(c: Color, amount: float) -> Color:
	# «светлее при наведении»: на тёмной теме осветляем, на светлой — чуть темним
	return c.lightened(amount) if is_dark() else c.darkened(amount * 0.6)

func _button_set(t: Theme, type: String, bg: Color, fg: Color, font: Font) -> void:
	var r := int(_pal.radius)
	var edge := int(_pal.edge)
	var bw := int(_pal.border_w)
	var contrast := current_id == "contrast"
	var normal: StyleBox = _box(bg, r)
	var hover: StyleBox = _box(_shade(bg, 0.08), r)
	var pressed: StyleBox = _box(bg.darkened(0.12), r)
	if contrast:
		for sb in [normal, hover, pressed]:
			(sb as StyleBoxFlat).set_border_width_all(bw)
			(sb as StyleBoxFlat).border_color = _c.border
		(hover as StyleBoxFlat).border_color = _c.accent
		(pressed as StyleBoxFlat).bg_color = bg.lerp(_c.accent, 0.32)
	var disabled: StyleBox = _box(Color(bg, bg.a * 0.45), r)
	if not contrast:
		# игровая кнопка: градиент, блик, тёмная нижняя кромка; при нажатии «проседает»
		var e := maxi(edge, 4)
		var sel_col: Color = bg if type == "PrimaryButton" else bg.lerp(_c.accent2, 0.5)
		normal = GameSkin.button_box(bg, r, e, "normal", is_dark())
		hover = GameSkin.button_box(bg, r, e, "hover", is_dark())
		pressed = GameSkin.button_box(sel_col, r, e, "pressed", is_dark())
		disabled = GameSkin.button_box(bg, r, e, "disabled", is_dark())
	var focus := _box(Color(0, 0, 0, 0), r)
	focus.draw_center = false
	focus.set_border_width_all(2)
	focus.border_color = Color(_c.accent, 0.85)
	focus.set_expand_margin_all(2)
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, pressed)
	t.set_stylebox("disabled", type, disabled)
	t.set_stylebox("focus", type, focus)
	for nm in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(nm, type, fg)
	t.set_color("font_disabled_color", type, Color(_c.dim, 0.55))
	t.set_color("icon_normal_color", type, fg)
	t.set_font("font", type, font)

func _build_theme() -> Theme:
	var t := Theme.new()
	var r := int(_pal.radius)
	var bw := int(_pal.border_w)
	t.default_font = _font_regular
	t.default_font_size = 16

	# текст
	t.set_color("font_color", "Label", _c.text)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	t.set_color("default_color", "RichTextLabel", _c.text)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())

	# кнопки: обычная, главная (акцент) и «опасная»
	_button_set(t, "Button", _c.raised, _c.text, _font_semi)
	t.set_type_variation("PrimaryButton", "Button")
	_button_set(t, "PrimaryButton", _c.accent, _c.on_accent, _font_bold)
	t.set_type_variation("DangerButton", "Button")
	_button_set(t, "DangerButton", _c.raised, _c.bad, _font_semi)
	_button_set(t, "OptionButton", _c.raised, _c.text, _font_semi)
	_button_set(t, "MenuButton", _c.raised, _c.text, _font_semi)
	t.set_constant("arrow_margin", "OptionButton", 10)

	# переключатели: строка без фона и свой рисованный переключатель
	for type in ["CheckButton", "CheckBox"]:
		var empty := _box(Color(0, 0, 0, 0), r, Vector4(6, 6, 6, 6))
		var hov := _box(Color(_c.text, 0.06), r, Vector4(6, 6, 6, 6))
		for st in ["normal", "pressed", "disabled", "hover_pressed"]:
			t.set_stylebox(st, type, empty)
		t.set_stylebox("hover", type, hov)
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		for nm in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			t.set_color(nm, type, _c.text)
		t.set_color("font_disabled_color", type, Color(_c.dim, 0.55))
		t.set_font("font", type, _font_regular)
	var on_tex := _switch_texture(true)
	var off_tex := _switch_texture(false)
	for nm in ["checked", "checked_mirrored"]:
		t.set_icon(nm, "CheckButton", on_tex)
	for nm in ["unchecked", "unchecked_mirrored"]:
		t.set_icon(nm, "CheckButton", off_tex)
	for nm in ["checked_disabled", "checked_disabled_mirrored", "unchecked_disabled", "unchecked_disabled_mirrored"]:
		t.set_icon(nm, "CheckButton", off_tex)

	# карточки
	var card := _box(_c.surface, r + 2, Vector4(18, 16, 18, 16))
	card.set_border_width_all(bw)
	card.border_color = _c.border
	if float(_pal.shadow) > 0.0:
		card.shadow_color = Color(0, 0, 0, float(_pal.shadow))
		card.shadow_size = 14
		card.shadow_offset = Vector2(0, 5)
	_flat_card = card
	var game_card: StyleBox = card
	if current_id != "contrast":
		var edge_col: Color = _c.border.lerp(_c.gold, 0.28) if is_dark() else _c.border
		game_card = GameSkin.card_box(_c.surface, edge_col, r + 4, maxf(bw, 1.0) + (0.5 if is_dark() else 0.0), float(_pal.shadow) + 0.1, is_dark())
	t.set_stylebox("panel", "PanelContainer", game_card)
	t.set_stylebox("panel", "Panel", game_card)
	t.set_type_variation("InnerPanel", "PanelContainer")
	var inner := _box(_c.raised if is_dark() else _c.bg, r, Vector4(14, 10, 14, 10))
	if current_id == "contrast":
		inner.set_border_width_all(1)
		inner.border_color = _c.border
	t.set_stylebox("panel", "InnerPanel", inner)

	# поля ввода
	var field_bg: Color = _c.bg.lerp(_c.surface, 0.35) if is_dark() else Color.WHITE
	var le := _box(field_bg, r - 2, Vector4(12, 8, 12, 8))
	le.set_border_width_all(maxi(bw, 1))
	le.border_color = _c.border
	var le_focus := le.duplicate() as StyleBoxFlat
	le_focus.set_border_width_all(2)
	le_focus.border_color = _c.accent
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, le)
		t.set_stylebox("focus", type, le_focus)
		t.set_stylebox("read_only", type, le)
		t.set_color("font_color", type, _c.text)
		t.set_color("font_placeholder_color", type, Color(_c.dim, 0.75))
		t.set_color("caret_color", type, _c.accent)
		t.set_color("selection_color", type, Color(_c.accent, 0.35))
		t.set_color("font_selected_color", type, _c.text)

	# ползунок и полоса прогресса
	var track := _box(Color(_c.text, 0.14), 4, Vector4(0, 3, 0, 3))
	var fill := _box(_c.accent, 4, Vector4(0, 3, 0, 3))
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(_c.accent.lightened(0.12), 4, Vector4(0, 3, 0, 3)))
	var grab := _knob_texture(_c.accent)
	t.set_icon("grabber", "HSlider", grab)
	t.set_icon("grabber_highlight", "HSlider", grab)
	t.set_stylebox("background", "ProgressBar", _box(Color(_c.text, 0.12), 6, Vector4(0, 4, 0, 4)))
	t.set_stylebox("fill", "ProgressBar", _box(_c.accent, 6, Vector4(0, 4, 0, 4)))
	t.set_color("font_color", "ProgressBar", _c.text)

	# разделители и полосы прокрутки
	var line := StyleBoxLine.new()
	line.color = _c.border
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", 10)
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, _box(Color(0, 0, 0, 0), 6, Vector4(3, 3, 3, 3)))
		t.set_stylebox("scroll_focus", type, _box(Color(0, 0, 0, 0), 6, Vector4(3, 3, 3, 3)))
		t.set_stylebox("grabber", type, _box(Color(_c.text, 0.22), 6, Vector4(4, 4, 4, 4)))
		t.set_stylebox("grabber_highlight", type, _box(Color(_c.text, 0.36), 6, Vector4(4, 4, 4, 4)))
		t.set_stylebox("grabber_pressed", type, _box(Color(_c.accent, 0.7), 6, Vector4(4, 4, 4, 4)))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())

	# всплывающие меню, подсказки, окна
	var pop := _box(_c.surface, r, Vector4(6, 6, 6, 6))
	pop.set_border_width_all(1)
	pop.border_color = _c.border
	pop.shadow_color = Color(0, 0, 0, 0.35)
	pop.shadow_size = 10
	t.set_stylebox("panel", "PopupMenu", pop)
	t.set_stylebox("hover", "PopupMenu", _box(Color(_c.accent, 0.22), r - 4, Vector4(8, 4, 8, 4)))
	t.set_color("font_color", "PopupMenu", _c.text)
	t.set_color("font_hover_color", "PopupMenu", _c.heading)
	t.set_color("font_disabled_color", "PopupMenu", Color(_c.dim, 0.55))
	t.set_font("font", "PopupMenu", _font_regular)
	t.set_stylebox("panel", "PopupPanel", pop)
	var tip := _box(_c.raised, 6, Vector4(10, 6, 10, 6))
	tip.set_border_width_all(1)
	tip.border_color = _c.border
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", _c.text)
	var win := _box(_c.surface, r + 2, Vector4(0, 0, 0, 0))
	win.set_border_width_all(maxi(bw, 1))
	win.border_color = _c.border
	win.expand_margin_top = 34
	win.set_expand_margin(SIDE_LEFT, 10)
	win.set_expand_margin(SIDE_RIGHT, 10)
	win.set_expand_margin(SIDE_BOTTOM, 10)
	win.shadow_color = Color(0, 0, 0, 0.45)
	win.shadow_size = 18
	t.set_stylebox("embedded_border", "Window", win)
	t.set_stylebox("embedded_unfocused_border", "Window", win)
	t.set_color("title_color", "Window", _c.heading)
	t.set_font("title_font", "Window", _font_bold)
	t.set_constant("title_height", "Window", 34)
	t.set_stylebox("panel", "AcceptDialog", StyleBoxEmpty.new())
	return t

# Переключатель-«таблетка» 44×24: акцентный со смещённой вправо ручкой или серый.
func _switch_texture(on: bool) -> Texture2D:
	var w := 44
	var h := 24
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track: Color = _c.accent if on else Color(_c.dim, 0.45)
	var knob_x := w - h / 2.0 if on else h / 2.0
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(p.x, h / 2.0, w - h / 2.0)
			var d := p.distance_to(Vector2(cx, h / 2.0))
			var a := clampf(h / 2.0 - d + 0.5, 0.0, 1.0)
			var c := Color(track, track.a * a)
			var dk := p.distance_to(Vector2(knob_x, h / 2.0))
			var ka := clampf(h / 2.0 - 3.0 - dk + 0.5, 0.0, 1.0)
			if ka > 0.0:
				c = c.lerp(Color(1, 1, 1, 1), ka)
				c.a = maxf(c.a, ka)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

# Ручка ползунка: круг цвета акцента с белой серединой.
func _knob_texture(col: Color) -> Texture2D:
	var s := 22
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c0 := Vector2(s / 2.0, s / 2.0)
	for y in s:
		for x in s:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c0)
			var a := clampf(s / 2.0 - d, 0.0, 1.0)
			var c := Color(col, a)
			var inner := clampf(s / 2.0 - 5.0 - d, 0.0, 1.0)
			if inner > 0.0:
				c = c.lerp(Color(1, 1, 1, a), inner)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

# --- перевод старых цветов -------------------------------------------------------------------

func _lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b

# Роль старого неонового цвета: "", "bg", "surface", "raised", "text", "dim", "accent", "accent_text",
# "accent2", "gold", "good", "bad", "white_overlay".
func _role(c: Color) -> String:
	var mx := maxf(c.r, maxf(c.g, c.b))
	var mn := minf(c.r, minf(c.g, c.b))
	var l := _lum(c)
	if c.r >= 0.99 and c.g >= 0.99 and c.b >= 0.99:
		if c.a < 0.3:
			return "white_overlay"
		return "" if is_dark() else "white_text" # белый текст на светлом фоне пропал бы
	if c.r > 0.5 and c.r < 0.7 and c.g > 0.85 and c.b > 0.95:
		return "accent_text" # светло-голубой текст неоновых кнопок
	if c.r < 0.3 and c.g > 0.7 and c.b > 0.8:
		return "accent"
	if c.r < 0.45 and c.g > 0.55 and c.b > 0.85:
		return "accent"
	if c.r > 0.8 and c.b > 0.75 and c.g < 0.75:
		return "accent2"
	if c.r > 0.85 and c.g > 0.55 and c.g < 0.92 and c.b < 0.45:
		return "gold"
	if c.g > 0.75 and c.r < 0.65 and c.b < 0.7 and c.g - c.r > 0.25:
		return "good"
	if c.r > 0.8 and c.g < 0.5 and c.b < 0.55:
		return "bad"
	if l > 0.7 and c.b >= c.r and (mx - mn) < 0.25:
		return "text"
	if (mx - mn) < 0.25 and c.b >= c.r and l >= 0.28 and l <= 0.75:
		return "dim"
	if mx < 0.22 and c.b >= c.r - 0.02:
		if l < 0.035:
			return "bg"
		return "surface" if l < 0.07 else "raised"
	return ""

# Цвет текущей темы для старого неонового цвета (прозрачность сохраняется).
func ink(c: Color) -> Color:
	if is_neon():
		return c
	var role := _role(c)
	var out: Color
	match role:
		"": return c
		"white_overlay": out = Color.WHITE if is_dark() else _c.text
		"white_text": out = _c.heading
		"accent_text": out = _c.text
		"accent": out = _c.ink
		"bg": out = _c.bg
		"surface": out = _c.surface
		"raised": out = _c.raised
		_: out = _c[role]
	out.a = c.a
	return out

const COLOR_NAMES := ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
	"font_disabled_color", "default_color", "font_placeholder_color", "caret_color", "font_outline_color"]
const STYLE_NAMES := ["panel", "normal", "hover", "pressed", "focus", "disabled", "background", "fill"]
const PRIMARY_NAMES := ["PlayButton", "CreateButton", "StartButton", "NewUserButton", "ContinueButton"]
const PRIMARY_TEXTS := ["Играть", "Быстрая игра", "Записаться", "Войти", "Создать", "Начать", "Сыграть", "Продолжить"]
const DANGER_TEXTS := ["Сдаться", "Удалить", "✕"]

# Старая светящаяся коробка → спокойная карточка или кнопка текущей темы.
func _restyle(sb: StyleBoxFlat) -> void:
	var bg_role := _role(sb.bg_color)
	var border_role := _role(sb.border_color)
	sb.bg_color = ink(sb.bg_color)
	var strong_border := border_role in ["accent", "accent2", "gold"] and sb.border_color.a > 0.6
	if strong_border:
		sb.border_color = ink(sb.border_color)
		sb.set_border_width_all(2)
	elif bg_role in ["bg", "surface", "raised", ""]:
		sb.border_color = _c.border
		sb.set_border_width_all(int(_pal.border_w))
	else:
		sb.border_color = ink(sb.border_color)
	sb.set_corner_radius_all(int(_pal.radius))
	if sb.shadow_size > 0:
		sb.shadow_color = Color(0, 0, 0, float(_pal.shadow) * 0.8)
		sb.shadow_size = mini(sb.shadow_size, 10)
		sb.shadow_offset = Vector2(0, 3)

# Каждый новый элемент переводится один раз, в конце кадра — после того как сцена или код
# выставили свои цвета и тексты.
func _on_node_added(node: Node) -> void:
	if node.get_parent() == get_tree().root and (node is Control or node is Node2D) and DisplayServer.get_name() != "headless":
		_fade_in.call_deferred()
	if is_neon() or not (node is Control):
		return
	if node.has_meta("themed"):
		return
	node.set_meta("themed", true)
	_apply_to.call_deferred(node)

func _apply_to(node: Node) -> void:
	if not is_instance_valid(node) or node.has_meta("brand"):
		return # элементы с фирменной окраской (экран входа) тема не трогает
	if node is ColorRect:
		var cr := node as ColorRect
		var was_bg := _role(cr.color) == "bg"
		cr.color = ink(cr.color)
		if was_bg and (cr.name == "Background" or cr.name == "Bg"):
			_add_gradient(cr)
		return
	var c := node as Control
	if c.theme != null and c.theme.resource_path == NEON_THEME_PATH:
		c.theme = _theme
	if c.name == "BoardFrame":
		c.add_theme_stylebox_override("panel", _frame_box())
		return
	for nm in COLOR_NAMES:
		if c.has_theme_color_override(nm):
			c.add_theme_color_override(nm, ink(c.get_theme_color(nm)))
	if c.has_theme_color_override("font_shadow_color"):
		c.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	for nm in STYLE_NAMES:
		if c.has_theme_stylebox_override(nm):
			var sb := c.get_theme_stylebox(nm)
			if sb is StyleBoxFlat:
				var copy := sb.duplicate() as StyleBoxFlat
				_restyle(copy)
				c.add_theme_stylebox_override(nm, copy)
	if c is Label:
		_style_label(c as Label)
	elif c is Button and not (c is CheckButton or c is CheckBox or c is OptionButton):
		_style_button(c as Button)
	elif c is PanelContainer and not c.has_theme_stylebox_override("panel") and c.theme_type_variation == "":
		var p := c.get_parent()
		while p != null:
			if p is PanelContainer or p is Panel:
				c.theme_type_variation = "InnerPanel"
				break
			if not (p is Control):
				break
			p = p.get_parent()

# Крупные надписи — заголовки: полужирные; цветной неоновый заголовок → цвет заголовков темы,
# чтобы шапки экранов были одного цвета, а акцент оставался для чисел и выделений.
func _style_label(l: Label) -> void:
	if not l.has_theme_font_size_override("font_size"):
		return
	var size := l.get_theme_font_size("font_size")
	if size >= 18:
		l.add_theme_font_override("font", _font_bold if size >= 20 else _font_semi)
		var col := l.get_theme_color("font_color")
		for k in ["ink", "accent2", "gold"]:
			if col == Color(_c[k], col.a):
				l.add_theme_color_override("font_color", Color(_c.heading, col.a))
				break
	elif size >= 17:
		l.add_theme_font_override("font", _font_semi)

# Новый экран проявляется из темноты за четверть секунды — переходы не «мигают».
func _fade_in() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	var cr := ColorRect.new()
	cr.color = _c.get("bg2", Color.BLACK) if not is_neon() else Color.BLACK
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cr.set_meta("themed", true)
	layer.add_child(cr)
	get_tree().root.add_child(layer)
	var tw := cr.create_tween()
	tw.tween_property(cr, "color:a", 0.0, 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_callback(layer.queue_free)

# Кнопка чуть подрастает под курсором и «вдавливается» при нажатии — как в играх.
func _add_hover(b: Button) -> void:
	if b.has_meta("hover_fx"):
		return
	b.set_meta("hover_fx", true)
	b.mouse_entered.connect(func(): _pop(b, 1.04))
	b.mouse_exited.connect(func(): _pop(b, 1.0))
	b.button_down.connect(func(): _pop(b, 0.96))
	b.button_up.connect(func(): _pop(b, 1.04 if b.is_hovered() else 1.0))

func _pop(b: Button, s: float) -> void:
	if not is_instance_valid(b) or (b.disabled and s > 1.0):
		return
	b.pivot_offset = b.size / 2.0
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2(s, s), 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _style_button(b: Button) -> void:
	_add_hover(b)
	# кнопки-строки в прокручиваемых списках (турниры, игроки) читаются лучше с текстом слева
	var parent := b.get_parent()
	if parent is VBoxContainer and parent.get_parent() is ScrollContainer and b.alignment == HORIZONTAL_ALIGNMENT_CENTER \
			and b.text.length() >= 16:
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if b.theme_type_variation != "" or b.has_theme_stylebox_override("normal"):
		return
	var txt := b.text.strip_edges()
	if b.name in PRIMARY_NAMES:
		b.theme_type_variation = "PrimaryButton"
		return
	if txt.contains("→") or txt.length() > 24:
		return # пункты-переходы и длинные подписи — обычные кнопки; акцентом выделяем одно действие
	for p in PRIMARY_TEXTS:
		if txt.begins_with(p):
			b.theme_type_variation = "PrimaryButton"
			return
	for d in DANGER_TEXTS:
		if txt.begins_with(d):
			b.theme_type_variation = "DangerButton"
			return

# Рамка доски: цвет рамки темы и мягкая тень, без свечения.
func _frame_box() -> StyleBoxFlat:
	var sb := _box(_c.frame, 8, Vector4(0, 0, 0, 0))
	if current_id == "contrast":
		sb.set_border_width_all(2)
		sb.border_color = _c.border
	sb.shadow_color = Color(0, 0, 0, maxf(float(_pal.shadow), 0.15))
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(0, 6)
	return sb

# Фон экрана: живой фон (небо, сияние, шахматный пол, искры). Старый градиент — запасной вариант.
func _add_gradient(cr: ColorRect) -> void:
	if current_id != "contrast":
		cr.add_child(GameBackdrop.new())
		return
	_add_flat_gradient(cr)

func _add_flat_gradient(cr: ColorRect) -> void:
	var g := Gradient.new()
	g.set_color(0, _c.bg.lightened(0.04) if is_dark() else _c.bg)
	g.set_color(1, _c.bg2)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 8
	gt.height = 256
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	var tr := TextureRect.new()
	tr.set_meta("themed", true)
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cr.add_child(tr)
