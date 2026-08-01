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
| `animationSpeed` | `0.5`–`1.5` | `1.0` (scales motion durations via `PulseTokens.scaleMotion`) |
| `textScale` | `0.9`–`1.3` | `1.0` (applied in `PulseApp` `MediaQuery.textScaler`, multiplied with compact `0.94`) |

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
| `PulseSection` | Collapsible titled section (chevron, `AnimatedSize`, soft divider); `builder` runs only when expanded; parent owns `expanded` / optional `storageKey` persistence |
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
4. Phase B migrates System Health detail panels onto `PulseSection` with
   expand state persisted in `SettingsController` (`health.sections.expanded`).
   Appearance controls surface in Settings.

## Accessibility & reduced motion

- **Sidebar / command palette:** nav tiles and the palette search field expose `Semantics` labels for screen readers and automation.
- **Focus:** primary `PulseButton`s wrap with `PulseFocus` (Windows-style focus ring) for keyboard users.
- **Text size:** Settings → Appearance → Text size (`textScale` 0.9–1.3) multiplies with compact mode in `PulseApp`’s `MediaQuery` builder.
- **Reduced motion:** `SettingsController.animationsEnabled` sets `MediaQuery.disableAnimations`. Page transitions (`AppShell` `AnimatedSwitcher`), command palette fade/scale, `PulseSection` expand, and sidebar selection honor that flag (duration → `Duration.zero`). Prefer `MediaQuery.disableAnimationsOf(context)` over ad-hoc checks.
- **Motion speed:** when animations are on, shell page transitions use `PulseTokens.scaleMotion(PulseTokens.motionPage, settings.animationSpeed)`.
- **Performance:** `PulseSection` takes a `WidgetBuilder` and builds body content only while expanded.

## Related

- Theme implementation: `apps/pulse_app/lib/app/theme/pulse_theme.dart`
- App wiring: `apps/pulse_app/lib/app/pulse_app.dart`
- Prefs: `apps/pulse_app/lib/application/settings_controller.dart`
- Flutter architecture: [03-flutter-architecture.md](03-flutter-architecture.md)
