import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/application/window_close_behavior.dart';

void main() {
  test('Background ON: close window -> hide to tray', () {
    expect(
      resolveWindowCloseDecision(backgroundModeEnabled: true),
      PulseUiCloseDecision.hideToTray,
    );
  });

  test('Background OFF: close window -> exit UI', () {
    expect(
      resolveWindowCloseDecision(backgroundModeEnabled: false),
      PulseUiCloseDecision.exitUi,
    );
  });

  test('Tray Exit: always exit UI regardless of Background Mode', () {
    expect(resolveTrayExitDecision(), PulseUiCloseDecision.exitUi);
  });
}
