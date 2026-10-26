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
# Вход: почта + пароль (почта обязательна — по ней приходит письмо для сброса пароля и можно
# открыть свой прогресс на другом устройстве). Ник — имя игрока в таблице школы; он уникален:
# перед регистрацией ник «занимается» документом nicks/{ник} (создать можно только один раз).
# Одна почта на нескольких детей: у Gmail подойдёт форма имя+саша@gmail.com — письма придут в один ящик.

const CONFIG_PATH := "res://firebase_config.json"
const SESSION_PATH := "user://cloud.cfg"
const PUSH_DELAY := 20.0 # секунд между отправками профиля в облако
const MAX_PRIVATE_BYTES := 700000 # лимит документа Firestore ~1 МБ, а base64 раздувает на треть

var enabled := false
var signed_in := false
var nick := ""
var email := ""
var uid := ""
var role := "player" # роль в школе (roles/{uid}); обновляется при входе
var award := "" # именной титул от тренера
var _api_key := ""
var _project := ""
var _id_token := ""
var _refresh_token := ""
var _expires_at := 0.0
var _push_pending := false
var _pushing := false
var push_blocked := false # вход без загруженной облачной копии: пустой локальный профиль не должен её затереть
var last_error := ""
var synced_saved := -1 # метка «saved» облачной копии, уже влитой в локальный профиль
signal profile_merged # в локальный профиль влились данные с другого устройства

func _ready() -> void:
	_load_config()
	if enabled:
		_restore_session()
		if signed_in:
			_startup_sync.call_deferred()

func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	_api_key = String(data.get("apiKey", "")).strip_edges()
	_project = String(data.get("projectId", "")).strip_edges()
	enabled = _api_key != "" and _project != ""

# --- почта и ник ------------------------------------------------------------------------------------

static func nick_key(n: String) -> String:
	return n.strip_edges().to_lower()

# Простая проверка вида «что-то@что-то.домен»; настоящую проверку делает Firebase.
static func valid_email(e: String) -> bool:
	var t := e.strip_edges()
	var at := t.find("@")
	return at > 0 and t.find(" ") < 0 and t.rfind(".") > at + 1 and t.rfind(".") < t.length() - 1 and t.count("@") == 1

static func valid_nick(n: String) -> bool:
	var t := n.strip_edges()
	return t.length() >= 2 and t.length() <= 60 and not t.contains("/") and not t.contains("\\")

# ФИО вместо ника: лишние пробелы убираем, в базе имя хранится как «Фамилия Имя Отчество».
static func normalize_name(n: String) -> String:
	var parts := n.strip_edges().split(" ", false)
	return " ".join(parts)

# Нужны минимум фамилия и имя (два слова).
static func valid_full_name(n: String) -> bool:
	var t := normalize_name(n)
	return t.split(" ", false).size() >= 2 and valid_nick(t)

# --- HTTP ----------------------------------------------------------------------------------------

# Возвращает {ok, code, data}. Не бросает ошибок: сеть может быть недоступна.
func _http(method: int, url: String, body: Variant = null, auth: bool = false, form: bool = false) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 30.0
	req.accept_gzip = false # браузер сам договаривается о сжатии; лишний заголовок в вебе бывает причиной сбоя
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
		print("Cloud: запрос не отправлен, ошибка ", err, " ", url.get_slice("?", 0))
		return {"ok": false, "code": 0, "data": {}, "net": true, "detail": "запрос не отправлен, код %d" % err}
	var res: Array = await req.request_completed
	req.queue_free()
	var code := int(res[1])
	var text := (res[3] as PackedByteArray).get_string_from_utf8()
	var parsed = JSON.parse_string(text) if text != "" else {}
	var raw = parsed # runQuery отвечает массивом, остальные запросы — словарём
	if typeof(parsed) != TYPE_DICTIONARY:
		parsed = {}
	var net_fail := int(res[0]) != HTTPRequest.RESULT_SUCCESS
	if net_fail:
		print("Cloud: нет ответа от ", url.get_slice("?", 0), ", результат ", int(res[0]))
	return {"ok": code >= 200 and code < 300, "code": code, "data": parsed, "raw": raw, "net": net_fail,
		"detail": "результат сети %d" % int(res[0]) if net_fail else ""}

