extends RefCounted

# Быстрое ядро поиска для ChessAI. Не заменяет ChessEngine (тот остаётся
# «источником правды» для игры, UI и генераторов задач) — это отдельное
# компактное представление позиции только для перебора:
#   - плоская доска из 64 целых (без словарей и клонирования),
#   - ходы делаются и откатываются на месте (make/unmake),
#   - оценка «материал + PST» считается инкрементально,
#   - таблица позиций (TT), итеративное углубление, killer/history,
#   - лимит времени: если глубина не успела — берём ход прошлой итерации.
# Оценка и правила ничьей повторяют старый ChessAI, поэтому сила уровней
# сохраняется, а ход считается на порядки быстрее.
#
# Кодировка: клетка = rank*8 + file (a1 = 0). Фигура = тип | (8 если чёрная),
# тип: P=1 N=2 B=3 R=4 Q=5 K=6. Ход = from | to<<6 | promo<<12 | flags<<16,
# flags: 1 = взятие на проходе, 2 = короткая рокировка, 4 = длинная, 8 = двойной ход пешки.
# Превращение только в ферзя — как и в ChessEngine.legal_moves().

const INF := 1000000
const MATE := 100000
const VAL := [0, 100, 320, 330, 500, 900, 0]
const TYPE_CODE := {"P": 1, "N": 2, "B": 3, "R": 4, "Q": 5, "K": 6}
# вес фигуры для «фазы партии»: 24 = все фигуры на доске (дебют), 0 = только короли и пешки
const PHASE_W := [0, 0, 1, 1, 2, 4, 0]
# расстояние клетки до центра доски (0 — центр, 6 — угол): для загона короля в эндшпиле
# превращение: ферзь первым, затем ладья, слон, конь
const PROMOS := [5, 4, 3, 2]
const TYPE_LETTER := {"p": 1, "n": 2, "b": 3, "r": 4, "q": 5, "k": 6}

# --- общие статические таблицы (строятся один раз при загрузке скрипта) ---
static var T: Dictionary = _build_static()

static func _build_static() -> Dictionary:
	var rays: Array = []
	var dirs := [[0, 1], [0, -1], [1, 0], [-1, 0], [1, 1], [-1, 1], [1, -1], [-1, -1]]
	var knight: Array = []
	var king: Array = []
	var kd := [[1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]]
	for sq in range(64):
		var f: int = sq & 7
		var r: int = sq >> 3
		for d in dirs:
			var ray := PackedInt32Array()
			var nf: int = f + d[0]
			var nr: int = r + d[1]
			while nf >= 0 and nf < 8 and nr >= 0 and nr < 8:
				ray.append(nr * 8 + nf)
				nf += d[0]
				nr += d[1]
			rays.append(ray)
		var kn := PackedInt32Array()
		for d in kd:
			var nf2: int = f + d[0]
			var nr2: int = r + d[1]
			if nf2 >= 0 and nf2 < 8 and nr2 >= 0 and nr2 < 8:
				kn.append(nr2 * 8 + nf2)
		knight.append(kn)
		var kg := PackedInt32Array()
		for d in dirs:
			var nf3: int = f + d[0]
			var nr3: int = r + d[1]
			if nf3 >= 0 and nf3 < 8 and nr3 >= 0 and nr3 < 8:
				kg.append(nr3 * 8 + nf3)
		king.append(kg)
	# клетки, с которых пешка цвета c бьёт клетку sq
	var pawn_src: Array = []
	for c in range(2):
		for sq in range(64):
			var src := PackedInt32Array()
			var f: int = sq & 7
			var r: int = sq >> 3
			var pr: int = r - (1 if c == 0 else -1)
			if pr >= 0 and pr < 8:
				if f > 0:
					src.append(pr * 8 + f - 1)
				if f < 7:
					src.append(pr * 8 + f + 1)
			pawn_src.append(src)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260930
	var zp := PackedInt64Array()
	zp.resize(16 * 64)
	for i in range(16 * 64):
		zp[i] = (rng.randi() << 32) | rng.randi()
	var zc := PackedInt64Array()
	zc.resize(16)
	for i in range(16):
		zc[i] = (rng.randi() << 32) | rng.randi()
	var ze := PackedInt64Array()
	ze.resize(64)
	for i in range(64):
		ze[i] = (rng.randi() << 32) | rng.randi()
	var cmask := PackedInt32Array()
	cmask.resize(64)
	cmask.fill(15)
	cmask[0] = 13
	cmask[4] = 12
	cmask[7] = 14
	cmask[56] = 7
	cmask[60] = 3
	cmask[63] = 11
	var cdist := PackedInt32Array()
	cdist.resize(64)
	for sq in range(64):
		var cf: int = sq & 7
		var cr: int = sq >> 3
		cdist[sq] = maxi(3 - cf, cf - 4) + maxi(3 - cr, cr - 4)
	return {
		"cdist": cdist, "rays": rays, "knight": knight, "king": king, "pawn_src": pawn_src,
		"zp": zp, "zc": zc, "ze": ze, "zs": (rng.randi() << 32) | rng.randi(),
		"cmask": cmask,
	}

