#Requires -Version 5.1
<#
.SYNOPSIS
  Verify Pulse package includes MSVC CRT DLLs required on clean Windows.
#>
param(
  [string]$PackageDir = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $PackageDir) {
  $PackageDir = Join-Path $root "dist\Pulse"
}

$required = @(
  "vcruntime140.dll",
  "vcruntime140_1.dll",
  "msvcp140.dll"
)

function Assert-CrtBeside([string]$ExePath) {
  if (-not (Test-Path $ExePath)) { throw "Missing executable: $ExePath" }
  $dir = Split-Path $ExePath -Parent
  foreach ($name in $required) {
    $path = Join-Path $dir $name
    if (-not (Test-Path $path)) {
      throw "Missing $name next to $(Split-Path $ExePath -Leaf) (expected app-local CRT in $dir)"
    }
  }
  Write-Host "OK CRT beside $(Split-Path $ExePath -Leaf)"
}

Assert-CrtBeside (Join-Path $PackageDir "Pulse.exe")
Assert-CrtBeside (Join-Path $PackageDir "service\PulseService.exe")

$redist = Join-Path $PackageDir "redist\VC_redist.x64.exe"
if (-not (Test-Path $redist)) {
  throw "Missing $redist - package should ship the official VC++ redistributable installer"
}
Write-Host "OK VC_redist.x64.exe present"

$dumpbin = Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft Visual Studio" -Recurse -Filter "dumpbin.exe" -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match '\\Hostx64\\x64\\dumpbin\.exe$' } |
  Select-Object -First 1 -ExpandProperty FullName

if ($dumpbin) {
  foreach ($exe in @(
      (Join-Path $PackageDir "Pulse.exe"),
      (Join-Path $PackageDir "service\PulseService.exe")
    )) {
    $deps = (& $dumpbin /dependents $exe 2>&1 | Out-String).ToLowerInvariant()
    foreach ($name in $required) {
      if ($deps -notmatch [regex]::Escape($name.ToLowerInvariant())) {
        Write-Warning "$(Split-Path $exe -Leaf) dumpbin did not list $name (toolset may differ)"
      }
    }
  }
  Write-Host "OK dumpbin dependency check finished"
} else {
  Write-Warning "dumpbin.exe not found - skipped PE dependency listing"
}

Write-Host ""
Write-Host "Runtime packaging looks good for a clean Windows 10/11 machine."
