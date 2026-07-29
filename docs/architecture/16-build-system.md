# 16 — Build System

## Toolchain

VS 2022 + Windows SDK, CMake 3.25+, Flutter 3.x, protoc, vcpkg (protobuf, sqlite3, gtest).

## Targets (v1)

| Target | Notes |
|--------|-------|
| `PulseService.exe` | Link `wevtapi`, `advapi32`; **not** `tdh` / `mi` required for v1 |
| `Pulse.exe` | Flutter Windows |
| `pulse_proto` | Generated C++/Dart |
| Unit / integration tests | Google Test + Flutter test |

## Dependencies

vcpkg: protobuf, sqlite3, gtest.

System: Wevtapi for Event Log. Defer TDH/MI until M2/M3.

## Codegen

`tools/codegen/generate_proto.ps1` — same as before.

## Installer

Manual install for v1; WiX later.

## CI

Build + unit/integration with **fixtures** (no live ETW/kernel). Event Log live tests optional/manual.

---

## Related Documents

- [15 — Folder Structure](15-folder-structure.md)
- [18 — Testing](18-testing.md)
