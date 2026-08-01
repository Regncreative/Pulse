#pragma once

#include "collectors/gpu_adapter_info.hpp"
#include "collectors/process_metrics.hpp"
#include "collectors/network_etw_engine.hpp"
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

  [[nodiscard]] bool Initialize();

  void Shutdown();

  [[nodiscard]] ipc::HealthStaticInfo CollectStatic();

  /// Sample live counters. Call ~1 Hz. First call may lack rate metrics.
  [[nodiscard]] ipc::HealthSample CollectSample();

  /// Sample + Task Manager–style process inventory delta/full update.
  [[nodiscard]] ipc::HealthUpdate CollectHealthUpdate();

  /// Best-effort enrichment for process detail panel (may be partial).
  [[nodiscard]] ipc::ProcessDetails QueryProcessDetails(uint32_t pid);

  /// Default: TimeBased. CycleBased uses SPI CycleTime + idle cycles.
  void SetProcessCpuMode(ProcessCpuMode mode);
  [[nodiscard]] ProcessCpuMode process_cpu_mode() const;

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
  void SampleTopGpuFromPdh(ipc::HealthSample* out);
  void SampleGpuAdapterMemory(ipc::HealthSample* out);
  void SampleCpuCores(ipc::HealthSample* out);
  void SampleCachedMemoryFromPdh(ipc::HealthSample* out);
  void SampleCompressedAndFaultsFromPdh(ipc::HealthSample* out);
  void SampleProcessesCombined(ipc::HealthSample* sample_out,
                               ipc::HealthProcessInventoryUpdate* inv_out);
  void SamplePerProcessNetwork(
      std::unordered_map<uint32_t, NetworkPidBytes>* bytes_by_pid);

  /// Per-PID GPU engine util + process dedicated/shared memory (LUID-filtered).
  struct GpuByPid {
    bool has_util = false;
    double util = 0.0;
    std::string engine;
    bool has_dedicated = false;
    uint64_t dedicated_bytes = 0;
    bool has_shared = false;
    uint64_t shared_bytes = 0;
  };
  void SampleGpuMetricsByPid(std::unordered_map<uint32_t, GpuByPid>* out);

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

  bool have_cpu_baseline_ = false;
  uint64_t prev_idle_ = 0;
  uint64_t prev_kernel_ = 0;
  uint64_t prev_user_ = 0;

  bool have_net_baseline_ = false;
  uint64_t prev_net_in_ = 0;
  uint64_t prev_net_out_ = 0;
  uint64_t prev_net_tick_ms_ = 0;
  uint32_t active_if_index_ = 0;
  std::string active_adapter_;

  uint32_t cpu_base_mhz_ = 0;
  uint32_t cpu_logical_ = 0;

  GpuAdapterSelection gpu_adapter_;
  uint64_t health_monitor_start_ms_ = 0;
  double net_peak_download_bps_ = 0.0;
  double net_peak_upload_bps_ = 0.0;
  double net_sum_download_bps_ = 0.0;
  double net_sum_upload_bps_ = 0.0;
  uint64_t net_rate_samples_ = 0;

  void* pdh_gpu_dedicated_ = nullptr;
  void* pdh_gpu_shared_ = nullptr;
  bool pdh_gpu_mem_ok_ = false;
  void* pdh_gpu_proc_ded_ = nullptr;
  void* pdh_gpu_proc_shr_ = nullptr;
  bool pdh_gpu_proc_mem_ok_ = false;

  ProcessCpuCalculator process_cpu_{ProcessCpuMode::TimeBased};
  IdleCycleTracker idle_cycles_;

  /// Per-process baselines keyed by (pid, create_time) — PID recycle safe.
  struct ProcCpuPrev {
    uint64_t cpu_100ns = 0;
    uint64_t cycle_time = 0;
  };
  struct ProcIoPrev {
    uint64_t bytes = 0;
  };
  std::unordered_map<ProcessKey, ProcCpuPrev, ProcessKeyHash> prev_proc_cpu_;
  std::unordered_map<ProcessKey, ProcIoPrev, ProcessKeyHash> prev_proc_io_;
  /// Cumulative ETW send/recv totals (NetworkEtwEngine snapshot).
  std::unordered_map<ProcessKey, NetworkPidBytes, ProcessKeyHash> prev_net_bytes_;
  /// Last create_time_100ns seen for a PID (detect recycle for TCP map).
  std::unordered_map<uint32_t, uint64_t> prev_pid_create_time_;
  uint64_t prev_proc_tick_ms_ = 0;
  bool have_proc_baseline_ = false;

  NetworkEtwEngine network_etw_;

  struct InvRowPrev {
    ProcessKey key;
    std::string name;
    double cpu_percent = 0.0;
    bool has_cpu = false;
    uint64_t memory_bytes = 0;
    uint64_t working_set_bytes = 0;
    uint64_t commit_bytes = 0;
    uint64_t paged_pool_bytes = 0;
    uint64_t nonpaged_pool_bytes = 0;
    double disk_bps = 0.0;
    bool has_disk = false;
    double net_bps = 0.0;
    bool has_net = false;
    double net_upload_bps = 0.0;
    bool has_net_upload = false;
    double net_download_bps = 0.0;
    bool has_net_download = false;
    uint64_t net_bytes_total = 0;
    bool has_net_bytes_total = false;
    bool has_gpu = false;
    double gpu_percent = 0.0;
    std::string gpu_engine;
    bool has_gpu_dedicated = false;
    uint64_t gpu_dedicated_bytes = 0;
    bool has_gpu_shared = false;
    uint64_t gpu_shared_bytes = 0;
    uint32_t thread_count = 0;
    uint32_t handle_count = 0;
    std::string path;
    bool is_critical = false;
    bool has_is_critical = false;
    uint32_t parent_pid = 0;
  };
  std::unordered_map<ProcessKey, InvRowPrev, ProcessKeyHash> prev_inventory_;
  uint64_t inventory_seq_ = 0;
  uint64_t last_full_resync_ms_ = 0;
  bool force_full_resync_ = true;

  void* pdh_query_ = nullptr;
  void* pdh_disk_read_ = nullptr;
  void* pdh_disk_write_ = nullptr;
  void* pdh_disk_read_all_ = nullptr;
  void* pdh_disk_write_all_ = nullptr;
  void* pdh_gpu_ = nullptr;
  void* pdh_cpu_perf_ = nullptr;
  void* pdh_cpu_utility_ = nullptr;
  void* pdh_cpu_cores_ = nullptr;
  void* pdh_mem_cache_ = nullptr;
  void* pdh_mem_modified_ = nullptr;
  void* pdh_mem_standby_reserve_ = nullptr;
  void* pdh_mem_standby_normal_ = nullptr;
  void* pdh_mem_standby_core_ = nullptr;
  void* pdh_mem_compressed_ = nullptr;
  void* pdh_mem_page_faults_ = nullptr;
  bool pdh_disk_ok_ = false;
  bool pdh_disk_instances_ok_ = false;
  bool pdh_gpu_ok_ = false;
  bool pdh_cpu_perf_ok_ = false;
  bool pdh_cpu_utility_ok_ = false;
  bool pdh_cpu_cores_ok_ = false;
  bool pdh_mem_cache_ok_ = false;
  bool pdh_mem_compressed_ok_ = false;
  bool pdh_mem_page_faults_ok_ = false;
  bool pdh_primed_ = false;
  bool pdh_collected_this_sample_ = false;
};

}  // namespace pulse
