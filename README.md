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
  <img alt="CI" src="https://img.shields.io/github/actions/workflow/status/Regncreative/Pulse/ci.yml?branch=master&style=flat-square&label=CI" />
  <img alt="Release" src="https://img.shields.io/badge/release-v0.3.0--beta-orange?style=flat-square" />
  <img alt="Flutter" src="https://img.shields.io/badge/UI-Flutter-02569B?style=flat-square&logo=flutter&logoColor=white" />
  <img alt="C++" src="https://img.shields.io/badge/service-C%2B%2B%2020-00599C?style=flat-square&logo=cplusplus&logoColor=white" />
  <img alt="License" src="https://img.shields.io/badge/license-MIT-22C55E?style=flat-square" />
  <img alt="Privacy" src="https://img.shields.io/badge/privacy-local--first-0EA5E9?style=flat-square" />
</p>

<p align="center">
  <img src="docs/readme/timeline.png" alt="Pulse Timeline — human-readable Windows events" width="900" />
</p>

<p align="center"><em>Timeline — live Event Log events in plain language</em></p>

---

## What is Pulse?

Windows already knows everything about itself — crashes, service starts, explorer restarts, boot failures. The problem is how that knowledge is presented: Event Viewer IDs, opaque XML, and tools that feel like they were built for another decade.

**Pulse observes. Pulse explains. Pulse visualizes. Pulse never changes Windows.**

It turns raw system activity into a readable timeline:

| Instead of… | Pulse shows… |
|---|---|
| Application Error · Event ID 1000 | Explorer unexpectedly closed. Windows restarted Explorer. |
| Service Control Manager · 7036 | Windows Update service entered the running state. |
| Kernel-Power · 41 | The system restarted without a clean shutdown. |

Designed to feel like a built-in Windows 11 utility (Fluent Design, Mica, dark-first) — not a typical diagnostics utility.

> **Philosophy:** Observation only. No injection. No hooks. No patches. No telemetry. No cloud.

---

## Features

### Timeline
- **Human-readable events** — Level 1 plain language first; technical summary and raw XML on demand
- **Live monitoring** — Windows Event Log via `EvtSubscribe`, pushed over named-pipe IPC
- **Historical snapshot** — recent events on connect, then live prepend as Windows works
- **Detail panel** — metadata, process context, and expandable raw event payload
- **Auto-scroll & filters** — stay on the live edge or browse calmly

### System Health
- **CPU, Memory, GPU, Disk, Network** — live cards aligned with Task Manager methodology where APIs allow
- **PDH Processor Utility** — frequency-aware CPU % (not just classic Processor Time)
- **Process list** — memory, CPU, disk I/O, and network per process with app icons
- **Graceful offline mode** — clear empty states when PulseService is not running

### Diagnostics
- **Service snapshot** — uptime, queue depth, IPC stats, pipeline health
- **Inject test event** — verify the full collector → IPC → Timeline path
- **Export report** — zip diagnostics for support without leaving the machine

### Settings
- Live monitoring, auto-scroll, compact density, animations
- Preferences persist locally (`SharedPreferences`) — no account, no sync

### Product principles
- **Read-only** — never modifies OS behavior
- **Local-first** — everything stays on this PC
- **No telemetry / analytics / ads**
- **Fast & light** — idle near-zero CPU, responsive scrolling
- **Native Windows feel** — custom title bar, acrylic/mica, DPI-aware

---

## Screenshots

<p align="center">
  <img src="docs/readme/timeline.png" alt="Timeline" width="48%" />
  &nbsp;
  <img src="docs/readme/system-health.png" alt="System Health" width="48%" />
</p>

<p align="center">
  <strong>Timeline</strong> — live humanized events &nbsp;·&nbsp;
  <strong>System Health</strong> — CPU, memory, GPU, disk, network
</p>

<p align="center">
  <img src="docs/readme/diagnostics.png" alt="Diagnostics" width="48%" />
  &nbsp;
  <img src="docs/readme/settings.png" alt="Settings" width="48%" />
</p>

<p align="center">
  <strong>Diagnostics</strong> — service, IPC, pipeline &nbsp;·&nbsp;
  <strong>Settings</strong> — local preferences, no cloud
</p>

---

## Architecture

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
│         Flutter Desktop · Timeline · Health UI           │
└──────────────────────────────────────────────────────────┘
```

**v1 pipeline**

```
Windows Event Log → Collector → Humanizer → IPC → Timeline UI
```

ETW, WMI, and plugins are intentional future milestones — see [docs/architecture](docs/architecture/README.md).

---

## Installation

### For everyone (beta package)

1. Download **`Pulse-Setup-0.3.0-beta-windows-x64.exe`** from [GitHub Releases](https://github.com/Regncreative/Pulse/releases)
2. Run the installer and accept the UAC prompt
3. PulseService is registered and started automatically
4. Skip or complete the short welcome — then open Timeline or System Health

Tip: for troubleshooting without the SCM service, run `service\PulseService.exe --console` from a payload folder.

Developers can also build a local package:

```powershell
.\tools\scripts\package_beta.ps1
```

Output: `dist\Pulse-Setup-0.3.0-beta-windows-x64.exe`, `dist\Pulse\`, and `dist\Pulse-0.3.0-beta-windows-x64.zip`

### For developers (day-to-day)

```powershell
# 1) Build & run the service (console mode — preferred while developing)
.\tools\scripts\run_service_console.ps1

