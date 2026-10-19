extends Control

@onready var handicap_check: CheckButton = $ContentCenter/InnerCenter/CenterPanel/VBox/HandicapRow/HandicapCheck
@onready var adaptive_check: CheckButton = $ContentCenter/InnerCenter/CenterPanel/VBox/AdaptiveRow/AdaptiveCheck
@onready var fifty_move_check: CheckButton = $ContentCenter/InnerCenter/CenterPanel/VBox/FiftyMoveRow/FiftyMoveCheck
@onready var export_button: Button = $ContentCenter/InnerCenter/CenterPanel/VBox/ExportButton
@onready var import_button: Button = $ContentCenter/InnerCenter/CenterPanel/VBox/ImportButton
@onready var backup_status: Label = $ContentCenter/InnerCenter/CenterPanel/VBox/BackupStatus
@onready var music_slider: HSlider = $ContentCenter/InnerCenter/CenterPanel/VBox/MusicRow/MusicSlider
@onready var sfx_slider: HSlider = $ContentCenter/InnerCenter/CenterPanel/VBox/SfxRow/SfxSlider
@onready var move_sound_option: OptionButton = $ContentCenter/InnerCenter/CenterPanel/VBox/MoveSoundRow/MoveSoundOption
@onready var fullscreen_check: CheckButton = $ContentCenter/InnerCenter/CenterPanel/VBox/FullscreenRow/FullscreenCheck
@onready var resolution_option: OptionButton = $ContentCenter/InnerCenter/CenterPanel/VBox/ResolutionRow/ResolutionOption

var _preview_fx: SoundFX
const RESOLUTION_NAMES := ["1024 × 640", "1280 × 800 (по умолчанию)", "1366 × 768", "1600 × 900", "1920 × 1080"]

func _ready() -> void:
	_preview_fx = SoundFX.new()
	add_child(_preview_fx)
	for name in RESOLUTION_NAMES:
		resolution_option.add_item(name)
	resolution_option.selected = clampi(Global.window_resolution_index, 0, Global.WINDOW_RESOLUTIONS.size() - 1)
	resolution_option.disabled = Global.fullscreen_enabled
	resolution_option.item_selected.connect(_on_resolution_selected)
	fullscreen_check.button_pressed = Global.fullscreen_enabled
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	for st in SoundFX.MOVE_STYLES:
		move_sound_option.add_item(st.name)
	move_sound_option.selected = clampi(Global.move_sound_style, 0, SoundFX.MOVE_STYLES.size() - 1)
	move_sound_option.item_selected.connect(_on_move_sound_selected)
	handicap_check.button_pressed = Global.handicap_enabled
	handicap_check.toggled.connect(_on_handicap_toggled)
	_build_theme_row()
	_build_real_rating_row()
	adaptive_check.button_pressed = Global.adaptive_difficulty
	adaptive_check.toggled.connect(func(pressed: bool):
		Global.adaptive_difficulty = pressed
		Global.save_settings())
	fifty_move_check.button_pressed = Global.fifty_move_rule_enabled
	fifty_move_check.toggled.connect(func(pressed: bool):
		Global.fifty_move_rule_enabled = pressed
		Global.save_settings())
	export_button.pressed.connect(_on_export_pressed)
	import_button.pressed.connect(_on_import_pressed)
	if OS.has_feature("web"):
		# в браузере нет выбора размера окна и внешних файлов — только полный экран
		# и обмен профилем через скачивание/загрузку файла
		resolution_option.get_parent().visible = false
	var report_button: Button = $ContentCenter/InnerCenter/CenterPanel/VBox/ReportButton
	report_button.visible = not OS.has_feature("web")
	report_button.pressed.connect(func():
		Profile.write_game_report()
		OS.shell_open(Profile.report_path()))
	music_slider.value = Global.music_volume
	sfx_slider.value = Global.sfx_volume
	music_slider.value_changed.connect(func(v): Global.music_volume = v; Global.save_settings())
	sfx_slider.value_changed.connect(func(v): Global.sfx_volume = v; Global.save_settings())

func _make_file_dialog(save: bool) -> FileDialog:
	var dlg = FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE if save else FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.use_native_dialog = true
	dlg.filters = ["*.cfg ; Профиль шахмат"]
	add_child(dlg)
	return dlg

func _on_export_pressed() -> void:
	if not Profile.has_user():
		return
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(Profile.export_profile_bytes(), "chessoff_%s.cfg" % Profile.current_user, "text/plain")
		backup_status.text = "Профиль скачан — перенесите файл на другое устройство и нажмите «Загрузить»"
		return
	var dlg = _make_file_dialog(true)
	dlg.current_file = "chessoff_%s.cfg" % Profile.current_user
	dlg.file_selected.connect(func(path: String):
		if Profile.export_profile(path):
			backup_status.text = "Профиль сохранён: " + path
		else:
			backup_status.text = "Не удалось сохранить файл"
		dlg.queue_free())
	dlg.popup_centered_ratio(0.7)

