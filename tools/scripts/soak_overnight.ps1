# Overnight soak for PulseService + Pulse UI (R1 validation tooling).
# Run manually; leave the machine awake. Emits CSV samples plus final JSON/MD reports.
#
# Example (8 hours):
#   powershell -ExecutionPolicy Bypass -File .\tools\scripts\soak_overnight.ps1 -Hours 8
#
# Final reports (always):
#   tools/soak-results/soak-report-<stamp>.json
#   tools/soak-results/soak-report-<stamp>.md
# Plus a detailed working folder under artifacts/soak/<stamp>/ (gitignored).
#
# Prerequisites:
#   - PulseService Running
#   - Pulse.exe open (System Health or Timeline preferred)
#   - Optional: rebuild pulse_diagnostics_ping for SOAK_METRICS (dropped / reconnects)
#   - Optional: WER local dumps for Pulse.exe / PulseService.exe

param(
  [double]$Hours = 8,
  [int]$SampleSeconds = 60,
  [string]$OutDir = "",
  [string]$ResultsDir = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
if ([string]::IsNullOrWhiteSpace($OutDir)) {
  $OutDir = Join-Path $root "artifacts\soak\$stamp"
}
if ([string]::IsNullOrWhiteSpace($ResultsDir)) {
  $ResultsDir = Join-Path $root "tools\soak-results"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
New-Item -ItemType Directory -Force -Path $ResultsDir | Out-Null

$logCsv = Join-Path $OutDir "soak-samples.csv"
$eventLog = Join-Path $OutDir "soak-events.txt"
$readme = Join-Path $OutDir "README.txt"
$startedAt = Get-Date
$logicalCpus = [Environment]::ProcessorCount
if ($logicalCpus -lt 1) { $logicalCpus = 1 }

@"
Pulse soak session
Started: $($startedAt.ToString("o"))
Hours: $Hours
Sample interval: ${SampleSeconds}s
OutDir: $OutDir
ResultsDir: $ResultsDir

Reports written at end:
  tools/soak-results/soak-report-*.json
  tools/soak-results/soak-report-*.md
"@ | Set-Content -Path $readme -Encoding UTF8

"timestamp,pulseCount,pulseWs,pulseCpuPct,pulsePid,serviceCount,serviceWs,serviceCpuPct,servicePid,mcpCount,mcpWs,mcpCpuPct,mcpPid,scmStatus" |
  Set-Content -Path $logCsv -Encoding UTF8
"" | Set-Content -Path $eventLog -Encoding UTF8

$end = $startedAt.AddHours($Hours)
Write-Host "Soak until $($end.ToString('o')) -> $OutDir"
Write-Host "Final reports -> $ResultsDir"

# --- helpers ---

function Write-SoakEvent([string]$Level, [string]$Message) {
  $line = "{0} {1} {2}" -f (Get-Date).ToString("o"), $Level, $Message
  Add-Content -Path $eventLog -Value $line -Encoding UTF8
  Write-Host $line
}

function Get-ProcBundle([string]$Name) {
  $list = @(Get-Process -Name $Name -ErrorAction SilentlyContinue)
  if ($list.Count -eq 0) {
    return [pscustomobject]@{
      Count = 0
      Ws = [int64]0
      CpuSec = [double]0
      Pid = 0
      StartTime = $null
    }
  }
  $primary = $list | Sort-Object WorkingSet64 -Descending | Select-Object -First 1
  return [pscustomobject]@{
    Count = $list.Count
    Ws = [int64](($list | Measure-Object WorkingSet64 -Sum).Sum)
    CpuSec = [double](($list | Measure-Object CPU -Sum).Sum)
    Pid = [int]$primary.Id
    StartTime = $primary.StartTime
  }
}

function Get-CpuPct([double]$PrevCpuSec, [double]$CurrCpuSec, [double]$ElapsedSec) {
  if ($ElapsedSec -le 0) { return $null }
  $delta = $CurrCpuSec - $PrevCpuSec
  if ($delta -lt 0) { $delta = 0 }
  # Percent of one logical CPU (not divided by core count) - comparable across samples.
  return [math]::Round(($delta / $ElapsedSec) * 100.0, 2)
}

function Find-DiagnosticsPing {
  $candidates = @(
    "C:\dev\Pulse-service-build-r1\pulse_diagnostics_ping.exe",
    (Join-Path $root "build\service\Release\pulse_diagnostics_ping.exe"),
    (Join-Path $root "build\service\pulse_diagnostics_ping.exe"),
    "C:\dev\Pulse-service-release\pulse_diagnostics_ping.exe",
    "C:\dev\Pulse-service-build\pulse_diagnostics_ping.exe"
  )
  foreach ($p in $candidates) {
    if (Test-Path $p) { return $p }
  }
  return $null
}

function Invoke-SoakMetricsCapture([string]$Label) {
  $exe = Find-DiagnosticsPing
  $result = [ordered]@{
    label = $Label
    capturedAt = (Get-Date).ToString("o")
    available = $false
    toolPath = $exe
    exitCode = $null
    liveEventsDropped = $null
    liveSubscriberReconnects = $null
    liveQueueDepth = $null
    liveQueueCapacity = $null
    liveEventsPushed = $null
    ipcErrors = $null
    serviceUptimeMs = $null
    raw = $null
    note = $null
  }
  if (-not $exe) {
    $result.note = "pulse_diagnostics_ping.exe not found - rebuild service tools to capture SOAK_METRICS"
    return [pscustomobject]$result
  }
  $outFile = Join-Path $OutDir ("diagnostics-ping-{0}.txt" -f $Label)
  $errFile = Join-Path $OutDir ("diagnostics-ping-{0}.err.txt" -f $Label)
  try {
    # Bound runtime: a stuck named-pipe client must not block the soak report.
    $proc = Start-Process -FilePath $exe `
      -NoNewWindow -PassThru `
      -RedirectStandardOutput $outFile `
      -RedirectStandardError $errFile
    $ok = $proc.WaitForExit(45000)
    if (-not $ok -or -not $proc.HasExited) {
      try { if (-not $proc.HasExited) { $proc.Kill() } } catch { }
      $result.note = "diagnostics ping timed out after 45s ($Label)"
      Write-SoakEvent "WARN" $result.note
      return [pscustomobject]$result
    }
    # Ensure ExitCode is populated after HasExited.
    Start-Sleep -Milliseconds 50
    $exit = $proc.ExitCode
    if ($null -eq $exit) { $exit = -1 }
    $output = @()
    if (Test-Path $outFile) { $output += Get-Content $outFile -ErrorAction SilentlyContinue }
    if (Test-Path $errFile) { $output += Get-Content $errFile -ErrorAction SilentlyContinue }
    $result.exitCode = $exit
    $result.raw = ($output -join "`n")
    $metricsLine = $output | Where-Object { $_ -match '^SOAK_METRICS\b' } | Select-Object -Last 1
    if ($metricsLine) {
      $result.available = $true
      if ($metricsLine -match 'live_events_dropped=(\d+)') { $result.liveEventsDropped = [int64]$Matches[1] }
      if ($metricsLine -match 'live_subscriber_reconnects=(\d+)') { $result.liveSubscriberReconnects = [int64]$Matches[1] }
      if ($metricsLine -match 'live_queue_depth=(\d+)') { $result.liveQueueDepth = [int64]$Matches[1] }
      if ($metricsLine -match 'live_queue_capacity=(\d+)') { $result.liveQueueCapacity = [int64]$Matches[1] }
      if ($metricsLine -match 'live_events_pushed=(\d+)') { $result.liveEventsPushed = [int64]$Matches[1] }
      if ($metricsLine -match 'ipc_errors=(\d+)') { $result.ipcErrors = [int64]$Matches[1] }
      if ($metricsLine -match 'service_uptime_ms=(\d+)') { $result.serviceUptimeMs = [int64]$Matches[1] }
    } else {
      $result.note = "SOAK_METRICS line missing - rebuild pulse_diagnostics_ping from current tree"
    }
    if ($exit -ne 0 -and -not ($output -match 'SMOKE_OK')) {
      Write-SoakEvent "WARN" "diagnostics ping ($Label) exit=$exit"
    } elseif ($exit -ne 0 -and ($output -match 'SMOKE_OK')) {
      # Some hosts report a blank/odd ExitCode even on success; trust SMOKE_OK.
      $result.exitCode = 0
    }
  } catch {
    $result.note = "diagnostics ping failed: $($_.Exception.Message)"
    Write-SoakEvent "WARN" $result.note
  }
  return [pscustomobject]$result
}

function Get-PulseCrashDumps {
  $dirs = @(
    (Join-Path $env:LOCALAPPDATA "CrashDumps"),
    "C:\Windows\System32\config\systemprofile\AppData\Local\CrashDumps"
  )
  $found = @()
  foreach ($d in $dirs) {
    try {
      if (-not (Test-Path -LiteralPath $d -ErrorAction Stop)) { continue }
      Get-ChildItem -LiteralPath $d -Filter "*.dmp" -ErrorAction Stop |
        Where-Object {
          $_.Name -match '(?i)^(Pulse|PulseService|PulseMCP)' -or
          $_.Name -match '(?i)Pulse'
        } |
        ForEach-Object {
          $found += [pscustomobject]@{
            path = $_.FullName
            name = $_.Name
            lengthBytes = $_.Length
            lastWriteTime = $_.LastWriteTime.ToString("o")
          }
        }
    } catch {
      # Access denied / missing folder - skip; do not abort soak report.
    }
  }
  return $found
}

function Get-PulseEventLogErrors([datetime]$Since) {
  # Run in a background job with a hard timeout - Application logs can stall.
  $job = Start-Job -ScriptBlock {
    param($SinceUtc)
    $since = [datetime]::Parse($SinceUtc, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
    $errors = @()
    foreach ($logName in @("Application", "System")) {
      try {
        Get-WinEvent -FilterHashtable @{ LogName = $logName; StartTime = $since } -MaxEvents 200 -ErrorAction Stop |
          Where-Object {
            ($_.Level -in 2, 3) -and (
              $_.ProviderName -match '(?i)Pulse' -or
              $_.Message -match '(?i)Pulse(Service|MCP)?\.exe' -or
              $_.Message -match '(?i)\\Pulse\\'
            )
          } |
          Select-Object -First 30 |
          ForEach-Object {
            $msg = ""
            try {
              $msg = (($_.Message -replace '\s+', ' ').Trim())
              if ($msg.Length -gt 400) { $msg = $msg.Substring(0, 400) }
            } catch { }
            $errors += [pscustomobject]@{
              logName = $logName
              timeCreated = $_.TimeCreated.ToString("o")
              level = $_.LevelDisplayName
              provider = $_.ProviderName
              id = $_.Id
              message = $msg
            }
          }
      } catch { }
    }
    return $errors
  } -ArgumentList $Since.ToUniversalTime().ToString("o")

  $done = Wait-Job $job -Timeout 20
  if (-not $done) {
    Stop-Job $job -ErrorAction SilentlyContinue
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    return @([pscustomobject]@{
      logName = "n/a"
      timeCreated = (Get-Date).ToString("o")
      level = "Warning"
      provider = "soak_overnight.ps1"
      id = 0
      message = "Event Log scan timed out after 20s; skipped for soak report"
    })
  }
  $result = @(Receive-Job $job)
  Remove-Job $job -Force -ErrorAction SilentlyContinue
  return $result
}

function Format-Duration([TimeSpan]$Span) {
  if ($null -eq $Span) { return $null }
  return "{0:d2}:{1:d2}:{2:d2}" -f [int]$Span.TotalHours, $Span.Minutes, $Span.Seconds
}

# --- sampling loop ---

$prev = @{
  PulseCpu = $null
  ServiceCpu = $null
  McpCpu = $null
  SampleAt = $null
}
$prevServicePid = $null
$serviceRestartCount = 0
$pulseMissingSamples = 0
$serviceMissingSamples = 0
$exceptionLines = @()

$metricsStart = Invoke-SoakMetricsCapture "start"

function Sample-Row {
  $now = Get-Date
  $pulse = Get-ProcBundle "Pulse"
  $svc = Get-ProcBundle "PulseService"
  $mcp = Get-ProcBundle "PulseMCP"
  $scm = Get-Service -Name "PulseService" -ErrorAction SilentlyContinue
  $scmStatus = if ($scm) { $scm.Status.ToString() } else { "missing" }

  $elapsed = if ($prev.SampleAt) { ($now - $prev.SampleAt).TotalSeconds } else { [double]$SampleSeconds }
  $pulseCpuPct = if ($null -ne $prev.PulseCpu) { Get-CpuPct $prev.PulseCpu $pulse.CpuSec $elapsed } else { $null }
  $svcCpuPct = if ($null -ne $prev.ServiceCpu) { Get-CpuPct $prev.ServiceCpu $svc.CpuSec $elapsed } else { $null }
  $mcpCpuPct = if ($null -ne $prev.McpCpu -and $mcp.Count -gt 0) { Get-CpuPct $prev.McpCpu $mcp.CpuSec $elapsed } else { $null }

  $ts = $now.ToString("o")
  $row = "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11},{12},{13}" -f `
    $ts, `
    $pulse.Count, `
    $pulse.Ws, `
    $(if ($null -eq $pulseCpuPct) { "" } else { $pulseCpuPct }), `
    $pulse.Pid, `
    $svc.Count, `
    $svc.Ws, `
    $(if ($null -eq $svcCpuPct) { "" } else { $svcCpuPct }), `
    $svc.Pid, `
    $mcp.Count, `
    $mcp.Ws, `
    $(if ($null -eq $mcpCpuPct) { "" } else { $mcpCpuPct }), `
    $mcp.Pid, `
    $scmStatus
  Add-Content -Path $logCsv -Value $row -Encoding UTF8

  if ($pulse.Count -eq 0) {
    $script:pulseMissingSamples++
    Write-SoakEvent "WARN" "Pulse UI not running"
  }
  if ($svc.Count -eq 0 -or $scmStatus -ne "Running") {
    $script:serviceMissingSamples++
    Write-SoakEvent "WARN" "PulseService not running (SCM=$scmStatus)"
  }
  if ($null -ne $prevServicePid -and $svc.Pid -ne 0 -and $svc.Pid -ne $prevServicePid) {
    $script:serviceRestartCount++
    Write-SoakEvent "WARN" "PulseService PID changed $($prevServicePid) -> $($svc.Pid) (restart detected)"
  }
  if ($svc.Pid -ne 0) { $script:prevServicePid = $svc.Pid }

  $prev.PulseCpu = $pulse.CpuSec
  $prev.ServiceCpu = $svc.CpuSec
  $prev.McpCpu = $mcp.CpuSec
  $prev.SampleAt = $now

  return [pscustomobject]@{
    At = $now
    Pulse = $pulse
    Service = $svc
    Mcp = $mcp
    PulseCpuPct = $pulseCpuPct
    ServiceCpuPct = $svcCpuPct
    McpCpuPct = $mcpCpuPct
    ScmStatus = $scmStatus
  }
}

# First sample (CPU % null - no prior baseline)
$firstSample = Sample-Row
while ((Get-Date) -lt $end) {
  Start-Sleep -Seconds $SampleSeconds
  [void](Sample-Row)
}

$finishedAt = Get-Date
$totalRuntime = $finishedAt - $startedAt
Write-Host "Collecting end-of-soak diagnostics metrics..."
$metricsEnd = Invoke-SoakMetricsCapture "end"

Write-Host "Aggregating samples..."

$lines = @(Get-Content $logCsv | Select-Object -Skip 1 | Where-Object { $_.Trim() -ne "" })
$pulseWsSeries = @()
$serviceWsSeries = @()
$mcpWsSeries = @()
$pulseCpuSeries = @()
$serviceCpuSeries = @()
$mcpCpuSeries = @()

foreach ($line in $lines) {
  $c = $line.Split(",")
  if ($c.Length -lt 14) { continue }
  if ($c[1] -as [int] -gt 0) { $pulseWsSeries += [int64]$c[2] }
  if ($c[3] -ne "") { $pulseCpuSeries += [double]$c[3] }
  if ($c[5] -as [int] -gt 0) { $serviceWsSeries += [int64]$c[6] }
  if ($c[7] -ne "") { $serviceCpuSeries += [double]$c[7] }
  if ($c[9] -as [int] -gt 0) { $mcpWsSeries += [int64]$c[10] }
  if ($c[11] -ne "") { $mcpCpuSeries += [double]$c[11] }
}

function Series-Stats([array]$Values) {
  if (-not $Values -or $Values.Count -eq 0) {
    return [pscustomobject]@{
      count = 0; peak = $null; average = $null; first = $null; last = $null; growth = $null
    }
  }
  $first = $Values[0]
  $last = $Values[$Values.Count - 1]
  return [pscustomobject]@{
    count = $Values.Count
    peak = ($Values | Measure-Object -Maximum).Maximum
    average = [math]::Round((($Values | Measure-Object -Average).Average), 2)
    first = $first
    last = $last
    growth = $last - $first
  }
}

$pulseMem = Series-Stats $pulseWsSeries
$serviceMem = Series-Stats $serviceWsSeries
$mcpMem = Series-Stats $mcpWsSeries
$pulseCpu = Series-Stats $pulseCpuSeries
$serviceCpu = Series-Stats $serviceCpuSeries
$mcpCpu = Series-Stats $mcpCpuSeries

# Process uptimes at end
$pulseEnd = Get-ProcBundle "Pulse"
$svcEnd = Get-ProcBundle "PulseService"
$mcpEnd = Get-ProcBundle "PulseMCP"

function Get-UptimeSeconds($StartTime, [datetime]$Until) {
  if ($null -eq $StartTime) { return $null }
  return [math]::Round(($Until - $StartTime).TotalSeconds, 1)
}

$pulseUptimeSec = Get-UptimeSeconds $pulseEnd.StartTime $finishedAt
$serviceUptimeSec = Get-UptimeSeconds $svcEnd.StartTime $finishedAt
$mcpUptimeSec = Get-UptimeSeconds $mcpEnd.StartTime $finishedAt

# Prefer service uptime from SOAK_METRICS when available (service clock)
if ($null -ne $metricsEnd.serviceUptimeMs) {
  $serviceUptimeSecFromSnap = [math]::Round($metricsEnd.serviceUptimeMs / 1000.0, 1)
} else {
  $serviceUptimeSecFromSnap = $null
}

Write-Host "Scanning crash dumps..."
$crashDumpsInWindow = @(Get-PulseCrashDumps | Where-Object {
  try { [datetime]$_.lastWriteTime -ge $startedAt } catch { $false }
})

Write-Host "Scanning Windows Event Log (bounded)..."
$eventLogHits = @(Get-PulseEventLogErrors $startedAt)
Write-Host "Building verdict..."
$soakEventLines = @(Get-Content $eventLog -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -ne "" } | ForEach-Object { [string]$_ })
$exceptionDetected = [System.Collections.ArrayList]@()
foreach ($line in $soakEventLines) {
  if ($line -match '\b(ERROR|EXCEPTION|CRASH|FATAL)\b') { [void]$exceptionDetected.Add([string]$line) }
  elseif ($line -match 'Pulse UI not running|PulseService not running|PID changed') { [void]$exceptionDetected.Add([string]$line) }
}
$exceptionDetected = @($exceptionDetected | Select-Object -Unique)

$droppedSamples = $null
$queueOverflows = $null
$ipcReconnects = $null
if ($metricsEnd.available) {
  $queueOverflows = $metricsEnd.liveEventsDropped
  $droppedSamples = $null
  $ipcReconnects = $metricsEnd.liveSubscriberReconnects
} elseif ($metricsStart.available) {
  $queueOverflows = $metricsStart.liveEventsDropped
  $ipcReconnects = $metricsStart.liveSubscriberReconnects
}

$clientReconnectNote = "Flutter IPC client reconnectCount is UI-only; soak harness reports service live_subscriber_reconnects when SOAK_METRICS is available."

# --- verdict ---
Write-Host "Computing pass/fail reasons..."
$failReasons = New-Object System.Collections.ArrayList
$warnReasons = New-Object System.Collections.ArrayList

if ($lines.Count -lt 2) {
  [void]$failReasons.Add("Insufficient samples collected ($($lines.Count))")
}
if ($serviceMissingSamples -gt 0) {
  [void]$failReasons.Add("PulseService missing or not Running on $serviceMissingSamples sample(s)")
}
if ($crashDumpsInWindow.Count -gt 0) {
  [void]$failReasons.Add("Crash dump(s) found during soak window: $($crashDumpsInWindow.Count)")
}
$appErrors = @($eventLogHits | Where-Object { $_.level -match '(?i)error' -and $_.provider -ne "soak_overnight.ps1" })
if ($appErrors.Count -gt 0) {
  [void]$failReasons.Add("Windows Event Log error(s) related to Pulse: $($appErrors.Count)")
}

if ($pulseMissingSamples -gt 0) {
  [void]$warnReasons.Add("Pulse UI missing on $pulseMissingSamples sample(s)")
}
if ($serviceRestartCount -gt 0) {
  [void]$warnReasons.Add("PulseService restart(s) detected: $serviceRestartCount")
}
# Memory growth warnings (honest thresholds - not AGENTS invent)
$uiGrowthMb = if ($null -ne $pulseMem.growth) { [math]::Round($pulseMem.growth / 1MB, 2) } else { $null }
$svcGrowthMb = if ($null -ne $serviceMem.growth) { [math]::Round($serviceMem.growth / 1MB, 2) } else { $null }
if ($null -ne $uiGrowthMb -and $uiGrowthMb -ge 50) {
  [void]$warnReasons.Add("Pulse UI working-set growth ${uiGrowthMb} MB (>= 50 MB warn threshold)")
}
if ($null -ne $svcGrowthMb -and $svcGrowthMb -ge 30) {
  [void]$warnReasons.Add("PulseService working-set growth ${svcGrowthMb} MB (>= 30 MB warn threshold)")
}
if ($null -ne $queueOverflows -and $queueOverflows -gt 0) {
  [void]$warnReasons.Add("Live queue overflows (live_events_dropped)=$queueOverflows")
}
if ($null -ne $ipcReconnects -and $ipcReconnects -gt 0) {
  [void]$warnReasons.Add("Event Log subscription reconnects=$ipcReconnects")
}
if (-not $metricsEnd.available) {
  [void]$warnReasons.Add("End-of-soak SOAK_METRICS unavailable ($($metricsEnd.note))")
}
$realEventWarnings = @($eventLogHits | Where-Object { $_.level -match '(?i)warning' -and $_.provider -ne "soak_overnight.ps1" })
if ($realEventWarnings.Count -gt 0) {
  [void]$warnReasons.Add("Windows Event Log warning(s) related to Pulse")
}
$eventScanTimeout = @($eventLogHits | Where-Object { $_.provider -eq "soak_overnight.ps1" })
if ($eventScanTimeout.Count -gt 0) {
  [void]$warnReasons.Add("Event Log scan timed out or was skipped")
}

if ($failReasons.Count -gt 0) {
  $verdict = "FAIL"
} elseif ($warnReasons.Count -gt 0) {
  $verdict = "PASS WITH WARNINGS"
} else {
  $verdict = "PASS"
}

function Compact-Metrics($m) {
  if ($null -eq $m) { return $null }
  return [ordered]@{
    label = $m.label
    capturedAt = $m.capturedAt
    available = $m.available
    exitCode = $m.exitCode
    liveEventsDropped = $m.liveEventsDropped
    liveSubscriberReconnects = $m.liveSubscriberReconnects
    liveQueueDepth = $m.liveQueueDepth
    liveQueueCapacity = $m.liveQueueCapacity
    liveEventsPushed = $m.liveEventsPushed
    ipcErrors = $m.ipcErrors
    serviceUptimeMs = $m.serviceUptimeMs
    note = $m.note
  }
}

Write-Host "Assembling JSON report..."
# Flatten to primitives only. Deserialized WinEvent/Match objects explode under ConvertTo-Json.
$eventLogPlain = New-Object System.Collections.ArrayList
foreach ($e in @($eventLogHits)) {
  [void]$eventLogPlain.Add([ordered]@{
    logName = [string]$e.logName
    timeCreated = [string]$e.timeCreated
    level = [string]$e.level
    provider = [string]$e.provider
    id = [int]($(if ($null -eq $e.id) { 0 } else { $e.id }))
    message = [string]$e.message
  })
}
$crashPlain = New-Object System.Collections.ArrayList
foreach ($d in @($crashDumpsInWindow)) {
  [void]$crashPlain.Add([ordered]@{
    path = [string]$d.path
    name = [string]$d.name
    lengthBytes = [int64]($(if ($null -eq $d.lengthBytes) { 0 } else { $d.lengthBytes }))
    lastWriteTime = [string]$d.lastWriteTime
  })
}
$exceptionPlain = @($exceptionDetected | ForEach-Object { [string]$_ })
$failPlain = @($failReasons | ForEach-Object { [string]$_ })
$warnPlain = @($warnReasons | ForEach-Object { [string]$_ })

$report = [ordered]@{
  schemaVersion = 1
  generatedAt = [string]$finishedAt.ToString("o")
  soak = [ordered]@{
    startedAt = [string]$startedAt.ToString("o")
    finishedAt = [string]$finishedAt.ToString("o")
    requestedHours = [double]$Hours
    sampleSeconds = [int]$SampleSeconds
    totalRuntimeSeconds = [double]([math]::Round($totalRuntime.TotalSeconds, 1))
    totalRuntime = [string](Format-Duration $totalRuntime)
    sampleCount = [int]$lines.Count
    logicalCpus = [int]$logicalCpus
    outDir = [string]$OutDir
  }
  uptimeSeconds = [ordered]@{
    pulse = $pulseUptimeSec
    pulseService = $(if ($null -ne $serviceUptimeSecFromSnap) { $serviceUptimeSecFromSnap } else { $serviceUptimeSec })
    pulseServiceSource = $(if ($null -ne $serviceUptimeSecFromSnap) { "diagnostics_snapshot" } else { "process_start_time" })
    pulseMcp = $mcpUptimeSec
    pulseMcpRunning = [bool]($mcpEnd.Count -gt 0)
  }
  cpuPercentOfOneLogicalCpu = [ordered]@{
    pulse = [ordered]@{ peak = $pulseCpu.peak; average = $pulseCpu.average }
    pulseService = [ordered]@{ peak = $serviceCpu.peak; average = $serviceCpu.average }
    pulseMcp = [ordered]@{ peak = $mcpCpu.peak; average = $mcpCpu.average }
  }
  memoryWorkingSetBytes = [ordered]@{
    pulse = [ordered]@{
      peak = $pulseMem.peak
      final = $pulseMem.last
      growth = $pulseMem.growth
      growthMb = $uiGrowthMb
    }
    pulseService = [ordered]@{
      peak = $serviceMem.peak
      final = $serviceMem.last
      growth = $serviceMem.growth
      growthMb = $svcGrowthMb
    }
    pulseMcp = [ordered]@{
      peak = $mcpMem.peak
      final = $mcpMem.last
      growth = $mcpMem.growth
      growthMb = $(if ($null -ne $mcpMem.growth) { [math]::Round($mcpMem.growth / 1MB, 2) } else { $null })
    }
  }
  ipcAndQueues = [ordered]@{
    ipcReconnectCount = $ipcReconnects
    ipcReconnectSource = "live_subscriber_reconnects (service)"
    ipcClientReconnectCount = $null
    ipcClientReconnectNote = [string]$clientReconnectNote
    queueOverflows = $queueOverflows
    queueOverflowSource = "live_events_dropped (drop-oldest outbound)"
    droppedSamplesCollectors = $null
    droppedSamplesNote = "Collector dropped-samples counter is Not supported; use queueOverflows for live backpressure"
    liveQueueDepthEnd = $metricsEnd.liveQueueDepth
    liveQueueCapacity = $metricsEnd.liveQueueCapacity
    ipcErrors = $metricsEnd.ipcErrors
    metricsStart = (Compact-Metrics $metricsStart)
    metricsEnd = (Compact-Metrics $metricsEnd)
  }
  stability = [ordered]@{
    serviceRestarts = [int]$serviceRestartCount
    pulseUiMissingSamples = [int]$pulseMissingSamples
    pulseServiceMissingSamples = [int]$serviceMissingSamples
    exceptionsDetected = $exceptionPlain
    exceptionCount = [int]$exceptionPlain.Count
    crashDumpsFound = @($crashPlain)
    crashDumpCount = [int]$crashPlain.Count
    windowsEventLogRelated = @($eventLogPlain)
    windowsEventLogCount = [int]$eventLogPlain.Count
  }
  verdict = [ordered]@{
    result = [string]$verdict
    failReasons = $failPlain
    warningReasons = $warnPlain
  }
}

$jsonPath = Join-Path $ResultsDir "soak-report-$stamp.json"
$mdPath = Join-Path $ResultsDir "soak-report-$stamp.md"
Write-Host "Writing $jsonPath"
$jsonText = ConvertTo-Json -InputObject ([pscustomobject]$report) -Depth 6
if ($jsonText.Length -gt 2MB) {
  throw "Soak JSON report unexpectedly large ($($jsonText.Length) bytes) - aborting write"
}
[System.IO.File]::WriteAllText($jsonPath, $jsonText, [System.Text.UTF8Encoding]::new($false))
Copy-Item $jsonPath (Join-Path $OutDir "soak-report.json") -Force
Write-Host "Writing $mdPath"

function Fmt-Bytes($b) {
  if ($null -eq $b) { return "n/a" }
  return ("{0:N1} MB ({1})" -f ($b / 1MB), $b)
}

$md = @"
# Pulse soak report

| Field | Value |
|-------|-------|
| **Verdict** | **$verdict** |
| Generated | $($finishedAt.ToString("o")) |
| Requested duration | $Hours h |
| Total runtime | $(Format-Duration $totalRuntime) ($([math]::Round($totalRuntime.TotalSeconds,1)) s) |
| Samples | $($lines.Count) (every ${SampleSeconds}s) |
| Session folder | ``$OutDir`` |

## Uptime

| Process | Uptime |
|---------|--------|
| Pulse | $(if ($null -eq $pulseUptimeSec) { "not running at end" } else { "$pulseUptimeSec s" }) |
| PulseService | $(if ($null -ne $serviceUptimeSecFromSnap) { "$serviceUptimeSecFromSnap s (diagnostics snapshot)" } elseif ($null -eq $serviceUptimeSec) { "not running at end" } else { "$serviceUptimeSec s (process StartTime)" }) |
| PulseMCP | $(if ($mcpEnd.Count -eq 0) { "not running" } elseif ($null -eq $mcpUptimeSec) { "running (uptime n/a)" } else { "$mcpUptimeSec s" }) |

## CPU (% of one logical CPU)

| Process | Peak | Average |
|---------|------|---------|
| Pulse | $(if ($null -eq $pulseCpu.peak) { "n/a" } else { $pulseCpu.peak }) | $(if ($null -eq $pulseCpu.average) { "n/a" } else { $pulseCpu.average }) |
| PulseService | $(if ($null -eq $serviceCpu.peak) { "n/a" } else { $serviceCpu.peak }) | $(if ($null -eq $serviceCpu.average) { "n/a" } else { $serviceCpu.average }) |
| PulseMCP | $(if ($null -eq $mcpCpu.peak) { "n/a" } else { $mcpCpu.peak }) | $(if ($null -eq $mcpCpu.average) { "n/a" } else { $mcpCpu.average }) |

## Memory (working set)

| Process | Peak | Final | Growth |
|---------|------|-------|--------|
| Pulse | $(Fmt-Bytes $pulseMem.peak) | $(Fmt-Bytes $pulseMem.last) | $(if ($null -eq $uiGrowthMb) { "n/a" } else { "$uiGrowthMb MB" }) |
| PulseService | $(Fmt-Bytes $serviceMem.peak) | $(Fmt-Bytes $serviceMem.last) | $(if ($null -eq $svcGrowthMb) { "n/a" } else { "$svcGrowthMb MB" }) |
| PulseMCP | $(Fmt-Bytes $mcpMem.peak) | $(Fmt-Bytes $mcpMem.last) | $(if ($null -eq $mcpMem.growth) { "n/a" } else { "{0:N2} MB" -f ($mcpMem.growth / 1MB) }) |

## IPC / queues

| Metric | Value | Notes |
|--------|-------|-------|
| IPC reconnect count | $(if ($null -eq $ipcReconnects) { "n/a" } else { $ipcReconnects }) | Service ``live_subscriber_reconnects`` |
| Flutter client reconnects | n/a | $clientReconnectNote |
| Queue overflows | $(if ($null -eq $queueOverflows) { "n/a" } else { $queueOverflows }) | ``live_events_dropped`` (drop-oldest) |
| Dropped samples (collectors) | Not supported | No collector drop counter |
| Live queue depth (end) | $(if ($null -eq $metricsEnd.liveQueueDepth) { "n/a" } else { $metricsEnd.liveQueueDepth }) | Sum across clients |
| IPC errors (service) | $(if ($null -eq $metricsEnd.ipcErrors) { "n/a" } else { $metricsEnd.ipcErrors }) | |

## Stability

| Metric | Value |
|--------|-------|
| Service restarts (PID changes) | $serviceRestartCount |
| Pulse UI missing samples | $pulseMissingSamples |
| PulseService missing samples | $serviceMissingSamples |
| Exception / exit signals | $(@($exceptionDetected | Select-Object -Unique).Count) |
| Crash dumps (soak window) | $($crashDumpsInWindow.Count) |
| Related Event Log hits | $($eventLogHits.Count) |

### Exception / exit signals
$(if (@($exceptionDetected | Select-Object -Unique).Count -eq 0) { "_None recorded._" } else { (@($exceptionDetected | Select-Object -Unique) | ForEach-Object { "- $_" }) -join "`n" })

### Crash dumps
$(if ($crashDumpsInWindow.Count -eq 0) { "_None in soak window._" } else { ($crashDumpsInWindow | ForEach-Object { "- ``$($_.path)`` ($($_.lastWriteTime))" }) -join "`n" })

### Windows Event Log (Pulse-related)
$(if ($eventLogHits.Count -eq 0) { "_None matched._" } else { ($eventLogHits | Select-Object -First 20 | ForEach-Object { "- [$($_.level)] $($_.timeCreated) $($_.provider) id=$($_.id): $($_.message)" }) -join "`n" })

## Verdict details

**Result: $verdict**

### Fail reasons
$(if ($failReasons.Count -eq 0) { "_None._" } else { ($failReasons | ForEach-Object { "- $_" }) -join "`n" })

### Warning reasons
$(if ($warnReasons.Count -eq 0) { "_None._" } else { ($warnReasons | ForEach-Object { "- $_" }) -join "`n" })

---
_R1 status unchanged by this report. Close Wave A only after maintainer review of this verdict plus clean-VM installer validation._
"@

$md | Set-Content -Path $mdPath -Encoding UTF8
Copy-Item $mdPath (Join-Path $OutDir "soak-report.md") -Force

# Short text summary retained for compatibility
$summaryPath = Join-Path $OutDir "soak-summary.txt"
@(
  "Verdict: $verdict"
  "Finished: $($finishedAt.ToString('o'))"
  "Runtime: $(Format-Duration $totalRuntime)"
  "Samples: $($lines.Count)"
  "JSON: $jsonPath"
  "Markdown: $mdPath"
  "Pulse WS growth MB: $(if ($null -eq $uiGrowthMb) { 'n/a' } else { $uiGrowthMb })"
  "Service WS growth MB: $(if ($null -eq $svcGrowthMb) { 'n/a' } else { $svcGrowthMb })"
) | Set-Content -Path $summaryPath -Encoding UTF8

Write-Host ""
Write-Host "Soak complete. Verdict: $verdict"
Write-Host "JSON:     $jsonPath"
Write-Host "Markdown: $mdPath"
Write-Host "Session:  $OutDir"

# Exit code reflects verdict for automation (does not mark R1 complete).
if ($verdict -eq "FAIL") { exit 2 }
if ($verdict -eq "PASS WITH WARNINGS") { exit 1 }
exit 0
