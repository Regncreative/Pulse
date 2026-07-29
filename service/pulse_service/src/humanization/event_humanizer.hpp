#pragma once

#include "models/event_record.hpp"

#include <string>

namespace pulse {

/// Human-facing interpretation of an EventRecord (TASK-003 Phase 1).
/// Produced only by the service Humanization Engine — never in Flutter.
struct HumanizedEvent {
  std::string title;
  std::string summary;
  std::string recommendation;
  std::string category;
  EventLevel severity = EventLevel::Unknown;
};

/// Rule-based Event Log humanizer. Independent of IPC and Win32 APIs.
class EventHumanizer {
 public:
  [[nodiscard]] HumanizedEvent Humanize(const EventRecord& record) const;
};

}  // namespace pulse