var _web_cb: JavaScriptObject

func _on_web_file_text(args: Array) -> void:
	var f := FileAccess.open("user://_import_tmp.cfg", FileAccess.WRITE)
	if f == null:
		backup_status.text = "Не удалось прочитать файл"
		return
	f.store_string(str(args[0]))
	f.close()
	var nm = Profile.import_profile("user://_import_tmp.cfg")
	DirAccess.remove_absolute("user://_import_tmp.cfg")
	if nm != "":
		backup_status.text = "Профиль «%s» загружен и выбран" % nm
	else:
		backup_status.text = "Это не файл профиля — импорт не удался"

func _on_import_pressed() -> void:
	if OS.has_feature("web"):
		_web_cb = JavaScriptBridge.create_callback(_on_web_file_text)
		JavaScriptBridge.get_interface("window").godotProfileCb = _web_cb
		JavaScriptBridge.eval("var i=document.createElement('input');i.type='file';i.accept='.cfg,text/plain';i.onchange=function(){var f=i.files[0];if(!f)return;f.text().then(function(t){window.godotProfileCb(t);});};i.click();")
		return
	var dlg = _make_file_dialog(false)
	dlg.file_selected.connect(func(path: String):
		var nm = Profile.import_profile(path)
		if nm != "":
			backup_status.text = "Профиль «%s» загружен и выбран" % nm
		else:
			backup_status.text = "Это не файл профиля — импорт не удался"
		dlg.queue_free())
	dlg.popup_centered_ratio(0.7)

func _on_move_sound_selected(idx: int) -> void:
	Global.move_sound_style = idx
	Global.save_settings()
	_preview_fx.play_move()

func _on_fullscreen_toggled(pressed: bool) -> void:
	Global.fullscreen_enabled = pressed
	resolution_option.disabled = pressed
	Global.save_settings()
	Global.apply_display_settings()

func _on_resolution_selected(idx: int) -> void:
	Global.window_resolution_index = idx
	Global.save_settings()
	Global.apply_display_settings()

func _on_handicap_toggled(pressed: bool) -> void:
	Global.handicap_enabled = pressed
	Global.save_settings()

func _on_back_pressed() -> void:
	Global.go_back()

# Ввод настоящего рейтинга (необязательно): точка отсчёта для турнирного рейтинга
# Кнопка экрана «Оформление» (карточки тем с превью) — первой строкой настроек.
func _build_theme_row() -> void:
	var vbox: Node = handicap_check.get_parent().get_parent()
	var btn := Button.new()
	btn.text = "🎨  Оформление: %s  →" % Themes.current_name()
	btn.custom_minimum_size = Vector2(0, 50)
	btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Appearance.tscn"))
	vbox.add_child(btn)
	vbox.move_child(btn, 2) # после заголовка и разделителя

func _build_real_rating_row() -> void:
	var vbox: Node = handicap_check.get_parent().get_parent()
	var anchor: Node = vbox.get_node("HandicapHint")
	var box := VBoxContainer.new()
	var title := Label.new()
	title.text = "Настоящий рейтинг (если есть)"
	box.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = Profile.REAL_RATING_MAX
	spin.step = 10
	spin.value = Profile.real_rating
	spin.editable = Profile.has_user()
	row.add_child(spin)
	var btn := Button.new()
	btn.text = "Применить"
	btn.disabled = not Profile.has_user()
	row.add_child(btn)
	var msg := Label.new()
	msg.add_theme_font_size_override("font_size", 12)
	msg.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.text = "Например, рейтинг федерации или клуба. Турнирный рейтинг начнётся с него и дальше изменится по результатам в игре. 0 — рейтинга нет."
	box.add_child(row)
	box.add_child(msg)
	btn.pressed.connect(func():
		var v := int(spin.value)
		if v != 0 and v < Profile.REAL_RATING_MIN:
			msg.text = "Рейтинг должен быть от %d до %d или 0." % [Profile.REAL_RATING_MIN, Profile.REAL_RATING_MAX]
			return
		Profile.set_real_rating(v)
		msg.text = "Сохранено. Турнирный рейтинг: %d." % int(Profile.tournament_rating) if v > 0 else "Настоящий рейтинг убран.")
	vbox.add_child(box)
	vbox.move_child(box, anchor.get_index() + 1)
