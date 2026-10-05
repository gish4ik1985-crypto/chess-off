extends Control

# Main menu, restructured to always fit one screen:
#   главный экран — только разделы (Карта / Турниры / Играть / Обучение /
#   Настройки / Выход);
#   "Турниры и соперники" — турниры, подготовка к ним и база игроков
#   (всё три раньше висели по отдельности на главном экране);
#   "Играть" — быстрая игра, папа и сын, товарищеская партия с игроком базы;
#   "Обучение и задачи" — подменю (Дорога домой, задачи, дневник).

@onready var main_panel: PanelContainer = $ContentCenter/MainPanel
@onready var play_panel: PanelContainer = $ContentCenter/PlayPanel
@onready var train_panel: PanelContainer = $ContentCenter/TrainPanel
@onready var tourney_panel: PanelContainer = $ContentCenter/TourneyPanel
@onready var difficulty_slider: HSlider = $ContentCenter/PlayPanel/VBox/DifficultyRow/DifficultySlider
@onready var difficulty_value_label: Label = $ContentCenter/PlayPanel/VBox/DifficultyRow/DifficultyValueLabel
@onready var difficulty_name_label: Label = $ContentCenter/PlayPanel/VBox/DifficultyNameLabel
@onready var white_button: Button = $ContentCenter/PlayPanel/VBox/ColorRow/WhiteButton
@onready var black_button: Button = $ContentCenter/PlayPanel/VBox/ColorRow/BlackButton
@onready var bg: Node2D = $DecorBoard
@onready var rating_label: Label = $ProfileBar/HBox/RatingLabel
@onready var achievements_label: Label = $ProfileBar/HBox/AchievementsSummary
@onready var user_label: Label = $ProfileBar/HBox/UserLabel

var chosen_color := "w"

# Подсказки при наведении: что делает кнопка и что значат термины.
const TOOLTIPS := {
	"ProfileBar/HBox/ProfileButton": "Профиль: рейтинг, ступень и Индекс мастерства — оценка 8 навыков (от 0 до 100) с диапазоном неопределённости.",
	"ProfileBar/HBox/TrophyButton": "Награды: кубки, медали и достижения.",
	"ProfileBar/HBox/JournalButton": "Дневник: качество ходов, партии и разбор ошибок.",
	"ProfileBar/HBox/SwitchUserButton": "Выбрать другого игрока. Прогресс каждого хранится отдельно.",
	"ContentCenter/MainPanel/VBox/MapButton": "Путь по стране: бои с персонажами и задачи. Сложность подстраивается под вас («живая сложность»).",
	"ContentCenter/MainPanel/VBox/TourneyMenuButton": "Турниры со своим рейтингом, подготовка к ним и база игроков.",
	"ContentCenter/MainPanel/VBox/PlayMenuButton": "Быстрая партия против компьютера, командная игра и товарищеские партии.",
	"ContentCenter/MainPanel/VBox/TrainMenuButton": "Задачи, Дорога домой, Внимательность, Школа и разбор партий великих.",
	"ContentCenter/PlayPanel/VBox/PlayButton": "Партия с выбранной сложностью. Подсказки и откаты не идут в ступень и рейтинг.",
	"ContentCenter/TrainPanel/VBox/RoadButton": "Личный путь: остановки появляются там, где вы чаще ошибаетесь.",
	"ContentCenter/TrainPanel/VBox/AttentionButton": "Тренажёр: на доске подсвечены угрозы, подсказки постепенно исчезают.",
	"ContentCenter/TrainPanel/VBox/SchoolButton": "Упражнения «Что изменилось?» и «Школа терпения»: смотреть и не спешить.",
}

func _ready() -> void:
	for path in TOOLTIPS:
		var n = get_node_or_null(path)
		if n != null:
			n.tooltip_text = TOOLTIPS[path]
	$ContentCenter/MainPanel/VBox/QuitButton.visible = not OS.has_feature("web")
	if not Profile.has_user():
		get_tree().change_scene_to_file.call_deferred("res://scenes/Login.tscn")
		return
	Global.tournament_game = {} # safety: no stale tournament context after returning to menu
	Global.friendly_game = {} # safety: товарищеская партия начинается только из базы игроков
	Global.attention_level = 0 # safety: attention mode only starts from its hub
	Global.school_mode = "" # safety: school modes only start from their hub
	Global.road_mode = "" # safety: road stages only start from RoadHome.tscn
	Global.map_assist = false # safety: assist choice only meant for the map battle it was picked for
	difficulty_slider.max_value = Global.MAX_DIFFICULTY
	difficulty_slider.value = Global.difficulty
	_update_difficulty_label()
	_update_color_buttons()
	_update_profile_bar()
	difficulty_slider.value_changed.connect(_on_difficulty_changed)
	white_button.pressed.connect(func(): chosen_color = "w"; _update_color_buttons())
	black_button.pressed.connect(func(): chosen_color = "b"; _update_color_buttons())
	bg.draw.connect(_on_bg_draw)

