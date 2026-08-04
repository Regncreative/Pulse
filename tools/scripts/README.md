# README

PowerShell helpers to run service, app, ping, and R1 stability tooling.

| Script | Purpose |
|--------|---------|
| `run_app.ps1` | Launch Flutter app |
| `run_service_console.ps1` | Dev console service |
| `install_service.ps1` | Install/start SCM service |
| `run_ipc_ping.ps1` / `run_diagnostics_ping.ps1` | Smoke IPC |
| `package_beta.ps1` | Build installer payload |
| `package_msix_store.ps1` | Microsoft Store MSIX / `.msixupload` (Partner Center) |
| `verify_runtime_deps.ps1` | VC++ runtime checks |
| `measure_performance.ps1` | One-shot WS / optional diagnostics ping (R1) |
| `soak_overnight.ps1` | ≥8 h sampling + final JSON/MD verdict in `tools/soak-results/` |

See [35-product-stability.md](../../docs/architecture/35-product-stability.md).
