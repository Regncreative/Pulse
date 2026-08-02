#Requires -Version 5.1
<#
.SYNOPSIS
  Build Pulse beta: Flutter Release payload + VC++ CRT + Inno Setup installer.

.DESCRIPTION
  Produces:
    dist/Pulse-Setup-<version>-windows-x64.exe  (primary end-user installer)
    dist/Pulse/                                  (payload)
    dist/Pulse-<version>-windows-x64.zip        (optional payload archive)

  The Setup.exe elevates via UAC, installs VC++ redist, registers/starts
  PulseService (--install-start), and launches Pulse — no PowerShell.
#>
$ErrorActionPreference = "Stop"
$Version = "0.3.0-beta"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$dist = Join-Path $root "dist\Pulse"
$flutterBin = @(
  "$env:USERPROFILE\flutter\bin",
  "C:\Users\ozsin\flutter\bin"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($flutterBin) { $env:Path = "$flutterBin;$env:Path" }

Write-Host "==> Packaging Pulse $Version"

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
# Non-ASCII OneDrive paths + VsDevCmd via cmd /c overflow ("input line is too long").
if ($root -match '[^\x00-\x7F]') {
  $serviceBuild = "C:\dev\Pulse-service-release"
  Write-Host "Non-ASCII workspace path detected - service build at $serviceBuild"
}
New-Item -ItemType Directory -Force -Path $serviceBuild | Out-Null

# Prefer importing the Dev Shell module (avoids a giant cmd.exe command line).
$vsInstall = Split-Path (Split-Path (Split-Path $vsDev -Parent) -Parent) -Parent
$devShell = Join-Path $vsInstall "Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
if (Test-Path $devShell) {
  Import-Module $devShell
  Enter-VsDevShell -VsInstallPath $vsInstall -SkipAutomaticLocation -DevCmdArguments "-arch=x64 -host_arch=x64" | Out-Null
  & $cmake -S (Join-Path $root "service\pulse_service") -B $serviceBuild -G Ninja -DCMAKE_BUILD_TYPE=Release
  if ($LASTEXITCODE -ne 0) { throw "PulseService cmake configure failed" }
  & $cmake --build $serviceBuild
  if ($LASTEXITCODE -ne 0) { throw "PulseService build failed" }
} else {
  cmd /c "`"$vsDev`" -arch=amd64 -host_arch=amd64 && `"$cmake`" -S `"$root\service\pulse_service`" -B `"$serviceBuild`" -G Ninja -DCMAKE_BUILD_TYPE=Release && `"$cmake`" --build `"$serviceBuild`""
  if ($LASTEXITCODE -ne 0) { throw "PulseService build failed" }
}

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
  Write-Host "Non-ASCII workspace path detected - staging to $stageRoot"
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

Write-Host "==> Bundling Visual C++ runtime (app-local + VC_redist)"
$crtCandidates = @(
  "${env:ProgramFiles(x86)}\Microsoft Visual Studio\18\BuildTools\VC\Redist\MSVC\14.50.35710\x64\Microsoft.VC145.CRT",
  "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC"
)
$crtDir = $null
foreach ($c in $crtCandidates) {
  if (Test-Path $c) {
    if ((Split-Path $c -Leaf) -eq "MSVC") {
      $ver = Get-ChildItem $c -Directory | Where-Object { $_.Name -match '^\d' } |
        Sort-Object Name -Descending | Select-Object -First 1
      $maybe = Join-Path $ver.FullName "x64"
      $crt = Get-ChildItem $maybe -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "Microsoft.VC*.CRT" } |
        Select-Object -First 1
      if ($crt) { $crtDir = $crt.FullName; break }
    } else {
      $crtDir = $c
      break
    }
  }
}
if (-not $crtDir -or -not (Test-Path $crtDir)) {
  throw "MSVC CRT redistributable folder not found. Install VS Build Tools C++ redistributables."
}
Write-Host "    CRT source: $crtDir"
# App-local next to Pulse.exe and PulseService.exe (licensed REDIST binaries).
Copy-Item (Join-Path $crtDir "*") -Destination $dist -Force
Copy-Item (Join-Path $crtDir "*") -Destination (Join-Path $dist "service") -Force

