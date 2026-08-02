import 'package:pulse_protocol/pulse_wire.dart';

import '../health/health_view_models.dart' show formatBytesBinary, formatMhz;

/// Rich sectioned detail panel model for the Inventory browser (ADR-011 P2).
///
/// Each domain builds a list of [InventoryDetailSection]s (Identity /
/// Hardware / Firmware / Driver / Capabilities / Network / Power, as
/// applicable) instead of one flat key/value bag. Empty fields are omitted
/// so the UI only renders values the collector actually returned.
class InventoryDetailSection {
  const InventoryDetailSection({required this.title, required this.fields});

  final String title;
  final List<(String label, String value)> fields;
}

/// Builds sections for a flat `Map<String, String>` legacy detail bag
/// (P0/P1 domains) under a single "Details" section — keeps the sectioned
/// panel usable everywhere without forcing every call site to migrate.
List<InventoryDetailSection> sectionsFromFlatDetails(
  Map<String, String> details,
) {
  final fields = <(String, String)>[
    for (final e in details.entries)
      if (e.value.trim().isNotEmpty) (_titleCase(e.key), e.value),
  ];
  if (fields.isEmpty) return const [];
  return [InventoryDetailSection(title: 'Details', fields: fields)];
}

List<InventoryDetailSection> motherboardDetailSections(
  InventoryMotherboardEntry e,
) {
  return _sections([
    (
      'Identity',
      [
        _s('Manufacturer', e.manufacturer),
        _s('Product', e.product),
        _s('Version', e.version),
        _s('Board type', e.boardType),
      ],
    ),
    (
      'Chassis',
      [
        _s('Serial number', e.serialNumber),
        _s('Asset tag', e.assetTag),
        _s('Location in chassis', e.locationInChassis),
      ],
    ),
  ]);
}

List<InventoryDetailSection> biosDetailSections(InventoryBiosEntry e) {
  return _sections([
    (
      'Firmware',
      [
        _s('Vendor', e.vendor),
        _s('Version', e.version),
        _s('Release date', e.releaseDate),
        if (e.hasMajorRelease && e.hasMinorRelease)
          _s('Release number', '${e.majorRelease}.${e.minorRelease}'),
        if (e.hasRomSizeBytes)
          _s('ROM size', formatBytesBinary(e.romSizeBytes, fractionDigits: 0)),
      ],
    ),
    (
      'Capabilities',
      [
        if (e.hasUefiCapable) _s('UEFI capable', e.uefiCapable ? 'Yes' : 'No'),
      ],
    ),
  ]);
}

List<InventoryDetailSection> cpuDetailSections(InventoryCpuEntry e) {
  return _sections([
    (
      'Identity',
      [
        _s('Name', e.name),
        _s('Manufacturer', e.manufacturer),
        _s('Architecture', e.architecture),
        _s('Instruction set', e.instructionSet),
        _s('Virtualization vendor', e.virtualizationVendor),
      ],
    ),
    (
      'Topology',
      [
        if (e.hasSockets) _s('Sockets', '${e.sockets}'),
        if (e.hasPhysicalCores) _s('Physical cores', '${e.physicalCores}'),
        if (e.hasLogicalProcessors)
          _s('Logical processors', '${e.logicalProcessors}'),
        if (e.hasNumaNodes) _s('NUMA nodes', '${e.numaNodes}'),
        if (e.hasSmtEnabled) _s('SMT enabled', e.smtEnabled ? 'Yes' : 'No'),
      ],
    ),
    (
      'Capabilities',
      [
        if (e.hasBaseClockMhz)
          _s('Base clock', formatMhz(e.baseClockMhz)),
        if (e.hasL1CacheBytes)
          _s('L1 cache', formatBytesBinary(e.l1CacheBytes, fractionDigits: 0)),
        if (e.hasL2CacheBytes)
          _s('L2 cache', formatBytesBinary(e.l2CacheBytes, fractionDigits: 0)),
        if (e.hasL3CacheBytes)
          _s('L3 cache', formatBytesBinary(e.l3CacheBytes, fractionDigits: 0)),
      ],
    ),
  ]);
}

