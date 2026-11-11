extends Node

# Синхронизация прогресса между двумя устройствами — целиком, с подставной базой вместо Firestore.
# Сценарий — тот, на котором до версии 1.17 пропадал прогресс: планшет решает задачи, компьютер со
# старым профилем сохраняется позже; после обмена через облако на обоих должно быть всё решённое.
# «Устройства» — два файла одного профиля, которые по очереди подкладываются на место.
#   godot --headless --path . res://scenes/tools/TestSync.tscn
# Работает только с игроком «ZzSync» и убирает за собой.

const NAME := "ZzSync"
var failures := 0

# Облако с памятью вместо сети: те же push/pull/sync, что в игре, но документы лежат в словаре.
class FakeCloud extends "res://scripts/Cloud.gd":
	var store := {}
	var fail_reads := false

	func _ready() -> void:
		pass # без настоящего входа и чтения настроек

	func get_doc(path: String) -> Dictionary:
		if fail_reads:
			return {"ok": false, "found": false, "data": {}, "error": "нет сети"}
		if not store.has(path):
			return {"ok": true, "found": false, "data": {}, "error": ""}
		return {"ok": true, "found": true, "data": store[path], "error": ""}

	func set_doc(path: String, data: Dictionary) -> Dictionary:
		store[path] = data.duplicate(true)
		return {"ok": true, "error": ""}

func check(cond: bool, what: String) -> void:
	if cond:
		print("OK   ", what)
	else:
		failures += 1
		print("FAIL ", what)

func _path() -> String:
	return Profile.USERS_DIR + Profile.sanitize_key(NAME) + ".cfg"

# Сохраняет файл текущего «устройства» и подкладывает файл другого.
func _swap(save_to: Dictionary, load_from: Dictionary, cloud: Node) -> void:
	Profile.save_profile()
	save_to["bytes"] = FileAccess.get_file_as_bytes(_path())
	save_to["synced"] = cloud.synced_rev
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	f.store_buffer(load_from["bytes"])
	f.close()
	Profile.load_profile()
	cloud.synced_rev = String(load_from["synced"])

func _ready() -> void:
	var prev_user: String = Profile.current_user
	Profile.switch_user(NAME, false)
	var cloud := FakeCloud.new()
	add_child(cloud)
	cloud.enabled = true
	cloud.signed_in = true
	cloud.uid = "u1"
	cloud.nick = NAME

	# обе копии начинаются с одного и того же пустого профиля
	Profile.save_profile()
	var tablet := {"bytes": FileAccess.get_file_as_bytes(_path()), "synced": ""}
	var pc := {"bytes": FileAccess.get_file_as_bytes(_path()), "synced": ""}

	# планшет: 5 вилок и пройденный узел карты, отправка в облако
	for i in 5:
		Profile.record_fork_puzzle_solved()
	Profile.defeated_characters["pawn_timofey"] = true
	Profile.save_profile()
	var r: Dictionary = await cloud.push_profile()
	check(r.ok, "планшет отправил профиль в облако")
	check(int(cloud.store["private/u1"].get("v", -1)) == Global.version_code(), "в облачной копии есть номер версии")

	# компьютер: старый профиль (вилок 0), решает связку и сохраняется ПОЗЖЕ планшета
	_swap(tablet, pc, cloud)
	check(Profile.fork_puzzles_solved == 0, "на компьютере старый профиль: вилок 0")
	Profile.record_pin_puzzle_solved()
	Profile.save_profile()
	r = await cloud.push_profile()
	check(r.ok, "компьютер отправил профиль")
	check(Profile.fork_puzzles_solved == 5, "компьютер перед отправкой забрал 5 вилок планшета, а не затёр их")
	check(Profile.pin_puzzles_solved == 1, "своя связка на компьютере осталась")

	# планшет снова: забирает связку с компьютера, вилки на месте
	_swap(pc, tablet, cloud)
	var changed: bool = await cloud.sync_profile()
	check(changed, "планшет получил изменения с компьютера")
	check(Profile.fork_puzzles_solved == 5, "на планшете вилки на месте: 5")
	check(Profile.pin_puzzles_solved == 1, "на планшете появилась связка с компьютера")
	check(Profile.defeated_characters.has("pawn_timofey"), "узел карты не потерялся")
	check(not await cloud.sync_profile(), "повторная синхронизация ничего не меняет")

	# нет сети: профиль не отправляется вслепую, облачная копия остаётся прежней
	var before: Dictionary = cloud.store["private/u1"].duplicate(true)
	cloud.fail_reads = true
	Profile.record_fork_puzzle_solved()
	Profile.save_profile()
	r = await cloud.push_profile()
	check(not r.ok and cloud.store["private/u1"] == before, "без связи облачная копия не перезаписывается")
	cloud.fail_reads = false
	r = await cloud.push_profile()
	check(r.ok, "связь вернулась — профиль отправлен")
	_swap(tablet, pc, cloud)
	await cloud.sync_profile()
	check(Profile.fork_puzzles_solved == 6, "шестая вилка дошла до компьютера")

	# уборка
	for ext in [".cfg", ".cfg.bak", ".before_merge", ".replaced", ".replaced.merged"]:
		var p: String = Profile.USERS_DIR + Profile.sanitize_key(NAME) + ext
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	Profile.current_user = prev_user
	if prev_user != "":
		Profile.load_profile()
	print("ИТОГО ошибок: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
