import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Deployment flavor for Pulse UI vs Windows service lifecycle.
///
/// Store / MSIX detection uses [GetCurrentPackageFullName], not install paths.
abstract class PulseDeployment {
  /// True when this process has a Windows package identity (MSIX / Store).
  bool get isPackagedMsix;
}

/// Production detector via kernel32 package identity APIs.
class WindowsPulseDeployment implements PulseDeployment {
  const WindowsPulseDeployment();

  static bool? _cached;

  @override
  bool get isPackagedMsix {
    if (!Platform.isWindows) return false;
    return _cached ??= _queryPackaged();
  }

  /// Clears the process cache (tests only).
  static void debugResetCacheForTest() => _cached = null;

  /// Forces a cached value (tests only).
  static void debugSetPackagedForTest(bool value) => _cached = value;

  static bool _queryPackaged() {
    final length = calloc<Uint32>();
    try {
      length.value = 0;
      final probe = GetCurrentPackageFullName(length, nullptr);
      // APPMODEL_ERROR_NO_PACKAGE (15700) — not running as a packaged app.
      if (probe == APPMODEL_ERROR_NO_PACKAGE) return false;
      // ERROR_INSUFFICIENT_BUFFER (122) — packaged; length now set.
      if (probe != ERROR_INSUFFICIENT_BUFFER && probe != 0) {
        return false;
      }
      if (length.value == 0) return false;

      final buffer = calloc<Uint16>(length.value).cast<Utf16>();
      try {
        final status = GetCurrentPackageFullName(length, buffer);
        return status == 0;
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(length);
    }
  }
}

/// Fixed deployment flavor for unit tests.
class FixedPulseDeployment implements PulseDeployment {
  const FixedPulseDeployment({required this.isPackagedMsix});

  @override
  final bool isPackagedMsix;
}
