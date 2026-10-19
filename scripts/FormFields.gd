class_name FormFields
extends RefCounted

# Поля ввода для форм: дата (число, месяц, год) и время (часы, минуты) — без ручного набора формата.

static func make_date(parent: Control, iso: String = "") -> HBoxContainer:
	var d := SchoolData.parse_iso(iso if iso != "" else SchoolData.today_iso())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var day := SpinBox.new()
	day.min_value = 1
	day.max_value = 31
	day.value = d.day
	h.add_child(day)
	var month := OptionButton.new()
	for m in SchoolData.MONTH_NOM:
		month.add_item(m)
	month.selected = int(d.month) - 1
	month.custom_minimum_size = Vector2(150, 0)
	h.add_child(month)
	var year := SpinBox.new()
	year.min_value = 2024
	year.max_value = 2040
	year.value = d.year
	h.add_child(year)
	h.set_meta("day", day)
	h.set_meta("month", month)
	h.set_meta("year", year)
	parent.add_child(h)
	return h

static func read_date(h: HBoxContainer) -> String:
	var y := int((h.get_meta("year") as SpinBox).value)
	var m := (h.get_meta("month") as OptionButton).selected + 1
	var d := int((h.get_meta("day") as SpinBox).value)
	d = mini(d, SchoolData.days_in_month(y, m))
	return "%04d-%02d-%02d" % [y, m, d]

static func make_time(parent: Control, hour := 18, minute := 0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var hh := SpinBox.new()
	hh.min_value = 0
	hh.max_value = 23
	hh.value = hour
	h.add_child(hh)
	var sep := Label.new()
	sep.text = ":"
	h.add_child(sep)
	var mm := SpinBox.new()
	mm.min_value = 0
	mm.max_value = 55
	mm.step = 5
	mm.value = minute
	h.add_child(mm)
	h.set_meta("h", hh)
	h.set_meta("m", mm)
	parent.add_child(h)
	return h

static func read_time(h: HBoxContainer) -> String:
	return "%02d:%02d" % [int((h.get_meta("h") as SpinBox).value), int((h.get_meta("m") as SpinBox).value)]
