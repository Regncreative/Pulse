# Changelog

All notable changes to Pulse are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-08-03

### Added

- First **stable** public release of Pulse for Windows 10/11
- Timeline with human-readable Event Log events, live monitoring, search, filters, and date presets
- System Health (CPU, memory, GPU, disk, network) with live charts
- Inventory (system, devices, software) via read-only Windows APIs
- Reports export (JSON, CSV, HTML, PDF)
- Diagnostics for PulseService, IPC, collectors, and PulseMCP
- Settings including optional **AI Integration** (PulseMCP) for Cursor and Claude Desktop
- Inno Setup installer that registers and starts PulseService

### Changed

- Product version stamped **1.0.0** (no beta channel label in UI or binaries)
- PulseMCP aligned to **1.0.0** with the product line
- Documentation and packaging updated from beta wording to stable release

### Security

- Observation-only: no injection, hooks, or OS modification
- Local-first: no telemetry, cloud, or accounts
- Elevation only for explicit service install / repair actions

### Upgrade notes

- Install over a previous beta using `Pulse-Setup-1.0.0-windows-x64.exe`
- Re-register AI clients after upgrade: **Settings → AI Integration → Unregister → Register**
- See [docs/releases/v1.0.0.md](docs/releases/v1.0.0.md) and [docs/guides/upgrade-notes.md](docs/guides/upgrade-notes.md)

## Prior pre-releases

Beta trains (`0.1.x-beta` … `0.3.2-beta`) are documented under [docs/releases/](docs/releases/).
