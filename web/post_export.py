# Дописывает то, что Godot берёт из имени проекта (chessoff): название в манифесте веб-приложения —
# оно видно, когда игру «устанавливают» на главный экран телефона или планшета.
# Запускать после экспорта: python web/post_export.py  (см. README, раздел «Веб-версия»).
import json, os
here = os.path.dirname(os.path.abspath(__file__))
path = os.path.join(here, "..", "docs", "index.manifest.json")
m = json.load(open(path, encoding="utf-8"))
m["name"] = "Шахматный клуб «ИРБИС»"
m["short_name"] = "ИРБИС"
m["background_color"] = "#161B3D"
m["theme_color"] = "#161B3D"
m["lang"] = "ru"
json.dump(m, open(path, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
print("манифест обновлён:", m["name"])
