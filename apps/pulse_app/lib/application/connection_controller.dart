import 'package:flutter/foundation.dart';

import '../ipc/pulse_ipc_client.dart';
import '../logging/app_logger.dart';

class ConnectionController extends ChangeNotifier {
  ConnectionController({required this.ipc, required this.logger}) {
    _lastState = ipc.status.state;
    _lastLabel = statusLabel;
    ipc.addListener(_onIpc);
  }

  final PulseIpcClient ipc;
  final AppLogger logger;

  IpcConnectionState? _lastState;
  String? _lastLabel;

  String get statusLabel {
    switch (ipc.status.state) {
      case IpcConnectionState.connected:
        return 'Connected';
      case IpcConnectionState.connecting:
        return 'Connecting…';
      case IpcConnectionState.error:
      case IpcConnectionState.disconnected:
        return 'Offline';
    }
  }

  Future<String> ping() async {
    try {
      final pong = await ipc.ping();
      final msg =
          'Pong nonce=${pong.nonce} service=${pong.serviceVersion} unixMs=${pong.unixMs}';
      logger.info('ConnectionController', msg);
      notifyListeners();
      return msg;
    } catch (e) {
      logger.error('ConnectionController', 'Ping failed: $e');
      notifyListeners();
      rethrow;
    }
  }

  void _onIpc() {
    final state = ipc.status.state;
    final label = statusLabel;
    if (state == _lastState && label == _lastLabel) return;
    _lastState = state;
    _lastLabel = label;
    notifyListeners();
  }

  @override
  void dispose() {
    ipc.removeListener(_onIpc);
    super.dispose();
  }
}