# --- состояние позиции ---
var b := PackedInt32Array()
var side: int = 0
var castle: int = 0
var ep: int = -1
var half: int = 0
var hash: int = 0
var score: int = 0        # оценка с точки зрения белых (миттельшпиль)
var score_eg: int = 0     # то же по таблицам эндшпиля
var phase: int = 0        # 24 — все фигуры, 0 — только короли и пешки
var nk: int = 0           # число фигур кроме королей
var ksq := PackedInt32Array([0, 0])

# --- стек отката ---
var sp: int = 0
var u_cap := PackedInt32Array()
var u_cas := PackedInt32Array()
var u_ep := PackedInt32Array()
var u_half := PackedInt32Array()
var u_hash := PackedInt64Array()
var u_score := PackedInt32Array()
var u_score_eg := PackedInt32Array()
var u_phase := PackedInt32Array()
var u_nk := PackedInt32Array()
var hist := PackedInt64Array()
var hist_n: int = 0

# --- параметры поиска ---
var pst := PackedInt32Array()
var pst_eg := PackedInt32Array()
var _cdist: PackedInt32Array
var qdepth: int = 0
var fifty_rule: bool = false
var tt := {}
var killers := PackedInt32Array()
var history := PackedInt32Array()
var nodes: int = 0
var deadline: int = 0
var aborted: bool = false

var _rays: Array
var _knight: Array
var _king: Array
var _pawn_src: Array
var _zp: PackedInt64Array
var _zc: PackedInt64Array
var _ze: PackedInt64Array
var _zs: int
var _cmask: PackedInt32Array

# tables: массив из 6 массивов по 64 значения (P N B R Q K), как PAWN_PST… в ChessAI:
# индекс ((7 - rank) * 8 + file) для белых и (rank * 8 + file) для чёрных.
func _init(tables: Array, quiescence_depth: int = 0) -> void:
	_rays = T.rays
	_knight = T.knight
	_king = T.king
	_pawn_src = T.pawn_src
	_zp = T.zp
	_zc = T.zc
	_ze = T.ze
	_zs = T.zs
	_cmask = T.cmask
	_cdist = T.cdist
	qdepth = quiescence_depth
	b.resize(64)
	var n := 320
	u_cap.resize(n)
	u_cas.resize(n)
	u_ep.resize(n)
	u_half.resize(n)
	u_hash.resize(n)
	u_score.resize(n)
	u_score_eg.resize(n)
	u_phase.resize(n)
	u_nk.resize(n)
	killers.resize(n * 2)
	history.resize(4096)
	pst.resize(16 * 64)
	pst_eg.resize(16 * 64)
	# tables: P N B R Q K (миттельшпиль), затем король и пешка для эндшпиля
	for t in range(1, 7):
		var tab: Array = tables[t - 1]
		var tab_eg: Array = tab
		if t == 6:
			tab_eg = tables[6]
		elif t == 1:
			tab_eg = tables[7]
		for sq in range(64):
			var r: int = sq >> 3
			var f: int = sq & 7
			pst[t * 64 + sq] = VAL[t] + int(tab[(7 - r) * 8 + f])
			pst[(t + 8) * 64 + sq] = -(VAL[t] + int(tab[r * 8 + f]))
			pst_eg[t * 64 + sq] = VAL[t] + int(tab_eg[(7 - r) * 8 + f])
			pst_eg[(t + 8) * 64 + sq] = -(VAL[t] + int(tab_eg[r * 8 + f]))
	fifty_rule = Global.fifty_move_rule_enabled

