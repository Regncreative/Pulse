#pragma once

#include <atomic>
#include <string>

namespace pulse {

// Placeholder collector for TASK-001. No Event Log / ingest yet.
class Collector {
 public:
  bool Start();
  void Stop();
  bool IsRunning() const { return running_; }
  std::string Status() const;

 private:
  std::atomic<bool> running_{false};
};

}  // namespace pulse
