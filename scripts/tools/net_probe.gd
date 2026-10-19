extends Node

# Проверка связи с Firebase без побочных эффектов: тот же путь запроса, что у регистрации, но
# со заведомо неверным токеном — ответ 400 INVALID_ID_TOKEN значит «доехало, Google ответил».
# Запуск: scenes/tools/NetProbe.tscn

func _ready() -> void:
	var url := "https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=" + Cloud._api_key
	var r: Dictionary = await Cloud._http(HTTPClient.METHOD_POST, url, {"idToken": "x"})
	print("lookup: code=", r.code, " net=", r.net, " ", String(r.data.get("error", {}).get("message", "")))
	# те же формы запросов, что у занятия ника и записи карточки, но с чужим токеном: ждём 401, а не сбой сети
	Cloud._id_token = "x"
	Cloud._expires_at = 1.0e12
	Cloud.signed_in = true
	var c: Dictionary = await Cloud.claim_nick("zz-probe-nick")
	print("claim_nick: ", c.error)
	var w: Dictionary = await Cloud.set_doc("players/zz-probe", {"nick": "x"})
	print("set_doc: ", w.error)
	Cloud.signed_in = false
	get_tree().quit()
