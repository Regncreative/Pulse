/// Pure close / exit policy for Pulse.exe (UI process only).
///
/// Never stops, uninstalls, or reconfigures PulseService.
enum PulseUiCloseDecision {
  /// Hide the main window; keep Pulse.exe, IPC, tray, and alerts alive.
  hideToTray,

  /// Terminate Pulse.exe. PulseService is unaffected.
  exitUi,
}

/// Window Close button / WM_CLOSE while Background Mode is considered.
PulseUiCloseDecision resolveWindowCloseDecision({
  required bool backgroundModeEnabled,
}) {
  return backgroundModeEnabled
      ? PulseUiCloseDecision.hideToTray
      : PulseUiCloseDecision.exitUi;
}

/// Tray → Exit Pulse always terminates the UI process.
PulseUiCloseDecision resolveTrayExitDecision() => PulseUiCloseDecision.exitUi;
