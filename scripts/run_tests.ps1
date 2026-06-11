# Narrative System — full headless verification suite.
# Usage:
#   .\scripts\run_tests.ps1                 # import + tests + purity + db validation + demo boots
#   .\scripts\run_tests.ps1 -Filter lexer   # only test scripts matching "lexer"
#   .\scripts\run_tests.ps1 -SkipImport
param(
    [string]$Filter = "",
    [switch]$SkipImport,
    [string]$GodotExe = "C:\Users\machoman\Godot\Editors\4.6.3-stable\Godot_v4.6.3-stable_win64_console.exe"
)

$projectRoot = Split-Path $PSScriptRoot -Parent
$failed = $false

if (-not (Test-Path $GodotExe)) {
    Write-Host "ERROR: Godot console executable not found at: $GodotExe" -ForegroundColor Red
    Write-Host "Pass -GodotExe <path to Godot_v4.x_win64_console.exe>"
    exit 2
}

if (-not $SkipImport) {
    Write-Host "=== [1/5] Godot import ===" -ForegroundColor Cyan
    & $GodotExe --headless --path $projectRoot --import | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Import failed (exit $LASTEXITCODE)" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

Write-Host "=== [2/5] Unit tests ===" -ForegroundColor Cyan
$godotArgs = @("--headless", "--path", $projectRoot, "-s", "res://addons/narrative_system/tests/run_tests.gd")
if ($Filter) { $godotArgs += @("--", "--filter=$Filter") }
$testOut = & $GodotExe @godotArgs 2>&1
$testExit = $LASTEXITCODE
$testOut | ForEach-Object { Write-Host $_ }
if ($testExit -ne 0) { $failed = $true }
$scriptErrors = ($testOut | Select-String "SCRIPT ERROR").Count
if ($scriptErrors -gt 0) {
    Write-Host "FAIL: $scriptErrors SCRIPT ERROR line(s) in test output (compile/abort problems)" -ForegroundColor Red
    $failed = $true
}

if (-not $Filter) {
    Write-Host "=== [3/5] Happy-path purity (integration flow must be error/warning-free) ===" -ForegroundColor Cyan
    $pureOut = & $GodotExe --headless --path $projectRoot -s res://addons/narrative_system/tests/run_tests.gd -- --filter=integration_flow 2>&1
    if ($LASTEXITCODE -ne 0) { $failed = $true }
    $noise = $pureOut | Select-String -Pattern "^\s*(ERROR|WARNING|SCRIPT ERROR)"
    if ($noise.Count -gt 0) {
        Write-Host "FAIL: happy path emitted engine errors/warnings:" -ForegroundColor Red
        $noise | ForEach-Object { Write-Host "  $_" }
        $failed = $true
    } else {
        Write-Host "happy path clean (no engine errors or warnings)" -ForegroundColor Green
    }

    Write-Host "=== [4/5] Demo database validation (CLI) ===" -ForegroundColor Cyan
    & $GodotExe --headless --path $projectRoot -s res://addons/narrative_system/validation/validate_cli.gd -- --db=res://examples/integrated_demo/demo_database.tres --strict
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Demo database validation failed" -ForegroundColor Red
        $failed = $true
    }

    Write-Host "=== [5/5] Demo scene boots (headless, 30 frames each) ===" -ForegroundColor Cyan
    $demoScenes = @(
        "res://examples/basic_dialogue_demo/basic.tscn",
        "res://examples/branching_choice_demo/branching.tscn",
        "res://examples/quest_demo/quest.tscn",
        "res://examples/localization_cutscene_demo/loc_cutscene.tscn",
        "res://examples/integrated_demo/demo.tscn"
    )
    foreach ($scene in $demoScenes) {
        $bootOut = & $GodotExe --headless --quit-after 30 --path $projectRoot $scene 2>&1
        $bootErrors = ($bootOut | Select-String "SCRIPT ERROR").Count
        if ($LASTEXITCODE -ne 0 -or $bootErrors -gt 0) {
            Write-Host "FAIL boot: $scene (exit $LASTEXITCODE, $bootErrors script error(s))" -ForegroundColor Red
            $bootOut | Select-String "ERROR" | Select-Object -First 4 | ForEach-Object { Write-Host "  $_" }
            $failed = $true
        } else {
            Write-Host "boot ok: $scene" -ForegroundColor Green
        }
    }
}

if ($failed) {
    Write-Host "RESULT: FAIL" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: ALL GREEN" -ForegroundColor Green
exit 0
