import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pulse_protocol/pulse_wire.dart';

/// Hierarchical Inventory browser catalog (UI navigation only).
class InventoryBrowserGroup {
  const InventoryBrowserGroup({
    required this.id,
    required this.label,
    required this.icon,
    required this.domains,
  });

  final String id;
  final String label;
  final IconData icon;
  final List<InventoryDomainNode> domains;
}

class InventoryDomainNode {
  const InventoryDomainNode({
    required this.id,
    required this.label,
    required this.icon,
    required this.implemented,
    required this.mcpTool,
  });

  final InventoryDomainId id;
  final String label;
  final IconData icon;
  final bool implemented;
  final String mcpTool;
}

const kInventoryBrowserGroups = <InventoryBrowserGroup>[
  InventoryBrowserGroup(
    id: 'system',
    label: 'System',
    icon: LucideIcons.server,
    domains: [
      InventoryDomainNode(
        id: InventoryDomainId.motherboard,
        label: 'Motherboard',
        icon: LucideIcons.circuitBoard,
        implemented: false,
        mcpTool: 'inventory.motherboard',
      ),
      InventoryDomainNode(
        id: InventoryDomainId.bios,
        label: 'BIOS',
        icon: LucideIcons.cpu,
        implemented: false,
        mcpTool: 'inventory.bios',
      ),
      InventoryDomainNode(
        id: InventoryDomainId.cpu,
        label: 'CPU',
        icon: LucideIcons.cpu,
        implemented: false,
        mcpTool: 'inventory.cpu',
      ),
      InventoryDomainNode(
        id: InventoryDomainId.memoryModules,
        label: 'Memory',
        icon: LucideIcons.database,
        implemented: false,
        mcpTool: 'inventory.memory',
      ),
      InventoryDomainNode(
        id: InventoryDomainId.storage,
        label: 'Storage',
        icon: LucideIcons.database,
        implemented: false,
        mcpTool: 'inventory.storage',
      ),
      InventoryDomainNode(
        id: InventoryDomainId.networkAdapters,
        label: 'Network',
        icon: LucideIcons.globe,
        implemented: false,
        mcpTool: 'inventory.network',
      ),
      InventoryDomainNode(
        id: InventoryDomainId.battery,
        label: 'Battery',
        icon: LucideIcons.zap,
        implemented: true,
        mcpTool: 'inventory.battery',
      ),
    ],
  ),
  InventoryBrowserGroup(
    id: 'devices',
    label: 'Devices',
    icon: LucideIcons.usb,
    domains: [
      InventoryDomainNode(
        id: InventoryDomainId.usb,
        label: 'USB',
        icon: LucideIcons.usb,
        implemented: true,
        mcpTool: 'inventory.usb',
      ),
      InventoryDomainNode(
        id: InventoryDomainId.pci,
        label: 'PCI',
        icon: LucideIcons.circuitBoard,
        implemented: true,
        mcpTool: 'inventory.pci',
      ),
      InventoryDomainNode(
        id: InventoryDomainId.displays,
        label: 'Displays',
        icon: LucideIcons.monitor,
        implemented: true,
        mcpTool: 'inventory.displays',
      ),
      InventoryDomainNode(
        id: InventoryDomainId.audio,
        label: 'Audio',
        icon: LucideIcons.headphones,
        implemented: true,
        mcpTool: 'inventory.audio',
      ),
      InventoryDomainNode(
        id: InventoryDomainId.bluetooth,
        label: 'Bluetooth',
        icon: LucideIcons.radio,
        implemented: true,
        mcpTool: 'inventory.bluetooth',
      ),
      InventoryDomainNode(
        id: InventoryDomainId.printers,
        label: 'Printers',
        icon: LucideIcons.fileText,
        implemented: true,
        mcpTool: 'inventory.printers',
      ),
    ],
  ),
  InventoryBrowserGroup(
    id: 'software',
    label: 'Software',
    icon: LucideIcons.package,
    domains: [
      InventoryDomainNode(
        id: InventoryDomainId.software,
        label: 'Installed software',
        icon: LucideIcons.package,
        implemented: true,
        mcpTool: 'inventory.software',
      ),
      InventoryDomainNode(
        id: InventoryDomainId.drivers,
        label: 'Drivers',
        icon: LucideIcons.cpu,
        implemented: true,
        mcpTool: 'inventory.drivers',
      ),
      InventoryDomainNode(
        id: InventoryDomainId.services,
        label: 'Services',
        icon: LucideIcons.cog,
        implemented: true,
        mcpTool: 'inventory.services',
      ),
    ],
  ),
];

InventoryDomainNode? inventoryNodeFor(InventoryDomainId id) {
  for (final group in kInventoryBrowserGroups) {
    for (final node in group.domains) {
      if (node.id == id) return node;
    }
  }
  return null;
}
