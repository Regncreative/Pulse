# Overnight soak for PulseService + Pulse UI (R1).
# Run manually; leave the machine awake. Collects periodic samples and optional dumps.
#
# Example (8 hours):
#   powershell -ExecutionPolicy Bypass -File .\tools\scripts\soak_overnight.ps1 -Hours 8
#
# Prerequisites:
#   - PulseService Running
#   - Pulse.exe open (System Health or Timeline preferred)
#   - Optional: enable Windows Error Reporting local dumps for Pulse.exe / PulseService.exe

param(
  [double]$Hours = 8,
  [int]$SampleSeconds = 60,
  [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ([string]::IsNullOrWhiteSpace($OutDir)) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $OutDir = Join-Path $root "artifacts\soak\$stamp"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$logCsv = Join-Path $OutDir "soak-samples.csv"
$eventLog = Join-Path $OutDir "soak-events.txt"
$readme = Join-Path $OutDir "README.txt"

@"
Pulse soak session
Started: $(Get-Date -Format o)
Hours: $Hours
Sample interval: ${SampleSeconds}s
OutDir: $OutDir

After completion, archive this folder with release notes.
Check:
  - soak-samples.csv for WorkingSet growth
  - soak-events.txt for unexpected exits
  - %LOCALAPPDATA%\CrashDumps for *.dmp (if WER local dumps enabled)
"@ | Set-Content -Path $readme -Encoding UTF8

"timestamp,pulseCount,pulseWs,serviceCount,serviceWs,mcpCount,mcpWs,scmStatus" |
  Set-Content -Path $logCsv -Encoding UTF8

$end = (Get-Date).AddHours($Hours)
Write-Host "Soak until $end → $OutDir"

function Sample-Row {
  $pulse = @(Get-Process -Name "Pulse" -ErrorAction SilentlyContinue)
  $svc = @(Get-Process -Name "PulseService" -ErrorAction SilentlyContinue)
  $mcp = @(Get-Process -Name "PulseMCP" -ErrorAction SilentlyContinue)
  $scm = Get-Service -Name "PulseService" -ErrorAction SilentlyContinue
  $scmStatus = if ($scm) { $scm.Status.ToString() } else { "missing" }
  $ts = (Get-Date).ToString("o")
  $row = "{0},{1},{2},{3},{4},{5},{6},{7}" -f `
    $ts, `
    $pulse.Count, `
    (($pulse | Measure-Object WorkingSet64 -Sum).Sum), `
    $svc.Count, `
    (($svc | Measure-Object WorkingSet64 -Sum).Sum), `
    $mcp.Count, `
    (($mcp | Measure-Object WorkingSet64 -Sum).Sum), `
    $scmStatus
  Add-Content -Path $logCsv -Value $row -Encoding UTF8

  if ($pulse.Count -eq 0) {
    Add-Content -Path $eventLog -Value "$ts WARN Pulse UI not running" -Encoding UTF8
  }
  if ($svc.Count -eq 0 -or $scmStatus -ne "Running") {
    Add-Content -Path $eventLog -Value "$ts WARN PulseService not running (SCM=$scmStatus)" -Encoding UTF8
  }
}

Sample-Row
while ((Get-Date) -lt $end) {
  Start-Sleep -Seconds $SampleSeconds
  Sample-Row
}

# Final summary
$lines = Get-Content $logCsv | Select-Object -Skip 1
$summaryPath = Join-Path $OutDir "soak-summary.txt"
if ($lines.Count -eq 0) {
  "No samples collected" | Set-Content $summaryPath
} else {
  $first = $lines[0].Split(",")
  $last = $lines[-1].Split(",")
  $pulseGrowth = [int64]$last[2] - [int64]$first[2]
  $svcGrowth = [int64]$last[4] - [int64]$first[4]
  @(
    "Soak finished: $(Get-Date -Format o)"
    "Samples: $($lines.Count)"
    "Pulse WS growth bytes: $pulseGrowth ($([math]::Round($pulseGrowth/1MB,2)) MB)"
    "PulseService WS growth bytes: $svcGrowth ($([math]::Round($svcGrowth/1MB,2)) MB)"
    "Review soak-events.txt for unexpected exits"
  ) | Set-Content -Path $summaryPath -Encoding UTF8
}

Write-Host "Soak complete. See $OutDir"
exit 0