# --- загрузка позиции из ChessEngine ---
func load_engine(e: ChessEngine, with_history: bool = true) -> void:
	b.fill(0)
	for r in range(8):
		for f in range(8):
			var p = e.board[r][f]
			if p != null:
				b[r * 8 + f] = int(TYPE_CODE[p.type]) | (8 if p.color == "b" else 0)
	side = 0 if e.side_to_move == "w" else 1
	castle = 0
	if e.castling.get("wk", false): castle |= 1
	if e.castling.get("wq", false): castle |= 2
	if e.castling.get("bk", false): castle |= 4
	if e.castling.get("bq", false): castle |= 8
	ep = -1
	if e.en_passant_target != null:
		ep = e.en_passant_target.y * 8 + e.en_passant_target.x
	half = e.halfmove_clock
	_recompute()
	sp = 0
	hist.resize(4)
	hist_n = 0
	if not with_history:
		hist[0] = hash
		hist_n = 1
		return
	# история позиций для повторов: только то, что после последнего необратимого хода
	var keys: Array = e.position_history
	var take: int = mini(half + 1, keys.size())
	hist.resize(take + 400)
	hist_n = 0
	for i in range(keys.size() - take, keys.size() - 1):
		hist[hist_n] = _hash_of_key(str(keys[i]))
		hist_n += 1
	hist[hist_n] = hash
	hist_n += 1
	sp = 0

func _recompute() -> void:
	hash = 0
	score = 0
	score_eg = 0
	phase = 0
	nk = 0
	for sq in range(64):
		var p: int = b[sq]
		if p == 0:
			continue
		hash ^= _zp[p * 64 + sq]
		score += pst[p * 64 + sq]
		score_eg += pst_eg[p * 64 + sq]
		phase += int(PHASE_W[p & 7])
		if (p & 7) == 6:
			ksq[p >> 3] = sq
		else:
			nk += 1
	if side == 1:
		hash ^= _zs
	hash ^= _zc[castle]
	if ep >= 0:
		hash ^= _ze[ep]

# хэш позиции из строки-ключа ChessEngine._position_key() (доска side castle ep)
func _hash_of_key(key: String) -> int:
	var parts := key.split(" ")
	var h: int = 0
	var rows := parts[0].split("/")
	for ri in range(8):
		var r: int = 7 - ri
		var f: int = 0
		for ch in rows[ri]:
			if ch.is_valid_int():
				f += ch.to_int()
			else:
				var lower: String = ch.to_lower()
				var code: int = int(TYPE_LETTER[lower]) | (0 if ch == ch.to_upper() else 8)
				h ^= _zp[code * 64 + r * 8 + f]
				f += 1
	if parts[1] == "b":
		h ^= _zs
	var cs: int = 0
	var cstr: String = parts[2]
	if cstr.contains("K"): cs |= 1
	if cstr.contains("Q"): cs |= 2
	if cstr.contains("k"): cs |= 4
	if cstr.contains("q"): cs |= 8
	h ^= _zc[cs]
	if parts[3] != "-":
		h ^= _ze[("abcdefgh".find(parts[3][0])) + (parts[3].substr(1).to_int() - 1) * 8]
	return h

# --- перевод ходов ---
static func encode(m: Dictionary, e: ChessEngine) -> int:
	var from: int = int(m.from.y) * 8 + int(m.from.x)
	var to: int = int(m.to.y) * 8 + int(m.to.x)
	var promo: int = 0
	if str(m.get("promo", "")) != "":
		promo = int(TYPE_CODE[str(m.promo)])
	var fl: int = 0
	if m.get("is_ep", false):
		fl |= 1
	var c: String = str(m.get("is_castle", ""))
	if c == "K":
		fl |= 2
	elif c == "Q":
		fl |= 4
	var p = e.board[int(m.from.y)][int(m.from.x)]
	if p != null and p.type == "P" and absi(int(m.to.y) - int(m.from.y)) == 2:
		fl |= 8
	return from | (to << 6) | (promo << 12) | (fl << 16)

