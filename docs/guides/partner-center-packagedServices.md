# Partner Center — packagedServices capability request

**Status:** Prepared — do not upload a new Store package until Microsoft approves `packagedServices`.

**Store ID:** `9PNDTLNTJ82T`  
**Product:** Pulse Diagnostics  
**Package identity:** `Regncreative.PulseDiagnostics`  
**Publisher:** `CN=72B69D57-C9E8-4280-AF56-B142286B0D20`  
**Package family name:** `Regncreative.PulseDiagnostics_epm7gp6hnh3h0`

**Branch (local):** `store/packaged-service` — not merged to `master` until approval.

---

## Capability requested

| Capability | Request? |
|------------|----------|
| `packagedServices` | **Yes** |
| `localSystemServices` | **No** |

Account: **Local Service** only (`desktop6:Service` `StartAccount="localService"`).

---

## Justification (paste into Partner Center)

Pulse Diagnostics is a read-only Windows observability application. Continuous collection of Windows Event Log data, system health metrics, and hardware/inventory diagnostics runs in a background Win32 service (`PulseService`) under the Local Service account so observation continues independently of the Flutter UI process lifecycle and does not require elevating the interactive user session. The service uses only officially supported Windows APIs, never injects into processes, and writes operational state under ProgramData—not into the package install directory. We request the `packagedServices` restricted capability so Microsoft Store can install and register this Local Service packaged service via the AppxManifest (`desktop6:Service`, `StartAccount=localService`). We do not require `localSystemServices` or Local System. Without this capability, the Store package cannot provide the core diagnostics experience and fails certification as an unusable feature.

---

## Manifest declaration (after approval)

```xml
<rescap:Capability Name="packagedServices" />

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

OS minimum for this Store package: **Windows 10 version 2004** (`10.0.19041.0`).

---

## Submission checklist

1. [ ] Submit `packagedServices` restricted capability request with the justification above.
2. [ ] Wait for Microsoft approval (do not merge `store/packaged-service` to `master` before this).
3. [ ] On approval: rebuild with `.\tools\scripts\package_msix_store.ps1`.
4. [ ] Confirm `validate_msix_store.ps1` PASS on the unpacked package.
5. [ ] Upload `dist/msix/PulseDiagnostics-*-Store.msixupload` to Partner Center Packages.
6. [ ] Merge `store/packaged-service` → `master` and tag only after Store package is accepted.

Until then:

- GitHub / Inno Setup on `master` remains the shipping channel.
- Do not tag a Store-related release from this branch.
- Do not push/merge this branch to `main`/`master` without explicit approval follow-up.

---

## Related docs

- [microsoft-store.md](../guides/microsoft-store.md)
- [41-store-packaged-service.md](../architecture/41-store-packaged-service.md)
