# Narrative System — full headless verification suite.
# Usage:
#   .\scripts\run_tests.ps1                 # import + all tests
#   .\scripts\run_tests.ps1 -Filter lexer   # only test scripts matching "lexer"
#   .\scripts\run_tests.ps1 -SkipImport     # skip the import step
param(
    [string]$Filter = "",
    [switch]$SkipImport,
    [string]$GodotExe = "C:\Users\machoman\Godot\Editors\4.6.3-stable\Godot_v4.6.3-stable_win64_console.exe"
)

$projectRoot = Split-Path $PSScriptRoot -Parent

if (-not (Test-Path $GodotExe)) {
    Write-Host "ERROR: Godot console executable not found at: $GodotExe" -ForegroundColor Red
    Write-Host "Pass -GodotExe <path to Godot_v4.x_win64_console.exe>"
    exit 2
}

if (-not $SkipImport) {
    Write-Host "=== Godot import ===" -ForegroundColor Cyan
    & $GodotExe --headless --path $projectRoot --import
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Import failed (exit $LASTEXITCODE)" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

Write-Host "=== Unit tests ===" -ForegroundColor Cyan
$godotArgs = @("--headless", "--path", $projectRoot, "-s", "res://addons/narrative_system/tests/run_tests.gd")
if ($Filter) { $godotArgs += @("--", "--filter=$Filter") }
& $GodotExe @godotArgs
$testExit = $LASTEXITCODE

if ($testExit -eq 0) {
    Write-Host "ALL GREEN" -ForegroundColor Green
} else {
    Write-Host "FAILURES (exit $testExit)" -ForegroundColor Red
}
exit $testExit
