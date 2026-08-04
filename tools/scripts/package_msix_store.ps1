#Requires -Version 5.1
<#
.SYNOPSIS
  Build a Microsoft Store-ready MSIX / .msixupload for Pulse Diagnostics.

.DESCRIPTION
  Uses Flutter msix with store:true (no development certificates).
  Partner Center identity is configured in apps/pulse_app/pubspec.yaml.

  Outputs under dist/msix/:
    PulseDiagnostics-1.0.0-Store.msix
    PulseDiagnostics-1.0.0-Store.msixupload
    AppxManifest.identity.txt
    store-validation-report.txt
#>
$ErrorActionPreference = "Stop"

$Version = "1.0.0"
$MsixVersion = "1.0.0.0"
$ExpectedIdentity = "Regncreative.PulseDiagnostics"
$ExpectedPublisher = "CN=72B69D57-C9E8-4280-AF56-B142286B0D20"
$ExpectedDisplayName = "Pulse Diagnostics"
$ExpectedPublisherDisplay = "Regncreative"
$ExpectedPfn = "Regncreative.PulseDiagnostics_epm7gp6hnh3h0"
$StoreId = "9PNDTLNTJ82T"

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$appDir = Join-Path $root "apps\pulse_app"
$outDir = Join-Path $root "dist\msix"
$flutterBin = @(
  "$env:USERPROFILE\flutter\bin",
  "C:\Users\ozsin\flutter\bin"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($flutterBin) { $env:Path = "$flutterBin;$env:Path" }

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$workApp = $appDir
$workspaceOut = $outDir
if ($root -match '[^\x00-\x7F]') {
  $stageRoot = "C:\dev\Pulse-build"
  Write-Host "Non-ASCII workspace path - staging to $stageRoot"
  New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
  robocopy $root $stageRoot /E /XD build dist .dart_tool .git "apps\pulse_app\build" "apps\pulse_app\.dart_tool" /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
  $workApp = Join-Path $stageRoot "apps\pulse_app"
  $outDir = Join-Path $stageRoot "dist\msix"
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

Write-Host "==> flutter pub get"
Push-Location $workApp
try {
  flutter pub get
  if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }

  Write-Host "==> dart run msix:create (Microsoft Store, unsigned)"
  dart run msix:create `
    --store `
    --sign-msix false `
    --install-certificate false `
    --display-name $ExpectedDisplayName `
    --publisher-display-name $ExpectedPublisherDisplay `
    --identity-name $ExpectedIdentity `
    --publisher $ExpectedPublisher `
    --version $MsixVersion `
    --output-path $outDir `
    --output-name "PulseDiagnostics-$Version-Store"
  if ($LASTEXITCODE -ne 0) { throw "msix:create failed" }
}
finally {
  Pop-Location
}

$msix = Join-Path $outDir "PulseDiagnostics-$Version-Store.msix"
if (-not (Test-Path $msix)) {
  $found = Get-ChildItem $outDir -Filter "*.msix" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $found) { throw "MSIX not found in $outDir" }
  $msix = $found.FullName
}

Write-Host "==> Extracting AppxManifest.xml for identity verification"
$extract = Join-Path $outDir "_extract"
if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
New-Item -ItemType Directory -Force -Path $extract | Out-Null

$makeAppx = @(
  "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.0.26100.0\x64\MakeAppx.exe",
  "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.0.22621.0\x64\MakeAppx.exe",
  "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.0.19041.0\x64\MakeAppx.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $makeAppx) {
  $kitBins = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending
  foreach ($k in $kitBins) {
    $candidate = Join-Path $k.FullName "x64\MakeAppx.exe"
    if (Test-Path $candidate) { $makeAppx = $candidate; break }
  }
}

if ($makeAppx) {
  & $makeAppx unpack /p $msix /d $extract /o
  if ($LASTEXITCODE -ne 0) { throw "MakeAppx unpack failed" }
} else {
  Copy-Item $msix (Join-Path $outDir "_pkg.zip") -Force
  Expand-Archive (Join-Path $outDir "_pkg.zip") -DestinationPath $extract -Force
}

