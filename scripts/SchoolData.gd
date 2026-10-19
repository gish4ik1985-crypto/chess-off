class_name SchoolData
extends RefCounted

# Расписание, события, годовой план (коллекция events) и объявления (announcements): загрузка из облака
# и расчёты по датам. Даты хранятся строкой «ГГГГ-ММ-ДД» — так их удобно сравнивать и сортировать.

const WEEKDAYS := ["Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье"]
const WEEKDAYS_SHORT := ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]
const MONTH_NOM := ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь", "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"]
const MONTH_GEN := ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
const KINDS := {"lesson": "Занятие (каждую неделю)", "event": "Событие", "tournament": "Турнир", "plan": "Пункт годового плана"}
const KIND_ICON := {"lesson": "📘", "event": "📌", "tournament": "🏆", "plan": "🗓"}

static var events: Array = []
static var announcements: Array = []
static var loaded := false

# ---- даты ----

static func today_iso() -> String:
	var d := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

static func parse_iso(s: String) -> Dictionary:
	var p := s.split("-")
	if p.size() != 3:
		return {"year": 2026, "month": 1, "day": 1}
	return {"year": int(p[0]), "month": int(p[1]), "day": int(p[2])}

static func days_in_month(y: int, m: int) -> int:
	if m == 2:
		return 29 if (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)) else 28
	return 30 if m in [4, 6, 9, 11] else 31

static func to_unix(iso: String) -> int:
	var d := parse_iso(iso)
	return int(Time.get_unix_time_from_datetime_dict({"year": d.year, "month": d.month, "day": d.day, "hour": 12, "minute": 0, "second": 0}))

static func from_unix(t: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(t)
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

static func add_days(iso: String, n: int) -> String:
	return from_unix(to_unix(iso) + n * 86400)

# День недели: 1 — понедельник … 7 — воскресенье.
static func weekday_of(iso: String) -> int:
	var w := int(Time.get_datetime_dict_from_unix_time(to_unix(iso)).weekday) # 0 — воскресенье
	return 7 if w == 0 else w

static func monday_of(iso: String) -> String:
	return add_days(iso, -(weekday_of(iso) - 1))

static func fmt_date(iso: String) -> String:
	if iso == "":
		return ""
	var d := parse_iso(iso)
	return "%d %s, %s" % [d.day, MONTH_GEN[clampi(int(d.month) - 1, 0, 11)], WEEKDAYS_SHORT[weekday_of(iso) - 1]]

# Учебный год, в который попадает дата: сентябрь–август. Возвращает год начала (2026 для 2026/27).
static func school_year_of(iso: String) -> int:
	var d := parse_iso(iso)
	return int(d.year) if int(d.month) >= 9 else int(d.year) - 1

# ---- кто видит ----

static func group_ok(g: String) -> bool:
	var t := g.strip_edges().to_lower()
	return t == "" or t == Profile.club_group.strip_edges().to_lower()

# ---- загрузка ----

static func load_all() -> bool:
	if not (Cloud.enabled and Cloud.signed_in):
		return false
	var e: Dictionary = await Cloud.query_top("events", "date", 600)
	var a: Dictionary = await Cloud.query_top("announcements", "at", 60)
	if not e.ok:
		return false
	events = e.docs
	announcements = a.docs if a.ok else []
	loaded = true
	return true

static func lessons() -> Array:
	var out := []
	for ev in events:
		if String(ev.get("kind", "")) == "lesson":
			out.append(ev)
	out.sort_custom(func(a, b): return String(a.get("time", "")) < String(b.get("time", "")))
	return out

# События и турниры (не занятия и не план) на дату.
static func events_on(iso: String) -> Array:
	var out := []
	for ev in events:
		if String(ev.get("kind", "")) in ["event", "tournament"] and String(ev.get("date", "")) == iso:
			out.append(ev)
	out.sort_custom(func(a, b): return String(a.get("time", "")) < String(b.get("time", "")))
	return out

# Ближайшие события для меня: от сегодня на days дней вперёд.
static func upcoming(days: int) -> Array:
	var today := today_iso()
	var last := add_days(today, days)
	var out := []
	for ev in events:
		var d := String(ev.get("date", ""))
		if String(ev.get("kind", "")) in ["event", "tournament"] and d >= today and d <= last and group_ok(String(ev.get("group", ""))):
			out.append(ev)
	out.sort_custom(func(a, b): return String(a.get("date", "")) + String(a.get("time", "")) < String(b.get("date", "")) + String(b.get("time", "")))
	return out

# ---- объявления ----

static func visible_announcements() -> Array:
	var out := []
	var now := int(Time.get_unix_time_from_system())
	for a in announcements:
		var until := int(a.get("until", 0))
		if (until == 0 or until > now) and group_ok(String(a.get("group", ""))):
			out.append(a)
	out.sort_custom(func(a, b):
		if bool(a.get("pinned", false)) != bool(b.get("pinned", false)):
			return bool(a.get("pinned", false))
		return int(a.get("at", 0)) > int(b.get("at", 0)))
	return out

static func unread_announcements() -> Array:
	var out := []
	for a in visible_announcements():
		if int(a.get("at", 0)) > Profile.ann_seen:
			out.append(a)
	return out

static func mark_announcements_seen() -> void:
	var newest := Profile.ann_seen
	for a in visible_announcements():
		newest = maxi(newest, int(a.get("at", 0)))
	if newest != Profile.ann_seen:
		Profile.ann_seen = newest
		Profile.request_save()
