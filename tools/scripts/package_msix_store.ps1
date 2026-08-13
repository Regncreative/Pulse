#Requires -Version 5.1
<#
.SYNOPSIS
  Build a Microsoft Store-ready MSIX / .msixupload with packaged PulseService.

.DESCRIPTION
  Builds PulseService.exe (Release), Flutter Windows Release, runs msix:build,
  embeds service\PulseService.exe, patches AppxManifest for desktop6:Service +
  packagedServices, packs the MSIX, and validates the unpacked result.

  GitHub / Inno Setup packaging is unchanged (package_beta.ps1 + Pulse.iss).

  Outputs under dist/msix/:
    PulseDiagnostics-1.1.0-Store.msix
    PulseDiagnostics-1.1.0-Store.msixupload
    AppxManifest.identity.txt
    store-validation-report.txt
#>
$ErrorActionPreference = "Stop"

$Version = "1.1.0"
$MsixVersion = "1.1.0.0"
$ExpectedIdentity = "Regncreative.PulseDiagnostics"
$ExpectedPublisher = "CN=72B69D57-C9E8-4280-AF56-B142286B0D20"
$ExpectedDisplayName = "Pulse Diagnostics"
$ExpectedPublisherDisplay = "Regncreative"
$ExpectedPfn = "Regncreative.PulseDiagnostics_epm7gp6hnh3h0"
$StoreId = "9PNDTLNTJ82T"
$ServiceRelPath = "service\PulseService.exe"

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$appDir = Join-Path $root "apps\pulse_app"
$outDir = Join-Path $root "dist\msix"
$validateScript = Join-Path $PSScriptRoot "validate_msix_store.ps1"
$flutterBin = @(
  "$env:USERPROFILE\flutter\bin",
  "C:\Users\ozsin\flutter\bin"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($flutterBin) { $env:Path = "$flutterBin;$env:Path" }

function Find-MakeAppx {
  $kitRoots = @(
    "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.0.26100.0\x64\MakeAppx.exe",
    "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.0.22621.0\x64\MakeAppx.exe",
    "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.0.19041.0\x64\MakeAppx.exe"
  )
  foreach ($c in $kitRoots) {
    if (Test-Path -LiteralPath $c) { return [string]$c }
  }
  $kitBins = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending
  foreach ($k in $kitBins) {
    $candidate = Join-Path $k.FullName "x64\MakeAppx.exe"
    if (Test-Path -LiteralPath $candidate) { return [string]$candidate }
  }
  return $null
}

function Resolve-CrtFolder {
  $crtCandidates = @(
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\18\BuildTools\VC\Redist\MSVC\14.50.35710\x64\Microsoft.VC145.CRT",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC"
  )
  foreach ($c in $crtCandidates) {
    if (-not (Test-Path $c)) { continue }
    if ((Split-Path $c -Leaf) -eq "MSVC") {
      $ver = Get-ChildItem $c -Directory | Where-Object { $_.Name -match '^\d' } |
        Sort-Object Name -Descending | Select-Object -First 1
      if (-not $ver) { continue }
      $maybe = Join-Path $ver.FullName "x64"
      $crt = Get-ChildItem $maybe -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "Microsoft.VC*.CRT" } |
        Select-Object -First 1
      if ($crt) { return $crt.FullName }
    } else {
      return $c
    }
  }
  return $null
}

