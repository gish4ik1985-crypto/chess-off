extends Node2D

@onready var map_draw: Node2D = $MapDraw
@onready var detail_panel: Panel = $UI/DetailPanel
@onready var detail_name: Label = $UI/DetailPanel/VBox/NameLabel
@onready var detail_region: Label = $UI/DetailPanel/VBox/RegionLabel
@onready var detail_blurb: Label = $UI/DetailPanel/VBox/BlurbLabel
@onready var detail_level: Label = $UI/DetailPanel/VBox/LevelLabel
@onready var detail_play_button: Button = $UI/DetailPanel/VBox/HBox/PlayButton
@onready var detail_assist_button: Button = $UI/DetailPanel/VBox/HBox/AssistButton
@onready var detail_assist_hint: Label = $UI/DetailPanel/VBox/AssistHint
@onready var progress_label: Label = $UI/TopBar/HBox/ProgressLabel
@onready var next_theme_label: Label = $UI/TopBar/HBox/NextThemeLabel
@onready var act_label: Label = $UI/TopBar/HBox/ActLabel
@onready var act_prev_button: Button = $UI/TopBar/HBox/ActPrevButton
@onready var act_next_button: Button = $UI/TopBar/HBox/ActNextButton
@onready var music: MusicPlayer = $Music

const NODE_RADIUS := 36.0

var selected_id: String = ""
var current_act := 1 # which of the three 18-node acts is shown

func _ready() -> void:
	# Node positions in MapData were laid out for a 1100px-wide design;
	# center the drawing when the viewport is wider.
	map_draw.position.x = (get_viewport_rect().size.x - 1100.0) / 2.0
	map_draw.draw.connect(_on_map_draw)
	detail_panel.visible = false
	current_act = _frontier_character().get("act", 1)
	act_prev_button.pressed.connect(_on_act_changed.bind(-1))
	act_next_button.pressed.connect(_on_act_changed.bind(1))
	_update_act_label()
	_update_progress_label()
	_play_frontier_theme()

func _act_nodes() -> Array:
	var out := []
	for c in MapData.CHARACTERS:
		if c.get("act", 1) == current_act:
			out.append(c)
	return out

func _on_act_changed(delta: int) -> void:
	current_act = clampi(current_act + delta, 1, 3)
	selected_id = ""
	detail_panel.visible = false
	_update_act_label()
	map_draw.queue_redraw()

func _update_act_label() -> void:
	act_label.text = "Акт %d/3 — %s" % [current_act, MapData.ACT_NAMES.get(current_act, "")]
	act_prev_button.disabled = current_act <= 1
	act_next_button.disabled = current_act >= 3

func _update_progress_label() -> void:
	var defeated = 0
	for c in MapData.CHARACTERS:
		# count only nodes actually reached on the path — a task node's own
		# quota can otherwise fill up from puzzle practice done elsewhere,
		# before the player has actually arrived at that stop
		if Profile.is_character_unlocked(c.id) and Profile.is_character_defeated(c.id):
			defeated += 1
	progress_label.text = "Побеждено: %d / %d" % [defeated, MapData.CHARACTERS.size()]
	_update_next_theme_label()

func _update_next_theme_label() -> void:
	for c in MapData.CHARACTERS:
		if Profile.is_character_unlocked(c.id):
			continue
		var required = c.get("theme_required", 0)
		if required <= 0:
			next_theme_label.text = ""
			return
		var progress = Profile.theme_progress(c.get("theme", ""))
		next_theme_label.text = "Дальше — тема «%s»: %d / %d" % [c.get("theme_label", ""), min(progress, required), required]
		return
	next_theme_label.text = ""

func _frontier_character() -> Dictionary:
	for c in MapData.CHARACTERS:
		if not Profile.is_character_defeated(c.id):
			return c
	return MapData.CHARACTERS[-1]

func _play_frontier_theme() -> void:
	var c = _frontier_character()
	music.start_theme(c.music)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local = map_draw.get_global_transform().affine_inverse() * event.position
		for c in _act_nodes():
			if local.distance_to(c.pos) <= NODE_RADIUS:
				_on_node_clicked(c)
				return
		_close_detail()