$manifestPath = Join-Path $extract "AppxManifest.xml"
if (-not (Test-Path $manifestPath)) { throw "AppxManifest.xml missing after unpack" }

[xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
$ns = New-Object System.Xml.XmlNamespaceManager($manifest.NameTable)
$ns.AddNamespace("def", "http://schemas.microsoft.com/appx/manifest/foundation/windows10")

$identity = $manifest.SelectSingleNode("//def:Identity", $ns)
$props = $manifest.SelectSingleNode("//def:Properties", $ns)
$displayName = [string]$props.DisplayName
$publisherDisplay = [string]$props.PublisherDisplayName
$identityName = [string]$identity.Name
$publisher = [string]$identity.Publisher
$pkgVersion = [string]$identity.Version

$identityReport = @"
Partner Center expected
  Store ID:                 $StoreId
  Package Identity Name:    $ExpectedIdentity
  Publisher:                $ExpectedPublisher
  Publisher Display Name:   $ExpectedPublisherDisplay
  DisplayName:              $ExpectedDisplayName
  Package Family Name:      $ExpectedPfn
  Version:                  $MsixVersion

AppxManifest Identity
  Name:                     $identityName
  Publisher:                $publisher
  Version:                  $pkgVersion
  DisplayName:              $displayName
  PublisherDisplayName:     $publisherDisplay
"@

$identityFile = Join-Path $outDir "AppxManifest.identity.txt"
Set-Content -Path $identityFile -Value $identityReport -Encoding UTF8
Write-Host $identityReport

$errors = New-Object System.Collections.Generic.List[string]
if ($identityName -ne $ExpectedIdentity) { [void]$errors.Add("Identity Name mismatch: $identityName") }
if ($publisher -ne $ExpectedPublisher) { [void]$errors.Add("Publisher mismatch: $publisher") }
if ($displayName -ne $ExpectedDisplayName) { [void]$errors.Add("DisplayName mismatch: $displayName") }
if ($publisherDisplay -ne $ExpectedPublisherDisplay) { [void]$errors.Add("PublisherDisplayName mismatch: $publisherDisplay") }
if ($pkgVersion -ne $MsixVersion) { [void]$errors.Add("Version mismatch: $pkgVersion") }

Write-Host "==> Building .msixupload"
$uploadStage = Join-Path $outDir "_upload"
if (Test-Path $uploadStage) { Remove-Item $uploadStage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $uploadStage | Out-Null
Copy-Item $msix $uploadStage -Force

$pdbCandidates = @(
  (Join-Path $workApp "build\windows\x64\runner\Release\Pulse.pdb"),
  (Join-Path $workApp "build\windows\runner\Release\Pulse.pdb")
) | Where-Object { Test-Path $_ }
if ($pdbCandidates.Count -gt 0) {
  $symDir = Join-Path $outDir "_symbols"
  if (Test-Path $symDir) { Remove-Item $symDir -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $symDir | Out-Null
  Copy-Item $pdbCandidates[0] $symDir -Force
  $appxsymZip = Join-Path $outDir "_sym.zip"
  if (Test-Path $appxsymZip) { Remove-Item $appxsymZip -Force }
  Compress-Archive -Path (Join-Path $symDir "*") -DestinationPath $appxsymZip -Force
  $appxsym = Join-Path $uploadStage "PulseDiagnostics-$Version-Store.appxsym"
  Move-Item $appxsymZip $appxsym -Force
}

$msixupload = Join-Path $outDir "PulseDiagnostics-$Version-Store.msixupload"
if (Test-Path $msixupload) { Remove-Item $msixupload -Force }
$zipTmp = Join-Path $outDir "_upload.zip"
if (Test-Path $zipTmp) { Remove-Item $zipTmp -Force }
Compress-Archive -Path (Join-Path $uploadStage "*") -DestinationPath $zipTmp -Force
Move-Item $zipTmp $msixupload -Force

Write-Host "==> Validation"
$validation = New-Object System.Collections.Generic.List[string]
[void]$validation.Add("Pulse Diagnostics Store package validation")
[void]$validation.Add("Generated: $(Get-Date -Format o)")
[void]$validation.Add("")
[void]$validation.Add($identityReport)
[void]$validation.Add("Expected Package Family Name (Partner Center): $ExpectedPfn")
[void]$validation.Add("")

if ($errors.Count -eq 0) {
  [void]$validation.Add("IDENTITY CHECK: PASS - AppxManifest matches Partner Center values.")
} else {
  [void]$validation.Add("IDENTITY CHECK: FAIL")
  foreach ($e in $errors) { [void]$validation.Add("  - $e") }
}

[void]$validation.Add("")
[void]$validation.Add("Package files:")
[void]$validation.Add("  MSIX:       $msix")
[void]$validation.Add("  MSIXUPLOAD: $msixupload")
[void]$validation.Add("  Identity:   $identityFile")

if ($makeAppx) {
  [void]$validation.Add("")
  [void]$validation.Add("MakeAppx unpack: OK")
}

$sig = Get-AuthenticodeSignature -FilePath $msix -ErrorAction SilentlyContinue
if ($null -ne $sig -and $sig.Status -eq "Valid") {
  [void]$validation.Add("SIGNING: Authenticode Status=Valid (unexpected for Store upload; Store should re-sign unsigned packages).")
  if ($sig.SignerCertificate -and ($sig.SignerCertificate.Subject -match "Flutter|Test|msix|Self")) {
    [void]$errors.Add("Development/test certificate detected on Store package")
    [void]$validation.Add("SIGNING CHECK: FAIL - development certificate present")
  }
} else {
  $statusText = if ($null -eq $sig) { "unknown" } else { [string]$sig.Status }
  [void]$validation.Add("SIGNING CHECK: PASS - package unsigned/not self-signed for Store (status=$statusText).")
}

$rawManifest = Get-Content -LiteralPath $manifestPath -Raw
if ($rawManifest -match "CN=Flutter|CN=Msix|Test Certificate") {
  [void]$errors.Add("Manifest contains development publisher residue")
  [void]$validation.Add("MANIFEST SANITY: FAIL - development publisher residue")
} else {
  [void]$validation.Add("MANIFEST SANITY: PASS")
}

[void]$validation.Add("")
[void]$validation.Add("Notes:")
[void]$validation.Add("  - Upload .msixupload to Partner Center Packages for Store ID $StoreId.")
[void]$validation.Add("  - PulseService remains a separate Windows service (Inno/SCM); Store package ships the Flutter UI client.")
[void]$validation.Add("  - Package Family Name is assigned by the Store from Identity+Publisher; expected PFN: $ExpectedPfn")

$reportPath = Join-Path $outDir "store-validation-report.txt"
$validation | Set-Content -Path $reportPath -Encoding UTF8

if ($outDir -ne $workspaceOut) {
  New-Item -ItemType Directory -Force -Path $workspaceOut | Out-Null
  Copy-Item $msix (Join-Path $workspaceOut (Split-Path $msix -Leaf)) -Force
  Copy-Item $msixupload (Join-Path $workspaceOut (Split-Path $msixupload -Leaf)) -Force
  Copy-Item $identityFile (Join-Path $workspaceOut "AppxManifest.identity.txt") -Force
  Copy-Item $reportPath (Join-Path $workspaceOut "store-validation-report.txt") -Force
  Copy-Item $manifestPath (Join-Path $workspaceOut "AppxManifest.xml") -Force
  $msix = Join-Path $workspaceOut (Split-Path $msix -Leaf)
  $msixupload = Join-Path $workspaceOut (Split-Path $msixupload -Leaf)
  $reportPath = Join-Path $workspaceOut "store-validation-report.txt"
}

Write-Host ""
Write-Host "Store package ready:"
Write-Host "  $msixupload"
Write-Host "  Report: $reportPath"

if ($errors.Count -gt 0) {
  Write-Host "VALIDATION FAILED:"
  $errors | ForEach-Object { Write-Host "  $_" }
  exit 1
}

Write-Host "VALIDATION PASSED"
exit 0
