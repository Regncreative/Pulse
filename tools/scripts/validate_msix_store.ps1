#Requires -Version 5.1
<#
.SYNOPSIS
  Validates an unpacked Store MSIX / AppxManifest for packaged PulseService.

.PARAMETER ExtractDir
  Directory produced by MakeAppx unpack (contains AppxManifest.xml).

.PARAMETER ManifestPath
  Optional direct path to AppxManifest.xml (defaults to ExtractDir\AppxManifest.xml).
#>
param(
  [Parameter(Mandatory = $true)]
  [string] $ExtractDir,
  [string] $ManifestPath = ""
)

$ErrorActionPreference = "Stop"

if (-not $ManifestPath) {
  $ManifestPath = Join-Path $ExtractDir "AppxManifest.xml"
}
if (-not (Test-Path -LiteralPath $ManifestPath)) {
  throw "AppxManifest.xml not found: $ManifestPath"
}

$errors = New-Object System.Collections.Generic.List[string]

$pulseExe = Join-Path $ExtractDir "Pulse.exe"
if (-not (Test-Path -LiteralPath $pulseExe)) {
  [void]$errors.Add("Pulse.exe missing from package root")
}

$serviceExe = Join-Path $ExtractDir "service\PulseService.exe"
if (-not (Test-Path -LiteralPath $serviceExe)) {
  [void]$errors.Add("service\PulseService.exe missing from package")
}

$raw = Get-Content -LiteralPath $ManifestPath -Raw

if ($raw -notmatch 'packagedServices') {
  [void]$errors.Add("rescap packagedServices capability missing from AppxManifest")
}
if ($raw -match 'localSystemServices') {
  [void]$errors.Add("localSystemServices must not be declared (LocalService only)")
}
if ($raw -notmatch 'desktop6:Service' -and $raw -notmatch 'Category="windows\.service"') {
  [void]$errors.Add("desktop6:Service / windows.service extension missing")
}

[xml]$manifest = $raw
$ns = New-Object System.Xml.XmlNamespaceManager($manifest.NameTable)
$ns.AddNamespace("def", "http://schemas.microsoft.com/appx/manifest/foundation/windows10")
$ns.AddNamespace("desktop6", "http://schemas.microsoft.com/appx/manifest/desktop/windows10/6")
$ns.AddNamespace("uap10", "http://schemas.microsoft.com/appx/manifest/uap/windows10/10")
$ns.AddNamespace("rescap", "http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities")

$serviceExt = $manifest.SelectSingleNode("//desktop6:Extension[@Category='windows.service']", $ns)
if ($null -eq $serviceExt) {
  # Some generators omit the prefix on Category only — try local-name.
  $serviceExt = $manifest.SelectSingleNode("//*[local-name()='Extension' and @Category='windows.service']", $ns)
}
if ($null -eq $serviceExt) {
  [void]$errors.Add("windows.service Extension element not found")
} else {
  $exeAttr = [string]$serviceExt.Executable
  if ($exeAttr -ne "service\PulseService.exe" -and $exeAttr -ne "service/PulseService.exe") {
    [void]$errors.Add("windows.service Executable must be service\PulseService.exe (got: '$exeAttr')")
  }
  $svc = $serviceExt.SelectSingleNode("desktop6:Service", $ns)
  if ($null -eq $svc) {
    $svc = $serviceExt.SelectSingleNode("*[local-name()='Service']", $ns)
  }
  if ($null -eq $svc) {
    [void]$errors.Add("desktop6:Service child element missing")
  } else {
    $name = [string]$svc.Name
    $startAccount = [string]$svc.StartAccount
    $startupType = [string]$svc.StartupType
    if ($name -ne "PulseService") {
      [void]$errors.Add("Service Name must be PulseService (got: '$name')")
    }
    if ($startAccount -ne "localService") {
      [void]$errors.Add("StartAccount must be localService (got: '$startAccount')")
    }
    if ($startupType -ne "auto") {
      [void]$errors.Add("StartupType must be auto (got: '$startupType')")
    }
  }
}

# Declared executable must exist in the package.
$declaredRel = "service\PulseService.exe"
$declaredPath = Join-Path $ExtractDir $declaredRel
if (-not (Test-Path -LiteralPath $declaredPath)) {
  [void]$errors.Add("Declared service executable path is invalid / missing on disk: $declaredRel")
}

if ($errors.Count -gt 0) {
  Write-Host "MSIX packaged-service validation FAILED:"
  foreach ($e in $errors) { Write-Host "  - $e" }
  exit 1
}

Write-Host "MSIX packaged-service validation PASSED"
Write-Host "  Pulse.exe: OK"
Write-Host "  service\PulseService.exe: OK"
Write-Host "  desktop6:Service Name=PulseService StartAccount=localService StartupType=auto: OK"
Write-Host "  packagedServices capability: OK"
exit 0
