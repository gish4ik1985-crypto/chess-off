# Сборка веб-версии для GitHub Pages одной командой:  ./web/build.ps1 -Version 1.13
# 1) ставит номер версии (внутрь игры и в docs/version.json — по нему игра узнаёт об обновлении и
#    показывает «Версия N» в углу меню), 2) экспортирует Web в docs/, 3) дописывает название клуба в манифест.
# Каждый выпуск — новый номер (1.12, 1.13, ...): без этого игроки не увидят «Вышла новая версия».
# Игроки, у которых игра открыта, НЕ вылетают: они увидят в 🔔 уведомление и обновятся сами
# (см. scripts/AppUpdate.gd). Путь к Godot: переменная GODOT (лучше 4.7 — той же версии, что проект).

param([Parameter(Mandatory = $true)][string]$Version)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$godot = $env:GODOT
if (-not $godot -or -not (Test-Path $godot -PathType Leaf)) {
	$godot = (Get-ChildItem -Path (Join-Path $env:USERPROFILE "Desktop"), (Join-Path $env:USERPROFILE "Downloads") -Recurse -Filter "Godot_v4*win64_console.exe" -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1).FullName
}
if (-not $godot) { throw "Godot не найден: задайте переменную GODOT (полный путь к Godot_v4*_console.exe)." }

$published = Join-Path $root "docs/version.json"
if (Test-Path $published) {
	$old = (Get-Content $published -Raw | ConvertFrom-Json).build
	if ($old -eq $Version) { throw "Версия $Version уже опубликована — укажите следующую." }
}
[IO.File]::WriteAllText((Join-Path $root "build_id.txt"), $Version, (New-Object Text.UTF8Encoding($false)))

& $godot --headless --path . --export-release "Web" docs/index.html
if ($LASTEXITCODE -ne 0) { throw "Экспорт не удался (код $LASTEXITCODE)" }
python web/post_export.py

# version.json пишем ПОСЛЕДНИМ: пока экспорт не закончен, игроки не видят новую версию
[IO.File]::WriteAllText($published, "{`"build`":`"$Version`"}", (New-Object Text.UTF8Encoding($false)))
Write-Host "Готово: версия $Version. Закоммитьте docs/, build_id.txt и отправьте (git push)."
