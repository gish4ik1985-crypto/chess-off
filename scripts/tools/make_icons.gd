extends Node

# Рисует PNG-иконки для веб-приложения (PWA) из icon.svg.
# Запуск один раз: scenes/tools/MakeIcons.tscn (файлы кладутся в корень проекта).

func _ready() -> void:
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	for size in [144, 180, 512]:
		var img := Image.new()
		img.load_svg_from_string(svg, float(size) / 128.0)
		img.resize(size, size)
		img.save_png("res://icon_%d.png" % size)
		print("icon_%d.png %dx%d" % [size, img.get_width(), img.get_height()])
	get_tree().quit()