# --- атаки ---
func attacked(sq: int, by: int) -> bool:
	var pawn: int = 1 | (by << 3)
	for s in _pawn_src[by * 64 + sq]:
		if b[s] == pawn:
			return true
	var kn: int = 2 | (by << 3)
	for s in _knight[sq]:
		if b[s] == kn:
			return true
	var kg: int = 6 | (by << 3)
	for s in _king[sq]:
		if b[s] == kg:
			return true
	var bq_b: int = 3 | (by << 3)
	var q: int = 5 | (by << 3)
	var rk: int = 4 | (by << 3)
	for d in range(4, 8):
		for s in _rays[sq * 8 + d]:
			var p: int = b[s]
			if p != 0:
				if p == bq_b or p == q:
					return true
				break
	for d in range(0, 4):
		for s in _rays[sq * 8 + d]:
			var p2: int = b[s]
			if p2 != 0:
				if p2 == rk or p2 == q:
					return true
				break
	return false

# --- генерация псевдолегальных ходов ---
func gen(caps_only: bool) -> PackedInt32Array:
	var out := PackedInt32Array()
	var s: int = side
	var opp: int = 1 - s
	for sq in range(64):
		var p: int = b[sq]
		if p == 0 or (p >> 3) != s:
			continue
		var t: int = p & 7
		if t == 1:
			var r: int = sq >> 3
			var f: int = sq & 7
			var d8: int = 8 if s == 0 else -8
			var promo_rank: int = 7 if s == 0 else 0
			var to1: int = sq + d8
			for df in [-1, 1]:
				var nf: int = f + df
				if nf < 0 or nf > 7:
					continue
				var to: int = to1 + df
				var tg: int = b[to]
				if tg != 0 and (tg >> 3) != s:
					if (to >> 3) == promo_rank:
						for pr in PROMOS:
							out.append(sq | (to << 6) | (pr << 12))
					else:
						out.append(sq | (to << 6))
				elif to == ep:
					out.append(sq | (to << 6) | (1 << 16))
			if not caps_only and b[to1] == 0:
				if (to1 >> 3) == promo_rank:
					for pr in PROMOS:
						out.append(sq | (to1 << 6) | (pr << 12))
				else:
					out.append(sq | (to1 << 6))
				var start: int = 1 if s == 0 else 6
				if r == start and b[to1 + d8] == 0:
					out.append(sq | ((to1 + d8) << 6) | (8 << 16))
		elif t == 2:
			for to in _knight[sq]:
				var tg2: int = b[to]
				if tg2 == 0:
					if not caps_only:
						out.append(sq | (to << 6))
				elif (tg2 >> 3) != s:
					out.append(sq | (to << 6))
		elif t == 6:
			for to in _king[sq]:
				var tg3: int = b[to]
				if tg3 == 0:
					if not caps_only:
						out.append(sq | (to << 6))
				elif (tg3 >> 3) != s:
					out.append(sq | (to << 6))
			if not caps_only:
				var home: int = 0 if s == 0 else 56
				if sq == home + 4:
					if (castle & (1 if s == 0 else 4)) != 0 and b[home + 5] == 0 and b[home + 6] == 0:
						if not attacked(home + 4, opp) and not attacked(home + 5, opp) and not attacked(home + 6, opp):
							out.append(sq | ((home + 6) << 6) | (2 << 16))
					if (castle & (2 if s == 0 else 8)) != 0 and b[home + 3] == 0 and b[home + 2] == 0 and b[home + 1] == 0:
						if not attacked(home + 4, opp) and not attacked(home + 3, opp) and not attacked(home + 2, opp):
							out.append(sq | ((home + 2) << 6) | (4 << 16))
		else:
			var d0: int = 4 if t == 3 else 0
			var d1: int = 4 if t == 4 else 8
			for d in range(d0, d1):
				for to in _rays[sq * 8 + d]:
					var tg4: int = b[to]
					if tg4 == 0:
						if not caps_only:
							out.append(sq | (to << 6))
					else:
						if (tg4 >> 3) != s:
							out.append(sq | (to << 6))
						break
	return out

