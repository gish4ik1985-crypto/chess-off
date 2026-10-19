class_name GameRecord
extends RefCounted

# Запись партии: ход в стандартной нотации (SAN), разбор записи, PGN (импорт и экспорт).
# Понимает и русские обозначения фигур (Кр, Ф, Л, С, К), и ходы вида «e2e4».

const START_FEN := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
const LETTERS := {"K": "K", "Q": "Q", "R": "R", "B": "B", "N": "N"}

# ---------------------------------------------------------------- SAN

static func san(eng: ChessEngine, m: Dictionary) -> String:
	var p = eng.board[m.from.y][m.from.x]
	var out := ""
	var castle := String(m.get("is_castle", ""))
	if castle == "K":
		out = "O-O"
	elif castle == "Q":
		out = "O-O-O"
	else:
		var capture: bool = eng.board[m.to.y][m.to.x] != null or bool(m.get("is_ep", false))
		if p.type == "P":
			if capture:
				out = char(97 + m.from.x)
		else:
			out = String(p.type)
			# уточнение, если так же может сходить другая такая фигура
			var same_file := false
			var same_rank := false
			var ambiguous := false
			for o in eng.legal_moves(eng.side_to_move):
				if o.to == m.to and o.from != m.from:
					var q = eng.board[o.from.y][o.from.x]
					if q.type == p.type:
						ambiguous = true
						if o.from.x == m.from.x:
							same_file = true
						if o.from.y == m.from.y:
							same_rank = true
			if ambiguous:
				if not same_file:
					out += char(97 + m.from.x)
				elif not same_rank:
					out += str(m.from.y + 1)
				else:
					out += BoardView.sq_name(m.from)
		if capture:
			out += "x"
		out += BoardView.sq_name(m.to)
		if String(m.get("promo", "")) != "":
			out += "=" + String(m.promo)
	var after := eng.clone()
	after.apply_move(m)
	if after.is_in_check(after.side_to_move):
		out += "#" if after.legal_moves(after.side_to_move).is_empty() else "+"
	return out

# Приводит запись хода к сравнимому виду: русские буквы → латиница, без знаков.
static func _norm(t: String) -> String:
	var s := t.strip_edges()
	s = s.replace("Кр", "K").replace("кр", "K")
	for pair in [["Ф", "Q"], ["Л", "R"], ["С", "B"], ["К", "N"], ["О", "O"], ["а", "a"], ["с", "c"], ["е", "e"], ["0", "O"]]:
		s = s.replace(pair[0], pair[1])
	for ch in ["x", "X", ":", "+", "#", "!", "?", "=", "-", "–", "—", " ", "×"]:
		s = s.replace(ch, "")
	return s

# Ищет допустимый ход по записи игрока. Возвращает {} если не нашёл или запись неоднозначна.
static func parse_move(eng: ChessEngine, text: String) -> Dictionary:
	var want := _norm(text)
	if want == "":
		return {}
	var legal := eng.legal_moves(eng.side_to_move)
	var found := {}
	var count := 0
	for m in legal:
		var cands := [_norm(san(eng, m)), _norm(BoardView.uci_of(m))]
		if String(m.get("promo", "")) == "Q":
			cands.append(_norm(BoardView.uci_of(m).substr(0, 4))) # e7e8 без буквы — ферзь
			cands.append(_norm(san(eng, m).replace("=Q", "")))
		# «O-O» и «OO» одинаково, без различия регистра у пешечных ходов
		if want in cands or want.to_lower() in cands.map(func(c): return String(c).to_lower()):
			if count == 0:
				found = m
			count += 1
			if count > 1 and not (String(m.get("promo", "")) != "" and BoardView.uci_of(m).substr(0, 4) == BoardView.uci_of(found).substr(0, 4)):
				return {}
	return found

# ---------------------------------------------------------------- PGN

