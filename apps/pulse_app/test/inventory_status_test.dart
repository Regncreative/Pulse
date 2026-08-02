import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/presentation/inventory/inventory_page.dart';
import 'package:pulse_protocol/pulse_wire.dart';

void main() {
  test('inventory status labels cover every InventoryStatus', () {
    for (final status in InventoryStatus.values) {
      final label = inventoryStatusLabel(status);
      expect(label, isNotEmpty);
      expect(inventoryStatusTone(status), isNotNull);
    }
  });

  test('failure statuses use distinct labels', () {
    expect(inventoryStatusLabel(InventoryStatus.available), 'Available');
    expect(inventoryStatusLabel(InventoryStatus.unsupported), 'Unsupported');
    expect(inventoryStatusLabel(InventoryStatus.accessDenied), 'Access denied');
    expect(inventoryStatusLabel(InventoryStatus.partial), 'Partial');
    expect(inventoryStatusLabel(InventoryStatus.error), 'Error');
  });
}
