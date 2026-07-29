$ErrorActionPreference = "Stop"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$exe = "$root\build\service\pulse_diagnostics_ping.exe"
if (-not (Test-Path $exe)) { throw "Build pulse_diagnostics_ping first" }
& $exe
exit $LASTEXITCODE
