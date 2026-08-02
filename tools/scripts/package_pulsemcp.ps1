#Requires -Version 5.1
<#
.SYNOPSIS
  Build PulseMCP payload: mcp\ + private Node runtime + PulseMCP.exe (+ .cmd fallback).

.DESCRIPTION
  End users do NOT need a system Node.js install. Packaging (this script) requires
  node/npm on the build machine, and downloads a pinned official Node win-x64 binary
  into dist\Pulse\runtime\ for redistribution.
#>
$ErrorActionPreference = "Stop"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$mcpSrc = Join-Path $root "apps\pulse_mcp"
$dist = Join-Path $root "dist\Pulse"
$mcpOut = Join-Path $dist "mcp"
$runtimeOut = Join-Path $dist "runtime"
$launcherSrc = Join-Path $root "tools\pulsemcp_launcher\main.cpp"

# Pinned official Node win-x64 (LTS). Bump intentionally when upgrading the private runtime.
$NodeVersion = "20.19.4"
$NodeZipName = "node-v$NodeVersion-win-x64.zip"
$NodeUrl = "https://nodejs.org/dist/v$NodeVersion/$NodeZipName"
$cacheDir = Join-Path $root "tools\cache\node-v$NodeVersion-win-x64"
$cachedZip = Join-Path (Join-Path $root "tools\cache") $NodeZipName

$node = Get-Command node -ErrorAction SilentlyContinue
$npm = Get-Command npm -ErrorAction SilentlyContinue
if (-not $node -or -not $npm) {
  throw "node/npm required on the BUILD machine to package PulseMCP"
}

