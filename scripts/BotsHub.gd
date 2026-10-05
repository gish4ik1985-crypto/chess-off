extends Control

# «База игроков» — просмотр всех 120 постоянных соперников (BotData).
# Слева фильтр по лигам, в середине список, справа карточка выбранного.
# Рейтинги живые: они меняются от сыгранных турниров (Profile.bot_state),
# поэтому база показывает не выдуманные цифры, а текущее положение дел.

const BotData = preload("res://scripts/BotData.gd")

@onready var status_label: Label = $TopBar/HBox/StatusLabel
@onready var league_vbox: VBoxContainer = $Main/LeaguePanel/LeagueVBox
@onready var list_vbox: VBoxContainer = $Main/ListScroll/ListVBox
@onready var card_name: Label = $Main/CardScroll/CardPanel/VBox/NameLabel
@onready var card_league: Label = $Main/CardScroll/CardPanel/VBox/LeagueLabel
@onready var card_style: Label = $Main/CardScroll/CardPanel/VBox/StyleLabel
@onready var card_stats: Label = $Main/CardScroll/CardPanel/VBox/StatsLabel
@onready var challenge_label: Label = $Main/CardScroll/CardPanel/VBox/ChallengeLabel
@onready var format_row: HBoxContainer = $Main/CardScroll/CardPanel/VBox/FormatRow
@onready var color_row: HBoxContainer = $Main/CardScroll/CardPanel/VBox/ColorRow
@onready var play_button: Button = $Main/CardScroll/CardPanel/VBox/PlayButton

# -1 — показывать все лиги
var filter_league := -1
var selected_id := ""
var league_buttons: Array = []
var format_idx := 0
var chosen_color := "w"
var format_buttons: Array = []
var showing_games := false
var color_buttons: Array = []

func _ready() -> void:
	filter_league = Profile.player_league_idx() # открываемся на своей лиге
	_update_status()
	_build_league_filter()
	_build_challenge_controls()
	_build_list()
	_show_card("")
	play_button.pressed.connect(_on_play_pressed)

# Формат и цвет для товарищеской партии. Вызвать можно ЛЮБОГО игрока базы,
# из любой лиги, — ограничение по лигам действует только в турнирах.
func _build_challenge_controls() -> void:
	for i in range(BotData.MATCH_FORMATS.size()):
		var f: Dictionary = BotData.MATCH_FORMATS[i]
		var b := Button.new()
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 36)
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.text = str(f.name)
		b.tooltip_text = str(f.hint)
		b.button_pressed = i == format_idx
		b.pressed.connect(_on_format_chosen.bind(i))
		format_row.add_child(b)
		format_buttons.append(b)
	for c in [["w", "Белыми"], ["b", "Чёрными"]]:
		var b := Button.new()
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 36)
		b.text = c[1]
		b.button_pressed = c[0] == chosen_color
		b.pressed.connect(_on_color_chosen.bind(c[0]))
		color_row.add_child(b)
		color_buttons.append(b)

func _on_format_chosen(i: int) -> void:
	format_idx = i
	for k in range(format_buttons.size()):
		format_buttons[k].button_pressed = k == i

func _on_color_chosen(c: String) -> void:
	chosen_color = c
	color_buttons[0].button_pressed = c == "w"
	color_buttons[1].button_pressed = c == "b"

func _set_challenge_visible(on: bool) -> void:
	challenge_label.visible = on
	format_row.visible = on
	color_row.visible = on
	play_button.visible = on

func _on_play_pressed() -> void:
	if selected_id == "":
		return
	var rec := Profile.bot_record(selected_id)
	if rec.is_empty():
		return
	var f: Dictionary = BotData.MATCH_FORMATS[clampi(format_idx, 0, BotData.MATCH_FORMATS.size() - 1)]
	Global.friendly_game = {
		"id": str(rec.id),
		"name": str(rec.name),
		"level": int(rec.level),
		"rating": int(round(float(rec.rating))),
		"tc": int(f.tc),
		"inc": int(f.inc),
		"format": str(f.id),
		"format_name": str(f.name),
		"color": chosen_color,
	}
	# товарищеская партия — не турнир и не карта: чистим чужие контексты
	Global.tournament_game = {}
	Global.map_character_id = ""
	Global.coop_team = false
	Global.road_mode = ""
	Global.school_mode = ""
	Global.attention_level = 0
	Global.player_color = chosen_color
	get_tree().change_scene_to_file("res://scenes/Board.tscn")

func _update_status() -> void:
	var li := Profile.player_league_idx()
	var l: Dictionary = BotData.LEAGUES[li]
	status_label.text = "Ваш турнирный рейтинг: %d · ваша лига: %s %s · всего игроков в базе: %d" % [
		round(Profile.tournament_rating), l.icon, l.name, BotData.count()]

