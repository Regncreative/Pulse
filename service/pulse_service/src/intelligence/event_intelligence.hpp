#pragma once

#include "pulse_wire.hpp"

#include <string>

namespace pulse {

enum class Importance : std::int32_t {
  Low = 0,
  Medium = 1,
  High = 2,
  Critical = 3,
};

enum class InsightCategory : std::int32_t {
  General = 0,
  Service = 1,
  Network = 2,
  Com = 3,
  Boot = 4,
  Time = 5,
  Http = 6,
  Crash = 7,
  Power = 8,
  Update = 9,
  Device = 10,
  Driver = 11,
  Security = 12,
  Storage = 13,
};

/// User-facing interpretation of a timeline event (TASK-005).
struct EventInsight {
  std::string title;
  std::string summary;
  /// Empty when not useful — never "No recommendation available."
  std::string recommendation;
  bool action_required = false;
  Importance importance = Importance::Low;
  InsightCategory category = InsightCategory::General;
};

/// Rule-based Event Intelligence Engine.
/// Operates on IPC TimelineEvent fields (provider, win_event_id, message, severity).
/// Independent of Win32 APIs and Flutter.
class EventIntelligence {
 public:
  [[nodiscard]] EventInsight Analyze(const ipc::TimelineEvent& event) const;
};

[[nodiscard]] const char* ImportanceName(Importance value);
[[nodiscard]] const char* InsightCategoryName(InsightCategory value);

}  // namespace pulse
