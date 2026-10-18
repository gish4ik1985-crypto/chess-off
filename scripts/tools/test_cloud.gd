extends Node

# Проверка облачного слоя без сети: кодирование значений Firestore туда-обратно и служебный адрес
# из ника (один и тот же ник в любом регистре и с пробелами — один аккаунт, адрес валиден для
# Firebase). Запуск: scenes/tools/TestCloud.tscn

var fails := 0

func check(name: String, ok: bool, info: String = "") -> void:
	print(("OK   " if ok else "FAIL ") + name + (" " + info if info != "" else ""))
	if not ok:
		fails += 1

func _ready() -> void:
	var data := {"nick": "Саша", "rating": 812, "x": 1.5, "ok": true, "arr": [1, "a"], "m": {"k": 2}}
	var fields := {}
	for k in data:
		fields[k] = Cloud._to_fs(data[k])
	var back: Dictionary = Cloud._fields_to_dict(fields)
	check("значения Firestore кодируются туда-обратно", back == data, str(back))
	check("целые кодируются строкой (формат Firestore)", Cloud._to_fs(5).integerValue == "5")
	var e1: String = Cloud.email_for("Саша")
	check("ник без учёта регистра и пробелов даёт один адрес", e1 == Cloud.email_for("  саша "))
	check("разные ники — разные адреса", e1 != Cloud.email_for("Маша"))
	check("служебный адрес валиден и короткий", e1.ends_with("@" + Cloud.MAIL_DOMAIN) and e1.length() < 64 and not e1.contains(" "), e1)
	check("без ключей облако выключено (игра работает локально)", not Cloud.enabled or Cloud._api_key != "")
	print("=== ИТОГО ошибок: %d ===" % fails)
	get_tree().quit(1 if fails > 0 else 0)
