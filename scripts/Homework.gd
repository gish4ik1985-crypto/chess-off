class_name Homework
extends RefCounted

# Домашние задания: данные в облаке (assignments / submissions / reviews) и расчёт выполнения.
#
# Виды заданий:
#   metric   — «решить N задач / выиграть N партий»: ученик занимается как обычно, прогресс считается
#              по счётчикам профиля с момента, когда он нажал «Начать» (в облаке — результат)
#   position — позиция с вопросом («найдите лучший ход»): ученик отвечает ходом на доске
#   text     — свободное задание (прочитать, разобрать партию…): ученик отмечает «сделано» и пишет комментарий

const KINDS := {"metric": "Задачи и партии (считаются сами)", "position": "Позиция: найти ход", "text": "Свободное задание"}

const METRICS := {
	"puzzles_mate": "Задачи на мат",
	"puzzles_fork": "Задачи на вилку",
	"puzzles_pin": "Задачи на связку",
	"puzzles_mix": "Микс задач",
	"attention": "Уровни «Внимательности»",
	"wins": "Победы над компьютером",
	"games": "Сыгранные партии",
}

# Текущее значение счётчика профиля.
static func counter(metric: String) -> int:
	match metric:
		"puzzles_mate": return Profile.solved_puzzles.size()
		"puzzles_fork": return Profile.fork_puzzles_solved
		"puzzles_pin": return Profile.pin_puzzles_solved
		"puzzles_mix": return Profile.mix_puzzles_solved
		"attention": return Profile.attention_done
		"wins": return Profile.wins
		"games": return Profile.games_played
	return 0

# Где заниматься по этому счётчику.
static func scene_for(metric: String) -> String:
	match metric:
		"attention": return "res://scenes/AttentionHub.tscn"
		"wins", "games": return "res://scenes/Menu.tscn"
	return "res://scenes/PuzzleHub.tscn"

static func started(a: Dictionary) -> bool:
	return Profile.homework_base.has(String(a.get("_id", "")))

static func progress(a: Dictionary) -> int:
	var base: int = int(Profile.homework_base.get(String(a.get("_id", "")), counter(String(a.get("metric", "")))))
	return maxi(0, counter(String(a.get("metric", ""))) - base)

static func begin(a: Dictionary) -> void:
	var id := String(a.get("_id", ""))
	if not Profile.homework_base.has(id):
		Profile.homework_base[id] = counter(String(a.get("metric", "")))
		Profile.request_save()

static func is_overdue(a: Dictionary) -> bool:
	var dl := int(a.get("deadline", 0))
	return dl > 0 and Time.get_unix_time_from_system() > dl

static func deadline_text(a: Dictionary) -> String:
	var dl := int(a.get("deadline", 0))
	if dl <= 0:
		return "без срока"
	var d := Time.get_datetime_dict_from_unix_time(dl + 3 * 3600) # москов­ское время приблизительно
	return "до %02d.%02d" % [d.day, d.month]

# Подходит ли задание этому ученику (группа пустая — для всех).
static func for_me(a: Dictionary) -> bool:
	if not bool(a.get("active", true)):
		return false
	var g := String(a.get("group", "")).strip_edges().to_lower()
	return g == "" or g == Profile.club_group.strip_edges().to_lower()

static func new_id() -> String:
	return "a%d%03d" % [int(Time.get_unix_time_from_system()), randi() % 1000]

static func sub_id(aid: String, uid: String) -> String:
	return aid + "_" + uid

# ---- кеш за сеанс: список заданий и мои сданные ----
static var assignments: Array = []
static var my_done: Dictionary = {} # aid -> документ сдачи
static var loaded := false

static func load_all() -> bool:
	if not (Cloud.enabled and Cloud.signed_in):
		return false
	var a: Dictionary = await Cloud.query_top("assignments", "created", 100)
	var s: Dictionary = await Cloud.query_top("submissions", "at", 500)
	if not a.ok:
		return false
	assignments = a.docs
	my_done = {}
	if s.ok:
		for d in s.docs:
			if String(d.get("uid", "")) == Cloud.uid:
				my_done[String(d.get("aid", ""))] = d
	loaded = true
	return true

# Задания, которые ещё ждут ученика: подходят ему, не сданы, не просрочены.
static func pending() -> Array:
	var out := []
	for a in assignments:
		if for_me(a) and not my_done.has(String(a.get("_id", ""))) and not is_overdue(a):
			out.append(a)
	return out

# Отправка результата ученика. detail — коротко «что получилось».
static func submit(a: Dictionary, score: int, detail: String, comment: String = "") -> Dictionary:
	var aid := String(a.get("_id", ""))
	var doc := {
		"aid": aid, "uid": Cloud.uid, "name": Profile.shown_name(), "group": Profile.club_group,
		"score": score, "detail": detail, "comment": comment.left(300),
		"at": int(Time.get_unix_time_from_system()),
	}
	var r: Dictionary = await Cloud.set_doc("submissions/" + sub_id(aid, Cloud.uid), doc)
	if r.ok:
		var saved := doc.duplicate()
		saved["_id"] = sub_id(aid, Cloud.uid)
		my_done[aid] = saved
	return r

# Автосдача заданий-счётчиков, где цель достигнута. Возвращает, сколько отправлено.
static func auto_submit_done() -> int:
	var n := 0
	for a in assignments:
		if String(a.get("kind", "")) != "metric" or not for_me(a) or my_done.has(String(a.get("_id", ""))) or not started(a):
			continue
		var target := int(a.get("target", 1))
		var got := progress(a)
		if got >= target:
			var r: Dictionary = await submit(a, got, "Выполнено: %d из %d" % [got, target])
			if r.ok:
				n += 1
	return n