# --- сделать / откатить ход ---
func make(m: int) -> void:
	var from: int = m & 63
	var to: int = (m >> 6) & 63
	var promo: int = (m >> 12) & 15
	var fl: int = m >> 16
	var p: int = b[from]
	var cap: int = b[to]
	var d: int = sp
	var col: int = p >> 3
	u_cas[d] = castle
	u_ep[d] = ep
	u_half[d] = half
	u_hash[d] = hash
	u_score[d] = score
	u_score_eg[d] = score_eg
	u_phase[d] = phase
	u_nk[d] = nk
	var h: int = hash ^ _zs ^ _zc[castle]
	if ep >= 0:
		h ^= _ze[ep]
	var sc: int = score
	var sce: int = score_eg
	var ph: int = phase
	b[from] = 0
	h ^= _zp[p * 64 + from]
	sc -= pst[p * 64 + from]
	sce -= pst_eg[p * 64 + from]
	if (fl & 1) != 0:
		var csq: int = to - 8 if col == 0 else to + 8
		cap = b[csq]
		b[csq] = 0
		h ^= _zp[cap * 64 + csq]
		sc -= pst[cap * 64 + csq]
		sce -= pst_eg[cap * 64 + csq]
		ph -= int(PHASE_W[cap & 7])
		nk -= 1
	elif cap != 0:
		h ^= _zp[cap * 64 + to]
		sc -= pst[cap * 64 + to]
		sce -= pst_eg[cap * 64 + to]
		ph -= int(PHASE_W[cap & 7])
		nk -= 1
	u_cap[d] = cap
	var np: int = p
	if promo != 0:
		np = promo | (col << 3)
	b[to] = np
	h ^= _zp[np * 64 + to]
	sc += pst[np * 64 + to]
	sce += pst_eg[np * 64 + to]
	if promo != 0:
		ph += int(PHASE_W[promo])
	if (fl & 6) != 0:
		var rf: int
		var rt: int
		if (fl & 2) != 0:
			rf = to + 1
			rt = to - 1
		else:
			rf = to - 2
			rt = to + 1
		var rook: int = b[rf]
		b[rf] = 0
		b[rt] = rook
		h ^= _zp[rook * 64 + rf] ^ _zp[rook * 64 + rt]
		sc += pst[rook * 64 + rt] - pst[rook * 64 + rf]
		sce += pst_eg[rook * 64 + rt] - pst_eg[rook * 64 + rf]
	if (p & 7) == 6:
		ksq[col] = to
	castle = castle & _cmask[from] & _cmask[to]
	if (fl & 8) != 0:
		ep = (from + to) >> 1
	else:
		ep = -1
	h ^= _zc[castle]
	if ep >= 0:
		h ^= _ze[ep]
	if (p & 7) == 1 or cap != 0:
		half = 0
	else:
		half += 1
	hash = h
	score = sc
	score_eg = sce
	phase = ph
	side = 1 - side
	sp += 1
	hist[hist_n] = hash
	hist_n += 1

func unmake(m: int) -> void:
	sp -= 1
	hist_n -= 1
	var d: int = sp
	var from: int = m & 63
	var to: int = (m >> 6) & 63
	var promo: int = (m >> 12) & 15
	var fl: int = m >> 16
	side = 1 - side
	var moved: int = b[to]
	if promo != 0:
		moved = 1 | ((moved >> 3) << 3)
	var cap: int = u_cap[d]
	b[from] = moved
	if (fl & 1) != 0:
		b[to] = 0
		var col: int = moved >> 3
		b[to - 8 if col == 0 else to + 8] = cap
	else:
		b[to] = cap
	if (fl & 6) != 0:
		var rf: int
		var rt: int
		if (fl & 2) != 0:
			rf = to + 1
			rt = to - 1
		else:
			rf = to - 2
			rt = to + 1
		b[rf] = b[rt]
		b[rt] = 0
	if (moved & 7) == 6:
		ksq[moved >> 3] = from
	castle = u_cas[d]
	ep = u_ep[d]
	half = u_half[d]
	hash = u_hash[d]
	score = u_score[d]
	score_eg = u_score_eg[d]
	phase = u_phase[d]
	nk = u_nk[d]

func in_check() -> bool:
	return attacked(ksq[side], 1 - side)

# после make(): ходивший король под боем — ход нелегален
func _illegal_after_make() -> bool:
	return attacked(ksq[1 - side], side)

