# Microsoft Store packaging (Pulse Diagnostics)

Store ID: **9PNDTLNTJ82T**

## Partner Center identity (authoritative)

| Field | Value |
|-------|--------|
| Package identity name | `Regncreative.PulseDiagnostics` |
| Publisher | `CN=72B69D57-C9E8-4280-AF56-B142286B0D20` |
| Publisher display name | `Regncreative` |
| Display name | `Pulse Diagnostics` |
| Package family name | `Regncreative.PulseDiagnostics_epm7gp6hnh3h0` |

Configured in [`apps/pulse_app/pubspec.yaml`](../../apps/pulse_app/pubspec.yaml) under `msix_config`.

## Architecture (Store vs GitHub)

| Channel | How PulseService is registered | UI Repair / Install |
|---------|--------------------------------|---------------------|
| **GitHub Setup.exe** (Inno) | Classic SCM: `PulseService.exe --install-start` | Shown |
| **Microsoft Store MSIX** | Package declaration: `desktop6:Service` + `packagedServices` | Hidden |

Both editions:

- Run PulseService as **Local Service** (`StartAccount="localService"` / `NT AUTHORITY\LocalService`)
- Use named pipe `\\.\pipe\PulseService`
- Write config/logs under `%ProgramData%\Pulse\` (never into the MSIX install directory)
- Share the same IPC protocol and diagnostics engine

Store detection uses Win32 **`GetCurrentPackageFullName`** (not install paths).

### AppxManifest service fragment

```xml
<desktop6:Extension
    Category="windows.service"
    Executable="service\PulseService.exe"
    EntryPoint="Windows.FullTrustApplication">
  <desktop6:Service
      Name="PulseService"
      StartupType="auto"
      StartAccount="localService" />
</desktop6:Extension>
```

Restricted capability: **`packagedServices` only** (not `localSystemServices`).

OS minimum for the Store package: **Windows 10 version 2004** (`10.0.19041.0`) — required for packaged services.

## Build Store package

Prerequisites: Flutter stable, VS C++ Build Tools, Windows 10 SDK (`MakeAppx` recommended).

```powershell
.\tools\scripts\package_msix_store.ps1
```

The script **fails loudly** if `PulseService.exe` cannot be built/embedded. After packing it unpacks the MSIX and runs [`validate_msix_store.ps1`](../../tools/scripts/validate_msix_store.ps1), which requires:

- `Pulse.exe`
- `service\PulseService.exe`
- `desktop6:Service` with `StartAccount="localService"`
- `packagedServices` capability
- Declared executable path present on disk

Outputs (`dist/msix/`):

| File | Role |
|------|------|
| `PulseDiagnostics-1.1.0-Store.msix` | Store-oriented MSIX (unsigned — Store re-signs) |
| `PulseDiagnostics-1.1.0-Store.msixupload` | Partner Center upload package |
| `AppxManifest.identity.txt` | Identity + service verification dump |
| `store-validation-report.txt` | Validation report |
| `AppxManifest.xml` | Extracted manifest copy |

## Rules

- `store: true` — **no** development / sideload certificates
- Do **not** install test certificates for Store builds
- Upload the **`.msixupload`** on the Partner Center Packages page **only after** `packagedServices` is approved
- Do not change GitHub Inno / `package_beta.ps1` for Store work

## Partner Center — `packagedServices` justification

**Full engineering whitepaper (preferred attachment for Microsoft):**  
[docs/store/packagedServices-business-justification.md](../store/packagedServices-business-justification.md)

Short paste for the capability form (summary only — attach the whitepaper for detail):

> Pulse Diagnostics is a read-only Windows observability application. Continuous collection of Windows Event Log data, system health metrics, and hardware/inventory diagnostics runs in a background Win32 service (`PulseService`) under the Local Service account so observation continues independently of the Flutter UI process lifecycle and does not require elevating the interactive user session. The service uses only officially supported Windows APIs, never injects into processes, and writes operational state under ProgramData—not into the package install directory. We request the `packagedServices` restricted capability so Microsoft Store can install and register this Local Service packaged service via the AppxManifest (`desktop6:Service`, `StartAccount=localService`). We do not require `localSystemServices` or Local System. Without this capability, the Store package cannot provide the core diagnostics experience and fails certification as an unusable feature.

Checklist and submission notes: [partner-center-packagedServices.md](partner-center-packagedServices.md).

## Migration / coexistence notes

See [41 — Store packaged service migration](../architecture/41-store-packaged-service.md).
