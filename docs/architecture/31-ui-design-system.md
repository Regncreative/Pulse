# 31 — UI design system (Phase A)

Status: Implemented foundation for the Pulse UX redesign.

## Purpose

Give Pulse a typed, themeable design system so light/dark modes and accent colors work without rewriting hundreds of call sites.

## ThemeExtension: `PulseThemeData`

Pulse carries design tokens as a Flutter [`ThemeExtension`](https://api.flutter.dev/flutter/material/ThemeExtension-class.html):

- Surfaces, strokes, text, accent*, semantic, and severity colors
- Radii and spacing as doubles
- Motion durations and curves
- Elevation helpers as methods (`elevationSoft`, `elevation1`, `elevationLift`, `severityGlow`, `newestGlow`)

Factory constructors:

- `PulseThemeData.dark({Color accent})`
- `PulseThemeData.light({Color accent})`

Accent-derived tokens (`accentMuted`, `accentSoft`, `onAccent`, `focusRing`) are computed from the accent HSV so presets and custom colors stay cohesive.

`PulseTheme.dark({Color? accent})` / `PulseTheme.light({Color? accent})` return full `ThemeData` with `extensions: [PulseThemeData...]`.

Layout constants (`sidebarWidth`, `pagePad*`, `window*`, icon sizes) remain static on `PulseTokens` / `PulseThemeData`.

## Accent presets

`PulseAccentPreset`: `blue` | `green` | `purple` | `orange` | `custom`

Persisted via `SettingsController`:

| Pref | Values | Default |
|------|--------|---------|
| `themeMode` | `system` \| `light` \| `dark` | `dark` |
| `accentPreset` | preset names above | `blue` |
| `customAccentArgb` | ARGB int | `0xFF60CDFF` |
| `animationSpeed` | `0.5`–`1.5` | `1.0` (stored for later duration scaling) |

Helpers: `materialThemeMode`, `resolvedAccent`.

`PulseApp` wires:

```dart
theme: PulseTheme.light(accent: settings.resolvedAccent),
darkTheme: PulseTheme.dark(accent: settings.resolvedAccent),
themeMode: settings.materialThemeMode,
```

## Migration via `PulseThemeScope`

Hundreds of widgets use ambient tokens such as `PulseTokens.canvas`. Those color/duration accessors are **no longer `const Color`s** — they read from:

```dart
class PulseThemeScope {
  static PulseThemeData current = PulseThemeData.dark();
}
```

`PulseApp`'s `builder` syncs after theme resolution:

```dart
PulseThemeScope.current = Theme.of(context).extension<PulseThemeData>()!;
```

Preferred new call sites:

```dart
extension PulseThemeX on BuildContext {
  PulseThemeData get pulseTheme =>
      Theme.of(this).extension<PulseThemeData>() ?? PulseThemeScope.current;
}
```

**Const caveat:** `const Divider(color: PulseTokens.strokeSubtle)` (and similar) no longer compile because color getters are not compile-time constants. Drop `const` on those widgets.

## Design-system widgets

Folder: `apps/pulse_app/lib/presentation/design_system/`

| Widget | Role |
|--------|------|
| `PulseSection` | Collapsible titled section (chevron, `AnimatedSize`, soft divider); parent owns `expanded` / optional `storageKey` persistence |
| `PulseMetricRow` | Label / value / optional description row |
| `PulseMetricSection` | Titled group of metric rows |
| `PulseStatusBadge` | Typedef / thin re-export of `PulseBadge` |
| `PulseSkeleton` | Shimmer placeholder (wraps `PulseLoadingBlock`) |
| `showPulseDialog` / `showPulseConfirmDialog` | Themed `AlertDialog` helpers |

Barrel: `design_system.dart` (also re-exports key existing components).

## Migration guidance

1. New UI: prefer `context.pulseTheme` and design-system widgets.
2. Existing UI: keep `PulseTokens.*` — they track `PulseThemeScope`.
3. Do not introduce HTTP or cloud for appearance prefs — local `SharedPreferences` only.
4. Phase B+ can migrate Health/Timeline screens onto `PulseSection` / `PulseMetric*` and surface appearance controls in Settings.

## Related

- Theme implementation: `apps/pulse_app/lib/app/theme/pulse_theme.dart`
- App wiring: `apps/pulse_app/lib/app/pulse_app.dart`
- Prefs: `apps/pulse_app/lib/application/settings_controller.dart`
- Flutter architecture: [03-flutter-architecture.md](03-flutter-architecture.md)
