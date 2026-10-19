extends VBoxContainer

# Главный экран в стиле игрового лобби: большая золотая кнопка «Играть», карточка «Продолжить»
# и плитки разделов с крупными фигурами. Строится кодом; обработчики берёт у главного меню (Menu.gd).

const TILE_COLORS := {
	"train": Color("#2f9e5b"), "compete": Color("#d8692f"), "school": Color("#2f7fd6"), "profile": Color("#7d55e6"),
}
const W := 974.0

var _menu: Node
var _school_badge: Label

func build(menu: Node) -> void:
	_menu = menu
	add_theme_constant_override("separation", 18)
	var vw: float = menu.get_viewport_rect().size.x
	custom_minimum_size = Vector2(minf(W, vw - 40.0), 0)
	_header()
	var row1 := HFlowContainer.new()
	row1.alignment = FlowContainer.ALIGNMENT_CENTER
	row1.add_theme_constant_override("h_separation", 18)
	row1.add_theme_constant_override("v_separation", 18)
	add_child(row1)
	row1.add_child(_hero())
	row1.add_child(_continue_card())
	var row2 := HFlowContainer.new()
	row2.alignment = FlowContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("h_separation", 18)
	row2.add_theme_constant_override("v_separation", 18)
	add_child(row2)
	row2.add_child(_tile("Учиться", "Карта, задачи, школа юного шахматиста", "B", TILE_COLORS.train, func(): _menu._show_panel(_menu.train_panel)))
	row2.add_child(_tile("Соревнования", "Турниры, лига ботов, игроки", "R", TILE_COLORS.compete, func(): _menu._show_panel(_menu.tourney_panel)))
	var school := _tile("Школа", "Объявления, расписание, задания, чат", "K", TILE_COLORS.school, func(): _menu._show_panel(_menu.school_panel))
	_school_badge = school.get_meta("badge")
	row2.add_child(school)
	row2.add_child(_tile("Мой профиль", "Рейтинг, навыки, награды", "N", TILE_COLORS.profile, func(): _menu._on_profile_pressed()))
	if not OS.has_feature("web"):
		var quit := Button.new()
		quit.text = "Выход"
		quit.custom_minimum_size = Vector2(160, 40)
		quit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		quit.pressed.connect(func(): _menu._on_quit_pressed())
		add_child(quit)

func set_school_badge(n: int) -> void:
	if _school_badge == null:
		return
	_school_badge.text = str(n)
	_school_badge.get_parent().visible = n > 0

# ---- части ----

func _brand_label(text: String, size: int, color: Color, bold := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", Themes.font_bold())
	# тень под светлыми подписями (на цветных плитках и тёмной теме); тёмный текст на светлом — без тени
	if Themes.is_dark() or color.get_luminance() > 0.7:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
		l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_meta("brand", true)
	return l

func _header() -> void:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 12)
	add_child(h)
	var seal := TextureRect.new()
	seal.texture = load("res://assets/brand/seal_512.png")
	seal.custom_minimum_size = Vector2(52, 52)
	seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(seal)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	h.add_child(col)
	col.add_child(_brand_label("ИРБИС", 34, Themes.color("heading")))
	col.add_child(_brand_label("шахматный клуб · играй, учись, побеждай", 14, Themes.color("dim"), false))

