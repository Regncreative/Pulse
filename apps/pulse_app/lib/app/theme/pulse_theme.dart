import 'package:flutter/material.dart';

/// Windows 11 Fluent design tokens for Pulse (dark-first, commercial polish).
abstract final class PulseTokens {
  // Surfaces — Mica-inspired layered stack
  static const Color canvas = Color(0xFF17181B);
  static const Color canvasTint = Color(0xFF1A2430);
  static const Color sidebar = Color(0xCC1C1D21);
  static const Color sidebarSolid = Color(0xFF1C1D21);
  static const Color micaOverlay = Color(0x14FFFFFF);
  static const Color surface = Color(0xFF24252A);
  static const Color surfaceElevated = Color(0xFF2C2D32);
  static const Color surfaceHover = Color(0xFF34353B);
  static const Color surfacePressed = Color(0xFF3A3B42);
  static const Color acrylicFill = Color(0xE624252A);

  static const Color stroke = Color(0xFF3C3E44);
  static const Color strokeSubtle = Color(0xFF2A2B30);
  static const Color strokeStrong = Color(0xFF484A52);
  static const Color focusRing = Color(0xFF60CDFF);

  static const Color textPrimary = Color(0xFFF5F5F5);
  static const Color textSecondary = Color(0xFFB4B4B4);
  static const Color textTertiary = Color(0xFF9A9A9A);
  static const Color textDisabled = Color(0xFF5A5A5A);

  static const Color accent = Color(0xFF60CDFF);
  static const Color accentMuted = Color(0xFF3A7CA5);
  static const Color accentSoft = Color(0xFF1C3040);
  static const Color onAccent = Color(0xFF001B26);

  static const Color success = Color(0xFF6CCB5F);
  static const Color successSoft = Color(0xFF1C301E);
  static const Color warning = Color(0xFFE8B339);
  static const Color warningSoft = Color(0xFF302814);
  static const Color error = Color(0xFFFF99A4);
  static const Color errorSoft = Color(0xFF382024);
  static const Color info = Color(0xFF60CDFF);
  static const Color infoSoft = Color(0xFF1C3040);

  static const Color severityInfo = Color(0xFF60CDFF);
  static const Color severityWarning = Color(0xFFE8B339);
  static const Color severityError = Color(0xFFFF8A96);
  static const Color severitySuccess = Color(0xFF6CCB5F);
  static const Color severityCritical = Color(0xFFFF6B7A);

  static const double radiusSm = 6;
  static const double radiusMd = 8;
  static const double radiusLg = 10;
  static const double radiusXl = 14;
  static const double radiusCard = 12;
  static const double radiusPill = 999;
  static const double radiusIconWell = 10;
  static const double radiusProcessIcon = 7;

  static const double iconSm = 14;
  static const double iconMd = 16;
  static const double iconLg = 18;
  static const double iconNav = 17;

  static const double sidebarWidth = 256;
  static const double sidebarNarrow = 216;
  static const double appBarHeight = 52;

  /// Centered page content — prevents ultrawide stretch.
  static const double contentMaxWidth = 1600;

  /// Window chrome
  static const double windowMinWidth = 1200;
  static const double windowMinHeight = 800;
  static const double windowDefaultWidth = 1440;
  static const double windowDefaultHeight = 900;

  /// Content inset — consistent page rhythm
  static const double pagePadX = 32;
  static const double pagePadTop = 20;
  static const double pagePadBottom = 40;

  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;
  static const double space2xl = 48;

  static const Duration motionFast = Duration(milliseconds: 110);
  static const Duration motionNormal = Duration(milliseconds: 170);
  static const Duration motionSlow = Duration(milliseconds: 280);
  static const Duration motionPage = Duration(milliseconds: 240);
  static const Curve motionCurve = Curves.easeOutCubic;
  static const Curve motionEmphasized = Curves.easeOutQuint;