# --- ничья по правилам ---
func is_draw() -> bool:
	if fifty_rule and half >= 100:
		return true
	if nk <= 2 and _insufficient():
		return true
	var count: int = 0
	var i: int = hist_n - 3
	var steps: int = 2
	while i >= 0 and steps <= half:
		if hist[i] == hash:
			count += 1
			if count >= 2:
				return true
		i -= 2
		steps += 2
	return false

func _insufficient() -> bool:
	var first: int = 0
	var second: int = 0
	var s1: int = 0
	var s2: int = 0
	var n: int = 0
	for sq in range(64):
		var p: int = b[sq]
		if p != 0 and (p & 7) != 6:
			n += 1
			if n == 1:
				first = p
				s1 = sq
			else:
				second = p
				s2 = sq
	if n == 0:
		return true
	if n == 1:
		var t: int = first & 7
		return t == 2 or t == 3
	if n == 2 and (first & 7) == 3 and (second & 7) == 3 and (first >> 3) != (second >> 3):
		return ((s1 >> 3) + (s1 & 7)) % 2 == ((s2 >> 3) + (s2 & 7)) % 2
	return false

# Оценка с точки зрения белых: между таблицами миттельшпиля и эндшпиля — по фазе
# (число оставшихся фигур), плюс в чистом эндшпиле бонус за загон короля слабой
# стороны к краю и приближение своего короля — без него ИИ не умеет ставить мат
# ладьёй или ферзём против голого короля.
@warning_ignore("integer_division")
func eval_white() -> int:
	var ph: int = mini(phase, 24)
	var e: int = (score * ph + score_eg * (24 - ph)) / 24
	if ph <= 6 and absi(e) >= 250:
		var win: int = 0 if e > 0 else 1
		var lose_k: int = ksq[1 - win]
		var win_k: int = ksq[win]
		var kd: int = absi((lose_k & 7) - (win_k & 7)) + absi((lose_k >> 3) - (win_k >> 3))
		var bonus: int = _cdist[lose_k] * 10 + (14 - kd) * 4
		e += bonus if win == 0 else -bonus
	return e

func _eval_side() -> int:
	var e: int = eval_white()
	return e if side == 0 else -e

# --- порядок ходов ---
func _order_scores(moves: PackedInt32Array, tt_move: int, ply: int) -> PackedInt32Array:
	var sc := PackedInt32Array()
	sc.resize(moves.size())
	var k1: int = killers[ply * 2]
	var k2: int = killers[ply * 2 + 1]
	for i in range(moves.size()):
		var m: int = moves[i]
		var mv: int = m & 0xFFFFF
		if mv == tt_move:
			sc[i] = 10000000
			continue
		var to: int = (m >> 6) & 63
		var cap: int = b[to]
		var s: int = 0
		if cap != 0:
			s = 100000 + (cap & 7) * 16 - (b[m & 63] & 7)
		elif (m >> 16) & 1:
			s = 100000 + 16 - 1
		elif ((m >> 12) & 15) != 0:
			s = 90000 if ((m >> 12) & 15) == 5 else 1
		elif mv == k1:
			s = 80000
		elif mv == k2:
			s = 70000
		else:
			s = history[(m & 63) * 64 + to]
		sc[i] = s
	return sc

func _pick(moves: PackedInt32Array, sc: PackedInt32Array, i: int) -> int:
	var best: int = i
	var bs: int = sc[i]
	for j in range(i + 1, moves.size()):
		if sc[j] > bs:
			bs = sc[j]
			best = j
	if best != i:
		var tm: int = moves[i]
		moves[i] = moves[best]
		moves[best] = tm
		var ts: int = sc[i]
		sc[i] = sc[best]
		sc[best] = ts
	return moves[i]

