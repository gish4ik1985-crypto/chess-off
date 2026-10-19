class_name ChatScreen
extends Control

# Чат школы: общий, по группе и личные сообщения. Сообщения лежат в облаке (chat/{комната}/msgs),
# экран раз в 4 секунды проверяет новые. Учитель может удалять сообщения (режим модератора).

const POLL := 4.0
const MAX_LEN := 300

var _room := "school"
var _room_title := "Общий чат школы"
var _list: VBoxContainer
var _msgs_scroll: ScrollContainer
var _input: LineEdit
var _status: Label
var _title: Label
var _rooms_box: VBoxContainer
var _players: Array = []
var _timer := 0.0
var _busy := false
var _last_sent := 0
var _mod_mode := false
var _shown_ids: Array = []
var _newest := 0

static func school_room() -> String:
	return "school"

static func group_room(group: String) -> String:
	return "grp_" + group.strip_edges().to_lower().replace(" ", "_").replace("/", "")

static func dm_room(a: String, b: String) -> String:
	return "dm_" + (a + "_" + b if a < b else b + "_" + a)

func _ready() -> void:
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.02, 0.02, 0.05)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Global.add_floating_back(self, func(): Global.go_back())
	var head := Label.new()
	head.text = "ЧАТ ШКОЛЫ"
	head.add_theme_font_size_override("font_size", 26)
	head.add_theme_color_override("font_color", Color(0.96, 0.76, 0.3))
	head.position = Vector2(24, 16)
	add_child(head)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_top = 76.0
	row.offset_left = 24.0
	row.offset_right = -24.0
	row.offset_bottom = -16.0
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	# слева — комнаты
	var left := ScrollContainer.new()
	left.custom_minimum_size = Vector2(250, 0)
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(left)
	_rooms_box = VBoxContainer.new()
	_rooms_box.custom_minimum_size = Vector2(240, 0)
	_rooms_box.add_theme_constant_override("separation", 6)
	left.add_child(_rooms_box)
	# справа — переписка
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	right.add_child(_title)
	_msgs_scroll = ScrollContainer.new()
	_msgs_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_msgs_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(_msgs_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_msgs_scroll.add_child(_list)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	right.add_child(_status)
	var send_row := HBoxContainer.new()
	send_row.add_theme_constant_override("separation", 8)
	right.add_child(send_row)
	_input = LineEdit.new()
	_input.placeholder_text = "Написать сообщение…"
	_input.max_length = MAX_LEN
	_input.custom_minimum_size = Vector2(0, 48)
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(func(_t): _send())
	send_row.add_child(_input)
	var send := Button.new()
	send.text = "Отправить"
	send.custom_minimum_size = Vector2(140, 48)
	send.pressed.connect(_send)
	send_row.add_child(send)
	if not (Cloud.enabled and Cloud.signed_in):
		_status.text = "Чат работает через облако: войдите онлайн."
		_input.editable = false
		_title.text = "Чат школы"
		return
	_build_rooms()
	_open_room("school", "Общий чат школы")
	_load_players()

func _build_rooms() -> void:
	for ch in _rooms_box.get_children():
		ch.queue_free()
	_room_button("💬 Общий чат школы", "school", "Общий чат школы")
	if Profile.club_group.strip_edges() != "":
		_room_button("👥 Моя группа: " + Profile.club_group.strip_edges(), group_room(Profile.club_group), "Группа: " + Profile.club_group.strip_edges())
	if Roles.can(Profile.role, "open_admin"):
		var mod := CheckButton.new()
		mod.text = "Режим модератора"
		mod.toggled.connect(func(v):
			_mod_mode = v
			_shown_ids = []
			_poll())
		_rooms_box.add_child(mod)
	var l := Label.new()
	l.text = "ЛИЧНЫЕ СООБЩЕНИЯ"
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.96, 0.76, 0.3))
	_rooms_box.add_child(l)

func _room_button(text: String, room: String, title: String) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func(): _open_room(room, title))
	_rooms_box.add_child(b)

func _load_players() -> void:
	var r: Dictionary = await Cloud.query_top("players", "rating", 200)
	if not is_inside_tree() or not r.ok:
		return
	_players = r.docs
	for p in _players:
		var uid := String(p.get("_id", ""))
		if uid == Cloud.uid:
			continue
		var nm := String(p.get("name", ""))
		if nm == "":
			nm = String(p.get("nick", "?"))
		_room_button("✉ " + nm, dm_room(Cloud.uid, uid), "Личный чат: " + nm)