func _friendly(r: Dictionary) -> String:
	if r.get("net", false) or int(r.code) == 0:
		return "Нет связи с облаком (%s). Проверьте интернет; если включены VPN, блокировщик рекламы или антивирус с веб-защитой — попробуйте их отключить для этого сайта или другой браузер." % String(r.get("detail", "нет ответа"))
	var msg := String(r.data.get("error", {}).get("message", ""))
	if msg.begins_with("EMAIL_EXISTS"):
		return "Эта почта уже зарегистрирована. Нажмите «Войти» или «Забыли пароль?»."
	if msg.begins_with("INVALID_EMAIL"):
		return "Проверьте почту: она записана неверно."
	if msg.begins_with("INVALID_LOGIN_CREDENTIALS") or msg.begins_with("INVALID_PASSWORD") or msg.begins_with("EMAIL_NOT_FOUND"):
		return "Неверная почта или пароль."
	if msg.begins_with("WEAK_PASSWORD"):
		return "Пароль слишком простой — минимум 6 символов."
	if msg.begins_with("TOO_MANY_ATTEMPTS"):
		return "Слишком много попыток. Подождите немного."
	if msg.begins_with("PERMISSION_DENIED") or int(r.code) == 403:
		return "Нет доступа. Проверьте правила базы (firestore.rules). %s" % msg
	return "Ошибка облака (%d). %s" % [int(r.code), msg]

# --- аккаунт --------------------------------------------------------------------------------------

func _auth(endpoint: String, mail: String, password: String) -> Dictionary:
	var url := "https://identitytoolkit.googleapis.com/v1/accounts:%s?key=%s" % [endpoint, _api_key]
	var r := await _http(HTTPClient.METHOD_POST, url,
		{"email": mail.strip_edges(), "password": password, "returnSecureToken": true})
	if not r.ok:
		return {"ok": false, "error": _friendly(r)}
	_take_tokens(r.data)
	email = mail.strip_edges()
	signed_in = true
	return {"ok": true, "error": ""}

# Регистрация: аккаунт по почте → ник занимается (создать можно один раз) → карточка игрока.
# Если ник уже занят, только что созданный аккаунт удаляется, чтобы почту можно было использовать снова.
func register(mail: String, password: String, wanted_nick: String) -> Dictionary:
	if not enabled:
		return {"ok": false, "error": "Облако не настроено."}
	var res := await _auth("signUp", mail, password)
	if not res.ok:
		return res
	var claim := await claim_nick(wanted_nick)
	if not claim.ok:
		await _delete_current_account()
		return claim
	return {"ok": true, "error": ""}

# Занимает ник за текущим аккаунтом. Создание документа (POST) вместо записи поверх (PATCH): так занятый
# ник даёт 409, а в браузере не нужен метод PATCH, с которым у веб-запросов Godot бывают сбои.
func claim_nick(wanted_nick: String) -> Dictionary:
	var url := _doc_url("nicks") + "?documentId=" + nick_key(wanted_nick).uri_encode()
	var r := await _http(HTTPClient.METHOD_POST, url, {"fields": {"uid": _to_fs(uid)}}, true)
	if r.ok:
		nick = wanted_nick.strip_edges()
		_save_session()
		return {"ok": true, "error": ""}
	if int(r.code) == 409:
		# имя уже занято — но, возможно, этим же аккаунтом (регистрация оборвалась раньше): тогда всё в порядке
		var existing := await get_doc("nicks/" + nick_key(wanted_nick))
		if existing.ok and existing.found and String(existing.data.get("uid", "")) == uid:
			nick = wanted_nick.strip_edges()
			_save_session()
			return {"ok": true, "error": ""}
		return {"ok": false, "error": "Игрок «%s» уже зарегистрирован. Если это вы — нажмите «Войти»; если тёзка — добавьте отчество." % wanted_nick.strip_edges()}
	return {"ok": false, "error": _friendly(r)}

