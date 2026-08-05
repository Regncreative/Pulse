# 41 — Store packaged PulseService migration

**Status:** Implemented (Store packaging path). Partner Center `packagedServices` approval still required before Store resubmission.

**Non-goals:** Changing GitHub Setup.exe / Inno classic SCM (`--install-start`).

---

## Summary

The Microsoft Store edition ships `service\PulseService.exe` inside the MSIX and registers it with Windows via `desktop6:Service` (`StartAccount="localService"`). The Flutter UI detects package identity with `GetCurrentPackageFullName` and never runs Repair / Install or `--install-start` on that path. The GitHub installer remains the classic `CreateService` / `--install-start` distribution.

---

## Architectural changes

| Area | Before (Store 1.0.0) | After |
|------|----------------------|-------|
| MSIX contents | Flutter UI only | UI + `service\PulseService.exe` (+ CRT) |
| Service registration | None (docs pointed at Setup.exe) | `desktop6:Service` Name=`PulseService` |
| Capability | `runFullTrust`, `internetClient` | + `packagedServices` |
| OS MinVersion (Store) | 10.0.17763.0 | **10.0.19041.0** (packaged services) |
| Flutter Repair / Install | Same UAC `--install-start` as classic | Hidden / refused when packaged |
| PulseService `--install*` | Always CreateService | Refuses with exit 3 under package identity |
| Detection | N/A | `GetCurrentPackageFullName` |
| IPC / ProgramData | Unchanged | Unchanged |

---

## Files touched

| Path | Role |
|------|------|
| `apps/pulse_app/lib/platform/pulse_deployment.dart` | Package identity |
| `apps/pulse_app/lib/platform/pulse_service_launcher.dart` | Block install/uninstall when packaged |
| `apps/pulse_app/lib/application/service_lifecycle_controller.dart` | Store lifecycle |
| `apps/pulse_app/lib/presentation/components/service_lifecycle_controls.dart` | Hide Repair when `canRepair` false |
| `apps/pulse_app/lib/presentation/utils/pulse_user_errors.dart` | Store-oriented copy |
| `apps/pulse_app/pubspec.yaml` | `packagedServices`, MinVersion |
| `service/pulse_service/src/service_core/service_core.cpp` | Refuse `--install` / `--uninstall` when packaged |
| `tools/scripts/package_msix_store.ps1` | Build/embed/patch/validate |
| `tools/scripts/validate_msix_store.ps1` | Unpack assertions |
| `docs/guides/microsoft-store.md` | Store architecture + justification |
| `.github/workflows/ci.yml` | Store MSIX validation job |

**Unchanged:** `tools/installer/Pulse.iss`, `tools/scripts/package_beta.ps1`, classic SCM image path under Program Files.

---

## Compatibility matrix

| Scenario | Expected behavior |
|----------|-------------------|
| GitHub install → Store install | Avoid dual registration on the same machine when possible. Both use SCM name `PulseService`. Prefer uninstalling the classic service before Store install, or accept that Windows may reject a conflicting service create. Document for users. |
| Store install → GitHub install | Setup runs `--install-start` and may `ChangeServiceConfig` ImagePath to Program Files. Prefer uninstalling the Store app first for a clean classic install. |
| Store update | Package update replaces `service\PulseService.exe`; Windows updates the packaged service registration with the package. `%ProgramData%\Pulse\` persists. |
| Existing ProgramData | Shared. Config/logs remain under `%ProgramData%\Pulse\`. ACLs must allow LocalService (same as classic). |
| IPC protocol | Unchanged (`\\.\pipe\PulseService`, PULS framing, protobuf). |
| Security Event Log | Still often denied under LocalService — unchanged product honesty. |

---

## Partner Center remaining requirements

1. Request / receive approval for restricted capability **`packagedServices`**.
2. Do **not** request `localSystemServices`.
3. Upload new `.msixupload` only after approval.
4. Certification testers must install with service registration enabled (admin Store install).

Justification text: see [microsoft-store.md](../guides/microsoft-store.md).

---

## Verification checklist (local)

```powershell
.\tools\scripts\package_msix_store.ps1
# Inspect:
#   dist/msix/_extract/ or C:\dev\Pulse-build\dist\msix\_extract\
#   service\PulseService.exe present
#   AppxManifest desktop6:Service StartAccount=localService
```

Sideload install of an unsigned Store package may still be blocked until capability approval / Store signing; validation of **package contents** does not require a live Store install.
