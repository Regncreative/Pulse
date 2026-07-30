#Requires -Version 5.1
<#
.SYNOPSIS
  Build a portable Pulse beta package (Flutter Release + PulseService).

.DESCRIPTION
  Produces dist/Pulse/ with:
    - Pulse.exe and Flutter runner assets
    - PulseService.exe
    - install_service.ps1 / uninstall_service.ps1
    - README_INSTALL.txt

  No major installer framework required for beta — zip the folder for distribution.
#>
$ErrorActionPreference = "Stop"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$dist = Join-Path $root "dist\Pulse"
$flutterBin = @(
  "$env:USERPROFILE\flutter\bin",
  "C:\Users\ozsin\flutter\bin"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($flutterBin) { $env:Path = "$flutterBin;$env:Path" }

Write-Host "==> Cleaning $dist"
if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
New-Item -ItemType Directory -Force -Path $dist | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $dist "service") | Out-Null

Write-Host "==> Building PulseService (Release)"
$vsDevCandidates = @(
  "${env:ProgramFiles(x86)}\Microsoft Visual Studio\18\BuildTools\Common7\Tools\VsDevCmd.bat",
  "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat",
  "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat",
  "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\Common7\Tools\VsDevCmd.bat"
)
$vsDev = $vsDevCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $vsDev) { throw "VsDevCmd.bat not found. Install VS Build Tools with C++ workload." }

$cmakeCandidates = @(
  "${env:ProgramFiles(x86)}\Microsoft Visual Studio\18\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
  "${env:ProgramFiles}\CMake\bin\cmake.exe",
  "cmake"
)
$cmake = $null
foreach ($c in $cmakeCandidates) {
  if ($c -eq "cmake") {
    $cmd = Get-Command cmake -ErrorAction SilentlyContinue
    if ($cmd) { $cmake = $cmd.Source; break }
  } elseif (Test-Path $c) {
    $cmake = $c
    break
  }
}
if (-not $cmake) { throw "cmake not found" }

$serviceBuild = Join-Path $root "build\service-release"
cmd /c "`"$vsDev`" -arch=amd64 -host_arch=amd64 && `"$cmake`" -S `"$root\service\pulse_service`" -B `"$serviceBuild`" -G Ninja -DCMAKE_BUILD_TYPE=Release && `"$cmake`" --build `"$serviceBuild`""
if ($LASTEXITCODE -ne 0) { throw "PulseService build failed" }

$serviceExe = Join-Path $serviceBuild "PulseService.exe"
if (-not (Test-Path $serviceExe)) {
  # Some generators place under Release/
  $alt = Join-Path $serviceBuild "Release\PulseService.exe"
  if (Test-Path $alt) { $serviceExe = $alt }
}
if (-not (Test-Path $serviceExe)) { throw "PulseService.exe not found after build" }
Copy-Item $serviceExe (Join-Path $dist "service\PulseService.exe") -Force

Write-Host "==> Building Flutter Windows Release"
# MSBuild custom builds break on non-ASCII paths (e.g. OneDrive\Masaüstü).
# Prefer an ASCII staging copy when the workspace path is not ASCII-safe.
$stageRoot = $root
$needsStage = $root -match '[^\x00-\x7F]'
if ($needsStage) {
  $stageRoot = "C:\dev\Pulse-build"
  Write-Host "Non-ASCII workspace path detected — staging to $stageRoot"
  if (Test-Path $stageRoot) { Remove-Item -Recurse -Force $stageRoot }
  New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
  robocopy $root $stageRoot /E /XD build dist .dart_tool build-ninja .git "apps\pulse_app\build" "apps\pulse_app\.dart_tool" /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
}

Push-Location (Join-Path $stageRoot "apps\pulse_app")
try {
  if (Test-Path "windows\flutter\ephemeral") {
    Remove-Item -Recurse -Force "windows\flutter\ephemeral" -ErrorAction SilentlyContinue
  }
  flutter pub get
  if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
  flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw "flutter build windows --release failed" }
} finally {
  Pop-Location
}

$runner = Join-Path $stageRoot "apps\pulse_app\build\windows\x64\runner\Release"
if (-not (Test-Path $runner)) {
  $runner = Join-Path $stageRoot "apps\pulse_app\build\windows\runner\Release"
}
if (-not (Test-Path $runner)) { throw "Flutter Release runner not found at $runner" }

Write-Host "==> Copying Flutter Release bundle"
Copy-Item -Path (Join-Path $runner "*") -Destination $dist -Recurse -Force

Write-Host "==> Writing install helpers"
@'
#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe = Join-Path $here "PulseService.exe"
if (-not (Test-Path $exe)) { throw "PulseService.exe missing next to this script" }
& $exe --install
Start-Service -Name PulseService -ErrorAction SilentlyContinue
Write-Host "PulseService installed. Start Pulse.exe from the package root."
'@ | Set-Content -Path (Join-Path $dist "service\install_service.ps1") -Encoding UTF8

@'
#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe = Join-Path $here "PulseService.exe"
if (Get-Service -Name PulseService -ErrorAction SilentlyContinue) {
  Stop-Service -Name PulseService -Force -ErrorAction SilentlyContinue
}
if (Test-Path $exe) {
  & $exe --uninstall
} else {
  sc.exe delete PulseService | Out-Null
}
Write-Host "PulseService uninstalled."
'@ | Set-Content -Path (Join-Path $dist "service\uninstall_service.ps1") -Encoding UTF8

@'
Pulse — first public beta
========================

1) Install / start the service (elevated PowerShell):
     cd service
     .\install_service.ps1

   Or for development / troubleshooting without SCM:
     .\PulseService.exe --console

2) Launch the app:
     .\Pulse.exe

3) First launch shows a short welcome (skippable).
   Timeline, System Health, and Diagnostics need PulseService running.

Privacy: local-only. No telemetry. Observation only.

Uninstall service:
     cd service
     .\uninstall_service.ps1
'@ | Set-Content -Path (Join-Path $dist "README_INSTALL.txt") -Encoding UTF8

# Zip
$zip = Join-Path $root "dist\Pulse-0.1.0-beta-windows-x64.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Write-Host "==> Creating $zip"
Compress-Archive -Path (Join-Path $dist "*") -DestinationPath $zip -Force

Write-Host ""
Write-Host "Beta package ready:"
Write-Host "  Folder: $dist"
Write-Host "  Zip:    $zip"