# Имя, которое когда-то занял этот аккаунт (документ nicks/{имя}, где uid — мой). "" — не нашлось.
func _find_my_nick() -> String:
	if not await _ensure_token():
		return ""
	var url := "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents:runQuery" % _project
	var q := {"structuredQuery": {
		"from": [{"collectionId": "nicks"}],
		"where": {"fieldFilter": {"field": {"fieldPath": "uid"}, "op": "EQUAL", "value": {"stringValue": uid}}},
		"limit": 1}}
	var r := await _http(HTTPClient.METHOD_POST, url, q, true)
	if r.ok and typeof(r.raw) == TYPE_ARRAY:
		for item in r.raw:
			if typeof(item) == TYPE_DICTIONARY and item.has("document"):
				return String(item.document.get("name", "")).get_file().uri_decode()
	return ""

func login(mail: String, password: String) -> Dictionary:
	if not enabled:
		return {"ok": false, "error": "Облако не настроено."}
	var res := await _auth("signInWithPassword", mail, password)
	if not res.ok:
		return res
	# ник берём из карточки игрока; если её нет (регистрация оборвалась на выборе ника), ник ещё не выбран
	var card := await get_doc("players/" + uid)
	if card.ok and card.found and String(card.data.get("nick", "")) != "":
		nick = String(card.data.nick)
	else:
		# карточки нет (она не успела записаться при регистрации): ищем имя, которое этот аккаунт уже занял
		nick = await _find_my_nick()
	_save_session()
	return {"ok": true, "error": "", "needs_nick": nick == ""}

# Письмо со ссылкой для нового пароля. Firebase отвечает «успешно» и для незарегистрированной почты
# (чтобы нельзя было выведать, кто играет), поэтому формулировка осторожная.
func send_password_reset(mail: String) -> Dictionary:
	if not enabled:
		return {"ok": false, "error": "Облако не настроено."}
	var url := "https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=" + _api_key
	var r := await _http(HTTPClient.METHOD_POST, url, {"requestType": "PASSWORD_RESET", "email": mail.strip_edges()})
	if r.ok:
		return {"ok": true, "error": ""}
	var msg := String(r.data.get("error", {}).get("message", ""))
	if msg.begins_with("EMAIL_NOT_FOUND"):
		return {"ok": true, "error": ""}
	return {"ok": false, "error": _friendly(r)}

func _delete_current_account() -> void:
	var url := "https://identitytoolkit.googleapis.com/v1/accounts:delete?key=" + _api_key
	await _http(HTTPClient.METHOD_POST, url, {"idToken": _id_token})
	signed_in = false
	_id_token = ""
	_refresh_token = ""
	uid = ""
	email = ""

func logout() -> void:
	signed_in = false
	_id_token = ""
	_refresh_token = ""
	uid = ""
	nick = ""
	email = ""
	role = "player"
	award = ""
	DirAccess.remove_absolute(SESSION_PATH)

func _take_tokens(d: Dictionary) -> void:
	_id_token = String(d.get("idToken", d.get("id_token", "")))
	_refresh_token = String(d.get("refreshToken", d.get("refresh_token", _refresh_token)))
	uid = String(d.get("localId", d.get("user_id", uid)))
	_expires_at = Time.get_unix_time_from_system() + float(d.get("expiresIn", d.get("expires_in", 3600))) - 60.0

func _save_session() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("cloud", "nick", nick)
	cfg.set_value("cloud", "email", email)
	cfg.set_value("cloud", "uid", uid)
	cfg.set_value("cloud", "refresh", _refresh_token)
	cfg.save(SESSION_PATH)

func _restore_session() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SESSION_PATH) != OK:
		return
	_refresh_token = String(cfg.get_value("cloud", "refresh", ""))
	nick = String(cfg.get_value("cloud", "nick", ""))
	email = String(cfg.get_value("cloud", "email", ""))
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