function Patch-StoreAppxManifest([string]$ManifestPath) {
  [xml]$xml = Get-Content -LiteralPath $ManifestPath -Raw

  # Ensure desktop6 + rescap namespaces on Package.
  $pkg = $xml.Package
  if ($null -eq $pkg) { throw "AppxManifest missing Package root" }

  $nsUriDesktop6 = "http://schemas.microsoft.com/appx/manifest/desktop/windows10/6"
  $nsUriRescap = "http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  $nsUriUap10 = "http://schemas.microsoft.com/appx/manifest/uap/windows10/10"

  if (-not $pkg.GetAttribute("xmlns:desktop6")) {
    $pkg.SetAttribute("xmlns:desktop6", $nsUriDesktop6)
  }
  if (-not $pkg.GetAttribute("xmlns:rescap")) {
    $pkg.SetAttribute("xmlns:rescap", $nsUriRescap)
  }

  # IgnorableNamespaces must include desktop6 / rescap if present.
  $ignorable = [string]$pkg.GetAttribute("IgnorableNamespaces")
  $need = @("desktop6", "rescap", "uap10")
  $parts = @()
  if ($ignorable) { $parts = @($ignorable -split '\s+' | Where-Object { $_ }) }
  foreach ($n in $need) {
    if ($parts -notcontains $n) { $parts += $n }
  }
  $pkg.SetAttribute("IgnorableNamespaces", ($parts -join " "))

  # Raise TargetDeviceFamily MinVersion for packaged services (Win10 2004).
  $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
  $ns.AddNamespace("def", "http://schemas.microsoft.com/appx/manifest/foundation/windows10")
  $tdf = $xml.SelectSingleNode("//def:Dependencies/def:TargetDeviceFamily", $ns)
  if ($null -eq $tdf) {
    $tdf = $xml.SelectSingleNode("//*[local-name()='TargetDeviceFamily']")
  }
  if ($null -ne $tdf) {
    $tdf.SetAttribute("MinVersion", "10.0.19041.0")
    if (-not $tdf.GetAttribute("MaxVersionTested")) {
      $tdf.SetAttribute("MaxVersionTested", "10.0.26100.0")
    }
  }

  # Application node
  $app = $xml.SelectSingleNode("//def:Applications/def:Application", $ns)
  if ($null -eq $app) {
    $app = $xml.SelectSingleNode("//*[local-name()='Application']")
  }
  if ($null -eq $app) { throw "AppxManifest missing Application element" }

  # Remove any existing windows.service extensions before adding ours.
  $existing = @($app.SelectNodes(".//*[local-name()='Extension' and @Category='windows.service']"))
  foreach ($e in $existing) { [void]$e.ParentNode.RemoveChild($e) }

  $extensions = $app.SelectSingleNode("*[local-name()='Extensions']")
  if ($null -eq $extensions) {
    $extensions = $xml.CreateElement("Extensions", $app.NamespaceURI)
    [void]$app.AppendChild($extensions)
  }

  $ext = $xml.CreateElement("desktop6", "Extension", $nsUriDesktop6)
  $ext.SetAttribute("Category", "windows.service")
  $ext.SetAttribute("Executable", $ServiceRelPath)
  $ext.SetAttribute("EntryPoint", "Windows.FullTrustApplication")

  $svc = $xml.CreateElement("desktop6", "Service", $nsUriDesktop6)
  $svc.SetAttribute("Name", "PulseService")
  $svc.SetAttribute("StartupType", "auto")
  $svc.SetAttribute("StartAccount", "localService")
  [void]$ext.AppendChild($svc)
  [void]$extensions.AppendChild($ext)

  # Capabilities: ensure packagedServices; never localSystemServices.
  $caps = $xml.SelectSingleNode("//def:Capabilities", $ns)
  if ($null -eq $caps) {
    $caps = $xml.SelectSingleNode("//*[local-name()='Capabilities']")
  }
  if ($null -eq $caps) {
    $caps = $xml.CreateElement("Capabilities", $pkg.NamespaceURI)
    [void]$pkg.AppendChild($caps)
  }

  $hasPackaged = $false
  foreach ($c in @($caps.ChildNodes)) {
    if ($c.LocalName -eq "Capability" -and $c.GetAttribute("Name") -eq "localSystemServices") {
      [void]$caps.RemoveChild($c)
    }
    if ($c.LocalName -eq "Capability" -and $c.GetAttribute("Name") -eq "packagedServices") {
      $hasPackaged = $true
    }
  }
  if (-not $hasPackaged) {
    $cap = $xml.CreateElement("rescap", "Capability", $nsUriRescap)
    $cap.SetAttribute("Name", "packagedServices")
    [void]$caps.AppendChild($cap)
  }

  $xml.Save($ManifestPath)
  Write-Host "Patched AppxManifest: desktop6:Service + packagedServices ($ManifestPath)"
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$workRoot = $root
$workApp = $appDir
$workspaceOut = $outDir
if ($root -match '[^\x00-\x7F]') {
  $stageRoot = "C:\dev\Pulse-build"
  Write-Host "Non-ASCII workspace path - staging to $stageRoot"
  New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
  robocopy $root $stageRoot /E /XD build dist .dart_tool .git "apps\pulse_app\build" "apps\pulse_app\.dart_tool" /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
  $workRoot = $stageRoot
  $workApp = Join-Path $stageRoot "apps\pulse_app"
  $outDir = Join-Path $stageRoot "dist\msix"
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

# --- Build PulseService Release ---
Write-Host "==> Building PulseService (Release)"
$vsDevCandidates = @(
  "${env:ProgramFiles(x86)}\Microsoft Visual Studio\18\BuildTools\Common7\Tools\VsDevCmd.bat",
  "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat",
  "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"
)
$vsDev = $vsDevCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $vsDev) { throw "VsDevCmd.bat not found. Install VS Build Tools with C++ workload." }

$cmakeCandidates = @(
  "${env:ProgramFiles(x86)}\Microsoft Visual Studio\18\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
  "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
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

$serviceBuild = Join-Path $workRoot "build\service-msix"
if ($workRoot -match '[^\x00-\x7F]') {
  $serviceBuild = "C:\dev\Pulse-service-msix"
}
New-Item -ItemType Directory -Force -Path $serviceBuild | Out-Null

$vsInstall = Split-Path (Split-Path (Split-Path $vsDev -Parent) -Parent) -Parent
$devShell = Join-Path $vsInstall "Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
$serviceSrc = Join-Path $workRoot "service\pulse_service"

if (Test-Path $devShell) {
  Import-Module $devShell
  Enter-VsDevShell -VsInstallPath $vsInstall -SkipAutomaticLocation -DevCmdArguments "-arch=x64 -host_arch=x64" | Out-Null
  & $cmake -S $serviceSrc -B $serviceBuild -G Ninja -DCMAKE_BUILD_TYPE=Release
  if ($LASTEXITCODE -ne 0) { throw "PulseService cmake configure failed" }
  & $cmake --build $serviceBuild
  if ($LASTEXITCODE -ne 0) { throw "PulseService build failed" }
} else {
  cmd /c "`"$vsDev`" -arch=amd64 -host_arch=amd64 && `"$cmake`" -S `"$serviceSrc`" -B `"$serviceBuild`" -G Ninja -DCMAKE_BUILD_TYPE=Release && `"$cmake`" --build `"$serviceBuild`""
  if ($LASTEXITCODE -ne 0) { throw "PulseService build failed" }
}

$serviceExe = Join-Path $serviceBuild "PulseService.exe"
if (-not (Test-Path $serviceExe)) {
  $serviceExe = Join-Path $serviceBuild "Release\PulseService.exe"
}
if (-not (Test-Path $serviceExe)) {
  throw "PulseService.exe not found after Release build - Store package cannot be produced without it."
}
Write-Host "    PulseService.exe: $serviceExe"

# --- Flutter + msix:build ---
Write-Host "==> flutter pub get + msix:build"
Push-Location $workApp
try {
  flutter pub get
  if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }

  dart run msix:build `
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
  if ($LASTEXITCODE -ne 0) { throw "msix:build failed" }
}
finally {
  Pop-Location
}

$runnerCandidates = @(
  (Join-Path $workApp "build\windows\x64\runner\Release"),
  (Join-Path $workApp "build\windows\runner\Release")
)
$buildFilesFolder = $runnerCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $buildFilesFolder) {
  throw "Flutter Release runner folder not found after msix:build"
}
Write-Host "    MSIX staging folder: $buildFilesFolder"

# --- Embed PulseService ---
$serviceDestDir = Join-Path $buildFilesFolder "service"
New-Item -ItemType Directory -Force -Path $serviceDestDir | Out-Null
Copy-Item $serviceExe (Join-Path $serviceDestDir "PulseService.exe") -Force

$crtDir = Resolve-CrtFolder
if ($crtDir) {
  Write-Host "    Copying CRT redistributables beside PulseService ($crtDir)"
  Copy-Item (Join-Path $crtDir "*") -Destination $serviceDestDir -Force
} else {
  Write-Host "WARNING: MSVC CRT folder not found; relying on app-local CRT next to Pulse.exe"
}

$embedded = Join-Path $buildFilesFolder $ServiceRelPath
if (-not (Test-Path -LiteralPath $embedded)) {
  throw "FATAL: service\PulseService.exe missing after copy - refusing to pack Store MSIX."
}

$manifestPath = Join-Path $buildFilesFolder "AppxManifest.xml"
if (-not (Test-Path $manifestPath)) {
  throw "AppxManifest.xml missing in staging folder after msix:build"
}
Patch-StoreAppxManifest -ManifestPath $manifestPath

Write-Host "==> dart run msix:pack"
Push-Location $workApp
try {
  dart run msix:pack `
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
  if ($LASTEXITCODE -ne 0) { throw "msix:pack failed" }
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

Write-Host "==> Unpacking MSIX for validation"
$extract = Join-Path $outDir "_extract"
if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
New-Item -ItemType Directory -Force -Path $extract | Out-Null

$makeAppx = Find-MakeAppx
if ($makeAppx) {
  & $makeAppx unpack /p $msix /d $extract /o
  if ($LASTEXITCODE -ne 0) { throw "MakeAppx unpack failed" }
} else {
  Copy-Item $msix (Join-Path $outDir "_pkg.zip") -Force
  Expand-Archive (Join-Path $outDir "_pkg.zip") -DestinationPath $extract -Force
}

Write-Host "==> validate_msix_store.ps1"
& powershell -ExecutionPolicy Bypass -File $validateScript -ExtractDir $extract
if ($LASTEXITCODE -ne 0) { throw "Store MSIX packaged-service validation failed" }

$manifestPath = Join-Path $extract "AppxManifest.xml"
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

Packaged service
  Executable:               $ServiceRelPath
  Name:                     PulseService
  StartAccount:             localService
  StartupType:              auto
  Capability:               packagedServices
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

$validation = New-Object System.Collections.Generic.List[string]
[void]$validation.Add("Pulse Diagnostics Store package validation")
[void]$validation.Add("Generated: $(Get-Date -Format o)")
[void]$validation.Add("")
[void]$validation.Add($identityReport)
[void]$validation.Add("")
if ($errors.Count -eq 0) {
  [void]$validation.Add("IDENTITY CHECK: PASS")
} else {
  [void]$validation.Add("IDENTITY CHECK: FAIL")
  foreach ($e in $errors) { [void]$validation.Add("  - $e") }
}
[void]$validation.Add("PACKAGED SERVICE CHECK: PASS (validate_msix_store.ps1)")
[void]$validation.Add("")
[void]$validation.Add("Notes:")
[void]$validation.Add("  - Upload .msixupload only after Partner Center approves packagedServices.")
[void]$validation.Add("  - Classic GitHub Setup.exe remains the SCM --install-start path.")

$reportPath = Join-Path $outDir "store-validation-report.txt"
$validation | Set-Content -Path $reportPath -Encoding UTF8

# Copy manifest for inspection
Copy-Item $manifestPath (Join-Path $outDir "AppxManifest.xml") -Force

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
