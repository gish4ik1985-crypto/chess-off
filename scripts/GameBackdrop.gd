class_name GameBackdrop
extends Control

# Живой фон экранов: градиентное «небо», мягкое сияние сверху, шахматный пол в перспективе,
# затемнение по краям и медленно плывущие искры. Цвета берутся из текущей темы.

const SPARKS := 34

var _sparks: Array = []
var _sky: TextureRect
var _glow: Color
var _floor_a: Color
var _spark_col: Color
var _vignette: Color

func _ready() -> void:
	name = "Backdrop"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_meta("themed", true)
	var dark := Themes.is_dark()
	var bg := Themes.color("bg")
	var bg2 := Themes.color("bg2")
	var g := Gradient.new()
	g.set_color(0, bg.lightened(0.07) if dark else bg.lightened(0.04))
	g.set_color(1, bg2.darkened(0.15) if dark else bg2)
	g.add_point(0.55, bg) # после set_color(1): новая точка сдвигает номера
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 8
	gt.height = 256
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	_sky = TextureRect.new()
	_sky.texture = gt
	_sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sky.stretch_mode = TextureRect.STRETCH_SCALE
	_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sky.show_behind_parent = true
	_sky.set_meta("themed", true)
	add_child(_sky)
	var accent := Themes.color("accent")
	var gold := Themes.color("gold")
	_glow = Color(Themes.color("accent2").lerp(gold, 0.25), 0.010 if dark else 0.008)
	_floor_a = Color(Themes.color("accent2").lerp(Themes.color("text"), 0.5), 0.05 if dark else 0.06)
	_spark_col = Color(gold, 0.8 if dark else 0.55)
	_vignette = Color(0, 0, 0, 0.35 if dark else 0.06)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in SPARKS:
		_sparks.append({"x": rng.randf(), "y": rng.randf(), "s": rng.randf_range(0.6, 2.2), "v": rng.randf_range(0.004, 0.018), "ph": rng.randf() * TAU})
	resized.connect(queue_redraw)
	set_process(DisplayServer.get_name() != "headless")

func _process(delta: float) -> void:
	for sp in _sparks:
		sp.y -= sp.v * delta
		sp.ph += delta * 1.6
		if sp.y < -0.02:
			sp.y = 1.02
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	# сияние у верхнего края
	var gc := Vector2(w * 0.5, h * 0.12)
	for i in range(28, 0, -1):
		draw_circle(gc, maxf(w, h) * 0.026 * i, _glow)
	# шахматный пол в перспективе: клетки сужаются к горизонту
	var horizon := h * 0.62
	var rows := 7
	var cols := 16
	for r in rows:
		var t0 := float(r) / rows
		var t1 := float(r + 1) / rows
		var y0 := horizon + (h - horizon) * t0 * t0
		var y1 := horizon + (h - horizon) * t1 * t1
		var spread0 := lerpf(0.25, 1.6, t0)
		var spread1 := lerpf(0.25, 1.6, t1)
		for c in cols:
			if (r + c) % 2 == 1:
				continue
			var u0 := float(c) / cols - 0.5
			var u1 := float(c + 1) / cols - 0.5
			var pts := PackedVector2Array([
				Vector2(w * 0.5 + u0 * w * spread0, y0), Vector2(w * 0.5 + u1 * w * spread0, y0),
				Vector2(w * 0.5 + u1 * w * spread1, y1), Vector2(w * 0.5 + u0 * w * spread1, y1)])
			draw_colored_polygon(pts, Color(_floor_a, _floor_a.a * (0.4 + t1)))
	# искры
	for sp in _sparks:
		var a: float = 0.45 + 0.55 * (0.5 + 0.5 * sin(sp.ph))
		var p := Vector2(sp.x * w, sp.y * h)
		draw_circle(p, sp.s * 2.2, Color(_spark_col, _spark_col.a * a * 0.25))
		draw_circle(p, sp.s, Color(_spark_col, _spark_col.a * a))
	# затемнение по краям
	if _vignette.a > 0.0:
		var steps := 8
		for i in steps:
			var k := float(i) / steps
			var a2 := _vignette.a * (1.0 - k) * 0.22
			var inset := k * minf(w, h) * 0.18
			draw_rect(Rect2(0, 0, w, inset + 2), Color(0, 0, 0, a2 * 0.6))
			draw_rect(Rect2(0, h - inset - 2, w, inset + 2), Color(0, 0, 0, a2))
			draw_rect(Rect2(0, 0, inset + 2, h), Color(0, 0, 0, a2))
			draw_rect(Rect2(w - inset - 2, 0, inset + 2, h), Color(0, 0, 0, a2))
