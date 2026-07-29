import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/app/theme/pulse_theme.dart';

void main() {
  test('dark theme builds', () {
    final theme = PulseTheme.dark();
    expect(theme.brightness, Brightness.dark);
  });
}
