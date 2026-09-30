extends RefCounted
class_name PieceTextures

# Loads and caches the lichess "cburnett" SVG piece set (assets/pieces/),
# the same piece art used by default on lichess.org.

static var _cache: Dictionary = {}

static func get_texture(ptype: String, color: String) -> Texture2D:
	var key = color + ptype
	if _cache.has(key):
		return _cache[key]
	var path = "res://assets/pieces/%s%s.svg" % [color, ptype]
	var tex: Texture2D = load(path)
	_cache[key] = tex
	return tex

static func draw(cr: CanvasItem, ptype: String, color: String, center: Vector2, size: float) -> void:
	var tex = get_texture(ptype, color)
	if tex == null:
		return
	var rect = Rect2(center - Vector2(size, size) / 2.0, Vector2(size, size))
	cr.draw_texture_rect(tex, rect, false)
