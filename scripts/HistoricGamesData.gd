extends RefCounted
class_name HistoricGamesData

# База знаменитых партий для режима «Партии великих шахматистов», разбитая по
# шахматистам. Каждый файл в scripts/historic/ описывает одного игрока:
# {id, name, years, blurb, games:[...]}. Формат хода в games — либо строка SAN
# ("e4", "Nf3", "O-O"), к которой пояснение генерируется автоматически, либо
# словарь {"san": "...", "c": "написанное вручную объяснение"}.

const PLAYERS := [
	preload("res://scripts/historic/HGMorphy.gd"),
	preload("res://scripts/historic/HGAnderssen.gd"),
	preload("res://scripts/historic/HGSteinitz.gd"),
	preload("res://scripts/historic/HGLasker.gd"),
	preload("res://scripts/historic/HGCapablanca.gd"),
	preload("res://scripts/historic/HGAlekhine.gd"),
	preload("res://scripts/historic/HGTal.gd"),
	preload("res://scripts/historic/HGFischer.gd"),
	preload("res://scripts/historic/HGKarpov.gd"),
	preload("res://scripts/historic/HGKasparov.gd"),
	preload("res://scripts/historic/HGAnand.gd"),
	preload("res://scripts/historic/HGCarlsen.gd"),
]

# Список шахматистов с их партиями. Каждый элемент — Dictionary игрока.
static func players() -> Array:
	var out := []
	for p in PLAYERS:
		out.append(p.data())
	return out

# Плоский список всех партий (для обратной совместимости/тестов).
static func all() -> Array:
	var out := []
	for p in PLAYERS:
		out.append_array(p.data().games)
	return out