func _build_league_filter() -> void:
	for b in league_buttons:
		b.queue_free()
	league_buttons.clear()
	var counts := {}
	for rec in Profile.all_bot_records():
		counts[rec.league_idx] = int(counts.get(rec.league_idx, 0)) + 1
	var my := Profile.player_league_idx()
	var defs := [{"idx": -1, "text": "Все лиги (%d)" % BotData.count()}]
	for i in range(BotData.LEAGUES.size()):
		var l: Dictionary = BotData.LEAGUES[i]
		var mark := "  ← вы" if i == my else ""
		defs.append({"idx": i, "text": "%s %s (%d)%s" % [l.icon, l.name, int(counts.get(i, 0)), mark]})
	for d in defs:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 40)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# длинные названия лиг не должны распирать панель
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.text = d.text
		b.toggle_mode = true
		b.button_pressed = int(d.idx) == filter_league
		b.pressed.connect(_on_league_filter.bind(int(d.idx)))
		league_vbox.add_child(b)
		league_buttons.append(b)

func _on_league_filter(idx: int) -> void:
	filter_league = idx
	showing_games = false
	for i in range(league_buttons.size()):
		league_buttons[i].button_pressed = (i - 1) == idx
	_build_list()

func _build_list() -> void:
	for c in list_vbox.get_children():
		c.queue_free()
	if showing_games:
		_build_games_list()
		return
	var recs := Profile.all_bot_records()
	recs.sort_custom(func(a, b): return float(a.rating) > float(b.rating))
	var shown := 0
	for rec in recs:
		if filter_league >= 0 and int(rec.league_idx) != filter_league:
			continue
		shown += 1
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 44)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var marks := ""
		if bool(rec.weak):
			marks += " 🌿"
		if int(rec.tourneys_won) > 0:
			marks += " 🏆%d" % int(rec.tourneys_won)
		b.text = "%s%s — %d" % [rec.name, marks, int(round(float(rec.rating)))]
		b.tooltip_text = "%s · %s %s · рейтинг %d" % [
			rec.name, rec.league_def.icon, rec.league_def.name, int(round(float(rec.rating)))]
		b.pressed.connect(_show_card.bind(str(rec.id)))
		list_vbox.add_child(b)
	if shown == 0:
		var l := Label.new()
		l.text = "В этой лиге пока никого нет."
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list_vbox.add_child(l)

