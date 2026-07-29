$ErrorActionPreference = "Stop"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path "$root\build\service\PulseService.exe")) {
  Write-Host "Building PulseService..."
  $vsDev = "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\Common7\Tools\VsDevCmd.bat"
  $cmake = "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
  if (-not (Test-Path $cmake)) { throw "cmake not found" }
  cmd /c "`"$vsDev`" -arch=amd64 -host_arch=amd64 && `"$cmake`" -S `"$root\service\pulse_service`" -B `"$root\build\service`" -G Ninja -DCMAKE_BUILD_TYPE=Debug && `"$cmake`" --build `"$root\build\service`""
}
& "$root\build\service\PulseService.exe" --console
