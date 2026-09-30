extends Control

@onready var rating_big_label: Label = $Scroll/VBox/Header/HeaderVBox/RatingBig
@onready var rating_title_label: Label = $Scroll/VBox/Header/HeaderVBox/RatingTitle
@onready var rd_label: Label = $Scroll/VBox/Header/HeaderVBox/RdLabel
@onready var rating_bar: ProgressBar = $Scroll/VBox/Header/HeaderVBox/RatingBar
@onready var stats_grid: GridContainer = $Scroll/VBox/StatsPanel/StatsGrid
@onready var achievements_list: GridContainer = $Scroll/VBox/AchievementsPanel/AchievementsList
@onready var achievements_header: Label = $Scroll/VBox/AchievementsHeaderLabel

const RATING_MIN := 400.0
const RATING_MAX := 2800.0

func _ready() -> void:
	_populate_header()
	_populate_stats()
	_populate_achievements()

func _populate_header() -> void:
	rating_big_label.text = str(int(round(Profile.tournament_rating)))
	rating_title_label.text = "%s · ступень %d" % [Profile.rating_title(), Profile.clean_step()]
	rd_label.text = "± %d (чем меньше, тем стабильнее рейтинг)" % int(round(Profile.rd * 1.96))
	rating_bar.min_value = RATING_MIN
	rating_bar.max_value = RATING_MAX
	rating_bar.value = clampf(Profile.tournament_rating, RATING_MIN, RATING_MAX)

func _add_stat(label_text: String, value_text: String) -> void:
	var l1 = Label.new()
	l1.text = label_text
	l1.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	stats_grid.add_child(l1)
	var l2 = Label.new()
	l2.text = value_text
	l2.add_theme_color_override("font_color", Color(0.1, 0.95, 1))
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stats_grid.add_child(l2)

func _populate_stats() -> void:
	var win_rate = 0.0
	if Profile.games_played > 0:
		win_rate = 100.0 * float(Profile.wins) / float(Profile.games_played)
	_add_stat("Партий сыграно:", str(Profile.games_played))
	_add_stat("Побед:", str(Profile.wins))
	_add_stat("Поражений:", str(Profile.losses))
	_add_stat("Ничьих:", str(Profile.draws))
	_add_stat("Процент побед:", "%d%%" % int(round(win_rate)))
	_add_stat("Лучшая серия побед:", str(Profile.best_win_streak))
	_add_stat("Сильнейший обыгранный ИИ:", Global.difficulty_label(Profile.best_win_level) if Profile.best_win_level > 0 else "—")
	_add_stat("Задач на мат решено:", "%d / 50" % Profile.solved_puzzles.size())

func _populate_achievements() -> void:
	achievements_header.text = "Достижения (%d / %d)" % [Profile.achievement_count(), Profile.total_achievement_count()]
	# unlocked ones first — that's the interesting part, no need to scroll past locks to see them
	var sorted: Array = Profile.ACHIEVEMENTS.duplicate()
	sorted.sort_custom(func(a, b):
		var ua = Profile.unlocked_achievements.has(a.id)
		var ub = Profile.unlocked_achievements.has(b.id)
		return ua and not ub)
	for a in sorted:
		var unlocked = Profile.unlocked_achievements.has(a.id)
		var row = PanelContainer.new()
		row.custom_minimum_size = Vector2(300, 0)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb = StyleBoxFlat.new()
		if unlocked:
			sb.bg_color = Color(0.05, 0.12, 0.14, 0.9)
			sb.border_color = Color(0.1, 0.95, 1, 0.7)
		else:
			sb.bg_color = Color(0.05, 0.05, 0.06, 0.6)
			sb.border_color = Color(0.3, 0.3, 0.35, 0.3)
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
		sb.corner_radius_top_left = 8
		sb.corner_radius_top_right = 8
		sb.corner_radius_bottom_left = 8
		sb.corner_radius_bottom_right = 8
		sb.content_margin_left = 14
		sb.content_margin_top = 8
		sb.content_margin_right = 14
		sb.content_margin_bottom = 8
		if unlocked:
			sb.shadow_color = Color(0.05, 0.85, 1, 0.25)
			sb.shadow_size = 6
		row.add_theme_stylebox_override("panel", sb)

		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)
		row.add_child(hbox)

		var icon = Label.new()
		icon.text = "★" if unlocked else "🔒"
		icon.add_theme_font_size_override("font_size", 18)
		icon.custom_minimum_size = Vector2(28, 0)
		icon.add_theme_color_override("font_color", Color(1, 0.8, 0.2) if unlocked else Color(0.4, 0.4, 0.45))
		hbox.add_child(icon)

		var text_vbox = VBoxContainer.new()
		text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(text_vbox)

		var name_label = Label.new()
		name_label.text = a.name
		name_label.add_theme_color_override("font_color", Color(0.1, 0.95, 1) if unlocked else Color(0.5, 0.5, 0.55))
		text_vbox.add_child(name_label)

		var desc_label = Label.new()
		desc_label.text = a.desc
		desc_label.add_theme_font_size_override("font_size", 12)
		desc_label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7) if unlocked else Color(0.4, 0.4, 0.45))
		text_vbox.add_child(desc_label)

		achievements_list.add_child(row)

func _on_trophy_room_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/TrophyRoom.tscn")

func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")