# 2) In another terminal — run the Flutter app
.\tools\scripts\run_app.ps1
```

Or step by step:

```powershell
# Service
cmake -S service/pulse_service -B build/service -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build/service
.\build\service\PulseService.exe --console

# App
cd apps\pulse_app
flutter pub get
flutter run -d windows
```

Optional SCM install (elevated):

```powershell
.\build\service\PulseService.exe --install
Start-Service PulseService
```

Full prerequisites and flags: [BUILD.md](BUILD.md) · [DEVELOPMENT.md](DEVELOPMENT.md)

---

## AI Integration (MCP)

Pulse ships **PulseMCP** — a read-only Model Context Protocol server for Cursor, Claude Desktop, and future clients.

- Enable in **Settings → AI Integration** (opt-in policy file)
- One-click **Register** for Cursor (global `~\.cursor\mcp.json`) with backup + safe merge
- Diagnostics → **MCP** for live status metrics
- Guides: [AI Integration](docs/guides/ai-integration.md) · [Installation](docs/guides/installation.md) · [Troubleshooting](docs/guides/troubleshooting.md) · [Security](docs/guides/security.md)

---

## Development

| Command | Description |
|---|---|
| `.\tools\scripts\run_service_console.ps1` | Build (if needed) + run PulseService in console |
| `.\tools\scripts\run_app.ps1` | `flutter run -d windows` |
| `cmake --build build/service` | Rebuild native service |
| `.\build\service\pulse_wire_tests.exe` | Wire codec unit tests |
| `.\tools\scripts\run_ipc_ping.ps1` | IPC Ping/Pong smoke |
| `.\tools\scripts\run_diagnostics_ping.ps1` | Diagnostics + inject-event smoke |
| `.\tools\scripts\package_beta.ps1` | Build portable beta zip (Flutter Release + PulseService) |
| `cd apps\pulse_app; flutter test` | Flutter unit / widget tests |

---

## Tech stack

| Layer | Stack |
|---|---|
| **UI** | Flutter Desktop · Provider · window_manager · flutter_acrylic · Lucide icons |
| **Service** | C++20 · CMake · Win32 · Wevtapi · PDH · DXGI · IP Helper |
| **IPC** | Named pipes · framed binary protocol (`pulse_wire`) · shared Dart/C++ codec |
| **Protocol** | `shared/pulse_protocol` (C++ + Dart) · Protobuf schema for future evolution |
| **Persistence (app)** | SharedPreferences for settings · local diagnostics export (zip) |
| **CI** | GitHub Actions — Windows service build/tests + Flutter analyze/test |

---

## Project structure

```
Pulse/
├── apps/pulse_app/          Flutter Desktop UI (Timeline, Health, Diagnostics, Settings)
├── service/pulse_service/   Native Windows service (collector, humanizer, health, IPC)
├── shared/
│   ├── pulse_common/        Version, errors, constants
│   └── pulse_protocol/      Wire codec (C++ + Dart) + proto
├── tools/
│   ├── ipc_ping/            Smoke clients (IPC / health / diagnostics)
│   └── scripts/             Dev launch helpers
├── docs/architecture/       ADRs + system design (source of truth)
├── branding/                Logo source (Telemetry Peak)
├── tests/                   Fixtures / integration (expanding)
├── AGENTS.md                Product constitution
└── BUILD.md                 Build & install instructions
```

---

## Roadmap

- [x] Named-pipe IPC + framed wire protocol
- [x] Event Log collector → humanized Timeline
- [x] Live monitoring with page-visibility pause
- [x] System Health (Task Manager–aligned metrics)
- [x] Diagnostics page + export report
- [x] Settings persistence
- [x] Fluent dark-first UI polish
- [x] Official screenshots in README
- [x] First-launch welcome (skippable)
- [x] Timeline search, severity/source filters, JSON export
- [x] Portable beta package script (`package_beta.ps1`)
- [ ] Packaged MSI/Inno installer + GitHub Releases auto-update
- [ ] Crash / WER timeline
- [ ] ETW engine (future milestone)
- [ ] Plugin system (future milestone)
- [ ] Session recording / timeline replay

Every feature should answer one question: **"What is Windows doing right now?"**

---

## Privacy & security

- **No cloud, no login, no account**
- **No telemetry, analytics, or tracking**
- Data never leaves the machine unless **you** export a diagnostics zip
- Uses **official Windows APIs** only
- Never injects into processes, never hooks, never bypasses security
- Elevation only when **you** explicitly install the service

---

## Documentation

| Doc | Purpose |
|---|---|
| [AGENTS.md](AGENTS.md) | Product vision, principles, AI / development rules |
| [docs/architecture/README.md](docs/architecture/README.md) | Full architecture package + ADRs |
| [docs/architecture/24-health-metrics-task-manager.md](docs/architecture/24-health-metrics-task-manager.md) | Health metrics vs Task Manager |
| [BUILD.md](BUILD.md) | Prerequisites & build |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Local workflow |
| [IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md) | Implementation notes |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute |

---

## Contributing

Issues and pull requests are welcome.

1. Read [AGENTS.md](AGENTS.md) and the architecture docs first
2. Fork and create a feature branch
3. Keep changes observation-only — no cleaner / optimizer / antivirus features
4. Run `pulse_wire_tests` and `flutter analyze` / `flutter test` before opening a PR
5. Architectural changes need an ADR under `docs/architecture/decisions/`

---

## License

MIT © [Regncreative](https://github.com/Regncreative)
