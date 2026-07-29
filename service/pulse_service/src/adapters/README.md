# Event Log adapters / collectors

TASK-002.1 introduces a Wevtapi-based foundation collector:

- `src/collectors/event_log_collector.*` — business API (System channel snapshot)
- `src/windows/wevt_helpers.*` — RAII + Wevtapi wrappers
- `src/models/event_record.hpp` — strongly typed event model

`event_log_adapter.hpp` remains a placeholder for the future live pull
subscription path (EvtSubscribe). Do not add ETW/WMI trees here.
