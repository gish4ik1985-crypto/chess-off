<#
  Запуск всех автоматических проверок проекта одной командой.

    powershell -ExecutionPolicy Bypass -File run_tests.ps1            # всё
    powershell -ExecutionPolicy Bypass -File run_tests.ps1 -Only Rules # только тесты, в имени которых есть «Rules»
    powershell -ExecutionPolicy Bypass -File run_tests.ps1 -Quick      # без долгих проверок

  Путь к Godot берётся из переменной GODOT, иначе ищется в PATH и в папке Загрузки.

  ВАЖНО: часть проверок (AuditUI, TestBots, TestBestMoves) пишет в user://. Скрипт запускает
  их с подменённым APPDATA (временная песочница), поэтому живые профили игроков не трогаются.
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
	foreach ($dir in @("Downloads", "Desktop")) {
		$found = Get-ChildItem -Path (Join-Path $env:USERPROFILE $dir) -Recurse -Filter "Godot_v4*win64*.exe" -ErrorAction SilentlyContinue |
			Where-Object { $_.Name -notlike "*console*" } | Select-Object -First 1
		if ($found) { return $found.FullName }
	}
	throw "Godot не найден: задайте переменную GODOT (полный путь к Godot_v4*.exe)."
}

# Каждая проверка: имя, сцена (или скрипт для -s), как понять «всё хорошо», долгая ли она.
$tests = @(
	@{ Name = "Сцены компилируются (TestScenes)";        Scene = "TestScenes";       Pass = "ошибок 0 ===" },
	@{ Name = "Правила шахмат (TestRules)";              Scene = "TestRules";        Pass = "ИТОГО ошибок: 0" },
	@{ Name = "Рейтинг Glicko-2 (TestGlicko)";           Scene = "TestGlicko";       Pass = "ИТОГО ошибок: 0" },
	@{ Name = "Индекс мастерства и навыки (TestSkillProfile)"; Scene = "TestSkillProfile"; Pass = "ИТОГО ошибок: 0" },
	@{ Name = "Лестница уровней ИИ (TestLevelLadder)"; Scene = "TestLevelLadder"; Pass = "ИТОГО ошибок: 0" },
	@{ Name = "Правдоподобие рейтинга (TestRatingRealism)"; Scene = "TestRatingRealism"; Pass = "ИТОГО ошибок: 0" },
	@{ Name = "Согласованность шкал (TestScales)"; Scene = "TestScales"; Pass = "ИТОГО ошибок: 0" },
	@{ Name = "Помощь и рейтинг (TestHelpRating)";        Scene = "TestHelpRating";   Pass = "ИТОГО ошибок: 0" },
	@{ Name = "Живая сложность (TestAdaptive)"; Scene = "TestAdaptive"; Pass = "ИТОГО ошибок: 0" },
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
	@{ Name = "Сохранение профиля (test_profile_safety)"; Script = "res://scripts/tools/test_profile_safety.gd"; Pass = "ИТОГО ошибок: 0" },
	@{ Name = "Турниры (test_tournaments)";              Script = "res://scripts/tools/test_tournaments.gd";  Pass = "ALL TOURNAMENT TESTS PASSED" }
)

$godot = Find-Godot
Write-Host "Godot: $godot"
Write-Host "Проект: $project`n"

# --- изоляция от живых профилей игроков ---
# Проверки работают с настоящим Profile (AuditUI, TestBots, TestBestMoves), поэтому каждому
# запуску подсовываем СВОЙ APPDATA: Godot кладёт user:// в %APPDATA%\Godot\app_userdata\<проект>.
# Живые профили не копируются, не стираются и не возвращаются — их просто не видно тестам,
# так что обрыв скрипта (Ctrl+C, закрытое окно, kill) ничего не портит.
$realAppData = $env:APPDATA
$sandbox = Join-Path $env:TEMP ("chessoff_test_data_" + [guid]::NewGuid().ToString("N"))
$userDir = Join-Path $sandbox "Godot\app_userdata\chessoff"
New-Item -ItemType Directory -Force -Path (Join-Path $userDir "users") | Out-Null
$env:APPDATA = $sandbox
Write-Host "Тестовое хранилище (живые профили не затрагиваются): $sandbox`n"

# Проверкам нужен текущий игрок (иначе главное меню уходит на экран входа, а аудит
# интерфейса идёт медленным путём), поэтому создаём временного игрока в песочнице.
[IO.File]::WriteAllText((Join-Path (Join-Path $userDir "users") "testrunner.cfg"), "[meta]`ndisplay_name=`"TestRunner`"`n", (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $userDir "session.cfg"), "[session]`ncurrent_user=`"testrunner`"`n", (New-Object Text.UTF8Encoding($false)))

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
	$env:APPDATA = $realAppData
	Remove-Item -Recurse -Force $sandbox -ErrorAction SilentlyContinue
}

$bad = @($results | Where-Object { $_.Status -ne "OK" })
Write-Host ("`nИТОГО: {0} проверок, успешно {1}, провалено {2}" -f $results.Count, ($results.Count - $bad.Count), $bad.Count) -ForegroundColor $(if ($bad.Count -eq 0) { "Green" } else { "Red" })
if ($bad.Count -gt 0) { exit 1 } else { exit 0 }
