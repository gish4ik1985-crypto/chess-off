extends Node

# Партии с помощью (подсказка, откат хода, фора, командный режим) не должны менять рейтинг,
# а чистые партии — должны. Запуск: scenes/tools/TestHelpRating.tscn

const BoardScript = preload("res://scripts/Board.gd")

var fails := 0

func check(name: String, ok: bool, info: String = "") -> void:
	print(("OK   " if ok else "FAIL ") + name + (" " + info if info != "" else ""))
	if not ok:
		fails += 1

func _ready() -> void:
	var old_assist: bool = Global.map_assist
	var b = BoardScript.new() # без add_child: нужна только логика причин, экран не строится
	check("чистая партия идёт в рейтинг", b._rating_skip_reason() == "")
	b.help_hints = 1
	check("с подсказкой — не идёт", b._rating_skip_reason().contains("подсказ"), b._rating_skip_reason())
	b.help_hints = 0
	b.help_undos = 1
	check("с откатом хода — не идёт", b._rating_skip_reason().contains("откат"), b._rating_skip_reason())
	b.help_undos = 0
	Global.map_assist = true
	check("с форой — не идёт", b._rating_skip_reason().contains("фор"), b._rating_skip_reason())
	Global.map_assist = false
	b.coop = "team"
	check("командная партия — не идёт", b._rating_skip_reason().contains("команд"), b._rating_skip_reason())
	b.coop = ""
	b.help_hints = 2
	b.help_undos = 1
	Global.map_assist = true
	var r: String = b._rating_skip_reason()
	check("несколько причин перечисляются вместе", r.contains("подсказ") and r.contains("откат") and r.contains("фор"), r)
	Global.map_assist = old_assist
	b.help_hints = 0
	b.help_undos = 0
	b.attention = 20
	check("«Внимательность» с маркерами — не идёт", b._rating_skip_reason().contains("угроз"), b._rating_skip_reason())
	b.attention = 45
	check("«Внимательность» без подсказок (45) — идёт", b._rating_skip_reason() == "", b._rating_skip_reason())
	b.attention = 0
	b.map_character = {"id": "drill_two_rooks_2"}
	check("учебный узел drill_* — не идёт", b._rating_skip_reason().contains("учебн"), b._rating_skip_reason())
	b.map_character = {"id": "restr_no_queen"}
	check("узел-испытание — идёт", b._rating_skip_reason() == "", b._rating_skip_reason())
	b.map_character = {}
	b.free()
	print("=== ИТОГО ошибок: %d ===" % fails)
	get_tree().quit(1 if fails > 0 else 0)
