extends Node

# Проверка облачного слоя без сети: кодирование значений Firestore туда-обратно, проверка почты и ника.
# Запуск: scenes/tools/TestCloud.tscn

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
	check("почта: обычный адрес подходит", Cloud.valid_email("masha@gmail.com"))
	check("почта: адрес с плюсом подходит (одна почта на нескольких детей)", Cloud.valid_email("mama+sasha@gmail.com"))
	check("почта: без @ не подходит", not Cloud.valid_email("masha.gmail.com"))
	check("почта: без домена не подходит", not Cloud.valid_email("masha@gmail"))
	check("почта: с пробелом не подходит", not Cloud.valid_email("ma sha@gmail.com"))
	check("ник: нормальный подходит, слишком короткий — нет", Cloud.valid_nick("Саша") and not Cloud.valid_nick("А"))
	check("ник: со слэшем нельзя (это путь документа)", not Cloud.valid_nick("а/б"))
	check("ник: без учёта регистра и пробелов один и тот же", Cloud.nick_key("  Саша ") == Cloud.nick_key("саша"))
	check("без ключей облако выключено (игра работает локально)", not Cloud.enabled or Cloud._api_key != "")
	print("=== ИТОГО ошибок: %d ===" % fails)
	get_tree().quit(1 if fails > 0 else 0)
