#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace pulse {

/// Unique process identity — PID alone is insufficient (PID recycling).
/// CreateTime is the SPI FILETIME (100 ns since 1601); 0 means unknown.
struct ProcessKey {
  uint32_t pid = 0;
  uint64_t create_time_100ns = 0;

  [[nodiscard]] bool valid() const { return pid != 0; }

  bool operator==(const ProcessKey& o) const {
    return pid == o.pid && create_time_100ns == o.create_time_100ns;
  }
};

struct ProcessKeyHash {
  size_t operator()(const ProcessKey& k) const noexcept {
    const uint64_t mixed =
        (static_cast<uint64_t>(k.pid) * 0x9E3779B97F4A7C15ULL) ^
        k.create_time_100ns;
    return static_cast<size_t>(mixed ^ (mixed >> 32));
  }
};

/// How per-process CPU % is derived from SPI samples.
enum class ProcessCpuMode {
  /// Δ(Kernel+User) / Δt / logical_processors × 100 (SI time-based / TM Details).
  TimeBased = 0,
  /// ΔCycleTime / (Σ process ΔCycle + Σ idle ΔCycle) × 100 (SI cycle-based).
  CycleBased = 1,
};

/// Separates CPU math from inventory walking.
class ProcessCpuCalculator {
 public:
  explicit ProcessCpuCalculator(
      ProcessCpuMode mode = ProcessCpuMode::TimeBased);

  [[nodiscard]] ProcessCpuMode mode() const { return mode_; }
  void set_mode(ProcessCpuMode mode) { mode_ = mode; }

  /// Time-based: cpu_100ns is Kernel+User in 100 ns units.
  [[nodiscard]] static std::optional<double> TimeBasedPercent(
      uint64_t delta_cpu_100ns, double dt_seconds, uint32_t logical_processors);

  /// Cycle-based: share of total cycles this interval (includes idle).
  [[nodiscard]] static std::optional<double> CycleBasedPercent(
      uint64_t delta_process_cycles, uint64_t total_delta_cycles);

  [[nodiscard]] static double ClampPercent(double pct);

 private:
  ProcessCpuMode mode_;
};

[[nodiscard]] uint64_t FileTimeToUnixMs(int64_t filetime_100ns);
[[nodiscard]] std::string ProcessCpuModeName(ProcessCpuMode mode);

/// Best-effort sum of idle-thread cycle deltas since previous sample.
class IdleCycleTracker {
 public:
  [[nodiscard]] std::optional<uint64_t> SampleDelta();

 private:
  std::vector<uint64_t> prev_;
  bool have_baseline_ = false;
};

}  // namespace pulse
