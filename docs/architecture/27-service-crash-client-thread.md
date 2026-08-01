# Service crash: joinable `std::thread` in ClientConnection

**Status:** Fixed (2026-08)  
**Symptom:** `PulseService.exe` under SCM exits with `0xc0000409` / `ucrtbase.dll`  
**Subcode:** `0x7` (`FAST_FAIL_FATAL_APP_EXIT`) — not a literal stack smash

---

## Call stack (dump + PDB)

```
ucrtbase!abort
ucrtbase!terminate
std::thread::{dtor}                                          // joinable → terminate
IpcServer::AcceptLoop::<lambda_1>::operator()                // shared_ptr deleter
_Ref_count_resource<ClientConnection*, lambda_1>::_Destroy
std::shared_ptr<ClientConnection>::{dtor}
std::thread::_Invoke<AcceptLoop::<lambda_2>>                 // client reader
ucrtbase!thread_start
kernel32!BaseThreadInitThunk
ntdll!RtlUserThreadStart
```

**Offending function:** `std::thread::~thread` while `reader` is still **joinable**, invoked from the custom `shared_ptr` deleter of `ClientConnection` as the **reader thread itself** drops the last reference.

---

## Reproduction

1. Install/start `PulseService` as **LocalService** (SCM).
2. Connect any IPC client (`process_trace`, Flutter health, `net_dump`).
3. Enable health monitoring (optional — any connect/disconnect cycle triggers).
4. Disconnect the client (tool exit, Flutter lost connection, `StopHealthMonitoring` + close).
5. Service process exits; Application log shows `0xc0000409`.

Console `--console` can survive longer depending on timing, but the same destructor path is reachable.

---

## Root cause

```cpp
auto conn = shared_ptr<ClientConnection>(new ClientConnection(), deleter);
conn->reader = std::thread([this, conn] { ClientReader(conn); });
```

`ClientReader` captures `conn` by value. On disconnect it removes itself from `clients_` and returns. The lambda then destroys the last `shared_ptr` → deleter → `delete ClientConnection` → `~std::thread` on still-joinable `reader` → **`std::terminate()`** → `abort` → `0xc0000409`.

This matches Raymond Chen’s note: `STATUS_STACK_BUFFER_OVERRUN` often means **fatal app exit**, not buffer overrun.

---

## Fix

In the `ClientConnection` custom deleter:

- If `reader.joinable()` and `reader.get_id() == this_thread::get_id()` → **`detach()`** (self-destruction path).
- Else → signal wake / cancel I/O and **`join()`** (Stop / foreign-thread path).

Then close `wake_event` and `delete`.

Regression: `service/pulse_service/test/ipc_client_thread_lifetime_test.cpp`.

---

## Related

- Source: `service/pulse_service/src/ipc/ipc_server.cpp` (`AcceptLoop`, `ClientReader`, `Stop`)
- Unrelated but removed in the same pass: unreliable ESTATS per-process net (see [24-health-metrics-task-manager.md](24-health-metrics-task-manager.md))
