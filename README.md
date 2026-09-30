# chessoff — шахматный тренажёр (Godot 4.6)

## Веб-версия (GitHub Pages)
Готовая сборка лежит в `docs/`. Публикация: репозиторий → Settings → Pages →
Source: «Deploy from a branch», ветка `main`, папка `/docs`.

Пересборка после изменений:

    godot --headless --path . --export-release "Web" docs/index.html

Сборка без потоков (GitHub Pages не отдаёт заголовки для многопоточности);
профили игроков хранятся в браузере (IndexedDB), перенос между устройствами —
Настройки → «Сохранить профиль» / «Загрузить профиль».

## Проверки
Запускаются как сцены: `godot --headless --path . res://scenes/tools/<Имя>.tscn`
(TestScenes, AuditUI, TestBots, TestFastSearch, HistoricValidator, ...).
