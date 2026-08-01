#pragma once

#include "pulse_wire.hpp"

#include <cstdint>
#include <string>

namespace pulse {

/// Fill CPU architecture, instruction set, NUMA, SMT, L1/L2/L3 from Win32.
void EnrichCpuOverview(ipc::HealthStaticInfo* info);

/// SMBIOS Type 17 memory modules — unset when unavailable.
void EnrichMemoryModules(ipc::HealthStaticInfo* info);

/// Primary physical disk identity via Storage IOCTLs — unset when unavailable.
void EnrichPrimaryDiskIdentity(ipc::HealthStaticInfo* info);

/// Rich network adapter static + sample fields for the active adapter.
void EnrichNetworkStatic(const std::string& active_adapter_name,
                         uint32_t active_if_index,
                         ipc::HealthStaticInfo* info);

void SampleNetworkExtended(uint32_t active_if_index,
                           const std::string& active_adapter_name,
                           double download_bps, double upload_bps,
                           bool have_rates, uint64_t monitor_start_ms,
                           uint64_t now_ms, double* peak_down, double* peak_up,
                           double* sum_down, double* sum_up, uint64_t* rate_samples,
                           ipc::HealthSample* out);

}  // namespace pulse
