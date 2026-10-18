extends Node

# Облако школы на Firebase (бесплатный тариф Spark): общие аккаунты, таблица игроков с публичным
# рейтингом и приватная копия профиля, чтобы игрок мог зайти с другого компьютера.
# Всё идёт по обычному REST-протоколу Firebase (HTTPRequest), без JS-библиотек — работает и в
# браузере, и в приложении. Если в res://firebase_config.json не заполнены ключи, облако выключено,
# игра работает как раньше (только локально).
#
# Что видят другие игроки: ник, турнирный рейтинг, звание, число партий, кубки.
# Что остаётся только у владельца: полный профиль (статистика ходов, сильные и слабые стороны) —
# лежит в private/{uid}, и правила базы (firestore.rules) разрешают читать его только хозяину.
#
# Вход: ник + пароль. Firebase требует e-mail, поэтому из ника делается служебный адрес
# (хэш ника @ players.chess-off.app) — реальной почты у детей не нужно.

const CONFIG_PATH := "res://firebase_config.json"
const SESSION_PATH := "user://cloud.cfg"
const MAIL_DOMAIN := "players.chess-off.app"
const PUSH_DELAY := 20.0 # секунд между отправками профиля в облако
const MAX_PRIVATE_BYTES := 700000 # лимит документа Firestore ~1 МБ, а base64 раздувает на треть

var enabled := false
var signed_in := false
var nick := ""
var uid := ""
var _api_key := ""
var _project := ""
var _id_token := ""
var _refresh_token := ""
var _expires_at := 0.0
var _push_pending := false
var _pushing := false
var last_error := ""

func _ready() -> void:
	_load_config()
	if enabled:
		_restore_session()

func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	_api_key = String(data.get("apiKey", "")).strip_edges()
	_project = String(data.get("projectId", "")).strip_edges()
	enabled = _api_key != "" and _project != ""

# --- служебный адрес из ника -----------------------------------------------------------------

static func nick_key(n: String) -> String:
	return n.strip_edges().to_lower()

static func email_for(n: String) -> String:
	return "p" + nick_key(n).sha256_text().substr(0, 40) + "@" + MAIL_DOMAIN

# --- HTTP ----------------------------------------------------------------------------------------

# Возвращает {ok, code, data}. Не бросает ошибок: сеть может быть недоступна.
func _http(method: int, url: String, body: Variant = null, auth: bool = false, form: bool = false) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 15.0
	add_child(req)
	var headers := PackedStringArray()
	var payload := ""
	if form:
		headers.append("Content-Type: application/x-www-form-urlencoded")
		payload = String(body)
	elif body != null:
		headers.append("Content-Type: application/json")
		payload = JSON.stringify(body)
	if auth:
		headers.append("Authorization: Bearer " + _id_token)
	var err := req.request(url, headers, method, payload)
	if err != OK:
		req.queue_free()
		return {"ok": false, "code": 0, "data": {}, "net": true}
	var res: Array = await req.request_completed
	req.queue_free()
	var code := int(res[1])
	var text := (res[3] as PackedByteArray).get_string_from_utf8()
	var parsed = JSON.parse_string(text) if text != "" else {}
	var raw = parsed # runQuery отвечает массивом, остальные запросы — словарём
	if typeof(parsed) != TYPE_DICTIONARY:
		parsed = {}
	return {"ok": code >= 200 and code < 300, "code": code, "data": parsed, "raw": raw, "net": int(res[0]) != HTTPRequest.RESULT_SUCCESS}

func _friendly(r: Dictionary) -> String:
	if r.get("net", false) or int(r.code) == 0:
		return "Нет связи с облаком. Проверьте интернет."
	var msg := String(r.data.get("error", {}).get("message", ""))
	if msg.begins_with("EMAIL_EXISTS"):
		return "Такой ник уже занят. Выберите другой или войдите."
	if msg.begins_with("INVALID_LOGIN_CREDENTIALS") or msg.begins_with("INVALID_PASSWORD") or msg.begins_with("EMAIL_NOT_FOUND"):
		return "Неверный ник или пароль."
	if msg.begins_with("WEAK_PASSWORD"):
		return "Пароль слишком простой — минимум 6 символов."
	if msg.begins_with("TOO_MANY_ATTEMPTS"):
		return "Слишком много попыток. Подождите немного."
	if msg.begins_with("PERMISSION_DENIED") or int(r.code) == 403:
		return "Нет доступа. Проверьте правила базы (firestore.rules)."
	return "Ошибка облака (%d). %s" % [int(r.code), msg]

