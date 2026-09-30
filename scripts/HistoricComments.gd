extends RefCounted

# Генератор пояснений к ходам «Партий великих», у которых нет комментария,
# написанного вручную. Каждая фраза строится из настоящих фактов позиции —
# что взято и защищено ли поле, кто под ударом, сколько клеток контролирует
# фигура, есть ли у пешки проходной путь, где стоят короли, — а не из шаблона
# «фигура пошла туда-то». Формулировки одного смысла чередуются по клетке и
# номеру хода, чтобы соседние ходы не звучали слово в слово одинаково.

const PIECE_RU := {"P": "пешка", "N": "конь", "B": "слон", "R": "ладья", "Q": "ферзь", "K": "король"}
const PIECE_RU_ACC := {"P": "пешку", "N": "коня", "B": "слона", "R": "ладью", "Q": "ферзя", "K": "короля"}
const PIECE_RU_INST := {"P": "пешкой", "N": "конём", "B": "слоном", "R": "ладьёй", "Q": "ферзём", "K": "королём"}
const PIECE_VALUE := {"P": 1, "N": 3, "B": 3, "R": 5, "Q": 9, "K": 0}
const PIECE_GENDER := {"P": "f", "N": "m", "B": "m", "R": "f", "Q": "m", "K": "m"}
const START_SQUARES := {
	"w": {"N": [Vector2i(1, 0), Vector2i(6, 0)], "B": [Vector2i(2, 0), Vector2i(5, 0)], "R": [Vector2i(0, 0), Vector2i(7, 0)], "Q": [Vector2i(3, 0)], "K": [Vector2i(4, 0)]},
	"b": {"N": [Vector2i(1, 7), Vector2i(6, 7)], "B": [Vector2i(2, 7), Vector2i(5, 7)], "R": [Vector2i(0, 7), Vector2i(7, 7)], "Q": [Vector2i(3, 7)], "K": [Vector2i(4, 7)]},
}
const CENTER4 := [Vector2i(3, 3), Vector2i(4, 3), Vector2i(3, 4), Vector2i(4, 4)] # d4 e4 d5 e5

# --- мелкие помощники ---

static func _g(ptype: String, m_form: String, f_form: String) -> String:
	return m_form if PIECE_GENDER.get(ptype, "m") == "m" else f_form

static func _prot(ptype: String) -> String:
	return _g(ptype, "защищён", "защищена")

# «1 клетку / 2 клетки / 5 клеток»
static func _kl(n: int) -> String:
	var last := n % 10
	var tens := n % 100
	if tens >= 11 and tens <= 14:
		return "%d клеток" % n
	if last == 1:
		return "%d клетку" % n
	if last >= 2 and last <= 4:
		return "%d клетки" % n
	return "%d клеток" % n

static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1)

static func _sq(v: Vector2i) -> String:
	return ChessEngine.square_name(v.x, v.y)

# номер горизонтали с точки зрения хода: 0 — своя первая, 7 — последняя
static func _rel_rank(r: int, color: String) -> int:
	return r if color == "w" else 7 - r

static func _opp(color: String) -> String:
	return "b" if color == "w" else "w"

# сумма ценности фигур без пешек и королей у обеих сторон
static func _piece_material(eng: ChessEngine) -> int:
	var total := 0
	for r in range(8):
		for f in range(8):
			var p = eng.board[r][f]
			if p != null and p.type != "P" and p.type != "K":
				total += int(PIECE_VALUE[p.type])
	return total

static func is_endgame(eng: ChessEngine) -> bool:
	return _piece_material(eng) <= 20

static func _has_queen(eng: ChessEngine, color: String) -> bool:
	for r in range(8):
		for f in range(8):
			var p = eng.board[r][f]
			if p != null and p.type == "Q" and p.color == color:
				return true
	return false

# разница материала в пешках: плюс — у белых
static func material_diff(eng: ChessEngine) -> int:
	var d := 0
	for r in range(8):
		for f in range(8):
			var p = eng.board[r][f]
			if p != null:
				d += int(PIECE_VALUE[p.type]) * (1 if p.color == "w" else -1)
	return d

