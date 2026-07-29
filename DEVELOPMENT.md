# DEVELOPMENT

## Daily loop (bootstrap)

1. Start service console:

```powershell
.\tools\scripts\run_service_console.ps1
```

2. In another terminal, verify IPC:

```powershell
.\tools\scripts\run_ipc_ping.ps1
```

3. Run UI:

```powershell
.\tools\scripts\run_app.ps1
```

Open **Diagnostics** and press **Ping**.

## Conventions

- Follow `docs/architecture` and ADRs
- Small commits, one concern each
- No Event Log / ETW / WMI code in TASK-001 branches
- C++20, clang-format for C++
- Dart `flutter analyze` clean

## Proto / wire codec

Canonical schema: `shared/pulse_protocol/proto/pulse.proto`  
Bootstrap codec: `shared/pulse_protocol/cpp/pulse_wire.*` and Dart `pulse_wire.dart`  
When `protoc` is available, `tools/codegen/generate_proto.ps1` documents the intended generation path.
