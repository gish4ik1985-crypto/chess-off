# Собирает index.html из template.html: вставляет фигуры cburnett из assets/pieces (те же, что в игре).
import json, os
here = os.path.dirname(os.path.abspath(__file__))
pieces_dir = os.path.join(here, "..", "assets", "pieces")
pieces = {}
for name in sorted(os.listdir(pieces_dir)):
    if name.endswith(".svg"):
        pieces[name[:-4]] = open(os.path.join(pieces_dir, name), encoding="utf-8").read().strip()
tpl = open(os.path.join(here, "template.html"), encoding="utf-8").read()
out = tpl.replace("__PIECES__", json.dumps(pieces, ensure_ascii=False))
open(os.path.join(here, "index.html"), "w", encoding="utf-8").write(out)
# preview.html — та же страница с обёрткой (кодировка, viewport) для просмотра без публикации
skeleton = '<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"></head><body style="margin:0">'
open(os.path.join(here, "preview.html"), "w", encoding="utf-8").write(skeleton + out + "</body></html>")
print("index.html:", len(out), "bytes")
