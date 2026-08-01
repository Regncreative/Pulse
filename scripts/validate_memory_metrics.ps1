# Memory metrics validation — same APIs Pulse uses vs raw Windows reads.
# Run: powershell -ExecutionPolicy Bypass -File scripts/validate_memory_metrics.ps1

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class MemWin {
  [StructLayout(LayoutKind.Sequential)]
  public struct MEMORYSTATUSEX {
    public uint dwLength;
    public uint dwMemoryLoad;
    public ulong ullTotalPhys;
    public ulong ullAvailPhys;
    public ulong ullTotalPageFile;
    public ulong ullAvailPageFile;
    public ulong ullTotalVirtual;
    public ulong ullAvailVirtual;
    public ulong ullAvailExtendedVirtual;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct PERFORMANCE_INFORMATION {
    public uint cb;
    public UIntPtr CommitTotal;
    public UIntPtr CommitLimit;
    public UIntPtr CommitPeak;
    public UIntPtr PhysicalTotal;
    public UIntPtr PhysicalAvailable;
    public UIntPtr SystemCache;
    public UIntPtr KernelTotal;
    public UIntPtr KernelPaged;
    public UIntPtr KernelNonpaged;
    public UIntPtr PageSize;
    public uint HandleCount;
    public uint ProcessCount;
    public uint ThreadCount;
  }

  [DllImport("kernel32.dll", SetLastError = true)]
  public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);

  [DllImport("psapi.dll", SetLastError = true)]
  public static extern bool GetPerformanceInfo(ref PERFORMANCE_INFORMATION pPerformanceInformation, uint cb);

  [DllImport("kernel32.dll", SetLastError = true)]
  public static extern bool GetPhysicallyInstalledSystemMemory(out ulong TotalMemoryInKilobytes);
}
"@

function Fmt([UInt64]$b) {
  if ($b -lt 1KB) { return "$b B" }
  if ($b -lt 1MB) { return ("{0:N1} KB" -f ($b / 1KB)) }
  $mb = $b / 1MB
  if ($mb -lt 1024) {
    if ($mb -ge 100) { return ("{0:N0} MB" -f $mb) }
    return ("{0:N1} MB" -f $mb)
  }
  return ("{0:N2} GB" -f ($mb / 1024))
}

$ms = New-Object MemWin+MEMORYSTATUSEX
$ms.dwLength = [uint32][Runtime.InteropServices.Marshal]::SizeOf($ms)
[void][MemWin]::GlobalMemoryStatusEx([ref]$ms)

$pi = New-Object MemWin+PERFORMANCE_INFORMATION
$pi.cb = [uint32][Runtime.InteropServices.Marshal]::SizeOf($pi)
[void][MemWin]::GetPerformanceInfo([ref]$pi, $pi.cb)
$page = [UInt64]$pi.PageSize.ToUInt64()

$installedKb = [UInt64]0
$hasInstalled = [MemWin]::GetPhysicallyInstalledSystemMemory([ref]$installedKb)
$installed = if ($hasInstalled) { [UInt64]($installedKb * 1024) } else { [UInt64]0 }
$hwReserved = $null
if ($hasInstalled -and $installed -ge $ms.ullTotalPhys) {
  $hwReserved = $installed - $ms.ullTotalPhys
}

$used = $ms.ullTotalPhys - $ms.ullAvailPhys
$commit = [UInt64]$pi.CommitTotal.ToUInt64() * $page
$limit = [UInt64]$pi.CommitLimit.ToUInt64() * $page
$sysCache = [UInt64]$pi.SystemCache.ToUInt64() * $page
$paged = [UInt64]$pi.KernelPaged.ToUInt64() * $page
$nonpaged = [UInt64]$pi.KernelNonpaged.ToUInt64() * $page

function PdhBytes([string]$counter) {
  try {
    $c = New-Object Diagnostics.PerformanceCounter 'Memory', $counter, $true
    return [UInt64][math]::Max(0, [math]::Round($c.NextValue()))
  } catch { return $null }
}

$cache = PdhBytes 'Cache Bytes'
$modified = PdhBytes 'Modified Page List Bytes'
$reserve = PdhBytes 'Standby Cache Reserve Bytes'
$normal = PdhBytes 'Standby Cache Normal Priority Bytes'
$core = $null
try { $core = PdhBytes 'Standby Cache Core Bytes' } catch {}
if ($null -eq $core) { try { $core = PdhBytes 'Standby Cache Code Bytes' } catch {} }
$compressed = PdhBytes 'Compressed Bytes'
$faults = $null
try {
  $fc = New-Object Diagnostics.PerformanceCounter 'Memory', 'Page Faults/sec', $true
  [void]$fc.NextValue(); Start-Sleep -Milliseconds 400
  $faults = [math]::Round($fc.NextValue(), 0)
} catch {}

$cachedPdh = $null
if ($null -ne $cache -and $null -ne $modified -and $null -ne $reserve -and $null -ne $normal -and $null -ne $core) {
  $cachedPdh = $cache + $modified + $reserve + $normal + $core
}

Write-Host ''
Write-Host '=== Memory validation (Windows APIs Pulse uses) ==='
Write-Host ('{0,-28} {1,-14} {2}' -f 'Metric', 'Value', 'Windows API / Formula')
Write-Host ('-' * 78)
$rows = @(
  @{ m = 'Total Physical'; a = 'GlobalMemoryStatusEx.ullTotalPhys'; v = $ms.ullTotalPhys },
  @{ m = 'Available'; a = 'ullAvailPhys'; v = $ms.ullAvailPhys },
  @{ m = 'Used (In use)'; a = 'TotalPhys - AvailPhys'; v = $used },
  @{ m = 'Committed'; a = 'GetPerformanceInfo CommitTotal*Page'; v = $commit },
  @{ m = 'Commit Limit'; a = 'CommitLimit*Page'; v = $limit },
  @{ m = 'Cached (PDH sum)'; a = 'Cache+Modified+Standby*'; v = $cachedPdh },
  @{ m = 'Cached (fallback SPI)'; a = 'SystemCache*Page'; v = $sysCache },
  @{ m = 'Memory Compression'; a = 'PDH \Memory\Compressed Bytes'; v = $compressed },
  @{ m = 'Hardware Reserved'; a = 'Installed - TotalPhys'; v = $hwReserved },
  @{ m = 'Paged Pool'; a = 'KernelPaged*Page'; v = $paged },
  @{ m = 'Non-paged Pool'; a = 'KernelNonpaged*Page'; v = $nonpaged }
)
foreach ($r in $rows) {
  $fmt = if ($null -eq $r.v) { '—' } else { Fmt ([UInt64]$r.v) }
  Write-Host ('{0,-28} {1,-14} {2}' -f $r.m, $fmt, $r.a)
}
if ($null -ne $faults) {
  Write-Host ('{0,-28} {1,-14} {2}' -f 'Page Faults/sec', $faults, 'PDH Page Faults/sec')
}
Write-Host ''
Write-Host 'Compare Formatted values to Pulse Memory Overview and Task Manager Performance > Memory.'
Write-Host 'Process Memory column = SPI WorkingSetPrivateSize (summed per app group).'
Write-Host ''