func _on_node_clicked(c: Dictionary) -> void:
	if not Profile.is_character_unlocked(c.id):
		_show_locked_hint(c)
		return
	selected_id = c.id
	detail_name.text = c.name
	detail_region.text = c.region
	detail_blurb.text = c.blurb
	if c.get("node", "") == "task" or c.get("node", "") == "mix":
		var progress = Profile.mix_puzzles_solved if c.get("node", "") == "mix" else Profile.theme_progress(c.get("theme", ""))
		var required = int(c.get("required", 0))
		detail_level.text = "Решено: %d / %d%s" % [min(progress, required), required, " ✔" if progress >= required else ""]
		detail_play_button.text = "Решать задачи"
		detail_play_button.visible = true
		detail_assist_button.visible = false
		detail_assist_hint.visible = false
		detail_panel.visible = true
		music.start_theme(c.music)
		map_draw.queue_redraw()
		return
	var status = " (побеждён)" if Profile.is_character_defeated(c.id) else ""
	detail_level.text = "Сложность: " + Global.difficulty_label(Global.adaptive_level(c.ai_level)) + status
	detail_play_button.text = "Играть снова" if Profile.is_character_defeated(c.id) else "Играть"
	detail_play_button.visible = true
	# Mastering the character's theme (enough clean solves) earns the
	# handicap option for this fight even when the global setting is off.
	var mastered = Profile.theme_mastered(c.get("theme", ""))
	var assist_ok = c.has("assist_fen") and (Global.handicap_enabled or mastered)
	detail_assist_button.visible = assist_ok
	detail_assist_hint.visible = assist_ok
	if mastered:
		detail_assist_hint.text = "Тема «%s» пройдена отлично — в награду доступна игра с форой!" % c.get("theme_label", "")
	else:
		detail_assist_hint.text = "«С форой» — начать с материальным перевесом, чтобы не вязнуть в трудной партии"
	detail_panel.visible = true
	music.start_theme(c.music)
	map_draw.queue_redraw()

func _show_locked_hint(c: Dictionary) -> void:
	selected_id = ""
	detail_name.text = c.name
	detail_region.text = c.region
	var required = c.get("theme_required", 0)
	if required > 0:
		var progress = Profile.theme_progress(c.get("theme", ""))
		detail_blurb.text = "Заперто. Чтобы открыть бой, порешайте тему «%s» в разделе «Задачи»." % c.get("theme_label", "")
		detail_level.text = "Прогресс темы: %d / %d" % [min(progress, required), required]
	else:
		detail_blurb.text = "Заперто. Пройдите предыдущую остановку на карте, чтобы открыть эту."
		detail_level.text = ""
	detail_play_button.visible = false
	detail_assist_button.visible = false
	detail_assist_hint.visible = false
	detail_panel.visible = true
	map_draw.queue_redraw()

func _close_detail() -> void:
	selected_id = ""
	detail_panel.visible = false
	_play_frontier_theme()
	map_draw.queue_redraw()

func _on_close_pressed() -> void:
	_close_detail()

func _on_play_pressed() -> void:
	if selected_id == "":
		return
	var c = MapData.by_id(selected_id)
	if c.get("node", "") == "task":
		Global.puzzle_theme = c.get("theme", "")
		get_tree().change_scene_to_file("res://scenes/Puzzle.tscn")
		return
	if c.get("node", "") == "mix":
		Global.puzzle_theme = "mix"
		get_tree().change_scene_to_file("res://scenes/Puzzle.tscn")
		return
	Global.difficulty = c.ai_level
	Global.map_character_id = c.id
	Global.map_assist = false
	Global.player_color = "w"
	get_tree().change_scene_to_file("res://scenes/Board.tscn")

func _on_play_assist_pressed() -> void:
	if selected_id == "":
		return
	var c = MapData.by_id(selected_id)
	if not Global.handicap_enabled and not Profile.theme_mastered(c.get("theme", "")):
		return
	Global.difficulty = c.ai_level
	Global.map_character_id = c.id
	Global.map_assist = true
	Global.player_color = "w"
	get_tree().change_scene_to_file("res://scenes/Board.tscn")

func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")

func _draw_soft_backdrop(center: Vector2, palette: Dictionary) -> void:
	var layers = 5
	for i in range(layers, 0, -1):
		var t = float(i) / float(layers)
		var r = 150.0 * t
		var col: Color = palette.bg_a.lerp(palette.bg_b, 1.0 - t)
		col.a = 0.10 * (1.0 - t) + 0.03
		map_draw.draw_circle(center, r, col)

