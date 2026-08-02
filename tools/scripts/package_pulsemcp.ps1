#Requires -Version 5.1
<#
.SYNOPSIS
  Build PulseMCP payload into dist\Pulse\mcp + PulseMCP.cmd launcher.
#>
$ErrorActionPreference = "Stop"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$mcpSrc = Join-Path $root "apps\pulse_mcp"
$dist = Join-Path $root "dist\Pulse"
$mcpOut = Join-Path $dist "mcp"

$node = Get-Command node -ErrorAction SilentlyContinue
$npm = Get-Command npm -ErrorAction SilentlyContinue
if (-not $node -or -not $npm) { throw "node/npm required to package PulseMCP" }

Write-Host "==> Building PulseMCP"
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
# Production node_modules (omit devDependencies)
Push-Location $mcpOut
try {
  npm install --omit=dev --no-package-lock
  if ($LASTEXITCODE -ne 0) { throw "npm install --omit=dev failed in payload" }
} finally {
  Pop-Location
}

$launcher = Join-Path $dist "PulseMCP.cmd"
@"
@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "MAIN=%SCRIPT_DIR%mcp\main.js"
where node >nul 2>nul
if errorlevel 1 (
  echo PulseMCP requires Node.js 20+ on PATH. >&2
  exit /b 1
)
node "%MAIN%" %*
"@ | Set-Content -Path $launcher -Encoding ASCII

Write-Host "PulseMCP packaged:"
Write-Host "  $launcher"
Write-Host "  $mcpOut\main.js"
