import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pulse/presentation/health/health_utilization_colors.dart';
import 'package:pulse/presentation/health/health_view_models.dart';

void main() {
  group('HealthUtilizationColors', () {
    test('thresholds match diagnostic bands', () {
      expect(HealthUtilizationColors.forPercent(0), HealthUtilizationColors.low);
      expect(HealthUtilizationColors.forPercent(49), HealthUtilizationColors.low);
      expect(
        HealthUtilizationColors.forPercent(50),
        HealthUtilizationColors.medium,
      );
      expect(
        HealthUtilizationColors.forPercent(69),
        HealthUtilizationColors.medium,
      );
      expect(HealthUtilizationColors.forPercent(70), HealthUtilizationColors.high);
      expect(HealthUtilizationColors.forPercent(89), HealthUtilizationColors.high);
      expect(
        HealthUtilizationColors.forPercent(90),
        HealthUtilizationColors.critical,
      );
      expect(
        HealthUtilizationColors.forPercent(100),
        HealthUtilizationColors.critical,
      );
    });

    test('percent metrics use semantic color; throughput stays neutral', () {
      final cpu = HealthMetric(
        id: 'cpu',
        title: 'CPU',
        value: '22',
        unit: '%',
        description: '',
        status: HealthStatus.good,
        icon: LucideIcons.cpu,
        sparkline: const [10, 22],
      );
      final disk = HealthMetric(
        id: 'disk',
        title: 'Disk',
        value: '12',
        unit: 'MB/s',
        description: '',
        status: HealthStatus.good,
        icon: LucideIcons.hardDrive,
        sparkline: const [1, 12],
      );
      expect(healthMetricChartColor(cpu), HealthUtilizationColors.low);
      expect(healthMetricChartColor(disk), HealthUtilizationColors.neutral);

      final hot = HealthMetric(
        id: 'cpu2',
        title: 'CPU',
        value: '96',
        unit: '%',
        description: '',
        status: HealthStatus.elevated,
        icon: LucideIcons.cpu,
        sparkline: const [80, 96],
      );
      expect(healthMetricChartColor(hot), HealthUtilizationColors.critical);
    });
  });

  testWidgets('SwitchTheme keeps thumb visible on hover', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: const ColorScheme.dark(primary: Color(0xFF4C8DFF)),
          switchTheme: SwitchThemeData(
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.white;
              }
              return const Color(0xFFE8ECF0);
            }),
            trackColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const Color(0xFF4C8DFF);
              }
              return const Color(0xFF3A4250);
            }),
          ),
        ),
        home: Scaffold(
          body: Switch(value: false, onChanged: (_) {}),
        ),
      ),
    );

    final theme = Theme.of(tester.element(find.byType(Switch)));
    final thumb = theme.switchTheme.thumbColor!;
    expect(
      thumb.resolve({WidgetState.hovered}),
      const Color(0xFFE8ECF0),
    );
    expect(
      thumb.resolve({WidgetState.selected, WidgetState.hovered}),
      Colors.white,
    );
  });
}
