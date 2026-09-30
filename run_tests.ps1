<#
  Запуск всех автоматических проверок проекта одной командой.

    powershell -ExecutionPolicy Bypass -File run_tests.ps1            # всё
    powershell -ExecutionPolicy Bypass -File run_tests.ps1 -Only Rules # только тесты, в имени которых есть «Rules»
    powershell -ExecutionPolicy Bypass -File run_tests.ps1 -Quick      # без долгих проверок

  Путь к Godot берётся из переменной GODOT, иначе ищется в PATH и в папке Загрузки.

  ВАЖНО: часть проверок (AuditUI, TestBots, TestBestMoves) работает с реальными профилями
  игроков. Скрипт заранее копирует профили и настройки во временную папку и возвращает их
  на место после запуска, чтобы проверки не портили ваши данные.
#>
param(
	[string]$Only = "",
	[switch]$Quick
)

$ErrorActionPreference = "Stop"
$project = $PSScriptRoot

function Find-Godot {
	if ($env:GODOT -and (Test-Path $env:GODOT)) { return $env:GODOT }
	$cmd = Get-Command godot -ErrorAction SilentlyContinue
	if ($cmd) { return $cmd.Source }
	$found = Get-ChildItem -Path (Join-Path $env:USERPROFILE "Downloads") -Recurse -Filter "Godot_v4.6*win64*.exe" -ErrorAction SilentlyContinue |
		Where-Object { $_.Name -notlike "*console*" } | Select-Object -First 1
	if ($found) { return $found.FullName }
	throw "Godot не найден: задайте переменную GODOT (полный путь к Godot_v4.6*.exe)."
}

# Каждая проверка: имя, сцена (или скрипт для -s), как понять «всё хорошо», долгая ли она.
$tests = @(
	@{ Name = "Сцены компилируются (TestScenes)";        Scene = "TestScenes";       Pass = "ошибок 0 ===" },
	@{ Name = "Правила шахмат (TestRules)";              Scene = "TestRules";        Pass = "ИТОГО ошибок: 0" },
	@{ Name = "Рейтинг Glicko-2 (TestGlicko)";           Scene = "TestGlicko";       Pass = "ИТОГО ошибок: 0" },
	@{ Name = "Помощь и рейтинг (TestHelpRating)";        Scene = "TestHelpRating";   Pass = "ИТОГО ошибок: 0" },
	@{ Name = "Быстрый ИИ и эндшпиль (TestFastSearch)";  Scene = "TestFastSearch";   Pass = "ИТОГО ошибок: 0" },
	@{ Name = "Честность линейки точности (TestQualityRuler)"; Scene = "TestQualityRuler"; Pass = "ИТОГО ошибок: 0" },
	@{ Name = "Партии великих читаются (HistoricValidator)"; Scene = "HistoricValidator"; Pass = "ошибок 0" },
	@{ Name = "Комментарии к партиям (CommentStats)";    Scene = "CommentStats";     Pass = "расхождений: 0"; Also = "нераскрытым шаблоном: 0" },
	@{ Name = "Генераторы задач (TestGenerators)";       Scene = "TestGenerators";   PassCount = 5; PassText = "0/30 failed" },
	@{ Name = "Задачи на мат (VerifyPuzzles)";           Scene = "VerifyPuzzles";    Pass = "bad: 0" },
	@{ Name = "Карта (TestMap)";                         Scene = "TestMap";          Pass = "problems: 0" },
	@{ Name = "Лучшие ходы в дневнике (TestBestMoves)";  Scene = "TestBestMoves";    Pass = "ИТОГО ошибок: 0" },
	@{ Name = "База игроков и лиги (TestBots)";          Scene = "TestBots";         Pass = "ИТОГО ошибок: 0"; Slow = $true },
	@{ Name = "Интерфейс: наложения, кнопки (AuditUI)";  Scene = "AuditUI";          Pass = "ИТОГО проблем: 0"; Slow = $true },
	@{ Name = "«Дорога домой» (test_dynamic_road)";      Script = "res://scripts/tools/test_dynamic_road.gd"; Pass = "ALL DYNAMIC ROAD TESTS PASSED" },
	@{ Name = "Турниры (test_tournaments)";              Script = "res://scripts/tools/test_tournaments.gd";  Pass = "ALL TOURNAMENT TESTS PASSED" }
)

$godot = Find-Godot
Write-Host "Godot: $godot"
Write-Host "Проект: $project`n"

