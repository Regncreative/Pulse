$ErrorActionPreference = "Stop"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$exe = "$root\build\service\pulse_ipc_ping.exe"
if (-not (Test-Path $exe)) { throw "Build pulse_ipc_ping first (cmake --build build/service)" }
& $exe
exit $LASTEXITCODE
