import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:pulse_protocol/pulse_constants.dart';
import 'package:win32/win32.dart';

/// SCM lifecycle states for PulseService (not IPC connectivity).
enum PulseServiceScmState {
  notInstalled,
  stopped,
  startPending,
  stopPending,
  running,
  unknown,
}

class PulseServiceScmSnapshot {
  const PulseServiceScmSnapshot({
    required this.state,
    this.win32Error,
  });

  final PulseServiceScmState state;
  final int? win32Error;

  String get label => switch (state) {
        PulseServiceScmState.notInstalled => 'Not installed',
        PulseServiceScmState.stopped => 'Stopped',
        PulseServiceScmState.startPending => 'Starting…',
        PulseServiceScmState.stopPending => 'Stopping…',
        PulseServiceScmState.running => 'Running',
        PulseServiceScmState.unknown => 'Unknown',
      };
}

/// Read-only query of the Windows Service Control Manager.
abstract class PulseServiceScm {
  PulseServiceScmSnapshot query();
}

/// Production SCM query (no elevation required for QUERY_STATUS).
class WindowsPulseServiceScm implements PulseServiceScm {
  const WindowsPulseServiceScm();

  @override
  PulseServiceScmSnapshot query() {
    if (!Platform.isWindows) {
      return const PulseServiceScmSnapshot(state: PulseServiceScmState.unknown);
    }

    final scm = OpenSCManager(nullptr, nullptr, SC_MANAGER_CONNECT);
    if (scm == NULL) {
      return PulseServiceScmSnapshot(
        state: PulseServiceScmState.unknown,
        win32Error: GetLastError(),
      );
    }

    try {
      final name = kServiceName.toNativeUtf16();
      try {
        final svc = OpenService(scm, name, SERVICE_QUERY_STATUS);
        if (svc == NULL) {
          final err = GetLastError();
          if (err == ERROR_SERVICE_DOES_NOT_EXIST) {
            return const PulseServiceScmSnapshot(
              state: PulseServiceScmState.notInstalled,
            );
          }
          return PulseServiceScmSnapshot(
            state: PulseServiceScmState.unknown,
            win32Error: err,
          );
        }

        try {
          final status = calloc<SERVICE_STATUS_PROCESS>();
          final bytesNeeded = calloc<DWORD>();
          try {
            final ok = QueryServiceStatusEx(
              svc,
              SC_STATUS_PROCESS_INFO,
              status.cast(),
              sizeOf<SERVICE_STATUS_PROCESS>(),
              bytesNeeded,
            );
            if (ok == FALSE) {
              return PulseServiceScmSnapshot(
                state: PulseServiceScmState.unknown,
                win32Error: GetLastError(),
              );
            }
            return PulseServiceScmSnapshot(
              state: _mapState(status.ref.dwCurrentState),
            );
          } finally {
            calloc.free(status);
            calloc.free(bytesNeeded);
          }
        } finally {
          CloseServiceHandle(svc);
        }
      } finally {
        free(name);
      }
    } finally {
      CloseServiceHandle(scm);
    }
  }

  static PulseServiceScmState _mapState(int dwCurrentState) {
    return switch (dwCurrentState) {
      SERVICE_STOPPED => PulseServiceScmState.stopped,
      SERVICE_START_PENDING => PulseServiceScmState.startPending,
      SERVICE_STOP_PENDING => PulseServiceScmState.stopPending,
      SERVICE_RUNNING => PulseServiceScmState.running,
      _ => PulseServiceScmState.unknown,
    };
  }
}