# --- аккаунт --------------------------------------------------------------------------------------

func _auth(endpoint: String, n: String, password: String) -> Dictionary:
	var url := "https://identitytoolkit.googleapis.com/v1/accounts:%s?key=%s" % [endpoint, _api_key]
	var r := await _http(HTTPClient.METHOD_POST, url,
		{"email": email_for(n), "password": password, "returnSecureToken": true})
	if not r.ok:
		return {"ok": false, "error": _friendly(r)}
	_take_tokens(r.data)
	nick = n.strip_edges()
	signed_in = true
	_save_session()
	return {"ok": true, "error": ""}

func register(n: String, password: String) -> Dictionary:
	if not enabled:
		return {"ok": false, "error": "Облако не настроено."}
	return await _auth("signUp", n, password)

func login(n: String, password: String) -> Dictionary:
	if not enabled:
		return {"ok": false, "error": "Облако не настроено."}
	return await _auth("signInWithPassword", n, password)

func logout() -> void:
	signed_in = false
	_id_token = ""
	_refresh_token = ""
	uid = ""
	nick = ""
	DirAccess.remove_absolute(SESSION_PATH)

func _take_tokens(d: Dictionary) -> void:
	_id_token = String(d.get("idToken", d.get("id_token", "")))
	_refresh_token = String(d.get("refreshToken", d.get("refresh_token", _refresh_token)))
	uid = String(d.get("localId", d.get("user_id", uid)))
	_expires_at = Time.get_unix_time_from_system() + float(d.get("expiresIn", d.get("expires_in", 3600))) - 60.0

func _save_session() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("cloud", "nick", nick)
	cfg.set_value("cloud", "uid", uid)
	cfg.set_value("cloud", "refresh", _refresh_token)
	cfg.save(SESSION_PATH)

func _restore_session() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SESSION_PATH) != OK:
		return
	_refresh_token = String(cfg.get_value("cloud", "refresh", ""))
	nick = String(cfg.get_value("cloud", "nick", ""))
	uid = String(cfg.get_value("cloud", "uid", ""))
	if _refresh_token == "" or nick == "":
		return
	signed_in = true # оптимистично: токен обновится при первом обращении
	_expires_at = 0.0

func _ensure_token() -> bool:
	if not signed_in:
		return false
	if _id_token != "" and Time.get_unix_time_from_system() < _expires_at:
		return true
	var url := "https://securetoken.googleapis.com/v1/token?key=" + _api_key
	var r := await _http(HTTPClient.METHOD_POST, url,
		"grant_type=refresh_token&refresh_token=" + _refresh_token.uri_encode(), false, true)
	if not r.ok:
		if int(r.code) == 400: # токен отозван — нужен новый вход
			signed_in = false
		return false
	_take_tokens(r.data)
	_save_session()
	return true

# --- Firestore: кодирование значений ----------------------------------------------------------

static func _to_fs(v: Variant) -> Dictionary:
	match typeof(v):
		TYPE_BOOL: return {"booleanValue": v}
		TYPE_INT: return {"integerValue": str(v)}
		TYPE_FLOAT: return {"doubleValue": v}
		TYPE_STRING, TYPE_STRING_NAME: return {"stringValue": String(v)}
		TYPE_ARRAY:
			var vals := []
			for x in v:
				vals.append(_to_fs(x))
			return {"arrayValue": {"values": vals}}
		TYPE_DICTIONARY:
			var f := {}
			for k in v:
				f[String(k)] = _to_fs(v[k])
			return {"mapValue": {"fields": f}}
	return {"nullValue": null}

static func _from_fs(v: Dictionary) -> Variant:
	if v.has("stringValue"): return String(v.stringValue)
	if v.has("integerValue"): return int(v.integerValue)
	if v.has("doubleValue"): return float(v.doubleValue)
	if v.has("booleanValue"): return bool(v.booleanValue)
	if v.has("arrayValue"):
		var a := []
		for x in v.arrayValue.get("values", []):
			a.append(_from_fs(x))
		return a
	if v.has("mapValue"):
		return _fields_to_dict(v.mapValue.get("fields", {}))
	return null

static func _fields_to_dict(fields: Dictionary) -> Dictionary:
	var d := {}
	for k in fields:
		d[k] = _from_fs(fields[k])
	return d

func _doc_url(path: String) -> String:
	return "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents/%s" % [_project, path]

