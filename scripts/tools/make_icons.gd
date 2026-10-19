extends Node

# Рисует PNG-иконки для веб-приложения (PWA) из icon.svg и печать клуба для заставки из
# assets/brand/seal.svg. Запуск один раз после смены логотипа: scenes/tools/MakeIcons.tscn
# (файлы кладутся в корень проекта и в assets/brand).

func _render(svg_path: String, size: int, out_path: String) -> void:
	var svg := FileAccess.get_file_as_string(svg_path)
	var img := Image.new()
	img.load_svg_from_string(svg, float(size) / 128.0)
	img.resize(size, size)
	img.save_png(out_path)
	print("%s %dx%d" % [out_path, img.get_width(), img.get_height()])

func _ready() -> void:
	for size in [144, 180, 512]:
		_render("res://icon.svg", size, "res://icon_%d.png" % size)
	_render("res://assets/brand/seal.svg", 512, "res://assets/brand/seal_512.png")
	get_tree().quit()