# --- поиск ---
func negamax(depth: int, alpha: int, beta: int, ply: int) -> int:
	nodes += 1
	if deadline > 0 and (nodes & 1023) == 0 and Time.get_ticks_msec() > deadline:
		aborted = true
	if aborted:
		return 0
	if is_draw():
		return 0
	if depth <= 0:
		if qdepth > 0:
			return qsearch(alpha, beta, qdepth, ply)
		# без поиска взятий (уровни 1–10) горизонт сам не видел мата: оценка шла по материалу,
		# и мат в 1 находился только случайно. Под шахом проверяем, есть ли ещё ходы.
		if in_check() and not _has_legal_move():
			return -MATE
		return _eval_side()
	if ply >= 150:
		return _eval_side()
	var alpha0: int = alpha
	var tt_move: int = 0
	var e: int = tt.get(hash, -1)
	if e != -1:
		tt_move = e & 0xFFFFF
		if ((e >> 22) & 255) >= depth:
			var flag: int = (e >> 20) & 3
			var sc0: int = (e >> 30) - 200000
			if flag == 0:
				return sc0
			if flag == 1:
				alpha = maxi(alpha, sc0)
			else:
				beta = mini(beta, sc0)
			if alpha >= beta:
				return sc0
	var moves := gen(false)
	var scores := _order_scores(moves, tt_move, ply)
	var legal: int = 0
	var best: int = -INF
	var best_move: int = 0
	for i in range(moves.size()):
		var m: int = _pick(moves, scores, i)
		make(m)
		if _illegal_after_make():
			unmake(m)
			continue
		legal += 1
		var s: int = -negamax(depth - 1, -beta, -alpha, ply + 1)
		unmake(m)
		if aborted:
			return 0
		if s > best:
			best = s
			best_move = m & 0xFFFFF
			if s > alpha:
				alpha = s
				if alpha >= beta:
					if b[(m >> 6) & 63] == 0 and ((m >> 16) & 1) == 0:
						var mv: int = m & 0xFFFFF
						if killers[ply * 2] != mv:
							killers[ply * 2 + 1] = killers[ply * 2]
							killers[ply * 2] = mv
						var hi: int = (m & 63) * 64 + ((m >> 6) & 63)
						history[hi] = mini(history[hi] + depth * depth, 60000)
					break
	if legal == 0:
		if in_check():
			return -MATE - depth
		return 0
	var flag2: int = 0
	if best <= alpha0:
		flag2 = 2
	elif best >= beta:
		flag2 = 1
	tt[hash] = best_move | (flag2 << 20) | (mini(depth, 255) << 22) | ((best + 200000) << 30)
	return best

func _has_legal_move() -> bool:
	var moves := gen(false)
	for i in range(moves.size()):
		var m: int = moves[i]
		make(m)
		var ok: bool = not _illegal_after_make()
		unmake(m)
		if ok:
			return true
	return false

func qsearch(alpha: int, beta: int, qd: int, ply: int) -> int:
	nodes += 1
	if deadline > 0 and (nodes & 1023) == 0 and Time.get_ticks_msec() > deadline:
		aborted = true
	if aborted:
		return 0
	if is_draw():
		return 0
	var chk: bool = in_check()
	var stand: int = _eval_side()
	if ply >= 150:
		return stand
	if not chk:
		if qd <= 0 or stand >= beta:
			return stand
		if stand > alpha:
			alpha = stand
	var moves := gen(not chk)
	var scores := _order_scores(moves, 0, ply)
	var legal: int = 0
	for i in range(moves.size()):
		var m: int = _pick(moves, scores, i)
		make(m)
		if _illegal_after_make():
			unmake(m)
			continue
		legal += 1
		var s: int = -qsearch(-beta, -alpha, qd - 1, ply + 1)
		unmake(m)
		if aborted:
			return 0
		if s >= beta:
			return s
		if s > alpha:
			alpha = s
	if chk and legal == 0:
		return -MATE
	return alpha

# Выбор хода среди корневых (уже легальных) ходов — индекс в root.
# noise: шум оценки последней итерации (как у старого ChessAI), rng — генератор.
# budget_ms <= 0 — без лимита времени.
func choose(root: PackedInt32Array, target_depth: int, noise: float, rng: RandomNumberGenerator, budget_ms: int) -> int:
	if root.size() <= 1:
		return 0
	# выигранный эндшпиль с подавляющим перевесом: шум оценки (10–130 сп) больше, чем шаг
	# «загнать короля к краю» (10 сп), и ИИ бродил без плана — здесь шум отключаем
	if phase <= 6 and absi(eval_white()) >= 250:
		noise = 0.0
	deadline = Time.get_ticks_msec() + budget_ms if budget_ms > 0 else 0
	aborted = false
	nodes = 0
	tt.clear()
	killers.fill(0)
	history.fill(0)
	var order := PackedInt32Array()
	for i in range(root.size()):
		order.append(i)
	# первичный порядок: взятия вперёд
	var pre := PackedInt32Array()
	for i in range(root.size()):
		pre.append(root[i])
	var pscores := _order_scores(pre, 0, 0)
	var idx_sorted: Array = range(root.size())
	idx_sorted.sort_custom(func(x, y): return pscores[x] > pscores[y])
	for i in range(root.size()):
		order[i] = idx_sorted[i]
	var best_i: int = order[0]
	return _choose_iter(root, order, best_i, target_depth, noise, rng)

