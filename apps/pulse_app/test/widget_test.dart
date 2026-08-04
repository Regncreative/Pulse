import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/app/theme/pulse_theme.dart';

void main() {
  test('dark theme builds with extension', () {
    final theme = PulseTheme.dark();
    expect(theme.brightness, Brightness.dark);
    final tokens = theme.extension<PulseThemeData>();
    expect(tokens, isNotNull);
    expect(tokens!.accent, PulseThemeData.defaultAccent);
  });

  test('light theme builds with accent', () {
    const accent = Color(0xFF6CCB5F);
    final theme = PulseTheme.light(accent: accent);
    expect(theme.brightness, Brightness.light);
    final tokens = theme.extension<PulseThemeData>();
    expect(tokens, isNotNull);
    // Light surfaces deepen the accent for contrast (_lightAccent).
    expect(tokens!.accent, PulseThemeData.light(accent: accent).accent);
    expect(tokens.accent, isNot(equals(accent)));
  });
}
