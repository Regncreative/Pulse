#Requires -Version 5.1
<#
.SYNOPSIS
  Read-only Inventory R3 spot-check vs Windows native sources.
  Observation only — no registry writes, no service changes.
#>
$ErrorActionPreference = 'Continue'
$outDir = Join-Path $PSScriptRoot '..\..\tools\validation-results'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$report = Join-Path $outDir "inventory-spotcheck-$stamp.md"
$jsonOut = Join-Path $outDir "inventory-spotcheck-$stamp.json"

function Get-Safe {
  param([scriptblock]$Block)
  try { & $Block } catch { $null }
}

$native = [ordered]@{}

# --- msinfo32 / CIM equivalents (System Information) ---
$cs = Get-Safe { Get-CimInstance Win32_ComputerSystem }
$bb = Get-Safe { Get-CimInstance Win32_BaseBoard }
$bios = Get-Safe { Get-CimInstance Win32_BIOS }
$cpu = Get-Safe { Get-CimInstance Win32_Processor | Select-Object -First 1 }
$os = Get-Safe { Get-CimInstance Win32_OperatingSystem }

$native.motherboard = [ordered]@{
  source = 'Win32_BaseBoard (msinfo32 BaseBoard)'
  manufacturer = $bb.Manufacturer
  product = $bb.Product
  version = $bb.Version
  serial = $bb.SerialNumber
}
$native.bios = [ordered]@{
  source = 'Win32_BIOS (msinfo32 BIOS)'
  vendor = $bios.Manufacturer
  version = $bios.SMBIOSBIOSVersion
  release_date = if ($bios.ReleaseDate) { $bios.ReleaseDate.ToString('u') } else { $null }
}
$native.cpu = [ordered]@{
  source = 'Win32_Processor (msinfo32 Processor)'
  name = $cpu.Name
  manufacturer = $cpu.Manufacturer
  cores = $cpu.NumberOfCores
  logical = $cpu.NumberOfLogicalProcessors
  max_clock_mhz = $cpu.MaxClockSpeed
}
$mem = @(Get-Safe { Get-CimInstance Win32_PhysicalMemory } | ForEach-Object {
  [ordered]@{
    bank = $_.BankLabel
    locator = $_.DeviceLocator
    capacity_bytes = [uint64]$_.Capacity
    speed = $_.Speed
    manufacturer = $_.Manufacturer
    part = $_.PartNumber
  }
})
$native.memory = [ordered]@{
  source = 'Win32_PhysicalMemory (msinfo32 Memory)'
  module_count = $mem.Count
  modules = $mem
}

# --- Disk Management / storage ---
$disks = @(Get-Safe { Get-CimInstance Win32_DiskDrive } | ForEach-Object {
  [ordered]@{
    model = $_.Model
    serial = $_.SerialNumber
    size_bytes = [uint64]$_.Size
    interface = $_.InterfaceType
    media = $_.MediaType
    index = $_.Index
    device_id = $_.DeviceID
  }
})
$native.storage = [ordered]@{
  source = 'Win32_DiskDrive (Disk Management / Device Manager)'
  disk_count = $disks.Count
  disks = $disks
}

# --- Network Connections ---
$adapters = @(Get-Safe {
  Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.HardwareInterface -or $_.Name }
} | ForEach-Object {
  [ordered]@{
    name = $_.Name
    interface_description = $_.InterfaceDescription
    status = $_.Status
    mac = $_.MacAddress
    link_speed = $_.LinkSpeed
    if_index = $_.ifIndex
  }
})
$native.network = [ordered]@{
  source = 'Get-NetAdapter (ncpa.cpl / Settings Network)'
  adapter_count = $adapters.Count
  adapters = $adapters
}

# --- Device Manager class counts (PnP) ---
function Count-PnpClass([string]$Class) {
  @(Get-Safe { Get-PnpDevice -Class $Class -PresentOnly -ErrorAction SilentlyContinue }).Count
}
$native.device_manager = [ordered]@{
  source = 'Get-PnpDevice -PresentOnly (Device Manager)'
  usb = (Count-PnpClass 'USB')
  display = (Count-PnpClass 'Display')
  monitor = (Count-PnpClass 'Monitor')
  media = (Count-PnpClass 'MEDIA')
  bluetooth = (Count-PnpClass 'Bluetooth')
  battery = (Count-PnpClass 'Battery')
  net = (Count-PnpClass 'Net')
  diskdrive = (Count-PnpClass 'DiskDrive')
  system = (Count-PnpClass 'System')
}

