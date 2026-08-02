# Export validation helper (JSON v2 + CSV)

# Usage (from repo root, with Flutter on PATH or -Flutter):
#   powershell -ExecutionPolicy Bypass -File tools/scripts/validate_timeline_export.ps1

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
$mdPath = Join-Path $OutDir "timeline-export-validate-$stamp.md"

$flutterCmd = $Flutter
if (-not $flutterCmd) {
  $candidate = "C:\Users\ozsin\flutter\bin\flutter.bat"
  if (Test-Path $candidate) { $flutterCmd = $candidate }
}

$lines = @()
$lines += "# Timeline export validation"
$lines += ""
$lines += "Generated: $((Get-Date).ToUniversalTime().ToString('o'))"
$lines += ""
$lines += "## Automated unit coverage"
$lines += ""
$lines += "- timeline_export_test.dart - JSON v2 + CSV columns, filters, bookmarks, pins, incident meta"
$lines += "- Real live exports: use Timeline Export JSON / Export CSV on a filtered subset"
$lines += ""

$testExit = "skipped"
if ($flutterCmd -and (Test-Path $flutterCmd)) {
  Push-Location (Join-Path $root "apps\pulse_app")
  try {
    $out = & $flutterCmd test test/timeline_export_test.dart 2>&1 | Out-String
    $testExit = $LASTEXITCODE
  } finally {
    Pop-Location
  }
  $lines += '```'
  $lines += $out.Trim()
  $lines += '```'
  $lines += ""
  $lines += "Exit code: $testExit"
} else {
  $lines += "_Flutter SDK not found - documentation-only mode._"
}

$lines += ""
$lines += "## Manual real-data checklist"
$lines += ""
$lines += "1. Connect PulseService, retain a few dozen live events."
$lines += "2. Bookmark and pin at least one event; apply a filter (e.g. Errors)."
$lines += "3. Export JSON and CSV of the visible set."
$lines += "4. Confirm JSON `version: 2`, `applied_filters`, `bookmarked`/`pinned`, optional `incident_id`."
$lines += "5. Confirm CSV `# filter_*` comments and header includes bookmarked/pinned/incident columns."
$lines += ""

$lines -join "`n" | Set-Content -Path $mdPath -Encoding UTF8
Write-Host "Wrote $mdPath"
if ($testExit -ne "skipped") { exit $testExit }