func _on_map_draw() -> void:
	var nodes = _act_nodes()
	# region backdrops first (behind everything)
	for c in nodes:
		_draw_soft_backdrop(c.pos, c.palette)

	# connecting path — a soft glow trail underneath a solid line, with small
	# waypoint dots so the route reads as a path rather than a ruler line
	for i in range(nodes.size() - 1):
		var a = nodes[i].pos
		var b = nodes[i + 1].pos
		var unlocked = Profile.is_character_unlocked(nodes[i + 1].id)
		var col = Color(0.15, 0.9, 1.0, 0.8) if unlocked else Color(0.4, 0.4, 0.45, 0.35)
		_draw_path_segment(a, b, col, unlocked)

	# nodes
	for c in nodes:
		var unlocked = Profile.is_character_unlocked(c.id)
		var defeated = Profile.is_character_defeated(c.id)
		var accent: Color = c.palette.accent
		var ring_col = accent if unlocked else Color(0.4, 0.4, 0.46)
		var fill_col = Color(0.05, 0.05, 0.08, 0.95)

		# soft drop shadow for depth
		map_draw.draw_circle(c.pos + Vector2(0, 5), NODE_RADIUS * 1.02, Color(0, 0, 0, 0.25))

		if unlocked:
			for i in range(3, 0, -1):
				var t = float(i) / 3.0
				var glow = accent
				glow.a = 0.10 * (1.0 - t) + 0.03
				map_draw.draw_circle(c.pos, NODE_RADIUS * (1.0 + 0.5 * t), glow)
		else:
			map_draw.draw_circle(c.pos, NODE_RADIUS * 1.15, Color(0.2, 0.2, 0.24, 0.12))

		map_draw.draw_circle(c.pos, NODE_RADIUS, fill_col)
		map_draw.draw_arc(c.pos, NODE_RADIUS, 0, TAU, 40, ring_col, 3.5, true)
		map_draw.draw_arc(c.pos, NODE_RADIUS - 5.0, 0, TAU, 40, Color(ring_col.r, ring_col.g, ring_col.b, 0.3), 1.0, true)

		if unlocked:
			var piece_color = "w"
			PieceTextures.draw(map_draw, c.piece, piece_color, c.pos, NODE_RADIUS * 1.3)
		else:
			_draw_lock(c.pos, Color(0.55, 0.55, 0.6))

		# a task node's puzzle quota can fill up before the player actually
		# reaches it on the path (theme practice happens elsewhere too) —
		# only show "done" once the node is actually unlocked, or a locked
		# node would show a checkmark under its own padlock
		if defeated and unlocked:
			var check_col = Color(0.4, 0.95, 0.5)
			var p1 = c.pos + Vector2(-NODE_RADIUS * 0.55, NODE_RADIUS * 0.75)
			var p2 = c.pos + Vector2(-NODE_RADIUS * 0.15, NODE_RADIUS * 1.05)
			var p3 = c.pos + Vector2(NODE_RADIUS * 0.6, NODE_RADIUS * 0.35)
			map_draw.draw_circle(c.pos + Vector2(0, NODE_RADIUS * 0.75), 14.0, Color(0.02, 0.1, 0.04, 0.9))
			map_draw.draw_polyline(PackedVector2Array([p1, p2, p3]), check_col, 3.0, true)

		var font = ThemeDB.fallback_font
		var name_pos = c.pos + Vector2(-70, NODE_RADIUS + 20)
		var label_col = Color(0.9, 0.95, 1.0) if unlocked else Color(0.5, 0.5, 0.55)
		var label_text = c.name

		# task/mix nodes: fold progress into the same label instead of a
		# floating line above the node — a separate line collided with the
		# name label of whichever node sits above it in the tight columns
		var node_kind = c.get("node", "")
		if (node_kind == "task" or node_kind == "mix") and unlocked and not defeated:
			var raw = Profile.mix_puzzles_solved if node_kind == "mix" else Profile.theme_progress(c.get("theme", ""))
			var prog = min(raw, int(c.get("required", 0)))
			label_text += "\n%d/%d" % [prog, int(c.get("required", 0))]

		map_draw.draw_multiline_string(font, name_pos, label_text, HORIZONTAL_ALIGNMENT_CENTER, 140, 11, 3, label_col)

		if c.get("is_boss", false) and unlocked and not defeated:
			var crown_pos = c.pos + Vector2(0, -NODE_RADIUS - 16)
			map_draw.draw_string(font, crown_pos, "★ БОСС ★", HORIZONTAL_ALIGNMENT_CENTER, 0, 12, Color(1, 0.8, 0.2))

func _draw_path_segment(a: Vector2, b: Vector2, col: Color, unlocked: bool) -> void:
	# trim the ends so the line starts/ends outside the node circles, then
	# draw a soft glow trail + solid dashes + small round waypoint dots
	var dir = (b - a).normalized()
	var pa = a + dir * (NODE_RADIUS + 6.0)
	var pb = b - dir * (NODE_RADIUS + 6.0)
	var seg_dist = pa.distance_to(pb)
	if seg_dist <= 0:
		return
	if unlocked:
		map_draw.draw_line(pa, pb, Color(col.r, col.g, col.b, 0.18), 9.0)
	var seg = 16.0
	var gap = 10.0
	var t = 0.0
	while t < seg_dist:
		var p1 = pa + dir * t
		var p2 = pa + dir * min(t + seg, seg_dist)
		map_draw.draw_line(p1, p2, col, 3.5)
		t += seg + gap
	var mid = pa.lerp(pb, 0.5)
	map_draw.draw_circle(mid, 4.5, col)

func _draw_lock(center: Vector2, col: Color) -> void:
	var shackle_top = center + Vector2(0, -6)
	map_draw.draw_arc(shackle_top, 8.5, PI, TAU, 16, col, 3.2, true)
	var body = Rect2(center + Vector2(-10, -2), Vector2(20, 15))
	map_draw.draw_rect(body, Color(0.14, 0.14, 0.17), true)
	map_draw.draw_rect(body, col, false, 2.0)
	map_draw.draw_circle(center + Vector2(0, 4.5), 2.5, col)
