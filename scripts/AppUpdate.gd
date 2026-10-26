extends Node
class_name AppUpdate

# Мягкое обновление веб-версии. Игра сама никогда не перезапускается посреди партии:
#  - у каждой сборки есть номер (res://build_id.txt внутри игры и docs/version.json на сайте);
#  - раз в несколько минут игра спрашивает сайт, не вышла ли сборка новее;
#  - если вышла — в колокольчике меню появляется пункт «Вышла новая версия», игрок нажимает сам;
#  - если игрок долго ничего не делает и находится в главном меню (ничего не идёт) — обновляемся сами.
# Перед перезагрузкой профиль сохраняется, и мы ждём, пока браузер допишет его в своё хранилище.

const CHECK_EVERY := 300.0 # секунд между проверками
const IDLE_APPLY := 600.0 # секунд бездействия в меню до самостоятельного обновления
const FLUSH_WAIT := 2.0 # пауза после сохранения профиля перед перезагрузкой

var my_build := ""
var _since_check := 0.0
var _idle := 0.0
var _applying := false

func _ready() -> void:
	if not OS.has_feature("web") or not FileAccess.file_exists("res://build_id.txt"):
		set_process(false)
		set_process_input(false)
		return
	my_build = FileAccess.get_file_as_string("res://build_id.txt").strip_edges()
	_ask_site.call_deferred()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventKey or event is InputEventScreenTouch or event is InputEventMouseMotion:
		_idle = 0.0

func _process(delta: float) -> void:
	_since_check += delta
	_idle += delta
	if _since_check >= CHECK_EVERY:
		_since_check = 0.0
		_ask_site()
	_read_answer()
	if Global.update_available and _idle >= IDLE_APPLY and _in_main_menu():
		apply()

func _in_main_menu() -> bool:
	var sc := get_tree().current_scene
	return sc != null and sc.scene_file_path == Global.MENU_SCENE

func _ask_site() -> void:
	# ответ приходит позже: кладём его в переменную страницы и забираем в _read_answer
	JavaScriptBridge.eval("window.__chessoffLatest = ''; fetch('version.json?t=' + Date.now(), {cache: 'no-store'}).then(r => r.json()).then(j => { window.__chessoffLatest = String(j.build || ''); }).catch(() => {});")

func _read_answer() -> void:
	var latest = JavaScriptBridge.eval("window.__chessoffLatest || ''")
	if latest == null:
		return
	var s := str(latest)
	if s != "" and s != my_build and not Global.update_available:
		Global.update_available = true
		Global.update_ready.emit()

# Сохраняет профиль и перезагружает страницу с самой свежей сборкой. Зовите только тогда,
# когда игрок сам нажал «Обновить» или ничего не идёт (главное меню).
func apply() -> void:
	if _applying:
		return
	_applying = true
	Profile.save_profile()
	await get_tree().create_timer(FLUSH_WAIT).timeout
	# снимаем старого сервис-воркера и его кеш, перепроверяем файлы на сайте и перезагружаемся
	JavaScriptBridge.eval("""(async () => {
		try {
			for (const r of await navigator.serviceWorker.getRegistrations()) { await r.unregister(); }
			for (const k of await caches.keys()) { await caches.delete(k); }
			await Promise.all(['index.html', 'index.js', 'index.pck', 'index.wasm'].map(u => fetch(u, {cache: 'no-cache'})));
		} catch (e) {}
		location.reload();
	})();""")
