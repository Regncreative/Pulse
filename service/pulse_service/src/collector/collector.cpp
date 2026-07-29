#include "collector/collector.hpp"

#include "logging/logger.hpp"

namespace pulse {

bool Collector::Start() {
  running_ = true;
  Logger::Instance().Info("Collector", "Placeholder collector started (no Event Log)");
  return true;
}

void Collector::Stop() {
  if (!running_.exchange(false)) return;
  Logger::Instance().Info("Collector", "Placeholder collector stopped");
}

std::string Collector::Status() const {
  return running_ ? "placeholder-running" : "stopped";
}

}  // namespace pulse
