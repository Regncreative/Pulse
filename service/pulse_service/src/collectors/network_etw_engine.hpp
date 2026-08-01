#pragma once

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>

namespace pulse {

/// Cumulative per-PID byte counters from Kernel-Network ETW send/recv events.
struct NetworkPidBytes {
  uint64_t send_bytes = 0;
  uint64_t recv_bytes = 0;

  [[nodiscard]] uint64_t total() const { return send_bytes + recv_bytes; }
};

/// Pulse-owned real-time ETW session (`PulseHealthNet`) for System Health
/// per-process network attribution. Observation only — no TDH in the callback.
/// See ADR-009 and docs/architecture/20-etw-integration.md.
class NetworkEtwEngine {
 public:
  NetworkEtwEngine();
  ~NetworkEtwEngine();

  NetworkEtwEngine(const NetworkEtwEngine&) = delete;
  NetworkEtwEngine& operator=(const NetworkEtwEngine&) = delete;

  /// Start session + ProcessTrace consumer thread. Idempotent on success.
  /// On failure, leaves metrics unset (running() == false) — never invent rates.
  [[nodiscard]] bool Start();

  /// Stop session, close handles, join consumer thread.
  void Stop();

  /// Copy cumulative send/recv totals by PID (does not clear counters).
  void Snapshot(std::unordered_map<uint32_t, NetworkPidBytes>* out);

  [[nodiscard]] bool running() const { return running_.load(); }
  [[nodiscard]] std::string last_error() const;

  /// Called from the ETW EventRecordCallback (light parse only — no TDH).
  void AddBytes(uint32_t pid, uint32_t size, bool is_send);

 private:
  void TraceThreadMain();
  void SetError(const std::string& message, unsigned long win32_error = 0);
  [[nodiscard]] bool StartSessionLocked();
  void StopSessionLocked();

  mutable std::mutex mu_;
  std::unordered_map<uint32_t, NetworkPidBytes> by_pid_;
  std::string last_error_;

  std::atomic<bool> running_{false};
  std::atomic<bool> stop_requested_{false};

  // TRACEHANDLE values as uint64_t so this header stays free of Windows includes.
  uint64_t session_handle_ = UINT64_MAX;
  uint64_t consumer_handle_ = UINT64_MAX;

  std::thread consumer_thread_;
};

}  // namespace pulse
