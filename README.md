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
Все сразу: `powershell -ExecutionPolicy Bypass -File run_tests.ps1` (флаги `-Quick`, `-Only <часть имени>`).
Перед запуском скрипт копирует профили игроков и возвращает их после, а проверкам даёт временного игрока.

По отдельности: Запускаются как сцены: `godot --headless --path . res://scenes/tools/<Имя>.tscn`
(TestScenes, AuditUI, TestBots, TestFastSearch, HistoricValidator, ...).
