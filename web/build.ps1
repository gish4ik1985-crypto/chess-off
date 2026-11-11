# Сборка веб-версии для GitHub Pages одной командой.
#
#   ./web/build.ps1 -Version 1.20 -Beta     пробная площадка: <сайт>/beta/  (ученики её не видят)
#   ./web/build.ps1 -Version 1.20           выпуск для всех: <сайт>/
#
# Порядок выпуска: сначала -Beta, посмотреть на планшете и телефоне по адресу .../beta/, и только
# потом та же версия без -Beta. Так ошибки ловит тренер, а не ученики.
#
# Скрипт: 1) ставит номер версии (внутрь игры и в version.json — по нему игра узнаёт об обновлении и
# показывает «Версия N» в углу меню), 2) экспортирует Web, 3) дописывает название клуба в манифест.
# Каждый выпуск — новый номер (1.19, 1.20, ...): без этого игроки не увидят «Вышла новая версия».
# Игроки, у которых игра открыта, НЕ вылетают: они увидят в 🔔 уведомление и обновятся сами
# (см. scripts/AppUpdate.gd). Путь к Godot: переменная GODOT (версия 4.7 — та же, что у проекта).
#
# Пробная площадка открывается с того же сайта, поэтому на одном устройстве у неё те же профили
# игроков и та же база школы, что у основной версии. Проверяйте её под своим аккаунтом.

param(
	[Parameter(Mandatory = $true)][string]$Version,
	[switch]$Beta
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$godot = $env:GODOT
if (-not $godot -or -not (Test-Path $godot -PathType Leaf)) {
	$godot = (Get-ChildItem -Path (Join-Path $env:USERPROFILE "Desktop"), (Join-Path $env:USERPROFILE "Downloads") -Recurse -Filter "Godot_v4*win64_console.exe" -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1).FullName
}
if (-not $godot) { throw "Godot не найден: задайте переменную GODOT (полный путь к Godot_v4*_console.exe)." }

# пробная сборка получает номер вида «1.20-beta» и уходит в docs/beta
$outRel = "docs"
$build = $Version
if ($Beta) {
	$outRel = "docs/beta"
	$build = "$Version-beta"
}
$outDir = Join-Path $root $outRel
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$published = Join-Path $outDir "version.json"
if ((Test-Path $published) -and -not $Beta) {
	$old = (Get-Content $published -Raw | ConvertFrom-Json).build
	if ($old -eq $build) { throw "Версия $build уже опубликована — укажите следующую." }
}
$stamp = $build
if ($Beta) { $stamp = "$build " + (Get-Date -Format "MMdd-HHmm") }
[IO.File]::WriteAllText((Join-Path $root "build_id.txt"), $stamp, (New-Object Text.UTF8Encoding($false)))

& $godot --headless --path . --export-release "Web" "$outRel/index.html"
if ($LASTEXITCODE -ne 0) { throw "Экспорт не удался (код $LASTEXITCODE)" }
python web/post_export.py $outRel
if ($LASTEXITCODE -ne 0) { throw "post_export.py не отработал (код $LASTEXITCODE)" }

# version.json пишем ПОСЛЕДНИМ: пока экспорт не закончен, игроки не видят новую версию.
# У пробной сборки добавляем время: повторная проба той же версии тоже должна предложить обновиться.
[IO.File]::WriteAllText($published, "{`"build`":`"$stamp`"}", (New-Object Text.UTF8Encoding($false)))
if ($Beta) {
	Write-Host "Готово: пробная версия $build в $outRel. Закоммитьте $outRel и отправьте (git push); адрес — сайт + /beta/."
} else {
	Write-Host "Готово: версия $build. Закоммитьте docs/, build_id.txt и отправьте (git push)."
}