# --- Printers ---
$printers = @(Get-Safe { Get-Printer -ErrorAction SilentlyContinue } | ForEach-Object {
  [ordered]@{ name = $_.Name; driver = $_.DriverName; port = $_.PortName; shared = $_.Shared }
})
$native.printers = [ordered]@{
  source = 'Get-Printer (Settings Printers)'
  count = $printers.Count
  printers = $printers
}

# --- Services / Drivers (counts) ---
$svc = @(Get-Safe { Get-Service -ErrorAction SilentlyContinue })
$native.services = [ordered]@{
  source = 'Get-Service (services.msc)'
  count = $svc.Count
}
$drv = @(Get-Safe { Get-CimInstance Win32_SystemDriver })
$native.drivers = [ordered]@{
  source = 'Win32_SystemDriver (Driver subset; Pulse uses SCM SERVICE_DRIVER)'
  count = $drv.Count
}

# --- Software (Apps & Features approximate) ---
$uninst = @(Get-Safe {
  Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue
  Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue
} | Where-Object { $_.DisplayName })
$native.software = [ordered]@{
  source = 'HKLM Uninstall (+ WOW6432Node) — Settings Apps machine-wide'
  count = $uninst.Count
}

# --- Battery ---
$batt = @(Get-Safe { Get-CimInstance Win32_Battery })
$native.battery = [ordered]@{
  source = 'Win32_Battery'
  count = $batt.Count
  present = ($batt.Count -gt 0)
}

# --- Displays ---
$mon = @(Get-Safe { Get-CimInstance Win32_DesktopMonitor })
$native.displays = [ordered]@{
  source = 'Win32_DesktopMonitor / Monitor PnP'
  monitor_cim_count = $mon.Count
  monitor_pnp_count = $native.device_manager.monitor
}

$native.host = [ordered]@{
  computer = $env:COMPUTERNAME
  os = $os.Caption
  captured_at = (Get-Date).ToString('o')
}

$native | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonOut -Encoding UTF8

# Markdown summary
$md = @()
$md += "# Inventory R3 native spot-check"
$md += ""
$md += "Captured: $($native.host.captured_at)"
$md += "Host: $($native.host.computer) / $($native.host.os)"
$md += ""
$md += "Read-only CIM/PnP/NetAdapter/Printer/Uninstall sources. Compare to Pulse Inventory dump."
$md += ""
$md += "## System (msinfo32)"
$md += "- Motherboard: $($native.motherboard.manufacturer) / $($native.motherboard.product)"
$md += "- BIOS: $($native.bios.vendor) $($native.bios.version) ($($native.bios.release_date))"
$md += "- CPU: $($native.cpu.name) cores=$($native.cpu.cores) logical=$($native.cpu.logical)"
$md += "- Memory modules (CIM): $($native.memory.module_count)"
$md += ""
$md += "## Storage (Disk Management)"
$md += "- Disks: $($native.storage.disk_count)"
foreach ($d in $native.storage.disks) {
  $gb = if ($d.size_bytes) { [math]::Round($d.size_bytes/1GB,1) } else { 0 }
  $md += "  - [$($d.index)] $($d.model) size=${gb}GB if=$($d.interface)"
}
$md += ""
$md += "## Network (ncpa.cpl)"
$md += "- Adapters: $($native.network.adapter_count)"
foreach ($a in $native.network.adapters) {
  $md += "  - $($a.name) | $($a.interface_description) | $($a.status) | $($a.mac)"
}
$md += ""
$md += "## Device Manager present counts"
$md += "- USB=$($native.device_manager.usb) Monitor=$($native.device_manager.monitor) MEDIA=$($native.device_manager.media) Bluetooth=$($native.device_manager.bluetooth) Battery=$($native.device_manager.battery) DiskDrive=$($native.device_manager.diskdrive) Net=$($native.device_manager.net)"
$md += ""
$md += "## Printers: $($native.printers.count)"
$md += "## Services: $($native.services.count) | System drivers (CIM): $($native.drivers.count)"
$md += "## Software uninstall keys: $($native.software.count)"
$md += "## Battery present: $($native.battery.present)"
$md += ""
$md += "JSON: $jsonOut"
$md -join "`n" | Set-Content -Path $report -Encoding UTF8

Write-Host "Wrote $report"
Write-Host "Wrote $jsonOut"
Get-Content $report