# Записывает (заменяет) документ path полями data. Возвращает {ok, error}.
func set_doc(path: String, data: Dictionary) -> Dictionary:
	if not await _ensure_token():
		return {"ok": false, "error": "Нет входа в облако."}
	var fields := {}
	for k in data:
		fields[k] = _to_fs(data[k])
	var r := await _http(HTTPClient.METHOD_PATCH, _doc_url(path), {"fields": fields}, true)
	return {"ok": r.ok, "error": "" if r.ok else _friendly(r)}

# Читает документ. Возвращает {ok, found, data, error}.
func get_doc(path: String) -> Dictionary:
	if not await _ensure_token():
		return {"ok": false, "found": false, "data": {}, "error": "Нет входа в облако."}
	var r := await _http(HTTPClient.METHOD_GET, _doc_url(path), null, true)
	if int(r.code) == 404:
		return {"ok": true, "found": false, "data": {}, "error": ""}
	if not r.ok:
		return {"ok": false, "found": false, "data": {}, "error": _friendly(r)}
	return {"ok": true, "found": true, "data": _fields_to_dict(r.data.get("fields", {})), "error": ""}

# Все документы коллекции, отсортированные по полю (по убыванию). Возвращает {ok, docs, error}.
func query_top(collection: String, order_field: String, limit: int) -> Dictionary:
	if not await _ensure_token():
		return {"ok": false, "docs": [], "error": "Нет входа в облако."}
	var url := "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents:runQuery" % _project
	var q := {"structuredQuery": {
		"from": [{"collectionId": collection}],
		"orderBy": [{"field": {"fieldPath": order_field}, "direction": "DESCENDING"}],
		"limit": limit}}
	var r := await _http(HTTPClient.METHOD_POST, url, q, true)
	if not r.ok:
		return {"ok": false, "docs": [], "error": _friendly(r)}
	var docs := []
	if typeof(r.raw) == TYPE_ARRAY:
		for item in r.raw:
			if typeof(item) == TYPE_DICTIONARY and item.has("document"):
				var d := _fields_to_dict(item.document.get("fields", {}))
				d["_id"] = String(item.document.get("name", "")).get_file()
				docs.append(d)
	return {"ok": true, "docs": docs, "error": ""}

# --- профиль игрока ---------------------------------------------------------------------------

# Публичная карточка: то, что видят другие игроки. Никакой статистики ходов.
func public_card() -> Dictionary:
	return {
		"nick": Profile.display_name,
		"rating": int(round(Profile.tournament_rating)),
		"title": Profile.title_for_rating(Profile.tournament_rating),
		"games": Profile.games_played,
		"cups": Profile.tournaments_won,
		"age": Profile.age_group,
		"seen": int(Time.get_unix_time_from_system()),
	}

# Загружает в облако публичную карточку и приватную копию профиля. Только для того профиля,
# под которым выполнен вход (иначе чужой рейтинг ушёл бы в чужой аккаунт).
func push_profile() -> Dictionary:
	if not enabled or not signed_in or Profile.current_user == "" or Profile.current_user != Profile.sanitize_key(nick):
		return {"ok": false, "error": "Вход в облако выполнен под другим именем."}
	if _pushing:
		return {"ok": false, "error": "Уже отправляется."}
	_pushing = true
	var res := await set_doc("players/" + uid, public_card())
	if res.ok:
		var bytes := Profile.export_profile_bytes()
		if bytes.size() > 0 and bytes.size() <= MAX_PRIVATE_BYTES:
			res = await set_doc("private/" + uid, {
				"blob": Marshalls.raw_to_base64(bytes),
				"saved": int(Profile.last_played_unix),
			})
	_pushing = false
	last_error = String(res.get("error", ""))
	return res

# Профиль вызывает это после каждой записи на диск: отправка откладывается, чтобы не частить.
func note_saved() -> void:
	if not enabled or not signed_in or _push_pending or _pushing:
		return
	_push_pending = true
	get_tree().create_timer(PUSH_DELAY).timeout.connect(func():
		_push_pending = false
		push_profile())

# Приватная копия профиля: {ok, found, bytes, saved, error}.
func pull_profile() -> Dictionary:
	var r := await get_doc("private/" + uid)
	if not r.ok or not r.found:
		return {"ok": r.ok, "found": false, "bytes": PackedByteArray(), "saved": 0, "error": r.error}
	return {"ok": true, "found": true,
		"bytes": Marshalls.base64_to_raw(String(r.data.get("blob", ""))),
		"saved": int(r.data.get("saved", 0)), "error": ""}
