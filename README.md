<p align="center">
  <img src="apps/pulse_app/assets/branding/app_icon_128.png" alt="Pulse logo" width="96" height="96" />
</p>

<h1 align="center">Pulse</h1>

<p align="center">
  <strong>See what Windows is really doing.</strong><br />
  A modern, read-only diagnostics platform for Windows — events you can understand, not logs you decode.
</p>

<p align="center">
  <a href="https://github.com/Regncreative/Pulse">github.com/Regncreative/Pulse</a>
</p>

<p align="center">
  <img alt="Windows" src="https://img.shields.io/badge/platform-Windows%2010%2F11-0078D4?style=flat-square&logo=windows&logoColor=white" />
  <img alt="Status" src="https://img.shields.io/badge/status-private%20pre--release-important?style=flat-square" />
  <img alt="Version" src="https://img.shields.io/badge/version-0.1.0--beta-orange?style=flat-square" />
  <img alt="Flutter" src="https://img.shields.io/badge/UI-Flutter-02569B?style=flat-square&logo=flutter&logoColor=white" />
  <img alt="C++" src="https://img.shields.io/badge/service-C%2B%2B%2020-00599C?style=flat-square&logo=cplusplus&logoColor=white" />
  <img alt="License" src="https://img.shields.io/badge/license-MIT-22C55E?style=flat-square" />
  <img alt="Privacy" src="https://img.shields.io/badge/privacy-local--first-0EA5E9?style=flat-square" />
</p>

---

## Development status