func _show_panel(panel: PanelContainer) -> void:
	main_panel.visible = panel == main_panel
	play_panel.visible = panel == play_panel
	train_panel.visible = panel == train_panel
	tourney_panel.visible = panel == tourney_panel

func _on_play_menu_pressed() -> void:
	_show_panel(play_panel)

func _on_train_menu_pressed() -> void:
	_show_panel(train_panel)

func _on_tourney_menu_pressed() -> void:
	_show_panel(tourney_panel)

func _on_back_pressed() -> void:
	_show_panel(main_panel)

func _update_profile_bar() -> void:
	user_label.text = Profile.display_name
	rating_label.text = "Турнирный рейтинг: %d (%s) · Ступень %d" % [round(Profile.tournament_rating), Profile.rating_title(), Profile.clean_step()]
	rating_label.tooltip_text = "Турнирный рейтинг растёт от турниров. Ступень — сильнейший уровень компьютера, побеждённый без помощи."
	rating_label.mouse_filter = Control.MOUSE_FILTER_STOP
	achievements_label.text = "Достижения: %d/%d" % [Profile.achievement_count(), Profile.total_achievement_count()]
	var streak = Profile.current_streak()
	if streak > 0 and Profile.streak_last_day == Time.get_date_string_from_system():
		achievements_label.text += "   🔥 Серия: %d дн." % streak
	elif streak > 0:
		achievements_label.text += "   🔥 Серия: %d дн. — решите задачу сегодня, чтобы не прервать!" % streak
	else:
		achievements_label.text += "   Решите задачу — начнётся серия дней!"

func _on_profile_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Achievements.tscn")

func _on_journal_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Diary.tscn")

func _on_switch_user_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Login.tscn")

func _on_difficulty_changed(v: float) -> void:
	Global.difficulty = int(v)
	_update_difficulty_label()

func _update_difficulty_label() -> void:
	difficulty_value_label.text = str(int(difficulty_slider.value))
	difficulty_name_label.text = Global.difficulty_label(int(difficulty_slider.value))

func _update_color_buttons() -> void:
	white_button.button_pressed = chosen_color == "w"
	black_button.button_pressed = chosen_color == "b"

func _on_play_pressed() -> void:
	Global.difficulty = int(difficulty_slider.value)
	Global.player_color = chosen_color
	Global.map_character_id = ""
	Global.coop_team = false
	get_tree().change_scene_to_file("res://scenes/Board.tscn")

# quick-play team match: opponent strength follows the difficulty slider
func _on_team_pressed() -> void:
	Global.difficulty = int(difficulty_slider.value)
	Global.player_color = "w"
	Global.map_character_id = ""
	Global.coop_team = true
	get_tree().change_scene_to_file("res://scenes/Board.tscn")

func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Settings.tscn")

func _on_map_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Map.tscn")

func _on_tournaments_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Tournaments.tscn")

func _on_tournament_prep_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/TournamentPrep.tscn")

func _on_bots_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/BotsHub.tscn")

func _on_historic_games_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/HistoricGames.tscn")

func _on_school_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/School.tscn")

func _on_trophy_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/TrophyRoom.tscn")

func _on_progress_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Diary.tscn")

func _on_road_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/RoadHome.tscn")

func _on_puzzles_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/PuzzleHub.tscn")

func _on_attention_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/AttentionHub.tscn")

func _on_quit_pressed() -> void:
	if OS.has_feature("web"):
		return # вкладку браузера закрывает сам игрок
	get_tree().quit()

func _on_bg_draw() -> void:
	# decorative faded chessboard pattern behind the menu
	var sq = 64.0
	# на весь экран 1280×800 (раньше рисовалось только в левом верхнем углу)
	for r in range(13):
		for f in range(20):
			if (r + f) % 2 == 0:
				continue
			var pos = Vector2(f * sq, r * sq)
			bg.draw_rect(Rect2(pos, Vector2(sq, sq)), Color(1, 1, 1, 0.035), true)