# строка о материале — для редких «сводок» по ходу партии
static func material_line(eng: ChessEngine) -> String:
	var d := material_diff(eng)
	if d == 0:
		return "Материал равный."
	var who := "белых" if d > 0 else "чёрных"
	var n := absi(d)
	if n <= 1:
		return "У %s лишняя пешка." % who
	if n <= 2:
		return "У %s перевес в две пешки." % who
	if n == 3:
		return "У %s перевес в фигуру." % who
	if n <= 5:
		return "У %s заметный материальный перевес." % who
	return "У %s решающий материальный перевес." % who

# сколько клеток может занять фигура на (f, r) в данной позиции
static func _mobility(eng: ChessEngine, f: int, r: int) -> int:
	return eng.pseudo_moves_for(f, r).size()

static func _king_sq(eng: ChessEngine, color: String) -> Vector2i:
	return eng.find_king(color)

static func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

# ход даёт шах самой сходившей фигурой (а не вскрытием линии)?
static func _direct_check(after: ChessEngine, mv: Dictionary, opp: String) -> bool:
	var k := _king_sq(after, opp)
	if k.x < 0:
		return false
	for m in after.pseudo_moves_for(mv.to.x, mv.to.y):
		if m.to == k:
			return true
	return false

static func _is_passed(eng: ChessEngine, f: int, r: int, color: String) -> bool:
	var dir := 1 if color == "w" else -1
	var rr := r + dir
	while rr >= 0 and rr <= 7:
		for df in [-1, 0, 1]:
			var ff: int = f + df
			if ff < 0 or ff > 7:
				continue
			var p = eng.board[rr][ff]
			if p != null and p.type == "P" and p.color != color:
				return false
		rr += dir
	return true

# конь на форпосту: глубоко в чужой половине, защищён своей пешкой, чужие пешки его не выбьют
static func _is_outpost(eng: ChessEngine, f: int, r: int, color: String) -> bool:
	var rel := _rel_rank(r, color)
	if rel < 4 or rel > 6 or f < 1 or f > 6:
		return false
	var dir := 1 if color == "w" else -1
	var protected_ := false
	for df in [-1, 1]:
		var p = eng.board[r - dir][f + df] if r - dir >= 0 and r - dir <= 7 else null
		if p != null and p.type == "P" and p.color == color:
			protected_ = true
	if not protected_:
		return false
	var opp := _opp(color)
	for df in [-1, 1]:
		var rr := r + dir
		while rr >= 0 and rr <= 7:
			var p2 = eng.board[rr][f + df]
			if p2 != null and p2.type == "P" and p2.color == opp:
				return false
			rr += dir
	return true

static func _file_openness(eng: ChessEngine, file: int, color: String) -> String:
	var own_pawn := false
	var any_pawn := false
	for r in range(8):
		var pc = eng.board[r][file]
		if pc != null and pc.type == "P":
			any_pawn = true
			if pc.color == color:
				own_pawn = true
	if own_pawn:
		return "closed"
	return "semi" if any_pawn else "open"

# король уже спрятан за пешками (рокировался или стоит в углу на своей горизонтали)
static func _tucked(eng: ChessEngine, color: String) -> bool:
	var k := _king_sq(eng, color)
	if k.x < 0:
		return false
	return _rel_rank(k.y, color) == 0 and (k.x <= 2 or k.x >= 6)

# Самая ценная вражеская фигура, оказавшаяся под ударом именно после этого хода.
static func _best_new_threat(before: ChessEngine, after: ChessEngine, mover_color: String) -> Dictionary:
	var opp := _opp(mover_color)
	var best := {}
	var best_value := -1
	for r in range(8):
		for f in range(8):
			var pc = after.board[r][f]
			if pc == null or pc.color != opp or pc.type == "K":
				continue
			if not after.is_square_attacked(f, r, mover_color):
				continue
			if before.is_square_attacked(f, r, mover_color):
				continue
			var val: int = int(PIECE_VALUE.get(pc.type, 1))
			if val > best_value:
				best_value = val
				best = {"sq": Vector2i(f, r), "sq_name": ChessEngine.square_name(f, r), "type": pc.type, "defended": after.is_square_attacked(f, r, opp)}
	return best

