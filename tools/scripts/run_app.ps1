$ErrorActionPreference = "Stop"
$env:Path = "$env:USERPROFILE\flutter\bin;C:\Users\ozsin\flutter\bin;$env:Path"
Set-Location (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "apps\pulse_app")
flutter pub get
flutter run -d windows