| Item | Status |
| --- | --- |
| Repository visibility | **Private** (prepared for a future public release — not published yet) |
| Current milestone | **v0.1.0 beta** (`0.1.0-beta` / tag `v0.1.0-beta`) |
| Public release | [#1 v0.1.0 Release Checklist](https://github.com/Regncreative/Pulse/issues/1) |
| Near-term roadmap | [#2 Roadmap: v1.1](https://github.com/Regncreative/Pulse/issues/2) · [#3 Roadmap: v1.2](https://github.com/Regncreative/Pulse/issues/3) |

Pulse is under active development. APIs, packaging, and UI may change before the first public release.

> **Philosophy:** Observation only. No injection. No hooks. No patches. No telemetry. No cloud.

---

## Features

### Timeline
- Human-readable events (plain language first; technical detail and raw XML on demand)
- Historical snapshot on connect (default **100** events), then live updates
- Live monitoring via Windows Event Log (`EvtSubscribe`) over named-pipe IPC
- Search, severity/source filters, JSON export
- Detail panel with metadata and expandable raw payload

### Live Monitoring
- Explicit start after the initial snapshot (deterministic startup order)
- Pauses when the Timeline page is not visible (idle-friendly)
- Restart / preference controls in Settings and Diagnostics

### System Health
- CPU, memory, GPU, disk, and network cards (Task Manager–aligned where APIs allow)
- Process tops (CPU / memory / disk) with graceful offline empty states

### Diagnostics
- Service / IPC / pipeline snapshot
- Inject diagnostics test event (end-to-end path check)
- Export local diagnostics zip (no cloud)

### Settings
- Live monitoring, auto-scroll, compact density, animations
- Preferences stored locally only (`SharedPreferences`)

### Installer
- Inno Setup UAC installer (`Pulse-Setup-*-windows-x64.exe`)
- Registers and starts `PulseService` automatically — no PowerShell for end users
- Bundles Visual C++ runtime when needed

### Product principles
- **Read-only** — never modifies OS behavior
- **Local-first** — everything stays on this PC
- **No telemetry / analytics / ads**
- **Native Windows feel** — Fluent, dark-first, Mica/acrylic

---

## Architecture overview

```
┌──────────────────────────────────────────────────────────┐
│                         Windows                          │
│   Event Log · PDH · DXGI · IP Helper · Process APIs      │
└────────────────────────────┬─────────────────────────────┘
                             │ read-only APIs
┌────────────────────────────▼─────────────────────────────┐
│                      PulseService                        │
│  Collector · Humanizer · Health metrics · IPC server     │
│              (native C++ Windows service)                │
└────────────────────────────┬─────────────────────────────┘
                             │ named pipe (framed binary)
┌────────────────────────────▼─────────────────────────────┐
│                       Pulse App                          │
│         Flutter Desktop · Timeline · Health · Settings   │
└──────────────────────────────────────────────────────────┘
```

**v1 pipeline (shipping direction)**

```
Windows Event Log → Collector → Humanizer → IPC → Timeline UI
```

ETW, WMI, and plugins are intentional later milestones. Full design: [docs/architecture](docs/architecture/README.md) · product rules: [AGENTS.md](AGENTS.md).

---

## Screenshots

> **Placeholders for public launch assets.** Replace or refresh files under `docs/readme/` before the public release.
> Also track polished marketing captures in the *v0.1.0 Release Checklist* (Website / Product Hunt / Demo Video).

| Surface | Placeholder path |
| --- | --- |
| Timeline | `docs/readme/timeline.png` |
| System Health | `docs/readme/system-health.png` |
| Diagnostics | `docs/readme/diagnostics.png` |
| Settings | `docs/readme/settings.png` |
| Website hero | *TBD — add under `docs/readme/website/`* |
| Product Hunt gallery | *TBD — add under `docs/readme/product-hunt/`* |

<p align="center">
  <img src="docs/readme/timeline.png" alt="Pulse Timeline (placeholder)" width="48%" />
  &nbsp;
  <img src="docs/readme/system-health.png" alt="System Health (placeholder)" width="48%" />
</p>

<p align="center">
  <img src="docs/readme/diagnostics.png" alt="Diagnostics (placeholder)" width="48%" />
  &nbsp;
  <img src="docs/readme/settings.png" alt="Settings (placeholder)" width="48%" />
</p>

---

## Installation (beta)

1. Build or obtain **`Pulse-Setup-0.1.0-beta-windows-x64.exe`**
2. Run the installer and accept UAC
3. PulseService is installed and started automatically
4. Pulse launches; complete or skip the welcome screen

Developer packaging:

```powershell
.\tools\scripts\package_beta.ps1
```

Output: `dist\Pulse-Setup-0.1.0-beta-windows-x64.exe` (plus payload folder/zip).

---

## Build instructions

### Prerequisites

- Windows 10 1809+ / Windows 11
- Visual Studio 2022+ or Build Tools (MSVC, CMake, Windows SDK)
- Flutter stable on `PATH`
- Git · Inno Setup 6 (for the installer)

### Day-to-day development

```powershell
# Terminal A — service (console)
.\tools\scripts\run_service_console.ps1

# Terminal B — Flutter UI
.\tools\scripts\run_app.ps1
```

### Service (CMake)

```powershell
cmake -S service/pulse_service -B build/service -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build/service
.\build\service\PulseService.exe --console
```

### App (Flutter)

```powershell
cd apps\pulse_app
flutter pub get
flutter run -d windows
```

### Tests

```powershell
.\build\service\pulse_wire_tests.exe
cd apps\pulse_app
flutter test
```

Full detail: [BUILD.md](BUILD.md) · [DEVELOPMENT.md](DEVELOPMENT.md).

---

## Roadmap

Tracked as GitHub issues (see repository Issues after push):

| Milestone | Focus |
| --- | --- |
| **[v0.1.0](https://github.com/Regncreative/Pulse/issues/1)** | First public release checklist — installer, Timeline, live, health, diagnostics, docs, website, demo, Product Hunt, QA |
| **[v1.1](https://github.com/Regncreative/Pulse/issues/2)** | Application / Security logs, Timeline/search/filter/export improvements |
| **[v1.2](https://github.com/Regncreative/Pulse/issues/3)** | ETW, WMI, Process/Service monitors, performance history, incident analysis |

High-level backlog:

- [x] Named-pipe IPC + framed wire protocol
- [x] Event Log → humanized Timeline + live subscribe
- [x] System Health metrics
- [x] Diagnostics + local export
- [x] Inno Setup installer (UAC, auto service)
- [ ] Code-signed installer + GitHub Releases
- [ ] Public website + demo video + Product Hunt kit
- [ ] Application / Security Event Log channels
- [ ] ETW engine
- [ ] Plugin system / timeline replay

Every feature should answer: **"What is Windows doing right now?"**

---

## Project structure

```
Pulse/
├── apps/pulse_app/          Flutter Desktop UI
├── service/pulse_service/   Native Windows service
├── shared/                  Common constants + wire protocol (C++ / Dart)
├── tools/                   Installer, packaging, IPC smoke clients
├── docs/architecture/       ADRs + system design
├── .github/                 Issue / PR templates, CI, support
├── AGENTS.md                Product constitution
├── BUILD.md                 Build & install
├── CONTRIBUTING.md          Contribution guide
├── SECURITY.md              Vulnerability reporting
└── LICENSE                  MIT (confirm before public release)
```

---

## Privacy & security

- No cloud, login, account, telemetry, analytics, or ads
- Data stays on the machine unless you export a diagnostics zip
- Official Windows APIs only — no injection, hooks, or security bypass
- Elevation only for explicit service install / uninstall

See [SECURITY.md](SECURITY.md).

---

## Contributing

The repository is private today; collaboration is by invitation until a public release.

1. Read [AGENTS.md](AGENTS.md) and [docs/architecture](docs/architecture/README.md)
2. Use Bug Report / Feature Request issue templates
3. Open PRs against `master` with the PR template checklist
4. Observation-only — no cleaner / optimizer / antivirus features

Details: [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Documentation

| Doc | Purpose |
| --- | --- |
| [AGENTS.md](AGENTS.md) | Vision, principles, AI / development rules |
| [docs/architecture/README.md](docs/architecture/README.md) | Architecture + ADRs |
| [BUILD.md](BUILD.md) | Prerequisites & build |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Local workflow |
| [SECURITY.md](SECURITY.md) | Security policy |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute |

---

## License

MIT — see [LICENSE](LICENSE).

> **Placeholder:** Confirm copyright holder name and year before making this repository public. Do not publish until the *v0.1.0 Release Checklist* is complete.
