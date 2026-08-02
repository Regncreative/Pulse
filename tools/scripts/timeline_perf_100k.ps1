# Timeline 100k retention / memory spot check helper.
# Does not inject Event Log data. Documents settings + optional Flutter perf test.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools/scripts/timeline_perf_100k.ps1

param(
  [string]$Flutter = "",
  [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path (Join-Path $root "AGENTS.md"))) { $root = (Get-Location).Path }
if (-not $OutDir) { $OutDir = Join-Path $root "tools\validation-results" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$mdPath = Join-Path $OutDir "timeline-perf-$stamp.md"

$lines = @()
$lines += "# Timeline 100k performance notes"
$lines += ""
$lines += "Generated: $((Get-Date).ToUniversalTime().ToString('o'))"
$lines += ""
$lines += "## Product gates"
$lines += ""
$lines += "- Settings → Timeline → Maximum stored events supports **100,000**."
$lines += "- List virtualization uses `SliverList` + stable `eventId` keys."
$lines += "- Raw Event XML is lazy-loaded via `GetTimelineEventDetail` (not kept on every list row)."
$lines += "- Raising the in-memory cap increases RAM roughly with average message size × count."
$lines += ""
$lines += "## Automated synthetic gate"
$lines += ""

$flutterCmd = $Flutter
if (-not $flutterCmd) {
  $candidate = "C:\Users\ozsin\flutter\bin\flutter.bat"
  if (Test-Path $candidate) { $flutterCmd = $candidate }
}

$testExit = "skipped"
$testOut = ""
if ($flutterCmd -and (Test-Path $flutterCmd)) {
  Push-Location (Join-Path $root "apps\pulse_app")
  try {
    $testOut = & $flutterCmd test test/timeline_perf_100k_test.dart 2>&1 | Out-String
    $testExit = $LASTEXITCODE
  } finally {
    Pop-Location
  }
  $lines += '```'
  $lines += $testOut.Trim()
  $lines += '```'
  $lines += ""
  $lines += "Flutter test exit code: $testExit"
} else {
  $lines += "_Flutter SDK not found - ran documentation-only mode._"
}

$lines += ""
$lines += "## Manual checklist"
$lines += ""
$lines += "1. Set Timeline max stored events to 100,000."
$lines += "2. Connect to a busy machine / leave Live running until the buffer fills."
$lines += "3. Confirm scrolling stays smooth and details open without hitching the list."
$lines += "4. Export JSON/CSV of a filtered subset and confirm file size is sane."
$lines += ""

$lines -join "`n" | Set-Content -Path $mdPath -Encoding UTF8
Write-Host "Wrote $mdPath"
if ($testExit -ne "skipped") { exit $testExit }
