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

## Build Store package

Prerequisites: Flutter stable, Windows 10 SDK (`MakeAppx` recommended).

```powershell
.\tools\scripts\package_msix_store.ps1
```

Outputs (`dist/msix/`):

| File | Role |
|------|------|
| `PulseDiagnostics-1.0.0-Store.msix` | Store-oriented MSIX (unsigned — Store re-signs) |
| `PulseDiagnostics-1.0.0-Store.msixupload` | Partner Center upload package |
| `AppxManifest.identity.txt` | Identity verification dump |
| `store-validation-report.txt` | Validation report |
| `AppxManifest.xml` | Extracted manifest copy |

## Rules

- `store: true` — **no** development / sideload certificates
- Do **not** install test certificates for Store builds
- Upload the **`.msixupload`** on the Partner Center Packages page

## Architecture note

The Store package ships the **Flutter desktop UI** (full-trust desktop bridge). **PulseService** continues to be installed via the GitHub Releases Setup / SCM path. Observation APIs remain in the native service; the Store client connects over the named pipe when the service is present.