  static List<BoxShadow> get elevationSoft => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.18),
          blurRadius: 8,
          offset: const Offset(0, 1),
          spreadRadius: -1,
        ),
      ];

  static List<BoxShadow> get elevation1 => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.22),
          blurRadius: 12,
          offset: const Offset(0, 2),
          spreadRadius: -2,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get elevationLift => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.28),
          blurRadius: 18,
          offset: const Offset(0, 6),
          spreadRadius: -3,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> severityGlow(Color color, {double intensity = 1}) => [
        BoxShadow(
          color: color.withValues(alpha: 0.22 * intensity),
          blurRadius: 14 * intensity,
          offset: Offset.zero,
        ),
      ];

  static List<BoxShadow> newestGlow(Color color, double t) => [
        BoxShadow(
          color: color.withValues(alpha: 0.12 + (t * 0.18)),
          blurRadius: 10 + (t * 14),
          offset: const Offset(0, 2),
          spreadRadius: -2,
        ),
        ...elevationSoft,
      ];
}

class PulseTheme {
  static const String _font = 'Segoe UI';

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true).textTheme.apply(
          fontFamily: _font,
          bodyColor: PulseTokens.textPrimary,
          displayColor: PulseTokens.textPrimary,
        );

    final textTheme = base.copyWith(
      headlineMedium: base.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.45,
        fontSize: 28,
        height: 1.22,
        color: PulseTokens.textPrimary,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.28,
        fontSize: 22,
        height: 1.28,
        color: PulseTokens.textPrimary,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.22,
        fontSize: 20,
        height: 1.28,
        color: PulseTokens.textPrimary,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.12,
        fontSize: 15,
        height: 1.38,
        color: PulseTokens.textPrimary,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontWeight: FontWeight.w500,
        fontSize: 13,
        height: 1.35,
        color: PulseTokens.textSecondary,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        height: 1.55,
        fontSize: 15,
        color: PulseTokens.textPrimary,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        height: 1.55,
        fontSize: 13.5,
        color: PulseTokens.textSecondary,
      ),
      bodySmall: base.bodySmall?.copyWith(
        height: 1.5,
        fontSize: 12,
        letterSpacing: 0.02,
        color: PulseTokens.textTertiary,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 13,
        height: 1.2,
        color: PulseTokens.textPrimary,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontWeight: FontWeight.w500,
        fontSize: 12,
        height: 1.2,
        color: PulseTokens.textSecondary,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 10.5,
        letterSpacing: 0.35,
        height: 1.2,
        color: PulseTokens.textTertiary,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: _font,
      scaffoldBackgroundColor: PulseTokens.canvas,
      colorScheme: const ColorScheme.dark(
        surface: PulseTokens.surface,
        primary: PulseTokens.accent,
        onPrimary: PulseTokens.onAccent,
        secondary: PulseTokens.textSecondary,
        onSurface: PulseTokens.textPrimary,
        outline: PulseTokens.stroke,
        error: PulseTokens.error,
      ),
      textTheme: textTheme,
      dividerColor: PulseTokens.strokeSubtle,
      splashFactory: InkSparkle.splashFactory,
      focusColor: PulseTokens.accent.withValues(alpha: 0.14),
      hoverColor: PulseTokens.surfaceHover.withValues(alpha: 0.35),
      highlightColor: PulseTokens.accent.withValues(alpha: 0.06),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: PulseTokens.surfaceElevated,
          borderRadius: BorderRadius.circular(PulseTokens.radiusSm),
          border: Border.all(color: PulseTokens.stroke),
          boxShadow: PulseTokens.elevation1,
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: PulseTokens.textPrimary),
        waitDuration: const Duration(milliseconds: 360),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.dragged)) {
            return 9.0;
          }
          return 6.0;
        }),
        radius: const Radius.circular(999),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return PulseTokens.textSecondary.withValues(alpha: 0.5);
          }
          if (states.contains(WidgetState.hovered)) {
            return PulseTokens.textTertiary.withValues(alpha: 0.42);
          }
          return PulseTokens.textTertiary.withValues(alpha: 0.22);
        }),
        trackColor: WidgetStateProperty.all(Colors.transparent),
        trackBorderColor: WidgetStateProperty.all(Colors.transparent),
        crossAxisMargin: 4,
        mainAxisMargin: 10,
        minThumbLength: 48,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: PulseTokens.textSecondary,
          hoverColor: PulseTokens.surfaceHover,
          focusColor: PulseTokens.accent.withValues(alpha: 0.14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
          ),
          minimumSize: const Size(36, 36),
          padding: const EdgeInsets.all(8),
        ),
      ),
    );
  }
}