func _open_room(room: String, title: String) -> void:
	_room = room
	_room_title = title
	_title.text = title
	_shown_ids = []
	_newest = 0
	for ch in _list.get_children():
		ch.queue_free()
	_poll()

func _process(delta: float) -> void:
	if not (Cloud.enabled and Cloud.signed_in):
		return
	_timer += delta
	if _timer >= POLL:
		_timer = 0.0
		_poll()

func _poll() -> void:
	if _busy:
		return
	_busy = true
	var room := _room
	var r: Dictionary = await Cloud.query_sub("chat/" + room, "msgs", "at", 80)
	_busy = false
	if not is_inside_tree() or room != _room:
		return
	if not r.ok:
		_status.text = String(r.error)
		return
	_status.text = ""
	var docs: Array = r.docs
	docs.reverse() # от старых к новым
	var ids := []
	for d in docs:
		ids.append(String(d.get("_id", "")))
	if ids == _shown_ids:
		return
	_shown_ids = ids
	for ch in _list.get_children():
		ch.queue_free()
	for d in docs:
		_list.add_child(_bubble(d))
		_newest = maxi(_newest, int(d.get("at", 0)))
	Profile.chat_seen[room] = _newest
	Profile.request_save()
	await get_tree().process_frame
	_msgs_scroll.scroll_vertical = int(_msgs_scroll.get_v_scroll_bar().max_value)

func _bubble(d: Dictionary) -> Control:
	var mine := String(d.get("uid", "")) == Cloud.uid
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var when := Time.get_datetime_dict_from_unix_time(int(d.get("at", 0)) + 3 * 3600)
	var head := Label.new()
	head.text = "%s  ·  %02d:%02d" % [String(d.get("name", "?")), when.hour, when.minute]
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", Color(1, 0.65, 0.95) if mine else Color(0.1, 0.95, 1))
	col.add_child(head)
	var t := Label.new()
	t.text = String(d.get("text", ""))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.add_theme_font_size_override("font_size", 15)
	col.add_child(t)
	if _mod_mode or mine:
		var del := Button.new()
		del.text = "✖"
		del.tooltip_text = "Удалить сообщение"
		del.custom_minimum_size = Vector2(44, 40)
		del.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		del.pressed.connect(func():
			await Cloud.del_doc("chat/%s/msgs/%s" % [_room, String(d.get("_id", ""))])
			_shown_ids = []
			_poll())
		row.add_child(del)
	return panel

func _send() -> void:
	var text := _input.text.strip_edges()
	if text == "" or not (Cloud.enabled and Cloud.signed_in):
		return
	var now := int(Time.get_unix_time_from_system())
	if Time.get_ticks_msec() - _last_sent < 1200:
		return # не чаще раза в 1,2 секунды
	_last_sent = Time.get_ticks_msec()
	_input.text = ""
	var id := "%d%04d" % [now, randi() % 10000]
	var r: Dictionary = await Cloud.set_doc("chat/%s/msgs/%s" % [_room, id], {
		"uid": Cloud.uid, "name": Profile.shown_name(), "text": text.left(MAX_LEN), "at": now})
	if not r.ok:
		_status.text = "Не отправилось: %s" % String(r.error)
		_input.text = text
		return
	_shown_ids = []
	_poll()

# ---- для главного экрана: есть ли новые сообщения в общем чате и в группе ----
static func has_unread() -> bool:
	return unread_rooms.size() > 0

static var unread_rooms: Array = []

static func check_unread() -> void:
	unread_rooms = []
	if not (Cloud.enabled and Cloud.signed_in):
		return
	var rooms := ["school"]
	if Profile.club_group.strip_edges() != "":
		rooms.append(group_room(Profile.club_group))
	for room in rooms:
		var r: Dictionary = await Cloud.query_sub("chat/" + room, "msgs", "at", 1)
		if r.ok and not r.docs.is_empty():
			var d: Dictionary = r.docs[0]
			if int(d.get("at", 0)) > int(Profile.chat_seen.get(room, 0)) and String(d.get("uid", "")) != Cloud.uid:
				unread_rooms.append(room)
