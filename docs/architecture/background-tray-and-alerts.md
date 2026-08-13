# Background mode, system tray, and local alerts

**Status:** Implemented (UI process). Does not change PulseService SCM / Store packaging.

**Privacy:** Local-only Windows notifications. No cloud, telemetry, or remote push.

---

## Process architecture

```
PulseService (Windows service — independent lifecycle)
    |
    | Named Pipe IPC
    v
Pulse.exe (Flutter desktop UI)
    |
    +-- Main window (may be hidden)
    +-- System tray icon + context menu
    +-- AlertStateEngine (debounce / hysteresis / cooldown)
    +-- local_notifier (Windows toast, local)
```

| Action | Pulse.exe | PulseService |
|--------|-----------|--------------|
| Window Close + Background Mode **ON** | Hide to tray; process stays alive | Unchanged |
| Window Close + Background Mode **OFF** | Exit | Unchanged |
| Tray → **Exit Pulse** | Exit | Unchanged |
| Uninstall / SCM stop | N/A from tray exit | Only via intentional service lifecycle UI / installer |

**Never** stop, uninstall, or reconfigure PulseService because the UI hid or exited.

---

## Tray lifecycle

- Icon: bundled Pulse `app_icon.ico` (tooltip: `Pulse Diagnostics`).
- Left click: restore / focus main window.
- Right click: context menu (Open, diagnostic pages, Settings, Pause Notifications, Background Mode, Exit Pulse).
- Checkboxes reflect `backgroundMode` and `notificationsPaused` from `SettingsController`.

Package: [`tray_manager`](https://pub.dev/packages/tray_manager) + `menu_base`.

---

## Window close

`window_manager.setPreventClose(true)` so close is handled in Dart:

- Policy: [`window_close_behavior.dart`](../../apps/pulse_app/lib/application/window_close_behavior.dart)
- Coordinator: [`BackgroundModeController`](../../apps/pulse_app/lib/application/background_mode_controller.dart)

No confirmation dialog on every close.

---

## Alert engine

Pure Dart FSM: [`alert_state_engine.dart`](../../apps/pulse_app/lib/application/alert_state_engine.dart).

Sources (no second collectors):

- `PulseIpcClient.healthUpdates` → CPU %, memory %, and residual critical system posture (e.g. disk ≥95% after CPU/mem dedicated kinds).
- `PulseIpcClient.liveEvents` → Event Log only when `Severity.critical` or `Importance.critical`.

Thresholds align with System Health:

| Parameter | Value |
|-----------|-------|
| Critical | ≥ **95%** (same as `deriveSystemStatus`) |
| Recovery hysteresis | **< 85%** |
| Sustain | **30 seconds** continuous critical |
| Default cooldown | **15 minutes** (Settings: 5 / 15 / 30 / 60) |

Phases: `idle` → `pending` → `active` (one notification) → `cooling` → `idle`.

`BackgroundModeController` calls `ipc.startHealthMonitoring()` when Background Mode or System Notifications is enabled so samples continue while the Health page is not open.

---

## Notifications

- Package: `local_notifier` (local Windows toast).
- Click: restore window + `ShellNavigation` deep-link to Health / Timeline / Settings as appropriate.
- Gated by Settings `systemNotifications` and tray **Pause Notifications**.
- Default: notifications **off** (opt-in).

---

## Settings (persisted via SharedPreferences)

| Key concept | Preference | Default |
|-------------|------------|---------|
| Background Mode | `background.mode` | `false` |
| Start with Windows | `background.start_with_windows` | `false` |
| System Notifications | `background.system_notifications` | `false` |
| Pause Notifications | `background.notifications_paused` | `false` |
| Cooldown minutes | `background.notification_cooldown_minutes` | `15` |

UI: Settings → **Background**.

### Start with Windows

- User-session registration via `launch_at_startup` (OS-supported Run-key style API).
- Args: `--background` → if Background Mode is on, start hidden in tray.
- Does **not** use PulseService to launch the UI.
- Does **not** modify SCM or packaged-service manifests.

---

## Security / privacy

- Observation only; no injection / hooks / OS patching.
- Notifications are local; no external notification backend.
- Exiting Pulse.exe never implies stopping PulseService.

---

## Limitations

- Cooldown duration updates apply to future cooling intervals (engine `updateCooldown`).
- Event Log alerts require live monitoring / critical classification already present on the wire event.
- Tray / toast plugins are Windows-desktop specific; unit tests cover the FSM and close policy without plugins.
- Manual verification required for tray icon, toast click-through, and “service still running after Exit Pulse”.
