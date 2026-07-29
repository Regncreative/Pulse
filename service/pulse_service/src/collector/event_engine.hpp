#pragma once

// Placeholder Event Engine surface for TASK-001.
namespace pulse {

class EventEnginePlaceholder {
 public:
  void Start() {}
  void Stop() {}
  const char* Name() const { return "EventEnginePlaceholder"; }
};

}  // namespace pulse