func _show_card(id: String) -> void:
	selected_id = id
	if id == "":
		card_name.text = "Выберите игрока"
		card_league.text = ""
		card_style.text = "Слева — лиги, в середине — состав. 🌿 отмечены игроки, которые растут медленно: они всегда останутся в своей лиге, чтобы вам было с кем начинать."
		card_stats.text = ""
		_set_challenge_visible(false)
		return
	var rec := Profile.bot_record(id)
	if rec.is_empty():
		return
	_set_challenge_visible(true)
	var l: Dictionary = rec.league_def
	card_name.text = str(rec.name)
	var moved := ""
	if bool(rec.promoted):
		moved = "  ▲ поднялся из «%s»" % BotData.LEAGUES[int(rec.home_league_idx)].name
	elif bool(rec.relegated):
		moved = "  ▼ опустился из «%s»" % BotData.LEAGUES[int(rec.home_league_idx)].name
	card_league.text = "%s %s · рейтинг %d%s" % [l.icon, l.name, int(round(float(rec.rating))), moved]
	var style: Dictionary = rec.style
	card_style.text = "Манера игры: %s — %s.\n%s" % [style.name, style.hint, l.desc]

	var games := int(rec.wins) + int(rec.draws) + int(rec.losses)
	var lines := []
	lines.append("Сила в игре: уровень ИИ %d." % int(rec.level))
	if games == 0:
		lines.append("\nПартий пока не сыграно — этот игрок ещё ждёт своего турнира.")
	else:
		lines.append("\nВсего партий: %d  ·  +%d =%d −%d" % [games, int(rec.wins), int(rec.draws), int(rec.losses)])
		lines.append("Лучший рейтинг: %d" % int(round(float(rec.peak))))
	if int(rec.tourneys_won) > 0:
		lines.append("Выиграно турниров: %d 🏆" % int(rec.tourneys_won))
	var archived := Profile.games_of_bot(id).size()
	lines.append("
В архиве партий для разбора: %d" % archived)
	var pg := int(rec.p_wins) + int(rec.p_draws) + int(rec.p_losses)
	if pg > 0:
		# счёт личных встреч показываем С ТОЧКИ ЗРЕНИЯ ИГРОКА, а не бота
		lines.append("\nВаши личные встречи: %d — ваш счёт +%d =%d −%d" % [
			pg, int(rec.p_losses), int(rec.p_draws), int(rec.p_wins)])
	else:
		lines.append("\nВы с ним ещё не встречались.")
	if bool(rec.weak):
		lines.append("\n🌿 Растёт медленно и никогда не поднимется выше середины своей лиги — такие игроки есть в каждой лиге, чтобы вам всегда было с кем побороться на равных.")
	var my := Profile.player_league_idx()
	if int(rec.league_idx) > my:
		lines.append("\n🔒 Играет в лиге выше вашей — вы встретитесь, когда вы подниметесь до «%s»." % l.name)
	elif int(rec.league_idx) < my:
		lines.append("\nИграет в лиге ниже вашей — в ваших турнирах больше не появится.")
	else:
		lines.append("\n✔ В вашей лиге — может попасться соперником в ближайшем турнире.")
	card_stats.text = "\n".join(lines)

# Лента изменений. Без неё жизнь мира невидима: боты растут и меняют лиги
# молча, и игрок никогда об этом не узнает.
func _build_games_list() -> void:
	var rec := Profile.bot_record(selected_id)
	var back := Button.new()
	back.custom_minimum_size = Vector2(0, 40)
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.text = "◂ Ко всем игрокам"
	back.pressed.connect(func(): showing_games = false; _build_list())
	list_vbox.add_child(back)

	var title := Label.new()
	title.text = "Партии: %s" % str(rec.name)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list_vbox.add_child(title)

	var games := Profile.games_of_bot(selected_id)
	for i in range(games.size()):
		var g: Dictionary = games[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 52)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var res := float(g.get("result", 0.5))
		var res_txt = "1:0" if res >= 1.0 else ("0:1" if res <= 0.0 else "½:½")
		b.text = "%s — %s  %s\n%s · %d ходов" % [
			str(g.get("w_name", "")), str(g.get("b_name", "")), res_txt,
			str(g.get("event", "")), int(g.get("moves", []).size() / 2)]
		b.tooltip_text = "%s · %s" % [str(g.get("event", "")), str(g.get("day", ""))]
		b.pressed.connect(_open_game.bind(i))
		list_vbox.add_child(b)

	var play := Button.new()
	play.custom_minimum_size = Vector2(0, 44)
	play.text = "▶ Сыграть новую партию (запишется сюда)"
	play.clip_text = true
	play.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	play.pressed.connect(_play_new_game)
	list_vbox.add_child(play)

	if games.is_empty():
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text = "Партий пока нет.\n\nВ архив попадают только по-настоящему сыгранные партии: ваши личные встречи с этим игроком и партии, которые он сыграет по кнопке выше."
		list_vbox.add_child(l)

# Архив партий выбранного бота — то, ради чего к сопернику и готовятся.
# Список партий показывается вместо списка игроков, чтобы не городить
# четвёртую колонку на и без того плотном экране.
func _on_watch_pressed() -> void:
	if selected_id == "":
		return
	showing_games = true
	_build_list()

func _open_game(idx: int) -> void:
	Global.bot_match = {"mode": "replay", "bot": selected_id, "index": idx}
	get_tree().change_scene_to_file("res://scenes/BotMatch.tscn")

# Партий в архиве может не быть: симуляция тура ходов не даёт, а ваши личные
# встречи ещё не сыграны. Тогда предлагаем сыграть настоящую партию сейчас —
# она и попадёт в архив.
func _play_new_game() -> void:
	if selected_id == "":
		return
	var rec := Profile.bot_record(selected_id)
	var pool := []
	for other in Profile.all_bot_records():
		if str(other.id) != selected_id and int(other.league_idx) == int(rec.league_idx):
			pool.append(other)
	if pool.is_empty():
		return
	pool.shuffle()
	var opp: Dictionary = pool[0]
	var white_first = randf() < 0.5
	Global.bot_match = {
		"mode": "live",
		"white": selected_id if white_first else str(opp.id),
		"black": str(opp.id) if white_first else selected_id,
	}
	get_tree().change_scene_to_file("res://scenes/BotMatch.tscn")

func _on_news_pressed() -> void:
	selected_id = ""
	_set_challenge_visible(false)
	card_name.text = "📰 Что изменилось в базе"
	card_league.text = ""
	card_style.text = "Пока вы играете свой турнир, остальные игроки играют свои — в каждой лиге. Между вашими партиями мир не меняется."
	var ev: Array = Profile.world_events
	if ev.is_empty():
		card_stats.text = "Пока ничего не происходило.\n\nДоиграйте турнир до конца — и здесь появится сводка: кто вырос, кто просел и кто сменил лигу."
		return
	var lines := []
	var day := ""
	for e in ev:
		var d := str(e.get("day", ""))
		if d != day:
			day = d
			lines.append("\n— %s —" % day)
		if str(e.get("kind", "")) == "league":
			var arrow = "▲ поднялся в" if bool(e.get("up", false)) else "▼ опустился в"
			lines.append("%s %s %s «%s» (рейтинг %d)" % [
				str(e.get("icon", "")), str(e.get("name", "")), arrow,
				str(e.get("league", "")), int(e.get("rating", 0))])
		else:
			var delta := int(e.get("delta", 0))
			lines.append("   %s %s%d → %d" % [
				str(e.get("name", "")), "+" if delta >= 0 else "", delta, int(e.get("rating", 0))])
	card_stats.text = "\n".join(lines)

func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")