# --- защита профилей игроков ---
$userDir = Join-Path $env:APPDATA "Godot\app_userdata\chessoff"
$backup = Join-Path $env:TEMP ("chessoff_test_backup_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $backup | Out-Null
foreach ($item in @("users", "session.cfg", "settings.cfg")) {
	$src = Join-Path $userDir $item
	if (Test-Path $src) { Copy-Item -Recurse -Force $src (Join-Path $backup $item) }
}
Write-Host "Профили сохранены во временную копию: $backup`n"

# Проверкам нужен текущий игрок (иначе главное меню уходит на экран входа, а аудит
# интерфейса идёт медленным путём). Создаём временного игрока — после запуска он удаляется.
New-Item -ItemType Directory -Force -Path (Join-Path $userDir "users") | Out-Null
Get-ChildItem (Join-Path $userDir "users") -Filter *.cfg -ErrorAction SilentlyContinue | Remove-Item -Force
[IO.File]::WriteAllText((Join-Path (Join-Path $userDir "users") "testrunner.cfg"), "[meta]`n`ndisplay_name=`"TestRunner`"`n", (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $userDir "session.cfg"), "[session]`n`ncurrent_user=`"testrunner`"`n", (New-Object Text.UTF8Encoding($false)))

$results = @()
try {
	foreach ($t in $tests) {
		if ($Only -and $t.Name -notlike "*$Only*") { continue }
		if ($Quick -and $t.Slow) { continue }
		$out = Join-Path $env:TEMP ("chessoff_test_out_" + [guid]::NewGuid().ToString("N") + ".txt")
		$err = $out + ".err"
		if ($t.Scene) { $args = @("--headless", "--path", $project, "res://scenes/tools/$($t.Scene).tscn") }
		else { $args = @("--headless", "--path", $project, "-s", $t.Script) }
		$sw = [Diagnostics.Stopwatch]::StartNew()
		$proc = Start-Process -FilePath $godot -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
		$finished = $proc.WaitForExit(600000)
		if (-not $finished) { try { $proc.Kill() } catch {} }
		$sw.Stop()
		$text = if (Test-Path $out) { Get-Content $out -Raw -Encoding UTF8 } else { "" }
		if ($null -eq $text) { $text = "" }
		$ok = $false
		if ($finished) {
			if ($t.PassCount) { $ok = ([regex]::Matches($text, [regex]::Escape($t.PassText))).Count -ge $t.PassCount }
			else { $ok = $text.Contains($t.Pass) }
			if ($ok -and $t.Also) { $ok = $text.Contains($t.Also) }
			# явные провалы в тестах, которые печатают FAIL
			if ($ok -and ($text -match "(?m)^FAIL ")) { $ok = $false }
			if ($ok -and ($text -match "SCRIPT ERROR|Parse Error")) { $ok = $false }
		}
		$status = if (-not $finished) { "ЗАВИС" } elseif ($ok) { "OK" } else { "ПРОВАЛ" }
		$results += [pscustomobject]@{ Name = $t.Name; Status = $status; Sec = [math]::Round($sw.Elapsed.TotalSeconds, 1) }
		$color = if ($ok) { "Green" } else { "Red" }
		Write-Host ("{0,-7} {1,-58} {2,6} с" -f $status, $t.Name, [math]::Round($sw.Elapsed.TotalSeconds, 1)) -ForegroundColor $color
		if (-not $ok) {
			$lines = ($text -split "`n") | Where-Object { $_ -match "FAIL|ПРОБЛЕМ|ERROR|ошибок|problems|bad:" } | Select-Object -First 8
			$lines | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkYellow }
		}
		Remove-Item $out, $err -ErrorAction SilentlyContinue
	}
}
finally {
	# возвращаем профили как были (проверки могли что-то записать)
	$liveUsers = Join-Path $userDir "users"
	if (Test-Path (Join-Path $backup "users")) {
		if (Test-Path $liveUsers) { Get-ChildItem $liveUsers -Filter *.cfg -ErrorAction SilentlyContinue | Remove-Item -Force }
		New-Item -ItemType Directory -Force -Path $liveUsers | Out-Null
		Get-ChildItem (Join-Path $backup "users") -Filter *.cfg -ErrorAction SilentlyContinue | Copy-Item -Destination $liveUsers -Force
	} elseif (Test-Path $liveUsers) {
		Get-ChildItem $liveUsers -Filter *.cfg -ErrorAction SilentlyContinue | Remove-Item -Force
	}
	foreach ($f in @("session.cfg", "settings.cfg")) {
		$b = Join-Path $backup $f
		$l = Join-Path $userDir $f
		if (Test-Path $b) { Copy-Item -Force $b $l } elseif (Test-Path $l) { Remove-Item -Force $l }
	}
	Write-Host "`nПрофили и настройки возвращены на место." -ForegroundColor Cyan
}

$bad = @($results | Where-Object { $_.Status -ne "OK" })
Write-Host ("`nИТОГО: {0} проверок, успешно {1}, провалено {2}" -f $results.Count, ($results.Count - $bad.Count), $bad.Count) -ForegroundColor $(if ($bad.Count -eq 0) { "Green" } else { "Red" })
if ($bad.Count -gt 0) { exit 1 } else { exit 0 }
