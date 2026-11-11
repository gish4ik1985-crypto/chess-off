# Дописывает то, что Godot берёт из имени проекта (chessoff): название в манифесте веб-приложения —
# оно видно, когда игру «устанавливают» на главный экран телефона или планшета.
# Запускать после экспорта: python web/post_export.py [папка]  (по умолчанию docs; см. web/build.ps1).
# Для пробной площадки (папка .../beta) приложение называется «ИРБИС (проба)», а кеш браузера получает
# своё имя — иначе пробная и основная версии на одном устройстве стирали бы кеш друг друга.
import json, os, sys

here = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(here, "..", sys.argv[1] if len(sys.argv) > 1 else "docs")
beta = os.path.basename(os.path.normpath(out)) == "beta"

path = os.path.join(out, "index.manifest.json")
m = json.load(open(path, encoding="utf-8"))
m["name"] = "Шахматный клуб «ИРБИС» (проба)" if beta else "Шахматный клуб «ИРБИС»"
m["short_name"] = "ИРБИС проба" if beta else "ИРБИС"
m["background_color"] = "#161B3D"
m["theme_color"] = "#161B3D"
m["lang"] = "ru"
json.dump(m, open(path, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))

if beta:
    sw = os.path.join(out, "index.service.worker.js")
    s = open(sw, encoding="utf-8").read()
    assert "'chessoff-sw-cache-'" in s, "в сервис-воркере не найдено имя кеша"
    open(sw, "w", encoding="utf-8", newline="").write(s.replace("'chessoff-sw-cache-'", "'chessoff-beta-sw-cache-'"))

print("манифест обновлён:", m["name"].encode("ascii", "replace").decode())
