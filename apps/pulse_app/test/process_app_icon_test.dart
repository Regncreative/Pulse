import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/presentation/health/widgets/process_app_icon.dart';

void main() {
  test('knownSystemExecutablePath maps common system binaries', () {
    expect(
      knownSystemExecutablePath('explorer.exe')?.toLowerCase(),
      endsWith(r'\explorer.exe'),
    );
    expect(
      knownSystemExecutablePath('svchost.exe')?.toLowerCase(),
      endsWith(r'\system32\svchost.exe'),
    );
    expect(
      knownSystemExecutablePath('DWM.EXE')?.toLowerCase(),
      endsWith(r'\system32\dwm.exe'),
    );
    expect(
      knownSystemExecutablePath('conhost.exe')?.toLowerCase(),
      endsWith(r'\system32\conhost.exe'),
    );
    expect(
      knownSystemExecutablePath('taskhostw.exe')?.toLowerCase(),
      endsWith(r'\system32\taskhostw.exe'),
    );
    expect(knownSystemExecutablePath('chrome.exe'), isNull);
    expect(knownSystemExecutablePath('System'), isNull);
    expect(knownSystemExecutablePath(''), isNull);
  });
}
