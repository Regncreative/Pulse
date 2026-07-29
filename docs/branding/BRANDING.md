# Pulse Brand Identity

**Product:** Pulse  
**Company:** Regn Creative  
**Document version:** 1.0  
**Date:** 2026-07-27

---

## Logo concept

**Name:** Telemetry Peak

Pulse’s mark is a precise activity spike on a calibrated baseline, with a sample node at the apex.

It communicates:

- System activity and monitoring
- Live signal / telemetry
- Diagnostic sampling
- Precision

It deliberately avoids medical hearts, ECG clichés, shields, bugs, and magnifying glasses.

The geometry is intended to feel at home next to Windows system utilities (Task Manager, Dev Home, PowerToys): flat, crisp, and recognizable at small sizes.

### Concepts considered

| Concept | Verdict |
|---|---|
| Histogram bars | Clear but generic “analytics” |
| Crosshair / scope | Too instrument-like |
| Letter “P” spike | Less distinctive at 16px |
| **Telemetry Peak** | Chosen — readable, unique, monochrome-safe |

---

## Geometry

Design grid: **32 × 32** units.

App icon tile:

- Rounded square, corner radius ≈ **22%** of edge (~7u on 32u)
- Tile fill: `#1B1F24`
- Mark stroke: `#60CDFF`
- Baseline at y = 22
- Peak apex at (14, 8)
- Sample node radius ≈ 2.1u

Mark-only (in-app chrome) uses the same polyline without the tile, for use on dark UI surfaces.

Safe area: keep **≥ 6.25%** padding inside the icon canvas (2u on 32u). Do not place competing marks in the corner radius zones.

---

## Color palette

| Role | Hex | Usage |
|---|---|---|
| Accent | `#60CDFF` | Logo mark, Windows Fluent accent |
| Tile | `#1B1F24` | App icon background |
| On-accent | `#001B26` | Text/icons on accent fills |
| Mono light | `#FFFFFF` | Dark backgrounds / taskbar mono |
| Mono dark | `#000000` | Light backgrounds |

Maximum two colors in the primary logo lockup (tile + accent). Monochrome variants are single-color.

---

## Icon sizing rules

| Size | Use |
|---|---|
| 16px | Title bar, dense lists |
| 24px | Small toolbar |
| 32px | Sidebar, Start menu small |
| 48–64px | Explorer medium |
| 128px | Installer, store tiles |
| 256px | Taskbar / jumplist high-DPI |
| 512px | Master marketing / store source |

At **16px**, favor stroke weight ≥ 2px equivalent and keep the sample node; do not add secondary ornament.

---

## Files

| Path | Purpose |
|---|---|
| `branding/logo/app_icon.svg` | Master vector (tile + mark) |
| `branding/logo/mark.svg` | Mark-only vector |
| `branding/logo/app_icon_mono.svg` | Monochrome tile |
| `branding/generated/*` | Generated PNG + ICO |
| `apps/pulse_app/assets/branding/*` | Flutter runtime assets |
| `apps/pulse_app/windows/runner/resources/app_icon.ico` | Windows executable / taskbar |

Regenerate rasters:

```bash
python tools/scripts/generate_brand_icons.py
```

---

## Usage examples

**Do**

- Use `app_icon.svg` / ICO for the Windows executable and taskbar
- Use `mark.svg` in the custom title bar and empty states
- Keep ample clear space around the mark (≈ half the mark height)
- Prefer accent on dark surfaces to match Windows 11 dark mode

**Don’t**

- Add gradients, shadows, or outlines to the logo
- Stretch or rotate the mark
- Place the mark on busy photography without a solid tile
- Recolor to arbitrary brand palettes outside the approved pair

---

## Window identity

| Field | Value |
|---|---|
| Window title | Pulse |
| Product name | Pulse |
| Company | Regn Creative |
| File description | Windows Diagnostics |
| Executable | `Pulse.exe` |
| Copyright | Copyright (C) 2026 Regn Creative. All rights reserved. |

The desktop shell uses a custom title bar blended with Pulse chrome, dark-mode DWM styling, Windows 11 rounded corners, and Mica/Acrylic when the OS supports it.
