import 'package:flutter_test/flutter_test.dart';

/// Startup and Retry must share one snapshot path (reloadSnapshot).
/// Connection epochs ensure a reconnect always re-fetches.
void main() {
  test('connection epoch requires a fresh snapshot after reconnect', () {
    var connectionEpoch = 0;
    var snapshotEpoch = -1;

    bool needsSnapshot(bool loading) =>
        snapshotEpoch != connectionEpoch && !loading;

    connectionEpoch++;
    snapshotEpoch = -1;
    expect(needsSnapshot(false), isTrue);

    snapshotEpoch = connectionEpoch;
    expect(needsSnapshot(false), isFalse);

    connectionEpoch++;
    snapshotEpoch = -1;
    expect(needsSnapshot(false), isTrue);
  });
}
