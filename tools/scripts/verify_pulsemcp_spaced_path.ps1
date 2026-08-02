#Requires -Version 5.1
<#
.SYNOPSIS
  Prove PulseMCP launches via the Windows-safe MCP registration shape
  used for Cursor/Claude when installed under a path with spaces.
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$PackageDir
)

$ErrorActionPreference = "Stop"

$exe = Join-Path $PackageDir "PulseMCP.exe"
$runtime = Join-Path $PackageDir "runtime\node.exe"
$main = Join-Path $PackageDir "mcp\main.js"
foreach ($p in @($exe, $runtime, $main)) {
  if (-not (Test-Path $p)) { throw "Missing: $p" }
}

$spaceRoot = Join-Path $env:TEMP "Pulse Program Files Test"
$install = Join-Path $spaceRoot "Pulse"
if (Test-Path $spaceRoot) { Remove-Item -Recurse -Force $spaceRoot }
New-Item -ItemType Directory -Force -Path $install | Out-Null

Write-Host "==> Staging install under path with spaces:"
Write-Host "    $install"
Copy-Item $exe (Join-Path $install "PulseMCP.exe") -Force
Copy-Item (Join-Path $PackageDir "runtime") (Join-Path $install "runtime") -Recurse -Force
Copy-Item (Join-Path $PackageDir "mcp") (Join-Path $install "mcp") -Recurse -Force

$spaceExe = Join-Path $install "PulseMCP.exe"
if ($spaceExe -notmatch ' ') { throw "Test path unexpectedly has no spaces: $spaceExe" }

# Mirror encoder output: command=cmd.exe args=['/c', fullPath]
$statusPath = Join-Path $env:TEMP ("pulse-mcp-space-status-{0}.json" -f [guid]::NewGuid().ToString("n"))
$cleanPath = ($env:PATH -split ';' | Where-Object {
  $_ -and ($_ -notmatch '(?i)[\\/]node') -and ($_ -notmatch '(?i)nodejs')
}) -join ';'

Write-Host "==> Launching via cmd.exe /c (Cursor/Claude registration shape)"
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "cmd.exe"
$psi.Arguments = "/c `"$spaceExe`" --status-daemon"
$psi.WorkingDirectory = $install
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
$ok = $false
while ((Get-Date) -lt $deadline) {
  if ($proc.HasExited) {
    $err = $proc.StandardError.ReadToEnd()
    $out = $proc.StandardOutput.ReadToEnd()
    throw "Exited early code=$($proc.ExitCode)`nSTDOUT:$out`nSTDERR:$err"
  }
  if (Test-Path $statusPath) {
    try {
      $json = Get-Content $statusPath -Raw | ConvertFrom-Json
      if ($json.running -eq $true) { $ok = $true; break }
    } catch {}
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
Remove-Item $spaceRoot -Recurse -Force -ErrorAction SilentlyContinue

if (-not $ok) { throw "PulseMCP did not become healthy under a spaced install path" }

Write-Host "OK: cmd.exe /c launch works for Program Files-style path"
