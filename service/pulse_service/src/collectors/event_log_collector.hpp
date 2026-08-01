#pragma once

#include "models/event_record.hpp"

#include <cstddef>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace pulse {

/// Result type for collector operations (C++20-friendly stand-in for expected).
template <typename T>
class CollectResult {
 public:
  static CollectResult Success(T value) {
    CollectResult r;
    r.ok_ = true;
    r.value_ = std::move(value);
    return r;
  }

  static CollectResult Failure(std::string error) {
    CollectResult r;
    r.ok_ = false;
    r.error_ = std::move(error);
    return r;
  }

  [[nodiscard]] bool ok() const noexcept { return ok_; }
  [[nodiscard]] explicit operator bool() const noexcept { return ok_; }

  [[nodiscard]] const T& value() const& { return value_; }
  [[nodiscard]] T& value() & { return value_; }
  [[nodiscard]] T&& value() && { return std::move(value_); }

  [[nodiscard]] const std::string& error() const noexcept { return error_; }

 private:
  bool ok_ = false;
  T value_{};
  std::string error_;
};

/// Reads recent events from a Windows Event Log channel via Wevtapi.
/// Win32 details live in windows/wevt_helpers — this class is business logic only.
class EventLogCollector {
 public:
  /// Collect up to `limit` newest events from `channel` (e.g. L"System").
  /// Events are returned newest-first.
  [[nodiscard]] CollectResult<std::vector<EventRecord>> CollectLatest(
      const std::wstring& channel,
      std::size_t limit = 100) const;

  /// Collect from multiple channels, merge by timestamp (newest first), bound to
  /// `limit`. Per-channel budget is fair-shared so one busy log cannot starve
  /// the snapshot. Inaccessible channels are skipped (logged); if every channel
  /// fails, returns Failure.
  [[nodiscard]] CollectResult<std::vector<EventRecord>> CollectLatestMulti(
      const std::vector<std::wstring>& channels,
      std::size_t limit = 100) const;

  /// Fetch one event by record id (XPath EventRecordID). Optionally render raw XML.
  /// Returns Failure when the channel cannot be queried; Success with empty
  /// optional when the record is not found.
  [[nodiscard]] CollectResult<std::optional<EventRecord>> CollectByRecordId(
      const std::wstring& channel,
      std::uint64_t record_id,
      bool include_raw_xml = true) const;

  /// Parse a single EVT_HANDLE into EventRecord (shared by snapshot + live).
  /// `system_context` must be from EvtCreateRenderContext(..., System).
  [[nodiscard]] static std::optional<EventRecord> ParseEvtHandle(
      void* event_handle,
      void* system_render_context);

  /// Prints records to stdout for TASK-002.1 console verification.
  static void PrintToConsole(const std::vector<EventRecord>& events);
};

}  // namespace pulse
