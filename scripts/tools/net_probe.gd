extends Node

# Проверка связи с Firebase без побочных эффектов: тот же путь запроса, что у регистрации, но
# со заведомо неверным токеном — ответ 400 INVALID_ID_TOKEN значит «доехало, Google ответил».
# Запуск: scenes/tools/NetProbe.tscn

func _ready() -> void:
	var url := "https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=" + Cloud._api_key
	var r: Dictionary = await Cloud._http(HTTPClient.METHOD_POST, url, {"idToken": "x"})
	print("cloud.enabled=", Cloud.enabled, " code=", r.code, " net=", r.net, " ", String(r.data.get("error", {}).get("message", "")))
	get_tree().quit()
