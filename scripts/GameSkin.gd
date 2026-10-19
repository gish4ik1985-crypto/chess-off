class_name GameSkin
extends RefCounted

# «Игровая» отрисовка интерфейса: объёмные кнопки с бликом и нижней кромкой, карточки с градиентом,
# рамкой и мягкой тенью. Текстуры рисуются один раз при выборе темы (по пикселям, со сглаживанием)
# и натягиваются на элементы как StyleBoxTexture с девятью частями — углы не растягиваются.

# Расстояние со знаком до скруглённого прямоугольника (отрицательное — внутри).
static func _sd_round_rect(p: Vector2, center: Vector2, half: Vector2, r: float) -> float:
	var q := (p - center).abs() - half + Vector2(r, r)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r

static func _blend(dst: Color, src: Color) -> Color:
	# src поверх dst (обычное смешивание с учётом прозрачности)
	var a := src.a + dst.a * (1.0 - src.a)
	if a <= 0.0001:
		return Color(0, 0, 0, 0)
	var rgb := (Color(src.r, src.g, src.b) * src.a + Color(dst.r, dst.g, dst.b) * dst.a * (1.0 - src.a)) / a
	return Color(rgb.r, rgb.g, rgb.b, a)

# Кнопка: лицевая часть с вертикальным градиентом и бликом сверху, под ней тёмная кромка высотой edge.
# state: normal / hover / pressed / disabled.
static var _cache: Dictionary = {}

static func button_texture(base: Color, radius: int, edge: int, state: String, dark_theme: bool) -> ImageTexture:
	var key := "%s|%d|%d|%s|%s" % [base.to_html(), radius, edge, state, dark_theme]
	if _cache.has(key):
		return _cache[key]
	var tex := _make_button_texture(base, radius, edge, state, dark_theme)
	_cache[key] = tex
	return tex

static func _make_button_texture(base: Color, radius: int, edge: int, state: String, dark_theme: bool) -> ImageTexture:
	var w := 64
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var col := base
	if state == "hover":
		col = base.lightened(0.10) if dark_theme else base.lightened(0.06)
	elif state == "disabled":
		col = Color(base.lerp(Color(0.5, 0.5, 0.5), 0.5), base.a * 0.5)
	var press := state == "pressed"
	var face_top := float(edge - 1) if press else 0.0
	var face_bottom := float(h - (1 if press else edge))
	var edge_col := col.darkened(0.42)
	var outline := Color(col.darkened(0.6), 0.55 * col.a)
	var top_col := col.lightened(0.16)
	var bot_col := col.darkened(0.05)
	var r := float(radius)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var c := Color(0, 0, 0, 0)
			# кромка (вся фигура)
			var d_all := _sd_round_rect(p, Vector2(w / 2.0, (face_top + h) / 2.0), Vector2(w / 2.0 - 0.5, (h - face_top) / 2.0 - 0.5), r)
			var a_all := clampf(0.5 - d_all, 0.0, 1.0)
			if a_all > 0.0:
				c = Color(edge_col, edge_col.a * a_all)
			# лицевая часть
			var fc := Vector2(w / 2.0, (face_top + face_bottom) / 2.0)
			var fh := Vector2(w / 2.0 - 0.5, (face_bottom - face_top) / 2.0 - 0.5)
			var d_face := _sd_round_rect(p, fc, fh, r)
			var a_face := clampf(0.5 - d_face, 0.0, 1.0)
			if a_face > 0.0:
				var t := clampf((p.y - face_top) / maxf(face_bottom - face_top, 1.0), 0.0, 1.0)
				var fcol := top_col.lerp(bot_col, t)
				if press:
					fcol = fcol.darkened(0.08)
				# блик: тонкая светлая линия у верхнего края лица
				if d_face > -2.6 and d_face < -1.2 and p.y < fc.y:
					fcol = fcol.lerp(Color(1, 1, 1), 0.22 if dark_theme else 0.35)
				c = _blend(c, Color(fcol, col.a * a_face))
			# тонкий контур
			if a_all > 0.0 and d_all > -1.2:
				c = _blend(c, Color(outline, outline.a * a_all * clampf(d_all + 1.2, 0.0, 1.0)))
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

static func button_box(base: Color, radius: int, edge: int, state: String, dark_theme: bool, pad := Vector2(18, 10)) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = button_texture(base, radius, edge, state, dark_theme)
	var m := float(radius + 2)
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m + edge
	sb.content_margin_left = pad.x
	sb.content_margin_right = pad.x
	var shift := float(edge - 1) if state == "pressed" else 0.0
	sb.content_margin_top = pad.y + shift
	sb.content_margin_bottom = pad.y + edge - shift
	return sb

# Карточка: градиент сверху вниз, рамка, светлая линия по верхнему краю, мягкая тень вокруг.
static func card_texture(bg: Color, border: Color, radius: int, border_w: float, shadow_a: float, dark_theme: bool, pad: int) -> ImageTexture:
	var body := 64
	var size := body + pad * 2
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var half := Vector2(body / 2.0, body / 2.0)
	var r := float(radius)
	var top := bg.lightened(0.07 if dark_theme else 0.02)
	var bot := bg.darkened(0.05 if dark_theme else 0.01)
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var c := Color(0, 0, 0, 0)
			# тень чуть ниже карточки
			var ds := _sd_round_rect(p, center + Vector2(0, pad * 0.3), half, r)
			if ds > -r and shadow_a > 0.0:
				var fall := clampf(1.0 - ds / float(pad), 0.0, 1.0)
				c = Color(0, 0, 0, shadow_a * fall * fall * 0.75)
			var d := _sd_round_rect(p, center, half, r)
			var a := clampf(0.5 - d, 0.0, 1.0)
			if a > 0.0:
				var t := clampf((p.y - (center.y - half.y)) / (half.y * 2.0), 0.0, 1.0)
				var fcol := top.lerp(bot, t)
				if border_w > 0.0 and d > -border_w - 0.5:
					fcol = fcol.lerp(Color(border, 1.0), clampf(d + border_w + 0.5, 0.0, 1.0) * border.a)
				elif d > -border_w - 1.6 and p.y < center.y - half.y * 0.2:
					fcol = fcol.lerp(Color(1, 1, 1), 0.08 if dark_theme else 0.25)
				c = _blend(c, Color(fcol, bg.a * a))
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

static func card_box(bg: Color, border: Color, radius: int, border_w: float, shadow_a: float, dark_theme: bool, content := Vector4(18, 16, 18, 16)) -> StyleBoxTexture:
	var pad := 14
	var sb := StyleBoxTexture.new()
	sb.texture = card_texture(bg, border, radius, border_w, shadow_a, dark_theme, pad)
	var m := float(pad + radius + 2)
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m
	sb.expand_margin_left = pad
	sb.expand_margin_right = pad
	sb.expand_margin_top = pad
	sb.expand_margin_bottom = pad
	sb.content_margin_left = content.x
	sb.content_margin_top = content.y
	sb.content_margin_right = content.z
	sb.content_margin_bottom = content.w
	return sb