# --- главный вход ---

static func _explain_core(before: ChessEngine, after: ChessEngine, mv: Dictionary, ply: int) -> String:
	var p = before.board[mv.from.y][mv.from.x]
	var ptype: String = p.type if p != null else "P"
	var color: String = p.color if p != null else "w"
	var opp := _opp(color)
	var piece: String = PIECE_RU.get(ptype, "фигура")
	var piece_inst: String = PIECE_RU_INST.get(ptype, "фигурой")
	var to_name := _sq(mv.to)
	var v: int = (ply + mv.to.x * 3 + mv.to.y) % 3
	var endgame := is_endgame(before)
	var rel_to := _rel_rank(mv.to.y, color)

	# превращение пешки
	if str(mv.get("promo", "")) != "":
		var pr_acc: String = PIECE_RU_ACC.get(str(mv.promo), "ферзя")
		if before.board[mv.to.y][mv.to.x] != null:
			return "пешка берёт на %s и заодно превращается в %s — взятие и превращение одним ходом." % [to_name, pr_acc]
		return "пешка прошла всю доску и превращается в %s — с доски пропадает пешка, появляется сильная фигура." % pr_acc

	var victim = before.board[mv.to.y][mv.to.x]
	var is_capture: bool = victim != null or mv.get("is_ep", false)
	var was_attacked := before.is_square_attacked(mv.from.x, mv.from.y, opp)
	var recapture: bool = before.last_move != null and before.last_move.to == mv.to and before.last_move.get("captured", null) != null
	var gives_check := after.is_in_check(opp)

	# вскрытый шах: шах объявляет не сама сходившая фигура
	if gives_check and not _direct_check(after, mv, opp):
		return [
			"%s освобождает линию — и стоявшая за ней фигура объявляет шах." % _cap(piece),
			"вскрытый шах: %s уходит с линии, открывая королю удар издалека." % piece,
			"%s отходит в сторону, а шах даёт фигура, которую она закрывала." % _cap(piece),
		][v]

	# --- взятие ---
	if is_capture:
		var vt: String = victim.type if victim != null else "P"
		var vname: String = PIECE_RU_ACC.get(vt, "фигуру")
		var vval: int = int(PIECE_VALUE.get(vt, 1))
		var pval: int = int(PIECE_VALUE.get(ptype, 1))
		var defended := after.is_square_attacked(mv.to.x, mv.to.y, opp)
		var tail := ""
		if was_attacked and ptype != "P":
			tail = " Заодно %s уходит из-под удара." % piece
		if recapture:
			return "%s отыгрывает %s, взятую на прошлом ходу, — материал снова уравнен.%s" % [_cap(piece), vname, tail]
		if ptype == "Q" and vt == "Q":
			return "обмен ферзей: %s берёт %s, партия заметно упрощается и уходит в эндшпиль." % [piece, vname] if defended else "%s берёт ферзя, и ответить нечем — это решает партию." % _cap(piece)
		if ptype == "P" and vt == "P":
			if mv.get("is_ep", false):
				return "взятие на проходе: пешка забирает пешку, которая только что прошла мимо, — редкое правило в действии."
			if mv.to.x in [3, 4]:
				return [
					"пешечный размен в центре: линии открываются, фигурам становится просторнее.",
					"пешка берёт пешку в центре — теперь понятнее, чья структура здоровее.",
					"размен пешек на %s меняет структуру центра и открывает дорогу фигурам." % to_name,
				][v]
			var opened := _file_openness(after, mv.from.x, color)
			if opened == "open":
				return "размен пешек на %s: линия %s теперь совсем без пешек — здесь пройдут ладьи." % [to_name, String.chr(97 + mv.from.x)]
			if opened == "semi":
				return "пешка берёт на %s: у сходившей стороны на линии %s пешек не осталось, а у соперника они есть — появилась полуоткрытая линия для ладьи." % [to_name, String.chr(97 + mv.from.x)]
			return ["размен пешек на %s: на фланге меняется структура пешек.", "пешка берёт пешку на %s — соседние пешки остаются, структура фланга сохраняется.", "взятие пешкой на %s: пешечная цепочка перестраивается."][v] % to_name
		if vval > pval:
			return "%s берёт %s — %s: отдаётся менее ценное, берётся более ценное.%s" % [_cap(piece), vname, ["выгодный размен", "материальный выигрыш", "чистая прибыль по материалу"][v], tail]
		if vval == pval:
			if defended:
				return "%s берёт %s — равный размен, соперник вправе взять в ответ.%s" % [_cap(piece), vname, tail]
			return "%s забирает %s, и взять %s назад нечем — материал выигран без потерь.%s" % [_cap(piece), vname, _g(vt, "его", "её"), tail]
		# ценная фигура берёт менее ценную
		if defended:
			return "%s берёт %s на %s, но поле под ударом соперника: если он возьмёт в ответ, %s потеряется за меньшее — значит, это либо точный расчёт, либо жертва." % [_cap(piece), vname, to_name, piece]
		return "%s забирает %s — %s без защиты, и брать %s было безопасно.%s" % [_cap(piece), vname, _g(vt, "тот остался", "та осталась"), _g(vt, "его", "её"), tail]

	# --- фигура уходит из-под удара ---
	if was_attacked and ptype != "P":
		if v == 0:
			return "%s %s под ударом — ход на %s уводит %s в безопасное место." % [_cap(piece), _g(ptype, "стоял", "стояла"), to_name, _g(ptype, "его", "её")]
		if v == 1:
			return "спасаем %s: соперник грозил %s забрать, а на %s %s вне опасности." % [PIECE_RU_ACC.get(ptype, "фигуру"), _g(ptype, "его", "её"), to_name, _g(ptype, "он", "она")]
		return "%s уходит на %s — там ей ничто не угрожает." % [_cap(piece), to_name] if ptype in ["R", "Q"] else "%s отходит на %s, %s." % [_cap(piece), to_name, ("и там %s защищает своя фигура" % _g(ptype, "его", "её")) if after.is_square_attacked(mv.to.x, mv.to.y, color) else "уходя из-под удара"]

	# --- новая угроза сопернику ---
	var threat := _best_new_threat(before, after, color)
	if not threat.is_empty():
		var t_nom: String = PIECE_RU.get(threat.type, "фигура")
		var t_acc: String = PIECE_RU_ACC.get(threat.type, "фигуру")
		var tv: int = int(PIECE_VALUE.get(threat.type, 1))
		var av: int = int(PIECE_VALUE.get(ptype, 1))
		if threat.defended:
			if tv > av:
				return "%s нападает на %s (%s): фигура защищена, но нападающий дешевле — размен ей невыгоден, придётся уходить." % [_cap(piece), t_acc, threat.sq_name]
			if tv == av:
				return "%s нападает на %s (%s) — %s %s, значит, дело идёт к равному размену." % [_cap(piece), t_acc, threat.sq_name, _g(threat.type, "он", "она"), _prot(threat.type)]
			return "%s нападает на %s (%s), но %s %s и стоит дешевле — это скорее давление, чем угроза выиграть материал." % [_cap(piece), t_acc, threat.sq_name, _g(threat.type, "он", "она"), _prot(threat.type)]
		if v == 0:
			return "%s создаёт угрозу: %s соперника на %s остаётся без защиты под ударом!" % [_cap(piece), t_nom, threat.sq_name]
		if v == 1:
			return "под ударом оказалась %s на %s — и защитить её нечем, придётся спасать." % [t_nom, threat.sq_name] if threat.type in ["R", "P"] else "под ударом оказался %s на %s — и защитить его нечем, придётся спасать." % [t_nom, threat.sq_name]
		return "ход на %s нападает на %s (%s) без защиты, и соперник вынужден отвечать." % [to_name, t_acc, threat.sq_name]

	# --- первый выход фигуры в игру ---
	var start_sqs: Array = START_SQUARES.get(color, {}).get(ptype, [])
	if start_sqs.has(mv.from) and ptype != "K":
		var mob_now := _mobility(after, mv.to.x, mv.to.y)
		match ptype:
			"N":
				var out := "конь выходит на %s и контролирует %s" % [to_name, _kl(mob_now)]
				if mv.to.x in [0, 7]:
					return out + " — у края доски он слабее, чем в центре."
				if mv.to in CENTER4 or (mv.to.x in [2, 3, 4, 5] and _rel_rank(mv.to.y, color) in [2, 3, 4]):
					return out + [" — почти максимум для коня.", " — активная позиция ближе к центру.", " — из центра он достаёт до обоих флангов."][v]
				return out + "."
			"B":
				return ["слон выходит из-за пешек на %s и получает %s для манёвра.", "развитие слона на %s: диагональ открыта, под контролем %s.", "слон занимает %s — теперь он смотрит на %s."][v] % [to_name, _kl(mob_now)]
			"Q":
				return "ферзь выходит на %s очень рано — фигуру такой ценности лучше не подставлять под атаку, пока не развиты лёгкие фигуры." % to_name if ply <= 14 else "ферзь включается в игру, выходя на %s." % to_name
			"R":
				var kind := _file_openness(after, mv.to.x, color)
				if kind == "open":
					return "ладья впервые вступает в игру на открытой линии %s." % String.chr(97 + mv.to.x)
				return "ладья впервые вступает в игру: с %s на %s." % [_sq(mv.from), to_name]

	# --- пешки ---
	if ptype == "P":
		var passed := _is_passed(after, mv.to.x, mv.to.y, color)
		var enemy_k := _king_sq(after, opp)
		var own_k := _king_sq(after, color)
		if passed and rel_to >= 4:
			return ["проходная пешка на %s: впереди у неё нет ни пешек, ни соседей соперника — теперь она угроза, которую придётся останавливать фигурами.", "пешка идёт на %s и остаётся проходной — до превращения %d шагов.", "проходная пешка делает шаг на %s — теперь соперник вынужден следить за ней постоянно."][v] % ([to_name] if v != 1 else [to_name, 7 - rel_to])
		# рычаг: пешка нападает на пешку соперника
		var dir := 1 if color == "w" else -1
		var lever := false
		for df in [-1, 1]:
			var nf: int = mv.to.x + df
			var nr: int = mv.to.y + dir
			if nf >= 0 and nf <= 7 and nr >= 0 and nr <= 7:
				var t = after.board[nr][nf]
				if t != null and t.type == "P" and t.color == opp:
					lever = true
		if mv.to in CENTER4:
			var extra := " и нападает на пешку соперника" if lever else ""
			return ["пешка занимает центральное поле %s%s — центр даёт фигурам простор на обоих флангах.", "пешка встаёт на %s%s: контроль центра — основа любой позиции.", "пешка на %s%s — соперник теперь ограничен в центре."][v] % [to_name, extra]
		if lever:
			return ["пешечный рычаг: пешка на %s нападает на пешку соперника и вынуждает решить, разменять её или поддержать.", "пешка идёт на %s с угрозой размена — так вскрывают позицию и создают слабости.", "пешка на %s атакует пешечную цепь соперника — напряжение растёт."][v] % to_name
		if rel_to >= 5:
			return "пешка глубоко продвинулась на %s — до последней горизонтали совсем близко, соперник должен её держать под контролем." % to_name
		# фланговая пешка: важно, у чьего короля она идёт
		if mv.to.x <= 2 or mv.to.x >= 5:
			var wing_left: bool = mv.to.x <= 2
			var near_own: bool = own_k.x >= 0 and (own_k.x <= 2) == wing_left and (own_k.x <= 2 or own_k.x >= 5) and _tucked(after, color)
			var near_enemy: bool = enemy_k.x >= 0 and (enemy_k.x <= 2) == wing_left and (enemy_k.x <= 2 or enemy_k.x >= 5)
			if near_own:
				return ["пешка около собственного короля идёт на %s — прикрытие короля становится тоньше, за это придётся отвечать.", "ход пешки на %s ослабляет пешечный щит собственного короля — плата за активность.", "пешка на %s продвигается рядом со своим королём: пространства больше, но безопасность меньше."][v] % to_name
			if near_enemy:
				return ["пешка идёт на %s — начинается пешечный штурм на фланге, где стоит король соперника.", "продвижение пешки на %s готовит вскрытие линий против короля соперника.", "пешка на %s открывает дорогу фигурам к королю соперника."][v] % to_name
			return ["пешка идёт на %s — на этом фланге растёт пространство.", "ход пешки на %s отвоёвывает пространство на фланге.", "пешка на %s готовит фигурам поля и может стать основой будущего наступления."][v] % to_name
		return ["пешка идёт на %s, отвоёвывая пространство.", "пешка на %s поддерживает соседние фигуры и открывает дорогу слонам.", "пешка продвигается на %s — структура в центре меняется."][v] % to_name

	# --- ладья ---
	if ptype == "R":
		var kind2 := _file_openness(after, mv.to.x, color)
		# удвоение ладей
		for r in range(8):
			var q = after.board[r][mv.to.x]
			if q != null and q.type == "R" and q.color == color and r != mv.to.y:
				return "ладьи удвоены на линии %s: две ладьи вместе давят гораздо сильнее, чем по отдельности." % String.chr(97 + mv.to.x)
		if rel_to == 6:
			var enemy_pawns_on := 0
			for f in range(8):
				var q2 = after.board[mv.to.y][f]
				if q2 != null and q2.type == "P" and q2.color == opp:
					enemy_pawns_on += 1
			if enemy_pawns_on > 0:
				return "ладья вторгается на седьмую горизонталь (%s): здесь стоят пешки соперника, и ладья может забрать их." % to_name
		if kind2 == "open":
			return ["ладья становится на полностью открытую линию %s — ни одна пешка её здесь не задерживает.", "ладья занимает открытую линию %s: отсюда она давит вдоль всей доски.", "открытая линия %s теперь принадлежит ладье."][v] % String.chr(97 + mv.to.x)
		if kind2 == "semi":
			return "ладья занимает полуоткрытую линию %s: своих пешек тут больше нет, а чужая пешка становится целью." % String.chr(97 + mv.to.x)

	# --- слон ---
	if ptype == "B" and (mv.to == Vector2i(6, 1) or mv.to == Vector2i(1, 1) or mv.to == Vector2i(6, 6) or mv.to == Vector2i(1, 6)):
		return "слон фианкеттируется на %s — встаёт рядом с королём и держит под прицелом длинную диагональ через всю доску." % to_name

	# --- король ---
	if ptype == "K":
		if endgame:
			var center := Vector2i(3, 3)
			var closer: bool = _cheb(mv.to, center) < _cheb(mv.from, center)
			var nearest := 99
			for r in range(8):
				for f in range(8):
					var pw = after.board[r][f]
					if pw != null and pw.type == "P":
						nearest = mini(nearest, _cheb(mv.to, Vector2i(f, r)))
			var pawn_txt := (" До ближайшей пешки — %d %s." % [nearest, "шаг" if nearest == 1 else "шага" if nearest in [2, 3, 4] else "шагов"]) if nearest < 99 else ""
			if closer:
				return ["король идёт к центру (%s): в эндшпиле он — полноценная боевая фигура.", "король активизируется, шагая на %s: без ферзей ему почти ничего не грозит.", "король на %s ближе к центру — эндшпиль зависит от активности короля."][v] % to_name + pawn_txt
			return "король переходит на %s: в эндшпиле каждый шаг короля — это ход по плану (к пешкам, на защиту или в атаку)." % to_name + pawn_txt
		if rel_to == 0 and _rel_rank(mv.from.y, color) == 0 and _tucked(before, color):
			return "король делает шаг по первой горизонтали на %s — профилактика: он уходит с линии возможных шахов, пока ферзи и ладьи на доске." % to_name
		if not _tucked(before, color) and _has_queen(before, opp):
			return "король идёт на %s сам, не рокируясь, пока у соперника есть ферзь, — это риск: в центре его легче атаковать." % to_name
		return "король переходит на %s; опасных атакующих фигур рядом нет, поэтому риска немного." % to_name

	# --- ферзь ---
	if ptype == "Q":
		var ek := _king_sq(after, opp)
		if ek.x >= 0 and _cheb(mv.to, ek) <= 3 and _cheb(mv.from, ek) > 3:
			return "ферзь подходит к королю соперника — на %s он уже участвует в атаке на короля." % to_name
		var mob_q := _mobility(after, mv.to.x, mv.to.y)
		var mob_q0 := _mobility(before, mv.from.x, mv.from.y)
		if mob_q - mob_q0 >= 4:
			return "ферзь на %s стал заметно активнее: %s вместо %d." % [to_name, _kl(mob_q), mob_q0]
		if ply <= 14 and start_sqs.has(mv.from):
			return "ферзь выходит рано, на %s — обычно с этим не спешат." % to_name
		return ["ферзь перемещается на %s, усиливая давление в этой части доски.", "ферзь занимает %s — отсюда он контролирует %s.", "ферзь идёт на %s, перестраивая давление."][v] % ([to_name] if v != 1 else [to_name, _kl(mob_q)])

	# --- конь / слон: активность и форпосты ---
	if ptype == "N" and _is_outpost(after, mv.to.x, mv.to.y, color):
		return "конь занимает форпост на %s: пешка защищает его, чужие пешки уже не могут его выбить — такая фигура может годами давить на соперника." % to_name
	if ptype == "N" and mv.to.x in [0, 7]:
		return "конь уходит на край доски (%s) — там он контролирует всего %s, обычно это плохое место." % [to_name, _kl(_mobility(after, mv.to.x, mv.to.y))]
	if ptype == "N" or ptype == "B" or ptype == "R":
		var m1 := _mobility(after, mv.to.x, mv.to.y)
		var m0 := _mobility(before, mv.from.x, mv.from.y)
		if m1 - m0 >= 3:
			return "%s становится активнее: на %s %s контролирует %s вместо %d." % [_cap(piece), to_name, _g(ptype, "он", "она"), _kl(m1), m0]
		if m0 - m1 >= 3:
			return "%s отступает на %s и теряет активность: %s вместо %d — ход, скорее всего, вынужденный или оборонительный." % [_cap(piece), to_name, _kl(m1), m0]
		match ptype:
			"N":
				return ["конь перебирается на %s, нацеливаясь на новые поля.", "конь идёт на %s — перегруппировка сил без потери активности.", "конь на %s: он готовится к прыжку в атаку или к защите слабого поля."][v] % to_name
			"B":
				return ["слон меняет диагональ, нацеливаясь на %s.", "слон перебирается на %s — новая диагональ, новые цели.", "слон идёт на %s, перестраивая давление."][v] % to_name
			"R":
				return ["ладья переходит на %s, готовясь подключиться к игре по этой линии.", "ладья идёт на %s — она ищет открытую линию.", "ладья на %s: перестройка тяжёлых фигур."][v] % to_name
	return "%s переходит на %s." % [_cap(piece), to_name]

# Основной вход: основной текст + предупреждение, если сходившая фигура осталась
# без защиты под ударом (либо жертва, либо расчёт — стоит присмотреться).
static func explain(before: ChessEngine, after: ChessEngine, mv: Dictionary, ply: int) -> String:
	var text := _explain_core(before, after, mv, ply)
	var p = before.board[mv.from.y][mv.from.x]
	if p == null or p.type == "K" or str(mv.get("promo", "")) != "":
		return text
	if before.board[mv.to.y][mv.to.x] != null or mv.get("is_ep", false):
		return text
	var color: String = p.color
	if after.is_square_attacked(mv.to.x, mv.to.y, _opp(color)) and not after.is_square_attacked(mv.to.x, mv.to.y, color):
		text += " %s на %s осталась без защиты под ударом — это жертва или расчёт, стоит присмотреться." % [_cap(PIECE_RU.get(p.type, "фигура")), _sq(mv.to)] if p.type in ["P", "R"] else " %s на %s остался без защиты под ударом — это жертва или расчёт, стоит присмотреться." % [_cap(PIECE_RU.get(p.type, "фигура")), _sq(mv.to)]
	return text
