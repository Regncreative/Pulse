import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

final Set<int> _enumAppPids = {};

int _enumWindowsProc(int hwnd, int lParam) {
  if (IsWindowVisible(hwnd) == 0) return TRUE;
  if (GetWindow(hwnd, GW_OWNER) != 0) return TRUE;
  final ex = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  if ((ex & WS_EX_TOOLWINDOW) != 0) return TRUE;
  final pidPtr = calloc<DWORD>();
  try {
    GetWindowThreadProcessId(hwnd, pidPtr);
    final pid = pidPtr.value;
    if (pid != 0) _enumAppPids.add(pid);
  } finally {
    calloc.free(pidPtr);
  }
  return TRUE;
}

final _enumCallback = Pointer.fromFunction<WNDENUMPROC>(_enumWindowsProc, 0);

/// Detects Task Manager "Apps" via visible top-level windows (user session).
class ProcessWindowClassifier {
  /// PIDs that own at least one visible, non-tool top-level window.
  static Future<Set<int>> visibleApplicationPids() async {
    _enumAppPids.clear();
    EnumWindows(_enumCallback, 0);
    return Set<int>.from(_enumAppPids);
  }
}
