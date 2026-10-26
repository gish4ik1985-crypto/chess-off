# Сборка веб-версии для GitHub Pages одной командой:  ./web/build.ps1
# 1) ставит новый номер сборки (внутрь игры и в docs/version.json — по ним игра узнаёт об обновлении),
# 2) экспортирует Web в docs/, 3) дописывает название клуба в манифест.
# Игроки, у которых игра открыта, НЕ вылетают: они увидят в 🔔 «Вышла новая версия» и обновятся сами
# (см. scripts/AppUpdate.gd). Путь к Godot: переменная GODOT или Godot_v4*.exe в «Загрузках».

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$godot = $env:GODOT
if (-not $godot -or -not (Test-Path $godot -PathType Leaf)) {
	$godot = (Get-ChildItem -Path (Join-Path $env:USERPROFILE "Downloads") -Recurse -Filter "Godot_v4*win64_console.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
}
if (-not $godot) { throw "Godot не найден: задайте переменную GODOT (полный путь к Godot_v4*_console.exe)." }

$build = Get-Date -Format "yyyyMMddHHmmss"
[IO.File]::WriteAllText((Join-Path $root "build_id.txt"), $build, (New-Object Text.UTF8Encoding($false)))

& $godot --headless --path . --export-release "Web" docs/index.html
if ($LASTEXITCODE -ne 0) { throw "Экспорт не удался (код $LASTEXITCODE)" }
python web/post_export.py

# version.json пишем ПОСЛЕДНИМ: пока экспорт не закончен, игроки не видят новую версию
[IO.File]::WriteAllText((Join-Path $root "docs/version.json"), "{`"build`":`"$build`"}", (New-Object Text.UTF8Encoding($false)))
Write-Host "Готово: сборка $build. Закоммитьте docs/, build_id.txt и отправьте (git push)."
