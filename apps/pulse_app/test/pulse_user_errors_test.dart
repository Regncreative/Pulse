import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/presentation/utils/pulse_user_errors.dart';
import 'package:pulse/ipc/pulse_ipc_client.dart';

void main() {
  test('maps offline and timeout errors to friendly copy', () {
    expect(
      PulseUserErrors.fromMessage('CreateFile failed: 2'),
      contains('offline'),
    );
    expect(
      PulseUserErrors.fromMessage('TimeoutException after 0:00:05.000000'),
      contains('too long'),
    );
    expect(
      PulseUserErrors.connectionHint(IpcConnectionState.connecting),
      contains('Looking for PulseService'),
    );
  });
}