# Записывает (заменяет) документ path полями data. Идёт через :commit (POST): так же работает и в
# браузере, где метод PATCH у запросов Godot ненадёжен. Возвращает {ok, error}.
func set_doc(path: String, data: Dictionary) -> Dictionary:
	if not await _ensure_token():
		return {"ok": false, "error": "Нет входа в облако."}
	var fields := {}
	for k in data:
		fields[k] = _to_fs(data[k])
	var root := "projects/%s/databases/(default)/documents/" % _project
	var url := "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents:commit" % _project
	var r := await _http(HTTPClient.METHOD_POST, url, {"writes": [{"update": {"name": root + path, "fields": fields}}]}, true)
	return {"ok": r.ok, "error": "" if r.ok else _friendly(r)}

# Удаляет документ path.
func del_doc(path: String) -> Dictionary:
	if not await _ensure_token():
		return {"ok": false, "error": "Нет входа в облако."}
	var root := "projects/%s/databases/(default)/documents/" % _project
	var url := "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents:commit" % _project
	var r := await _http(HTTPClient.METHOD_POST, url, {"writes": [{"delete": root + path}]}, true)
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

# --- роли ---------------------------------------------------------------------------------------

# Узнаёт роль и именной титул текущего пользователя и запоминает их в профиле (для показа без сети).
# Адреса из Roles.BOOTSTRAP_ADMINS — администраторы сразу; для них создаётся и документ роли.
func refresh_role() -> void:
	if not (enabled and signed_in) or Profile.current_user != Profile.sanitize_key(nick):
		return # роль применяем только к тому профилю, под которым выполнен вход
	var found_role := "player"
	var found_award := ""
	var r := await get_doc("roles/" + uid)
	if r.ok and r.found:
		found_role = String(r.data.get("role", "player"))
		found_award = String(r.data.get("award", ""))
		if not Roles.valid(found_role):
			found_role = "player"
	elif not r.ok:
		return # нет связи — оставляем то, что запомнено
	if email.strip_edges().to_lower() in Roles.BOOTSTRAP_ADMINS and found_role != "admin":
		found_role = "admin"
		await set_role(uid, "admin", found_award, nick)
	role = found_role
	award = found_award
	Profile.role = role
	Profile.award = award
	Profile.request_save()

# Все выданные роли: {_id (uid), role, award, nick}.
func list_roles() -> Dictionary:
	return await query_top("roles", "role", 300)

# Назначает роль и титул пользователю uid_target. Права проверяют правила базы.
func set_role(uid_target: String, new_role: String, new_award: String, target_nick: String) -> Dictionary:
	return await set_doc("roles/" + uid_target, {
		"role": new_role, "award": new_award.strip_edges().left(40),
		"nick": target_nick, "by": uid, "at": int(Time.get_unix_time_from_system())})