# Кнопка-плитка: объёмная текстура цвета col и содержимое поверх (подписи не ловят мышь).
func _big_button(col: Color, size: Vector2, radius: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	var dark := Themes.is_dark()
	b.add_theme_stylebox_override("normal", GameSkin.button_box(col, radius, 7, "normal", dark, Vector2(16, 14)))
	b.add_theme_stylebox_override("hover", GameSkin.button_box(col, radius, 7, "hover", dark, Vector2(16, 14)))
	b.add_theme_stylebox_override("pressed", GameSkin.button_box(col, radius, 7, "pressed", dark, Vector2(16, 14)))
	b.add_theme_stylebox_override("hover_pressed", GameSkin.button_box(col, radius, 7, "pressed", dark, Vector2(16, 14)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b

func _content_box(b: Button) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 20
	v.offset_right = -20
	v.offset_top = 14
	v.offset_bottom = -20
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	return v

func _piece_icon(piece: String, size: float, color := "w") -> TextureRect:
	var t := TextureRect.new()
	t.texture = PieceTextures.get_texture(piece, color)
	t.custom_minimum_size = Vector2(size, size)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

func _hero() -> Control:
	var accent := Themes.color("accent")
	var on := Themes.color("on_accent")
	var b := _big_button(accent, Vector2(478, 178), 22)
	b.pressed.connect(func(): _menu._show_panel(_menu.play_panel))
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 28
	h.offset_right = -20
	h.offset_bottom = -7
	h.add_theme_constant_override("separation", 18)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var icon := _piece_icon("K", 112, "b" if on.get_luminance() < 0.5 else "w")
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(icon)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var t := _brand_label("ИГРАТЬ", 50, on)
	t.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.25))
	v.add_child(t)
	var level := int(Global.difficulty)
	v.add_child(_brand_label("Партия с компьютером · уровень %d" % level, 15, Color(on, 0.8), false))
	return b

func _continue_card() -> Control:
	var info: Dictionary = _menu._continue_info()
	var raised := Themes.color("raised")
	var b := _big_button(raised, Vector2(478, 178), 22)
	var v := _content_box(b)
	var kind := String(info.get("kind", ""))
	b.pressed.connect(func(): _menu._on_continue_pressed(kind))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	top.add_child(_piece_icon("Q" if kind == "game" else ("R" if kind == "tourney" else "P"), 64))
	var tv := VBoxContainer.new()
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	tv.add_child(_brand_label(String(info.get("title", "Продолжить")), 24, Themes.color("heading")))
	var sub := _brand_label(String(info.get("sub", "")), 14, Themes.color("dim"), false)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(sub)
	var hint: String = _menu._road_hint()
	if hint != "":
		var l := _brand_label("✦ " + hint, 13, Themes.color("gold"), false)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	return b

func _tile(title: String, caption: String, piece: String, col: Color, cb: Callable) -> Button:
	var b := _big_button(col, Vector2(230, 196), 20)
	b.pressed.connect(cb)
	var v := _content_box(b)
	v.add_theme_constant_override("separation", 4)
	var icon := _piece_icon(piece, 78)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(icon)
	var t := _brand_label(title, 22, Color.WHITE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var c := _brand_label(caption, 12, Color(1, 1, 1, 0.82), false)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(c)
	# счётчик новостей в правом верхнем углу
	var pill := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#ff4d5e")
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	sb.border_color = Color.WHITE
	sb.set_border_width_all(2)
	pill.add_theme_stylebox_override("panel", sb)
	pill.set_meta("brand", true)
	pill.position = Vector2(196, -6)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.visible = false
	var n := _brand_label("0", 14, Color.WHITE)
	pill.add_child(n)
	b.add_child(pill)
	b.set_meta("badge", n)
	return b

# ---- верхняя полоса: карточка игрока и «ресурсы» ----

const TITLE_STEPS := [0, 500, 800, 1100, 1400, 1800, 2100, 2400, 2600, 3000]

static func _hud_label(text: String, size: int, color: Color, bold: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if bold:
		l.add_theme_font_override("font", Themes.font_bold())
	l.add_theme_color_override("font_color", color)
	l.set_meta("brand", true)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func build_hud(menu: Node, hb: HBoxContainer) -> void:
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.tooltip_text = "Мой профиль: рейтинг, навыки, награды"
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.07 if st in ["hover", "pressed", "hover_pressed"] else 0.0)
		sb.set_corner_radius_all(14)
		sb.content_margin_left = 6
		sb.content_margin_right = 12
		card.add_theme_stylebox_override(st, sb)
	card.custom_minimum_size = Vector2(300, 62)
	card.pressed.connect(func(): menu._on_profile_pressed())
	hb.add_child(card)
	hb.move_child(card, 0)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)
	var av := Control.new()
	av.custom_minimum_size = Vector2(54, 54)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring := Themes.color("gold")
	var fill := Themes.color("raised")
	av.draw.connect(func():
		var c := av.size / 2.0
		av.draw_circle(c, 27, ring.darkened(0.35))
		av.draw_circle(c, 25, ring)
		av.draw_circle(c, 22, fill)
		av.draw_arc(c, 19, PI * 1.1, PI * 1.7, 12, Color(1, 1, 1, 0.25), 2.0, true))
	h.add_child(av)
	var ava := Profile.avatar if Profile.avatar != "" else Profile.shown_name().left(1).to_upper()
	var letter := _hud_label(ava, 24, Themes.color("heading"), true)
	letter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	av.add_child(letter)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var role_icon := Roles.icon_for(Profile.role)
	var nm := _hud_label(Profile.shown_name() + (("  " + role_icon) if role_icon != "" else ""), 18, Themes.color("heading"), true)
	nm.clip_text = true
	nm.custom_minimum_size = Vector2(200, 0)
	v.add_child(nm)
	var r := float(Profile.tournament_rating)
	var lo := 0.0
	var hi := 3000.0
	for i in range(TITLE_STEPS.size() - 1):
		if r >= TITLE_STEPS[i] and r < TITLE_STEPS[i + 1]:
			lo = TITLE_STEPS[i]
			hi = TITLE_STEPS[i + 1]
	v.add_child(_hud_label("%s · Ступень %d" % [Profile.rating_title(), Profile.clean_step()], 12, Themes.color("dim"), false))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(200, 8)
	bar.show_percentage = false
	bar.min_value = lo
	bar.max_value = hi
	bar.value = r
	bar.tooltip_text = "До следующего звания: %d очков рейтинга" % int(hi - r)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Color(0, 0, 0, 0.35)
	bgs.set_corner_radius_all(4)
	var fgs := StyleBoxFlat.new()
	fgs.bg_color = Themes.color("gold")
	fgs.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bgs)
	bar.add_theme_stylebox_override("fill", fgs)
	bar.set_meta("brand", true)
	v.add_child(bar)
	# «ресурсы»: рейтинг, серия дней, достижения
	var idx := 1
	var chips := [["🏆", str(int(round(r))), "Турнирный рейтинг"],
		["🔥", str(Profile.current_streak()), "Серия дней с решёнными задачами"],
		["⭐", "%d/%d" % [Profile.achievement_count(), Profile.total_achievement_count()], "Достижения"]]
	for chip in chips:
		var pill := PanelContainer.new()
		var psb := StyleBoxFlat.new()
		psb.bg_color = Color(0, 0, 0, 0.28)
		psb.border_color = Color(Themes.color("gold"), 0.35)
		psb.set_border_width_all(1)
		psb.set_corner_radius_all(18)
		psb.content_margin_left = 12
		psb.content_margin_right = 14
		psb.content_margin_top = 4
		psb.content_margin_bottom = 4
		pill.add_theme_stylebox_override("panel", psb)
		pill.set_meta("brand", true)
		pill.tooltip_text = chip[2]
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pill.add_child(_hud_label("%s %s" % [chip[0], chip[1]], 17, Themes.color("text"), true))
		hb.add_child(pill)
		hb.move_child(pill, idx)
		idx += 1
