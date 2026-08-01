# 32 — UX / UI Redesign Milestone

Status: **Complete** (shipping as `0.2.0-beta`)

## Goal

Reorganize Pulse’s Flutter UI for clarity and discoverability without removing System Health, Timeline, Diagnostics, or IPC capabilities. Collector → IPC → Flutter unchanged.

## Delivered

| Phase | Outcome |
|-------|---------|
| A | `PulseThemeData` ThemeExtension; light/dark/system; accent presets; design-system widgets (`PulseSection`, metrics, skeleton, dialog) |
| B | Collapsible System Health detail sections with persisted expand state |
| C | Categorized Settings center; units/temp/clock/performance prefs; JSON export/import |
| D | Ctrl+K command palette; Reports nav; dashboard layout customize |
| E | Reports: Health/Timeline/Diagnostics/Hardware → JSON/CSV/HTML/PDF |
| F | Motion scaling, text scale, a11y Semantics/focus, lazy section bodies |
| G | Docs + `0.2.0-beta` package |

## Related

- [31 — UI design system](31-ui-design-system.md)
- [29 — System Health quality](29-system-health-quality-milestone.md)