func _choose_iter(root: PackedInt32Array, order: PackedInt32Array, best_start: int, target_depth: int, noise: float, rng: RandomNumberGenerator) -> int:
	var best_i: int = best_start
	for d in range(1, target_depth + 1):
		var last: bool = d == target_depth
		# С шумом последняя итерация считает ТОЧНУЮ оценку каждого хода (окно не сужается):
		# иначе у «неудачных» ходов возвращается лишь граница, и шум выбирал среди них почти
		# наугад — из-за этого уровень 11 (шум 2) проигрывал 10-му 23 партии из 24.
		var exact: bool = last and noise > 0.0
		var alpha: int = -INF
		var iter_best: int = -1
		var iter_score: float = -1.0e9
		var best_true: int = -INF
		for k in range(order.size()):
			var i: int = order[k]
			# ход, чья настоящая оценка хуже лучшей больше чем на 2·шум, не сможет её обогнать
			# даже с шумом, — таким считать точно не нужно (сильно ускоряет слабые уровни)
			var win_alpha: int = alpha
			if exact and best_true > -INF:
				win_alpha = best_true - int(2.0 * noise) - 1
			make(root[i])
			var s: int = -negamax(d - 1, -INF, -win_alpha, 1)
			unmake(root[i])
			if aborted:
				break
			if exact and best_true > -INF and s <= win_alpha:
				continue
			if exact:
				best_true = maxi(best_true, s)
			var sf: float = float(s)
			if exact:
				sf += rng.randf_range(-noise, noise)
			if sf > iter_score:
				iter_score = sf
				iter_best = i
			if not exact:
				alpha = maxi(alpha, int(sf))
		if aborted or iter_best < 0:
			break
		best_i = iter_best
		# лучший ход прошлой итерации — первым в следующей
		var pos: int = order.find(best_i)
		if pos > 0:
			order.remove_at(pos)
			order.insert(0, best_i)
	return best_i

# Оценка каждого корневого хода без шума и лимита — для best_move_clean / move_loss.
# Возвращает лучший индекс; если played >= 0 — работает как move_loss (см. ChessAI).
func best_clean(root: PackedInt32Array, depth: int) -> int:
	deadline = 0
	aborted = false
	tt.clear()
	killers.fill(0)
	history.fill(0)
	var pre := PackedInt32Array()
	for i in range(root.size()):
		pre.append(root[i])
	var pscores := _order_scores(pre, 0, 0)
	var idx_sorted: Array = range(root.size())
	idx_sorted.sort_custom(func(x, y): return pscores[x] > pscores[y])
	var best_i: int = idx_sorted[0]
	var best_s: int = -INF
	var alpha: int = -INF
	for i in idx_sorted:
		make(root[i])
		var s: int = -negamax(depth - 1, -INF, -alpha, 1)
		unmake(root[i])
		if s > best_s:
			best_s = s
			best_i = i
		alpha = maxi(alpha, s)
	return best_i

# сколько сантипешек хуже сыгранный ход лучшего (0 — лучший)
func move_loss(root: PackedInt32Array, played: int, depth: int) -> int:
	deadline = 0
	aborted = false
	tt.clear()
	killers.fill(0)
	history.fill(0)
	make(root[played])
	var played_score: int = -negamax(depth - 1, -INF, INF, 1)
	unmake(root[played])
	var best_score: int = played_score
	var alpha: int = played_score
	for i in range(root.size()):
		if i == played:
			continue
		make(root[i])
		var s: int = -negamax(depth - 1, -INF, -alpha, 1)
		unmake(root[i])
		if s > best_score:
			best_score = s
		alpha = maxi(alpha, s)
	return best_score - played_score