List<InventoryDetailSection> memoryModuleDetailSections(
  InventoryMemoryModuleEntry e,
) {
  return _sections([
    (
      'Identity',
      [
        _s('Bank locator', e.bankLocator),
        _s('Manufacturer', e.manufacturer),
        _s('Part number', e.partNumber),
        _s('Serial number', e.serialNumber),
        _s('Form factor', e.formFactor),
        _s('Memory type', e.memoryType),
      ],
    ),
    (
      'Capabilities',
      [
        _s('Populated', e.populated ? 'Yes' : 'No'),
        if (e.hasSizeBytes)
          _s('Size', formatBytesBinary(e.sizeBytes, fractionDigits: 0)),
        if (e.hasSpeedMts) _s('Rated speed', '${e.speedMts} MT/s'),
        if (e.hasConfiguredSpeedMts)
          _s('Configured speed', '${e.configuredSpeedMts} MT/s'),
        if (e.hasConfiguredVoltageMv)
          _s(
            'Configured voltage',
            '${(e.configuredVoltageMv / 1000).toStringAsFixed(2)} V',
          ),
        if (e.hasIsEcc) _s('ECC', e.isEcc ? 'Yes' : 'No'),
        if (e.hasTotalWidthBits) _s('Total width', '${e.totalWidthBits} bits'),
        if (e.hasDataWidthBits) _s('Data width', '${e.dataWidthBits} bits'),
      ],
    ),
  ]);
}

List<InventoryDetailSection> storageDetailSections(InventoryStorageEntry e) {
  return _sections([
    (
      'Identity',
      [
        _s('Model', e.model),
        _s('Vendor', e.vendor),
        _s('Manufacturer', e.manufacturer),
        _s('Description', e.description),
        _s('Serial number', e.serialNumber),
        _s('Firmware revision', e.firmwareRevision),
        _s('Device path', e.devicePath),
        if (e.hasPhysicalDriveNumber)
          _s('Physical drive number', '${e.physicalDriveNumber}'),
      ],
    ),
    (
      'Hardware',
      [
        _s('Bus type', e.busType),
        _s('Media type', e.mediaType),
        _s('Partition style', e.partitionStyle),
        if (e.hasSizeBytes)
          _s('Size', formatBytesBinary(e.sizeBytes, fractionDigits: 1)),
        if (e.hasSectorSizeBytes)
          _s('Sector size', '${e.sectorSizeBytes} B'),
      ],
    ),
    (
      'Capabilities',
      [
        if (e.hasIsRemovable) _s('Removable', e.isRemovable ? 'Yes' : 'No'),
        if (e.hasTrimSupported)
          _s('TRIM supported', e.trimSupported ? 'Yes' : 'No'),
      ],
    ),
  ]);
}

List<InventoryDetailSection> networkAdapterDetailSections(
  InventoryNetworkAdapterEntry e,
) {
  return _sections([
    (
      'Identity',
      [
        _s('Friendly name', e.friendlyName),
        _s('Description', e.description),
        _s('MAC address', e.macAddress),
        _s('Connection type', e.connectionType),
        if (e.hasIfIndex) _s('Interface index', '${e.ifIndex}'),
      ],
    ),
    (
      'Network',
      [
        _s('Operational status', e.operationalStatus),
        if (e.hasDhcpEnabled)
          _s('DHCP enabled', e.dhcpEnabled ? 'Yes' : 'No'),
        _s('Loopback', e.isLoopback ? 'Yes' : 'No'),
        if (e.hasMtu) _s('MTU', '${e.mtu}'),
        if (e.hasLinkSpeedBps)
          _s('Link speed', _bitsPerSecond(e.linkSpeedBps)),
        if (e.ipv4Addresses.isNotEmpty)
          _s('IPv4 addresses', e.ipv4Addresses.join(', ')),
        if (e.ipv6Addresses.isNotEmpty)
          _s('IPv6 addresses', e.ipv6Addresses.join(', ')),
        if (e.gatewayAddresses.isNotEmpty)
          _s('Gateway', e.gatewayAddresses.join(', ')),
        if (e.dnsAddresses.isNotEmpty)
          _s('DNS servers', e.dnsAddresses.join(', ')),
      ],
    ),
    (
      'Driver',
      [
        _s('Driver provider', e.driverProvider),
        _s('Driver version', e.driverVersion),
        _s('Driver date', e.driverDate),
      ],
    ),
  ]);
}

(String, String)? _s(String label, String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return (label, trimmed);
}

List<InventoryDetailSection> _sections(
  List<(String title, List<(String, String)?> fields)> raw,
) {
  final result = <InventoryDetailSection>[];
  for (final entry in raw) {
    final fields = <(String, String)>[
      for (final f in entry.$2)
        if (f != null) f,
    ];
    if (fields.isEmpty) continue;
    result.add(InventoryDetailSection(title: entry.$1, fields: fields));
  }
  return result;
}

String _bitsPerSecond(int bps) {
  if (bps <= 0) return '0 bps';
  const units = ['bps', 'Kbps', 'Mbps', 'Gbps', 'Tbps'];
  var value = bps.toDouble();
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  if (unit == 0) return '${value.round()} ${units[unit]}';
  return '${value.toStringAsFixed(1)} ${units[unit]}';
}

String _titleCase(String snakeCase) {
  return snakeCase
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
