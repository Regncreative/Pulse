# Measure Pulse process footprints and optional IPC ping (R1).
# Does not invent metrics — reports only what Windows / ping tools return.

param(
  [string]$OutDir = "",
  [int]$IdleSeconds = 5
)

$ErrorActionPreference = "Stop"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ([string]::IsNullOrWhiteSpace($OutDir)) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $OutDir = Join-Path $root "artifacts\perf\$stamp"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Get-ProcSample([string]$Name) {
  $list = @(Get-Process -Name $Name -ErrorAction SilentlyContinue)
  if ($list.Count -eq 0) {
    return [pscustomobject]@{
      name = $Name
      count = 0
      workingSetBytes = $null
      privateBytes = $null
      cpuSeconds = $null
    }
  }
  $ws = ($list | Measure-Object WorkingSet64 -Sum).Sum
  $priv = ($list | Measure-Object PagedMemorySize64 -Sum).Sum
  $cpu = ($list | Measure-Object CPU -Sum).Sum
  return [pscustomobject]@{
    name = $Name
    count = $list.Count
    workingSetBytes = [int64]$ws
    privateBytes = [int64]$priv
    cpuSeconds = [double]$cpu
  }
}

Write-Host "Waiting $IdleSeconds s for a quiet sample…"
Start-Sleep -Seconds $IdleSeconds

$samples = @(
  (Get-ProcSample "Pulse"),
  (Get-ProcSample "PulseService"),
  (Get-ProcSample "PulseMCP"),
  (Get-ProcSample "node") # PulseMCP may run as node during dev
)

$svc = Get-Service -Name "PulseService" -ErrorAction SilentlyContinue
$meta = [ordered]@{
  capturedAt = (Get-Date).ToString("o")
  machine = $env:COMPUTERNAME
  pulseServiceScm = if ($svc) { $svc.Status.ToString() } else { "not_installed" }
  targets = [ordered]@{
    coldStartUiSeconds = 1
    idleUiRssBytes = 157286400
    minFps = 60
    ipcRttMs = 50
  }
  processes = $samples
}

$jsonPath = Join-Path $OutDir "perf-snapshot.json"
$meta | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding UTF8

$summary = Join-Path $OutDir "perf-summary.txt"
@(
  "Pulse performance snapshot"
  "Captured: $($meta.capturedAt)"
  "SCM PulseService: $($meta.pulseServiceScm)"
  ""
  "Targets (AGENTS / doc 01): cold start <1s, idle UI RSS <150 MB, FPS >=60, IPC <50 ms"
  ""
) + ($samples | ForEach-Object {
  if ($_.count -eq 0) {
    "$($_.name): not running"
  } else {
    $mb = [math]::Round($_.workingSetBytes / 1MB, 1)
    "$($_.name) x$($_.count): WS=${mb} MB  CPU-seconds=$($_.cpuSeconds)"
  }
}) | Set-Content -Path $summary -Encoding UTF8

Write-Host "Wrote $jsonPath"
Write-Host "Wrote $summary"
Get-Content $summary

# Optional diagnostics ping if built
$pingCandidates = @(
  (Join-Path $root "build\service\pulse_diagnostics_ping.exe"),
  "C:\dev\Pulse-service-release\pulse_diagnostics_ping.exe",
  "C:\dev\Pulse-service-build\pulse_diagnostics_ping.exe"
)
foreach ($p in $pingCandidates) {
  if (Test-Path $p) {
    Write-Host "Running diagnostics ping: $p"
    & $p 2>&1 | Tee-Object -FilePath (Join-Path $OutDir "diagnostics-ping.txt")
    break
  }
}

exit 0
