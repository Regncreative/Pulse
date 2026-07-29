$ErrorActionPreference = "Stop"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$exe = "$root\build\service\PulseService.exe"
if (-not (Test-Path $exe)) { throw "Build PulseService first" }
Start-Process -FilePath $exe -ArgumentList "--install" -Verb RunAs -Wait
Write-Host "Installed. Start with: Start-Service PulseService"
