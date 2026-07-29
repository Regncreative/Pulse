#pragma once

#include "models/event_record.hpp"

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

namespace pulse {

/// Push-based System Event Log subscription (EvtSubscribe).
/// Independent of IPC — delivers EventRecord via callback.
class EventLogSubscriber {
 public:
  using EventCallback = std::function<void(EventRecord)>;

  EventLogSubscriber();
  ~EventLogSubscriber();

  EventLogSubscriber(const EventLogSubscriber&) = delete;
  EventLogSubscriber& operator=(const EventLogSubscriber&) = delete;

  /// Start receiving future events only (does not replay history).
  [[nodiscard]] bool Start(const std::wstring& channel, EventCallback callback);

  /// Cancel subscription and join reconnect worker. Idempotent.
  void Stop();

  [[nodiscard]] bool running() const noexcept { return running_.load(); }

  [[nodiscard]] uint64_t reconnect_count() const noexcept {
    return reconnect_count_.load();
  }

  /// Invoked from Wevtapi callback thread on subscription errors.
  void RequestReconnect(unsigned long status);

  /// Parse + deliver one event (called from Wevtapi callback thread).
  void DeliverEvent(void* event_handle);

 private:
  bool StartSubscriptionLocked();
  void StopSubscriptionLocked();
  void ReconnectWorker();

  std::mutex mu_;
  std::wstring channel_;
  EventCallback callback_;
  void* subscription_ = nullptr;     // EVT_HANDLE
  void* render_context_ = nullptr;   // EVT_HANDLE
  std::shared_ptr<void> callback_state_;
  std::atomic<bool> running_{false};
  std::atomic<bool> reconnect_requested_{false};
  std::atomic<uint64_t> reconnect_count_{0};
  std::thread reconnect_thread_;
};

}  // namespace pulse
