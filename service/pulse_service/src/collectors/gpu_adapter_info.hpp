#pragma once

#include "pulse_wire.hpp"

#include <cstdint>
#include <string>

namespace pulse {

/// Prefer discrete DXGI adapter; fall back to adapter 0.
struct GpuAdapterSelection {
  std::string model;
  std::string vendor;
  uint64_t dedicated_bytes = 0;
  uint64_t shared_bytes = 0;
  bool has_luid = false;
  int32_t luid_high = 0;
  uint32_t luid_low = 0;
  std::wstring luid_pdh_token;  // "0xHIGH_0xLOW" for PDH instance matching
};

[[nodiscard]] GpuAdapterSelection QueryPrimaryGpuAdapter();

/// SetupAPI / registry / D3DKMT / D3D feature level — unset fields stay empty.
void EnrichGpuStaticInfo(const GpuAdapterSelection& adapter,
                         ipc::HealthStaticInfo* info);

/// PDH engine utils (incl. Video Processing) for selected LUID.
void SampleGpuExtended(const GpuAdapterSelection& adapter, void* pdh_gpu_counter,
                       bool pdh_gpu_ok, void* pdh_query,
                       bool* pdh_collected_flag,
                       void (*collect_pdh_once)(void* self), void* self,
                       ipc::HealthSample* out);

/// D3DKMT ADAPTERPERFDATA / NODEPERFDATA — only sets fields when values are
/// non-zero / successfully returned (never invents sensors).
void SampleGpuD3dkmtTelemetry(const GpuAdapterSelection& adapter,
                              ipc::HealthSample* out);

/// Match PDH GPU instance name against selected adapter LUID token.
[[nodiscard]] bool GpuInstanceMatchesLuid(const wchar_t* instance_name,
                                          const std::wstring& luid_token);

[[nodiscard]] std::string GpuVendorNameFromPciId(uint32_t vendor_id);

/// Format WDDM enum from D3DKMT_DRIVERVERSION (e.g. 3100 → "3.1").
[[nodiscard]] std::string FormatWddmVersion(int driver_version_enum);

}  // namespace pulse
