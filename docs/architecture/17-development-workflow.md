# 17 — Development Workflow

## Daily Loop (v1)

1. `PulseService.exe --console`
2. Flutter app (`flutter run -d windows`)
3. Verify timeline shows Event Log Level 1 summaries

## Focus

Prove: Event Log → Collector → IPC → Timeline → human text.

Do not spend v1 cycles enabling ETW/WMI.

## Protobuf / commits

Same discipline as before: small commits; regenerate proto on schema change; I/O isolate for pipe work.

## Config

Enable System + Application channels; `logging.level: debug` while developing.

## Related Documents

- [04 — Native Service](04-native-service.md)
- [18 — Testing](18-testing.md)
