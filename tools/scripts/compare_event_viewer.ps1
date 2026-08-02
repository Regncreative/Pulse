# Compare recent Windows Event Log fields to what Pulse Timeline expects.
# Observation only — does not modify Windows.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools/scripts/compare_event_viewer.ps1
#   powershell -ExecutionPolicy Bypass -File tools/scripts/compare_event_viewer.ps1 -MaxEvents 40

param(
  [int]$MaxEvents = 30,
  [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
if (-not $OutDir) {
  $root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
  if (-not (Test-Path (Join-Path $root "AGENTS.md"))) {
    $root = (Get-Location).Path
  }
  $OutDir = Join-Path $root "tools\validation-results"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$jsonPath = Join-Path $OutDir "event-viewer-compare-$stamp.json"
$mdPath = Join-Path $OutDir "event-viewer-compare-$stamp.md"

$channels = @("System", "Application")
$rows = @()

foreach ($ch in $channels) {
  try {
    $events = Get-WinEvent -LogName $ch -MaxEvents $MaxEvents -ErrorAction Stop
  } catch {
    Write-Warning "Cannot read channel ${ch}: $_"
    continue
  }
  foreach ($ev in $events) {
    $rows += [pscustomobject]@{
      channel         = $ch
      record_id       = [int64]$ev.RecordId
      provider_name   = [string]$ev.ProviderName
      win_event_id    = [int]$ev.Id
      level_display   = [string]$ev.LevelDisplayName
      time_created    = $ev.TimeCreated.ToUniversalTime().ToString("o")
      machine_name    = [string]$ev.MachineName
      has_message     = -not [string]::IsNullOrWhiteSpace($ev.Message)
      message_preview = if ($ev.Message) { ($ev.Message -replace "\s+", " ").Substring(0, [Math]::Min(120, $ev.Message.Length)) } else { "" }
    }
  }
}

# Spot-check known correlation IDs if present in the sample.
$known = @(
  @{ provider = "Application Error"; id = 1000; rule = "app-crash-wer" },
  @{ provider = "Windows Error Reporting"; id = 1001; rule = "app-crash-wer" },
  @{ provider = "Microsoft-Windows-Kernel-Power"; id = 41; rule = "unexpected-shutdown" },
  @{ provider = "EventLog"; id = 6008; rule = "unexpected-shutdown" },
  @{ provider = "Display"; id = 4101; rule = "display-tdr-4101" },
  @{ provider = "Service Control Manager"; id = 7031; rule = "service-crash-recover" },
  @{ provider = "Service Control Manager"; id = 7036; rule = "service-crash-recover" }
)

$hits = @()
foreach ($k in $known) {
  $match = $rows | Where-Object {
    $_.win_event_id -eq $k.id -and ($_.provider_name -like ("*" + $k.provider + "*") -or $k.provider -like ("*" + $_.provider_name + "*"))
  } | Select-Object -First 3
  foreach ($m in $match) {
    $hits += [pscustomobject]@{
      rule = $k.rule
      expected_provider = $k.provider
      expected_id = $k.id
      found_provider = $m.provider_name
      found_channel = $m.channel
      found_record_id = $m.record_id
    }
  }
}

$report = [pscustomobject]@{
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  max_events_per_channel = $MaxEvents
  sample_count = $rows.Count
  channels = $channels
  samples = $rows
  correlation_id_hits = $hits
  field_checklist = @(
    "provider_name",
    "win_event_id",
    "channel",
    "record_id",
    "machine_name",
    "level_display",
    "time_created",
    "message"
  )
  notes = @(
    "Compare these rows side-by-side with Pulse Timeline details for the same channel+record_id.",
    "Pulse never invents missing fields; empty Pulse cells mean Wevtapi did not provide the value.",
    "Correlation hits only list known Event IDs present in this sample - absence is not a failure."
  )
}

$report | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding UTF8

$md = @()
$md += "# Event Viewer comparison sample"
$md += ""
$md += "Generated: $($report.generated_at)"
$md += "Sample count: $($report.sample_count)"
$md += ""
$md += "## Field checklist (Event Viewer → Pulse details)"
$md += ""
foreach ($f in $report.field_checklist) { $md += "- $f" }
$md += ""
$md += "## Correlation Event ID hits in sample"
$md += ""
if ($hits.Count -eq 0) {
  $md += "_No documented correlation Event IDs appeared in this sample._"
} else {
  foreach ($h in $hits) {
    $md += "- rule `$($h.rule)`: $($h.found_provider) Event $($h.expected_id) on $($h.found_channel) record $($h.found_record_id)"
  }
}
$md += ""
$md += "## How to validate in Pulse"
$md += ""
$md += "1. Open Timeline and select an event with matching Channel + Record ID."
$md += "2. Confirm Provider, Event ID, Level, Computer, Message match Event Viewer."
$md += "3. Load Raw Event XML and confirm it matches Event Viewer Details → XML View."
$md += ""
$md -join "`n" | Set-Content -Path $mdPath -Encoding UTF8

Write-Host "Wrote $jsonPath"
Write-Host "Wrote $mdPath"
Write-Host "Sample events: $($rows.Count); correlation hits: $($hits.Count)"
