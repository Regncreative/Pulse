import '../../ipc/pulse_ipc_client.dart';

/// Maps technical IPC / transport failures to calm, user-facing copy.
abstract final class PulseUserErrors {
  static String fromObject(Object error) {
    final raw = error.toString();
    return fromMessage(raw);
  }

  static String fromMessage(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('timeout')) {
      return 'The service took too long to respond. Pulse will keep trying.';
    }
    if (lower.contains('createfile') ||
        lower.contains('named pipe') ||
        (lower.contains('pipe') &&
            (lower.contains('2') ||
                lower.contains('fail') ||
                lower.contains('error') ||
                lower.contains('broken'))) ||
        lower.contains('offline') ||
        lower.contains('not connected') ||
        lower.contains('disconnected')) {
      return 'PulseService is offline. Start it to resume observation.';
    }
    if (lower.contains('protocol') || lower.contains('version')) {
      return 'Pulse and PulseService protocol versions do not match.';
    }
    if (lower.contains('unsupported') || lower.contains('only the system')) {
      return 'That channel is not available in this build.';
    }
    if (lower.contains('another diagnostics action')) {
      return 'Wait for the current diagnostics action to finish.';
    }
    // Strip StateError / Exception wrappers when present.
    final cleaned = raw
        .replaceFirst(RegExp(r'^Bad state:\s*'), '')
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .replaceFirst(RegExp(r'^StateError:\s*'), '')
        .trim();
    if (cleaned.length > 160) {
      return '${cleaned.substring(0, 157)}…';
    }
    return cleaned.isEmpty
        ? 'Something went wrong talking to PulseService.'
        : cleaned;
  }

  static String connectionHint(IpcConnectionState state) {
    return switch (state) {
      IpcConnectionState.connected =>
        'Connected to PulseService over the local named pipe.',
      IpcConnectionState.connecting =>
        'Looking for PulseService on this PC…',
      IpcConnectionState.disconnected || IpcConnectionState.error =>
        'Offline — start PulseService to observe Windows events.',
    };
  }
}