# Разбирает PGN: {headers, sans, comments (по одному на ход, "" если нет), result}.
static func parse_pgn(text: String) -> Dictionary:
	var headers := {}
	var body := ""
	for line in text.replace("\r", "").split("\n"):
		var l: String = line.strip_edges()
		if l.begins_with("[") and l.ends_with("]") and l.contains("\""):
			var k := l.substr(1, l.find(" ") - 1)
			var v := l.substr(l.find("\"") + 1, l.rfind("\"") - l.find("\"") - 1)
			headers[k] = v
		elif not l.begins_with("%"):
			body += l + " "
	# комментарии {…} привязываем к предыдущему ходу, ; — до конца строки (уже склеено, поэтому не трогаем)
	var tokens: Array = []
	var i := 0
	var depth := 0
	var buf := ""
	while i < body.length():
		var c := body[i]
		if c == "{":
			if buf.strip_edges() != "":
				tokens.append(buf.strip_edges())
			buf = ""
			var j := body.find("}", i)
			if j < 0:
				j = body.length()
			tokens.append("{" + body.substr(i + 1, j - i - 1).strip_edges())
			i = j + 1
			continue
		if c == "(":
			depth += 1
		elif c == ")":
			depth = maxi(0, depth - 1)
		elif depth == 0:
			buf += c
		i += 1
	if buf.strip_edges() != "":
		tokens.append(buf.strip_edges())
	var sans: Array = []
	var comments: Array = []
	var result := String(headers.get("Result", "*"))
	for tk in tokens:
		var t := String(tk)
		if t.begins_with("{"):
			if not comments.is_empty():
				comments[comments.size() - 1] = (String(comments.back()) + " " + t.substr(1)).strip_edges()
			continue
		for w in t.split(" ", false):
			var word: String = w
			if word in ["1-0", "0-1", "1/2-1/2", "*"]:
				result = word
				continue
			if word.begins_with("$"):
				continue
			# «12.» «12...» «12.Nf3» → оставляем сам ход
			var k := 0
			while k < word.length() and (word[k].is_valid_int() or word[k] == "."):
				k += 1
			word = word.substr(k)
			if word == "":
				continue
			sans.append(word)
			comments.append("")
	return {"headers": headers, "sans": sans, "comments": comments, "result": result}

# Проигрывает ходы с начальной позиции; возвращает {ok, moves (uci), sans (стандартные), fens, bad (номер плохого хода или -1)}.
static func replay(sans: Array, start_fen: String = START_FEN) -> Dictionary:
	var eng := ChessEngine.new()
	eng.setup_from_fen(start_fen)
	var ucis: Array = []
	var norm_sans: Array = []
	var fens: Array = [eng.to_fen()]
	for i in range(sans.size()):
		var m := parse_move(eng, String(sans[i]))
		if m.is_empty():
			return {"ok": false, "moves": ucis, "sans": norm_sans, "fens": fens, "bad": i}
		norm_sans.append(san(eng, m))
		ucis.append(BoardView.uci_of(m))
		eng.apply_move(m)
		fens.append(eng.to_fen())
	return {"ok": true, "moves": ucis, "sans": norm_sans, "fens": fens, "bad": -1}

static func build_pgn(headers: Dictionary, sans: Array, comments: Array, result: String) -> String:
	var out := ""
	for k in ["Event", "Site", "Date", "Round", "White", "Black", "Result", "FEN", "SetUp"]:
		if k == "Result":
			out += "[Result \"%s\"]\n" % result
		elif headers.has(k) and String(headers[k]) != "":
			out += "[%s \"%s\"]\n" % [k, String(headers[k]).replace("\"", "'")]
	out += "\n"
	var parts: Array = []
	var start_black := String(headers.get("FEN", "")).contains(" b ")
	for i in range(sans.size()):
		var ply := i + (1 if start_black else 0)
		if ply % 2 == 0:
			parts.append("%d. %s" % [ply / 2 + 1, sans[i]])
		elif i == 0:
			parts.append("%d... %s" % [ply / 2 + 1, sans[i]])
		else:
			parts.append(String(sans[i]))
		if i < comments.size() and String(comments[i]) != "":
			parts.append("{%s}" % String(comments[i]).replace("}", ")"))
	parts.append(result)
	return out + " ".join(parts) + "\n"