# Документы коллекции, у которых поле field равно value (порядок не задан — сортируйте сами).
func query_eq(collection: String, field: String, value: String, limit: int) -> Dictionary:
	if not await _ensure_token():
		return {"ok": false, "docs": [], "error": "Нет входа в облако."}
	var url := "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents:runQuery" % _project
	var q := {"structuredQuery": {
		"from": [{"collectionId": collection}],
		"where": {"fieldFilter": {"field": {"fieldPath": field}, "op": "EQUAL", "value": {"stringValue": value}}},
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

# Документы вложенной коллекции: parent — путь документа-родителя («chat/school»), sub — имя коллекции («msgs»).
func query_sub(parent: String, sub: String, order_field: String, limit: int) -> Dictionary:
	if not await _ensure_token():
		return {"ok": false, "docs": [], "error": "Нет входа в облако."}
	var url := "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents/%s:runQuery" % [_project, parent]
	var q := {"structuredQuery": {
		"from": [{"collectionId": sub}],
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
		"key": nick_key(Profile.display_name), # ключ ника в базе (строчными): правила сверяют по нему, т.к. lower() в правилах плохо дружит с кириллицей
		"rating": int(round(Profile.tournament_rating)),
		"title": Roles.class_text(Profile.tournament_rating, Profile.title_for_rating(Profile.tournament_rating)),
		"games": Profile.games_played,
		"cups": Profile.tournaments_won,
		"age": Profile.age_group,
		"avatar": Profile.avatar,
		"name": Profile.full_name if Profile.public_details else "",
		"hidden": not Profile.public_visible,
		"city": Profile.city if Profile.public_details else "",
		"about": Profile.about if Profile.public_details else "",
		"rank": Profile.rank_level,
		"group": Profile.club_group,
		"seen": int(Time.get_unix_time_from_system()),
	}

# Загружает в облако публичную карточку и приватную копию профиля. Только для того профиля,
# под которым выполнен вход (иначе чужой рейтинг ушёл бы в чужой аккаунт).
func push_profile() -> Dictionary:
	if not enabled or not signed_in or Profile.current_user == "" or Profile.current_user != Profile.sanitize_key(nick):
		return {"ok": false, "error": "Вход в облако выполнен под другим именем."}
	if push_blocked:
		return {"ok": false, "error": "Облачная копия не загрузилась при входе — отправка остановлена, чтобы не затереть её."}
	if _pushing:
		return {"ok": false, "error": "Уже отправляется."}
	_pushing = true
	# сначала забираем облачную копию: если её обновило другое устройство — вливаем, а не затираем
	var cloud := await pull_profile()
	if not cloud.ok:
		_pushing = false
		last_error = "Облако недоступно — профиль отправится позже: %s" % cloud.error
		return {"ok": false, "error": last_error}
	if cloud.found and int(cloud.saved) != synced_saved:
		if Profile.merge_profile_bytes(cloud.bytes):
			profile_merged.emit()
		synced_saved = int(cloud.saved)
	var res := await set_doc("players/" + uid, public_card())
	if not res.ok:
		# правила базы ещё старые (без новых полей анкеты) — отправляем короткую карточку
		var basic := public_card()
		for k in ["avatar", "hidden", "city", "about", "rank", "key", "name", "group"]:
			basic.erase(k)
		res = await set_doc("players/" + uid, basic)
	if res.ok:
		var bytes := Profile.export_profile_bytes()
		if bytes.size() > 0 and bytes.size() <= MAX_PRIVATE_BYTES:
			var saved := int(Profile.last_played_unix)
			res = await set_doc("private/" + uid, {
				"blob": Marshalls.raw_to_base64(bytes),
				"saved": saved,
			})
			if res.ok:
				synced_saved = saved
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

# Забирает облачную копию и вливает в локальный профиль, если её с прошлой синхронизации обновило
# другое устройство. Зовётся при запуске (вход восстановлен из прошлого сеанса), при входе и в меню.
var _last_sync_ms := -100000

func sync_profile(min_interval_ms := 0) -> bool:
	if not enabled or not signed_in or Profile.current_user == "" or Profile.current_user != Profile.sanitize_key(nick):
		return false
	if _pushing or Time.get_ticks_msec() - _last_sync_ms < min_interval_ms:
		return false
	_last_sync_ms = Time.get_ticks_msec()
	var r := await pull_profile()
	if not r.ok:
		return false
	push_blocked = false # облако отвечает — отправлять снова можно
	if not r.found or int(r.saved) == synced_saved:
		return false
	var changed := Profile.merge_profile_bytes(r.bytes)
	synced_saved = int(r.saved)
	if changed:
		profile_merged.emit()
		# экраны, которые показывают прогресс, перерисовываем; партии и задачи не трогаем
		var sc := get_tree().current_scene
		if sc != null and sc.name in ["Menu", "Map", "PuzzleHub", "RoadHome", "Diary", "TrophyRoom"]:
			get_tree().reload_current_scene()
	return changed

func _startup_sync() -> void:
	await get_tree().create_timer(1.0).timeout
	if Profile.merge_replaced_backup():
		note_saved() # вернувшийся прогресс — сразу в облако
	await sync_profile()

# Приватная копия профиля: {ok, found, bytes, saved, error}.
func pull_profile() -> Dictionary:
	var r := await get_doc("private/" + uid)
	if not r.ok or not r.found:
		return {"ok": r.ok, "found": false, "bytes": PackedByteArray(), "saved": 0, "error": r.error}
	return {"ok": true, "found": true,
		"bytes": Marshalls.base64_to_raw(String(r.data.get("blob", ""))),
		"saved": int(r.data.get("saved", 0)), "error": ""}
