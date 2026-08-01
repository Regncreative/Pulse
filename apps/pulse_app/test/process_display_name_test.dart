import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/presentation/health/health_view_models.dart';
import 'package:pulse/presentation/health/widgets/process_inventory/process_display_name.dart';

void main() {
  test('formatTransferRate never shows raw counters', () {
    expect(formatTransferRate(0), '0 B/s');
    expect(formatTransferRate(512), '512 B/s');
    expect(formatTransferRate(2048), '2.0 KB/s');
    expect(formatTransferRate(1.5 * 1024 * 1024), '1.5 MB/s');
    expect(formatTransferRate(2 * 1024 * 1024 * 1024), '2.0 GB/s');
  });

  test('friendly heuristics for shell / system processes', () {
    expect(
      ProcessDisplayNames.friendlySync('explorer.exe'),
      'Windows Explorer',
    );
    expect(ProcessDisplayNames.friendlySync('svchost.exe'), 'Service Host');
    final chrome = ProcessDisplayNames.splitLabels(
      imageName: 'chrome.exe',
      productName: 'Google Chrome',
    );
    expect(chrome.primary, 'Google Chrome');
    expect(chrome.secondary, 'chrome.exe');
  });
}
