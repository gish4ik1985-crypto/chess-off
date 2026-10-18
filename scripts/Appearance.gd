extends Control

# «Оформление»: выбор темы по карточкам с живым превью — фон, карточка, кнопка и кусочек доски
# с фигурами в цветах темы. Выбор сразу применяется: экран перезагружается уже в новой теме.

const CARD_SIZE := Vector2(272, 232)

func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	vbox.add_child(top)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(titles)
	var title := Label.new()
	title.text = "Оформление"
	title.add_theme_font_size_override("font_size", 30)
	titles.add_child(title)
	var sub := Label.new()
	sub.text = "Выберите тему — она применится ко всем экранам и к доске. Сейчас: «%s»." % Themes.current_name()
	sub.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(sub)
	var back := Button.new()
	back.name = "BackButton"
	back.text = "← Назад"
	back.custom_minimum_size = Vector2(140, 48)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Settings.tscn"))
	top.add_child(back)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 16)
	flow.add_theme_constant_override("v_separation", 16)
	scroll.add_child(flow)
	for p in Themes.PALETTES:
		flow.add_child(_card(p))

func _card(p: Dictionary) -> Control:
	var id := String(p.id)
	var selected := id == Themes.current_id
	var btn := Button.new()
	btn.custom_minimum_size = CARD_SIZE
	btn.tooltip_text = String(p.desc)
	btn.pressed.connect(func():
		if id != Themes.current_id:
			Themes.set_theme_id(id)
			get_tree().reload_current_scene())
	if selected:
		# выбранная тема — рамка цветом акцента (стиль задан явно, перевод темы не нужен)
		btn.set_meta("themed", true)
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.05, 0.12, 0.14, 0.9) if Themes.is_neon() else Themes.color("raised")
		box.set_border_width_all(3)
		box.border_color = Color(0.1, 0.95, 1) if Themes.is_neon() else Themes.color("accent")
		box.set_corner_radius_all(12)
		for st in ["normal", "hover", "pressed"]:
			btn.add_theme_stylebox_override(st, box)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 12
	col.offset_top = 12
	col.offset_right = -12
	col.offset_bottom = -10
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	btn.add_child(col)
	var preview := Control.new()
	preview.custom_minimum_size = Vector2(0, 128)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var colors := Themes.colors_of(id)
	var neon := bool(p.get("neon", false))
	preview.draw.connect(func(): _draw_preview(preview, colors, neon))
	col.add_child(preview)
	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_row)
	var nm := Label.new()
	nm.text = String(p.name)
	nm.add_theme_font_size_override("font_size", 18)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(nm)
	if selected:
		var mark := Label.new()
		mark.text = "✓ выбрана"
		mark.add_theme_font_size_override("font_size", 13)
		mark.add_theme_color_override("font_color", Color(0.1, 0.95, 1))
		name_row.add_child(mark)
	var desc := Label.new()
	desc.text = String(p.desc)
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(desc)
	return btn

# Миниатюра темы: фон, карточка с заголовком, строками текста и кнопкой, рядом доска 4×4 с фигурами.
func _draw_preview(ci: Control, c: Dictionary, neon: bool) -> void:
	var r := Rect2(Vector2.ZERO, ci.size)
	var bg := StyleBoxFlat.new()
	bg.bg_color = c.bg
	bg.set_corner_radius_all(10)
	if neon:
		bg.border_color = Color(c.accent, 0.6)
		bg.set_border_width_all(1)
	bg.draw(ci.get_canvas_item(), r)
	var bsize := r.size.y - 20.0
	var sq := bsize / 4.0
	var bo := Vector2(r.size.x - bsize - 10.0, 10.0)
	for y in 4:
		for x in 4:
			ci.draw_rect(Rect2(bo + Vector2(x * sq, y * sq), Vector2(sq, sq)), c.light if (x + y) % 2 == 0 else c.darksq, true)
	PieceTextures.draw(ci, "N", "w", bo + Vector2(1.5 * sq, 2.5 * sq), sq * 0.92)
	PieceTextures.draw(ci, "P", "b", bo + Vector2(2.5 * sq, 1.5 * sq), sq * 0.92)
	PieceTextures.draw(ci, "K", "w", bo + Vector2(0.5 * sq, 3.5 * sq), sq * 0.92)
	var card := Rect2(Vector2(10, 10), Vector2(bo.x - 20.0, r.size.y - 20.0))
	var cs := StyleBoxFlat.new()
	cs.bg_color = c.surface
	cs.set_corner_radius_all(8)
	if neon:
		cs.border_color = Color(c.accent, 0.7)
		cs.set_border_width_all(1)
		cs.shadow_color = Color(c.accent, 0.35)
		cs.shadow_size = 6
	cs.draw(ci.get_canvas_item(), card)
	var x0 := card.position.x + 10.0
	var w := card.size.x - 20.0
	var heading: Color = c.get("heading", c.text)
	_bar(ci, Rect2(x0, card.position.y + 12, w * 0.7, 9), heading)
	_bar(ci, Rect2(x0, card.position.y + 30, w * 0.9, 6), Color(c.text, 0.55))
	_bar(ci, Rect2(x0, card.position.y + 42, w * 0.6, 6), Color(c.text, 0.55))
	var btn := Rect2(x0, card.end.y - 34, w, 24)
	var bs := StyleBoxFlat.new()
	if neon:
		bs.bg_color = c.raised
		bs.border_color = c.accent
		bs.set_border_width_all(1)
	else:
		bs.bg_color = c.accent
		bs.border_width_bottom = 3
		bs.border_color = (c.accent as Color).darkened(0.32)
	bs.set_corner_radius_all(6)
	bs.draw(ci.get_canvas_item(), btn)
	var label_col: Color = c.accent if neon else c.get("on_accent", c.text)
	_bar(ci, Rect2(btn.position.x + btn.size.x * 0.3, btn.position.y + 9, btn.size.x * 0.4, 5), label_col)

func _bar(ci: Control, r: Rect2, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(r.size.y / 2.0))
	sb.draw(ci.get_canvas_item(), r)