$redistCandidates = @(
  "${env:ProgramFiles(x86)}\Microsoft Visual Studio\18\BuildTools\VC\Redist\MSVC\v145\vc_redist.x64.exe",
  "${env:ProgramFiles(x86)}\Microsoft Visual Studio\18\BuildTools\VC\Redist\MSVC\14.50.35710\vc_redist.x64.exe",
  "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\v143\vc_redist.x64.exe"
)
$vcRedist = $redistCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $vcRedist) { throw "vc_redist.x64.exe not found under Visual Studio Redist" }
New-Item -ItemType Directory -Force -Path (Join-Path $dist "redist") | Out-Null
Copy-Item $vcRedist (Join-Path $dist "redist\VC_redist.x64.exe") -Force

Write-Host "==> Packaging PulseMCP"
& powershell -ExecutionPolicy Bypass -File (Join-Path $root "tools\scripts\package_pulsemcp.ps1")
if ($LASTEXITCODE -ne 0) { throw "package_pulsemcp.ps1 failed" }

Write-Host "==> Copying AI Integration docs into payload"
$docsOut = Join-Path $dist "docs\guides"
New-Item -ItemType Directory -Force -Path $docsOut | Out-Null
Copy-Item (Join-Path $root "docs\guides\ai-integration.md") $docsOut -Force
$guideExtras = @(
  "installation.md",
  "troubleshooting.md",
  "security.md",
  "upgrade-notes.md"
)
foreach ($g in $guideExtras) {
  $src = Join-Path $root "docs\guides\$g"
  if (Test-Path $src) { Copy-Item $src $docsOut -Force }
}

Write-Host "==> Writing README for payload folder (advanced / portable)"
@"
Pulse payload folder (advanced)
===============================

End users should run Pulse-Setup-$Version-windows-x64.exe instead of this folder.

This folder is the install payload. For developers:

  service\PulseService.exe --install-start   (elevated)
  Pulse.exe
  PulseMCP.cmd                 (requires Node.js 20+ on PATH)

Privacy: local-only. No telemetry. Observation only.
MCP: enable in Settings → AI Integration. Policy: %LOCALAPPDATA%\Pulse\mcp\policy.json
"@ | Set-Content -Path (Join-Path $dist "README_INSTALL.txt") -Encoding UTF8

# Zip (payload / CI artifact - not the primary end-user deliverable)
$zip = Join-Path $root "dist\Pulse-$Version-windows-x64.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Write-Host "==> Creating $zip"
Compress-Archive -Path (Join-Path $dist "*") -DestinationPath $zip -Force

Write-Host "==> Verifying runtime deps"
& powershell -ExecutionPolicy Bypass -File (Join-Path $root "tools\scripts\verify_runtime_deps.ps1") -PackageDir $dist
if ($LASTEXITCODE -ne 0) { throw "verify_runtime_deps.ps1 failed" }

Write-Host "==> Building Inno Setup installer (no PowerShell for end users)"
$iscc = @(
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "${env:LocalAppData}\Programs\Inno Setup 6\ISCC.exe",
  "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) {
  throw "ISCC.exe not found. Install Inno Setup 6 (winget install JRSoftware.InnoSetup)."
}
$iss = Join-Path $root "tools\installer\Pulse.iss"
$setupOut = Join-Path $root "dist\Pulse-Setup-$Version-windows-x64.exe"
if (Test-Path $setupOut) { Remove-Item $setupOut -Force }
& $iscc "/DPulsePayloadDir=$dist" "/DPulseOutDir=$(Join-Path $root 'dist')" $iss
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compile failed" }
if (-not (Test-Path $setupOut)) { throw "Installer not produced: $setupOut" }

Write-Host ""
Write-Host "Beta package ready:"
Write-Host "  Installer (primary): $setupOut"
Write-Host "  Payload folder:      $dist"
Write-Host "  Payload zip:         $zip"
