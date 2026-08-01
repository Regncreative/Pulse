#include "collectors/process_metrics.hpp"

#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>

#include <cmath>

namespace pulse {
namespace {

using NtQuerySystemInformationFn = LONG(WINAPI*)(ULONG, PVOID, ULONG, PULONG);

// PHNT / Win7+: SystemProcessorIdleCycleTimeInformation.
constexpr ULONG kSystemProcessorIdleCycleTimeInformation = 55;
constexpr LONG kStatusSuccess = 0;
constexpr LONG kStatusInfoLengthMismatch = static_cast<LONG>(0xC0000004L);

NtQuerySystemInformationFn ResolveNtQuery() {
  static auto fn = reinterpret_cast<NtQuerySystemInformationFn>(GetProcAddress(
      GetModuleHandleW(L"ntdll.dll"), "NtQuerySystemInformation"));
  return fn;
}

}  // namespace

ProcessCpuCalculator::ProcessCpuCalculator(ProcessCpuMode mode) : mode_(mode) {}

double ProcessCpuCalculator::ClampPercent(double pct) {
  if (!std::isfinite(pct) || pct < 0.0) return 0.0;
  if (pct > 100.0) return 100.0;
  return pct;
}

std::optional<double> ProcessCpuCalculator::TimeBasedPercent(
    uint64_t delta_cpu_100ns, double dt_seconds, uint32_t logical_processors) {
  if (dt_seconds <= 0.0 || logical_processors == 0) return std::nullopt;
  const double cpu_seconds =
      static_cast<double>(delta_cpu_100ns) / 10'000'000.0;
  const double pct = (cpu_seconds / dt_seconds) /
                     static_cast<double>(logical_processors) * 100.0;
  return ClampPercent(pct);
}

std::optional<double> ProcessCpuCalculator::CycleBasedPercent(
    uint64_t delta_process_cycles, uint64_t total_delta_cycles) {
  if (total_delta_cycles == 0) return std::nullopt;
  const double pct = static_cast<double>(delta_process_cycles) /
                     static_cast<double>(total_delta_cycles) * 100.0;
  return ClampPercent(pct);
}

uint64_t FileTimeToUnixMs(int64_t filetime_100ns) {
  constexpr uint64_t kEpochDiff = 116444736000000000ULL;
  if (filetime_100ns <= 0) return 0;
  const auto ticks = static_cast<uint64_t>(filetime_100ns);
  if (ticks < kEpochDiff) return 0;
  return (ticks - kEpochDiff) / 10000ULL;
}

std::string ProcessCpuModeName(ProcessCpuMode mode) {
  switch (mode) {
    case ProcessCpuMode::TimeBased:
      return "time-based";
    case ProcessCpuMode::CycleBased:
      return "cycle-based";
  }
  return "unknown";
}

std::optional<uint64_t> IdleCycleTracker::SampleDelta() {
  auto* NtQuery = ResolveNtQuery();
  if (NtQuery == nullptr) return std::nullopt;

  ULONG needed = 0;
  LONG st = NtQuery(kSystemProcessorIdleCycleTimeInformation, nullptr, 0,
                    &needed);
  if (st != kStatusInfoLengthMismatch && st != kStatusSuccess) {
    return std::nullopt;
  }
  if (needed < sizeof(ULONG64) || needed > 64 * 1024) return std::nullopt;

  std::vector<uint8_t> buf(needed, 0);
  st = NtQuery(kSystemProcessorIdleCycleTimeInformation, buf.data(),
               static_cast<ULONG>(buf.size()), &needed);
  if (st != kStatusSuccess) return std::nullopt;

  const size_t count = needed / sizeof(ULONG64);
  if (count == 0) return std::nullopt;
  auto* values = reinterpret_cast<ULONG64*>(buf.data());

  std::optional<uint64_t> delta_sum;
  if (have_baseline_ && prev_.size() == count) {
    uint64_t sum = 0;
    for (size_t i = 0; i < count; ++i) {
      if (values[i] >= prev_[i]) {
        sum += static_cast<uint64_t>(values[i] - prev_[i]);
      }
    }
    delta_sum = sum;
  }

  prev_.assign(values, values + count);
  have_baseline_ = true;
  return delta_sum;
}

}  // namespace pulse
