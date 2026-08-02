#Requires -Version 5.1
<#
.SYNOPSIS
  Verify packaged PulseMCP starts without any system Node.js on PATH.
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$PackageDir
)

$ErrorActionPreference = "Stop"

$exe = Join-Path $PackageDir "PulseMCP.exe"
$runtime = Join-Path $PackageDir "runtime\node.exe"
$main = Join-Path $PackageDir "mcp\main.js"
$cmd = Join-Path $PackageDir "PulseMCP.cmd"

foreach ($p in @($exe, $runtime, $main, $cmd)) {
  if (-not (Test-Path $p)) { throw "Missing required payload file: $p" }
}

# Strip every PATH entry that looks like a Node install so `where node` fails.
$cleanPath = ($env:PATH -split ';' | Where-Object {
  $_ -and ($_ -notmatch '(?i)[\\/]node') -and ($_ -notmatch '(?i)nodejs')
}) -join ';'

$whereOut = & cmd /c "set `"PATH=$cleanPath`" && where node 2>nul"
if ($whereOut) {
  throw "Clean PATH still resolves node (verification invalid): $whereOut"
}
Write-Host "OK: system 'node' not on cleaned PATH"

$statusPath = Join-Path $env:TEMP ("pulse-mcp-verify-status-{0}.json" -f [guid]::NewGuid().ToString("n"))
Write-Host "==> Verifying PulseMCP.exe --status-daemon (bundled runtime only)"
Write-Host "    status: $statusPath"

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $exe
$psi.Arguments = "--status-daemon"
$psi.WorkingDirectory = $PackageDir
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$psi.EnvironmentVariables["PATH"] = $cleanPath
$psi.EnvironmentVariables["PULSE_MCP_STATUS_PATH"] = $statusPath

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
[void]$proc.Start()

$deadline = (Get-Date).AddSeconds(12)
$started = $false
$lastErr = ""
while ((Get-Date) -lt $deadline) {
  if ($proc.HasExited) {
    $err = $proc.StandardError.ReadToEnd()
    $out = $proc.StandardOutput.ReadToEnd()
    throw "PulseMCP.exe exited early code=$($proc.ExitCode)`nSTDOUT:`n$out`nSTDERR:`n$err"
  }
  if (Test-Path $statusPath) {
    try {
      $json = Get-Content $statusPath -Raw | ConvertFrom-Json
      if ($json.running -eq $true -and $json.mode -eq "status-daemon") {
        $started = $true
        break
      }
    } catch {
      $lastErr = "$_"
    }
  }
  Start-Sleep -Milliseconds 250
}

try {
  if (-not $proc.HasExited) {
    $proc.Kill()
    [void]$proc.WaitForExit(5000)
  }
} catch {}

Remove-Item $statusPath -Force -ErrorAction SilentlyContinue

if (-not $started) {
  throw "PulseMCP.exe ran but status.json was not healthy within timeout. Last parse error: $lastErr"
}

Write-Host "OK: PulseMCP started with bundled runtime only (no system Node.js)"
