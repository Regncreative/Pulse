#pragma once

#include "pulse_wire.hpp"

#include <cstdint>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

namespace pulse {

/// Read-only Windows telemetry for System Health (TASK-007 / 007.2).
/// Flutter never calls Win32 for these metrics — service only.
class HealthMetricsCollector {
 public:
  HealthMetricsCollector();
  ~HealthMetricsCollector();

  HealthMetricsCollector(const HealthMetricsCollector&) = delete;
  HealthMetricsCollector& operator=(const HealthMetricsCollector&) = delete;

  /// Open PDH queries / capture CPU baseline. Safe to call once.
  [[nodiscard]] bool Initialize();

  void Shutdown();

  [[nodiscard]] ipc::HealthStaticInfo CollectStatic();

  /// Sample live counters. Call ~1 Hz. First call may lack rate metrics.
  [[nodiscard]] ipc::HealthSample CollectSample();

 private:
  void RefreshCpuBaseline();
  [[nodiscard]] std::optional<double> SampleCpuPercentFromSystemTimes();
  [[nodiscard]] std::optional<double> SampleCpuPercent();
  void SampleMemory(ipc::HealthSample* out);
  void SampleDiskSpace(ipc::HealthSample* out);
  void SamplePhysicalDisks(ipc::HealthSample* out);
  void SampleUptime(ipc::HealthSample* out);
  void SampleNetwork(ipc::HealthSample* out);
  void CollectPdhOnce();
  void SampleDiskThroughput(ipc::HealthSample* out);
  void SampleGpuPercent(ipc::HealthSample* out);
  void SampleCpuFrequency(ipc::HealthSample* out);
  void SampleNetworkAddresses(ipc::HealthSample* out);
  void SampleTopProcesses(ipc::HealthSample* out);
  void SampleTopGpuFromPdh(ipc::HealthSample* out);
  void SampleCpuCores(ipc::HealthSample* out);
  void SampleCachedMemoryFromPdh(ipc::HealthSample* out);

  [[nodiscard]] static std::string ReadRegistryString(const wchar_t* subkey,
                                                      const wchar_t* value);
  [[nodiscard]] static uint32_t ReadRegistryDword(const wchar_t* subkey,
                                                  const wchar_t* value);
  [[nodiscard]] static void QueryGpuInfo(std::string* model,
                                         uint64_t* dedicated_bytes,
                                         uint64_t* shared_bytes);
  [[nodiscard]] static std::string QueryActiveAdapterName();
  [[nodiscard]] static uint64_t QueryPrimaryStorageBytes();
  [[nodiscard]] static void QueryCpuTopology(uint32_t* sockets, uint32_t* cores,
                                             uint32_t* logical);

  std::mutex mu_;
  bool initialized_ = false;

  // GetSystemTimes baseline
  bool have_cpu_baseline_ = false;
  uint64_t prev_idle_ = 0;
  uint64_t prev_kernel_ = 0;
  uint64_t prev_user_ = 0;

  // Network byte counters (active adapter only — Task Manager style)
  bool have_net_baseline_ = false;
  uint64_t prev_net_in_ = 0;
  uint64_t prev_net_out_ = 0;
  uint64_t prev_net_tick_ms_ = 0;
  uint32_t active_if_index_ = 0;
  std::string active_adapter_;

  // Cached static-ish detail
  uint32_t cpu_base_mhz_ = 0;
  uint32_t cpu_logical_ = 0;

  // Per-process baselines from NtQuerySystemInformation (no process handles).
  struct ProcCpuPrev {
    uint64_t cpu_100ns = 0;
  };
  struct ProcIoPrev {
    uint64_t bytes = 0;
  };
  std::unordered_map<uint32_t, ProcCpuPrev> prev_proc_cpu_;
  std::unordered_map<uint32_t, ProcIoPrev> prev_proc_io_;
  uint64_t prev_proc_tick_ms_ = 0;
  bool have_proc_baseline_ = false;

  // PDH (system counters — not used for process enumeration)
  void* pdh_query_ = nullptr;  // PDH_HQUERY
  void* pdh_disk_read_ = nullptr;
  void* pdh_disk_write_ = nullptr;
  void* pdh_disk_read_all_ = nullptr;   // PhysicalDisk(*)\Disk Read Bytes/sec
  void* pdh_disk_write_all_ = nullptr;  // PhysicalDisk(*)\Disk Write Bytes/sec
  void* pdh_gpu_ = nullptr;
  void* pdh_cpu_perf_ = nullptr;     // % Processor Performance (freq)
  void* pdh_cpu_utility_ = nullptr;  // % Processor Utility (_Total) — Task Manager
  void* pdh_cpu_cores_ = nullptr;    // Processor Information(*)\% Processor Utility
  void* pdh_mem_cache_ = nullptr;
  void* pdh_mem_modified_ = nullptr;
  void* pdh_mem_standby_reserve_ = nullptr;
  void* pdh_mem_standby_normal_ = nullptr;
  void* pdh_mem_standby_core_ = nullptr;
  bool pdh_disk_ok_ = false;
  bool pdh_disk_instances_ok_ = false;
  bool pdh_gpu_ok_ = false;
  bool pdh_cpu_perf_ok_ = false;
  bool pdh_cpu_utility_ok_ = false;
  bool pdh_cpu_cores_ok_ = false;
  bool pdh_mem_cache_ok_ = false;
  bool pdh_primed_ = false;
  bool pdh_collected_this_sample_ = false;
};

}  // namespace pulse