function Get-VsDevCmd {
  $candidates = @(
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\18\BuildTools\Common7\Tools\VsDevCmd.bat",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat",
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat",
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\Common7\Tools\VsDevCmd.bat"
  )
  return $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Ensure-PrivateNodeRuntime {
  param([string]$DestDir)

  New-Item -ItemType Directory -Force -Path (Split-Path $cachedZip -Parent) | Out-Null
  if (-not (Test-Path $cachedZip)) {
    Write-Host "==> Downloading private Node $NodeVersion (win-x64)"
    Write-Host "    $NodeUrl"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $NodeUrl -OutFile $cachedZip -UseBasicParsing
  } else {
    Write-Host "==> Using cached Node zip: $cachedZip"
  }

  if (-not (Test-Path (Join-Path $cacheDir "node.exe"))) {
    Write-Host "==> Extracting Node runtime to cache"
    if (Test-Path $cacheDir) { Remove-Item -Recurse -Force $cacheDir }
    $extractRoot = Join-Path $root "tools\cache\_extract_node"
    if (Test-Path $extractRoot) { Remove-Item -Recurse -Force $extractRoot }
    New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
    Expand-Archive -Path $cachedZip -DestinationPath $extractRoot -Force
    $inner = Get-ChildItem $extractRoot -Directory | Select-Object -First 1
    if (-not $inner) { throw "Unexpected Node zip layout" }
    Move-Item $inner.FullName $cacheDir
    Remove-Item -Recurse -Force $extractRoot -ErrorAction SilentlyContinue
  }

  $srcNode = Join-Path $cacheDir "node.exe"
  if (-not (Test-Path $srcNode)) { throw "node.exe missing after extract: $srcNode" }

  if (Test-Path $DestDir) { Remove-Item -Recurse -Force $DestDir }
  New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
  Copy-Item $srcNode (Join-Path $DestDir "node.exe") -Force

  $licenseSrc = Join-Path $cacheDir "LICENSE"
  if (Test-Path $licenseSrc) {
    Copy-Item $licenseSrc (Join-Path $DestDir "NODE_LICENSE.txt") -Force
  }

  $verFile = Join-Path $DestDir "NODE_VERSION.txt"
  @(
    "Node.js $NodeVersion (win-x64)"
    "Official binary from nodejs.org - private runtime for PulseMCP only."
    "End users do not need a system Node.js installation."
  ) | Set-Content -Path $verFile -Encoding ASCII

  Write-Host "Private runtime staged: $(Join-Path $DestDir 'node.exe')"
}

function Build-PulseMcpExe {
  param([string]$OutExe)

  if (-not (Test-Path $launcherSrc)) {
    throw "Launcher source missing: $launcherSrc"
  }

  $vsDev = Get-VsDevCmd
  if (-not $vsDev) {
    throw "VsDevCmd.bat not found - required to build PulseMCP.exe launcher"
  }

  $outDir = Split-Path $OutExe -Parent
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  $objDir = Join-Path $root "build\pulsemcp_launcher"
  New-Item -ItemType Directory -Force -Path $objDir | Out-Null

  $vsInstall = Split-Path (Split-Path (Split-Path $vsDev -Parent) -Parent) -Parent
  $devShell = Join-Path $vsInstall "Common7\Tools\Microsoft.VisualStudio.DevShell.dll"

  Write-Host "==> Building PulseMCP.exe launcher"
  if (Test-Path $devShell) {
    Import-Module $devShell
    Enter-VsDevShell -VsInstallPath $vsInstall -SkipAutomaticLocation -DevCmdArguments "-arch=x64 -host_arch=x64" | Out-Null
    $compileCmd = "cl.exe /nologo /O2 /EHsc /W3 /DUNICODE /D_UNICODE `"$launcherSrc`" /Fe:`"$OutExe`" /Fo:`"$objDir\\`""
    cmd /c $compileCmd
    if ($LASTEXITCODE -ne 0) { throw "PulseMCP.exe compile failed" }
  } else {
    $compileCmd = "`"$vsDev`" -arch=amd64 -host_arch=amd64 & cl.exe /nologo /O2 /EHsc /W3 /DUNICODE /D_UNICODE `"$launcherSrc`" /Fe:`"$OutExe`" /Fo:`"$objDir\\`""
    cmd /c $compileCmd
    if ($LASTEXITCODE -ne 0) { throw "PulseMCP.exe compile failed" }
  }

  if (-not (Test-Path $OutExe)) { throw "PulseMCP.exe was not produced: $OutExe" }
  Write-Host "PulseMCP.exe: $OutExe"
}

Write-Host "==> Building PulseMCP (TypeScript)"
Push-Location $mcpSrc
try {
  npm ci
  if ($LASTEXITCODE -ne 0) { throw "npm ci failed" }
  npm run build
  if ($LASTEXITCODE -ne 0) { throw "npm run build failed" }
} finally {
  Pop-Location
}

Write-Host "==> Staging PulseMCP into $mcpOut"
if (Test-Path $mcpOut) { Remove-Item -Recurse -Force $mcpOut }
New-Item -ItemType Directory -Force -Path $mcpOut | Out-Null
Copy-Item (Join-Path $mcpSrc "dist\*") -Destination $mcpOut -Recurse -Force
Copy-Item (Join-Path $mcpSrc "package.json") -Destination $mcpOut -Force

Push-Location $mcpOut
try {
  npm install --omit=dev --no-package-lock
  if ($LASTEXITCODE -ne 0) { throw "npm install --omit=dev failed in payload" }
} finally {
  Pop-Location
}

Ensure-PrivateNodeRuntime -DestDir $runtimeOut

$exeOut = Join-Path $dist "PulseMCP.exe"
Build-PulseMcpExe -OutExe $exeOut

# Compatibility launcher: always uses the private runtime (never PATH node).
$launcherCmd = Join-Path $dist "PulseMCP.cmd"
$cmdLines = @(
  '@echo off'
  'setlocal'
  'set "SCRIPT_DIR=%~dp0"'
  'set "NODE=%SCRIPT_DIR%runtime\node.exe"'
  'set "MAIN=%SCRIPT_DIR%mcp\main.js"'
  'if not exist "%NODE%" ('
  '  echo PulseMCP: bundled runtime missing. Reinstall Pulse. >&2'
  '  echo A system Node.js installation is not required or used. >&2'
  '  exit /b 1'
  ')'
  'if not exist "%MAIN%" ('
  '  echo PulseMCP: mcp\main.js missing. Reinstall Pulse. >&2'
  '  exit /b 1'
  ')'
  '"%NODE%" "%MAIN%" %*'
)
$cmdLines | Set-Content -Path $launcherCmd -Encoding ASCII

Write-Host "PulseMCP packaged (no system Node required):"
Write-Host "  $exeOut"
Write-Host "  $launcherCmd"
Write-Host "  $runtimeOut\node.exe  (Node $NodeVersion)"
Write-Host "  $mcpOut\main.js"
