#pragma once

#include <cstdint>
#include <optional>
#include <string>

namespace pulse {

/// Severity levels from Windows Event Log system properties (EvtSystemLevel).
enum class EventLevel : std::uint8_t {
  LogAlways = 0,
  Critical = 1,
  Error = 2,
  Warning = 3,
  Information = 4,
  Verbose = 5,
  Unknown = 255,
};

/// Strongly typed Event Log record for Pulse (read-only observation).
/// Missing fields are represented with empty / nullopt — never invent values.
struct EventRecord {
  /// UTC file-time converted to ISO-8601 when available.
  std::optional<std::string> timestamp_utc;

  /// UTC epoch milliseconds when available (0 / nullopt if unknown).
  std::optional<std::int64_t> timestamp_unix_ms;

  std::string provider_name;
  std::optional<std::uint16_t> event_id;
  EventLevel level = EventLevel::Unknown;
  std::string channel;
  std::string computer_name;

  /// Formatted message when EvtFormatMessage succeeds; empty otherwise.
  std::string message;

  /// Record id from the log (when available).
  std::optional<std::uint64_t> record_id;

  // R2 — additional Wevtapi system properties (nullopt / empty when absent).
  std::optional<std::uint16_t> task;
  std::optional<std::uint8_t> opcode;
  std::optional<std::uint64_t> keywords;
  std::optional<std::uint32_t> process_id;
  std::string process_name;
  std::optional<std::uint32_t> thread_id;
  std::string user_sid;
  std::string activity_id;
  std::string related_activity_id;

  /// Raw Event XML from EvtRender(EvtRenderEventXml). Empty unless requested.
  std::string raw_xml;
};

inline const char* EventLevelName(EventLevel level) {
  switch (level) {
    case EventLevel::LogAlways:
      return "LogAlways";
    case EventLevel::Critical:
      return "Critical";
    case EventLevel::Error:
      return "Error";
    case EventLevel::Warning:
      return "Warning";
    case EventLevel::Information:
      return "Information";
    case EventLevel::Verbose:
      return "Verbose";
    case EventLevel::Unknown:
    default:
      return "Unknown";
  }
}

}  // namespace pulse
