import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:pulse_protocol/pulse_constants.dart';
import 'package:win32/win32.dart';

/// SEE_MASK_NOCLOSEPROCESS — keep process handle so we can wait.
const int _kSeeMaskNocloseprocess = 0x00000040;

/// win32 package exposes SERVICE_QUERY_STATUS but not SERVICE_QUERY_CONFIG.
const int _kServiceQueryConfig = 0x0001;

/// Locates PulseService.exe and runs elevated CLI actions.
abstract class PulseServiceLauncher {
  /// Package-local binary used for install / repair / uninstall.
  String? resolvePackageServiceExePath();

  /// Installed service ImagePath from SCM (start / stop / restart).
  String? resolveInstalledServiceExePath();

  /// Runs `PulseService.exe <args>` elevated and waits for exit.
  ///
  /// Start/stop/restart prefer the SCM-installed binary. Install/repair require
  /// a package-local `PulseService.exe` (beside Pulse or under `service\`).
  Future<int> runElevated(
    String args, {
    Duration timeout = const Duration(seconds: 45),
  });
}

/// Production launcher: UAC (`runas`) + wait for process exit.
class WindowsPulseServiceLauncher implements PulseServiceLauncher {
  const WindowsPulseServiceLauncher();

  @override
  String? resolvePackageServiceExePath() {
    if (!Platform.isWindows) return null;
    final dir = File(Platform.resolvedExecutable).parent.path;
    final sep = Platform.pathSeparator;
    String join(List<String> parts) => parts.join(sep);
    final candidates = <String>[
      join([dir, 'PulseService.exe']),
      join([dir, 'service', 'PulseService.exe']),
      // Dev layouts: apps/pulse_app/build/... → repo build/service
      join([dir, '..', '..', '..', '..', '..', 'build', 'service', 'PulseService.exe']),
      join([dir, '..', 'service', 'PulseService.exe']),
    ];
    for (final path in candidates) {
      final normalized = File(path).absolute.path;
      if (File(normalized).existsSync()) return normalized;
    }
    return null;
  }

  @override
  String? resolveInstalledServiceExePath() {
    if (!Platform.isWindows) return null;

    final scm = OpenSCManager(nullptr, nullptr, SC_MANAGER_CONNECT);
    if (scm == NULL) return null;

    try {
      final name = kServiceName.toNativeUtf16();
      try {
        final svc = OpenService(scm, name, _kServiceQueryConfig);
        if (svc == NULL) return null;

        try {
          final needed = calloc<DWORD>();
          try {
            QueryServiceConfig(svc, nullptr, 0, needed);
            final bytes = needed.value;
            if (bytes == 0 || bytes > 16 * 1024) return null;

            final buffer = calloc<BYTE>(bytes);
            try {
              final ok = QueryServiceConfig(
                svc,
                buffer.cast(),
                bytes,
                needed,
              );
              if (ok == FALSE) return null;
              final config = buffer.cast<QUERY_SERVICE_CONFIG>();
              final raw = config.ref.lpBinaryPathName.toDartString();
              return _exePathFromImagePath(raw);
            } finally {
              calloc.free(buffer);
            }
          } finally {
            calloc.free(needed);
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

  /// Backward-compatible alias: package path, then installed SCM path.
  String? resolveServiceExePath() =>
      resolvePackageServiceExePath() ?? resolveInstalledServiceExePath();

  @override
  Future<int> runElevated(
    String args, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (!Platform.isWindows) {
      throw const PulseServiceLaunchException(
        'Service control is only available on Windows.',
      );
    }

    final trimmed = args.trim();
    final needsPackage = trimmed.contains('install') ||
        trimmed.contains('uninstall');
    final exe = needsPackage
        ? resolvePackageServiceExePath()
        : (resolveInstalledServiceExePath() ??
            resolvePackageServiceExePath());

    if (exe == null) {
      if (needsPackage) {
        throw const PulseServiceLaunchException(
          'PulseService.exe is missing from the Pulse install folder. '
          'Reinstall Pulse, then use Repair / Install service.',
        );
      }
      throw const PulseServiceLaunchException(
        'Could not locate the installed PulseService binary. '
        'If the service is missing, use Repair / Install service.',
      );
    }

    return _runElevatedAt(exe, args, timeout: timeout);
  }

  /// Parses SCM ImagePath (`"C:\...\PulseService.exe" --arg`) into an exe path.
  static String? _exePathFromImagePath(String imagePath) {
    var s = imagePath.trim();
    if (s.isEmpty) return null;

    String path;
    if (s.startsWith('"')) {
      final end = s.indexOf('"', 1);
      if (end <= 1) return null;
      path = s.substring(1, end);
    } else {
      final space = s.indexOf(' ');
      path = space < 0 ? s : s.substring(0, space);
    }

    path = path.trim();
    if (path.isEmpty) return null;
    if (!File(path).existsSync()) return null;
    return path;
  }

  Future<int> _runElevatedAt(
    String exePath,
    String args, {
    required Duration timeout,
  }) async {
    final info = calloc<SHELLEXECUTEINFO>();
    final verb = 'runas'.toNativeUtf16();
    final file = exePath.toNativeUtf16();
    final parameters = args.toNativeUtf16();
    try {
      info.ref.cbSize = sizeOf<SHELLEXECUTEINFO>();
      info.ref.fMask = _kSeeMaskNocloseprocess;
      info.ref.hwnd = NULL;
      info.ref.lpVerb = verb;
      info.ref.lpFile = file;
      info.ref.lpParameters = parameters;
      info.ref.lpDirectory = nullptr;
      info.ref.nShow = SW_HIDE;

      final ok = ShellExecuteEx(info);
      if (ok == FALSE) {
        final err = GetLastError();
        if (err == ERROR_CANCELLED) {
          throw const PulseServiceLaunchException(
            'Administrator approval was cancelled. Pulse did not change the service.',
          );
        }
        if (err == ERROR_ACCESS_DENIED) {
          throw const PulseServiceLaunchException(
            'Windows denied elevation. Approve the UAC prompt to control PulseService.',
          );
        }
        throw PulseServiceLaunchException(
          'Could not start an elevated PulseService action (error $err).',
        );
      }

      final process = info.ref.hProcess;
      if (process == NULL) {
        throw const PulseServiceLaunchException(
          'Elevated PulseService started but no process handle was returned.',
        );
      }

      try {
        final wait = WaitForSingleObject(process, timeout.inMilliseconds);
        if (wait == WAIT_TIMEOUT) {
          throw const PulseServiceLaunchException(
            'PulseService control timed out. Check Services.msc or try again.',
          );
        }
        final code = calloc<DWORD>();
        try {
          if (GetExitCodeProcess(process, code) == FALSE) {
            throw const PulseServiceLaunchException(
              'Could not read the elevated PulseService exit code.',
            );
          }
          return code.value;
        } finally {
          calloc.free(code);
        }
      } finally {
        CloseHandle(process);
      }
    } finally {
      free(verb);
      free(file);
      free(parameters);
      calloc.free(info);
    }
  }
}

class PulseServiceLaunchException implements Exception {
  const PulseServiceLaunchException(this.message);
  final String message;

  @override
  String toString() => message;
}
