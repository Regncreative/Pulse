#include "collectors/hardware_sensors_collector.hpp"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
#include <winioctl.h>
#include <nvme.h>

namespace pulse {
namespace {

constexpr int kMaxPhysicalDrives = 16;
constexpr SHORT kTempMinC = -40;
constexpr SHORT kTempMaxC = 125;

/// Little-endian 128-bit NVMe counter → lower 64 bits when high half is zero.
/// Returns false if the value does not fit in uint64_t (leave metric unset).
bool ReadNvmeU64(const UCHAR bytes[16], uint64_t* out) {
  if (out == nullptr || bytes == nullptr) return false;
  uint64_t lo = 0;
  uint64_t hi = 0;
  std::memcpy(&lo, bytes, sizeof(lo));
  std::memcpy(&hi, bytes + 8, sizeof(hi));
  if (hi != 0) return false;
  *out = lo;
  return true;
}

/// NVMe data units → bytes (spec: value is in thousands of 512-byte units).
bool NvmeDataUnitsToBytes(const UCHAR units[16], uint64_t* out_bytes) {
  uint64_t units64 = 0;
  if (!ReadNvmeU64(units, &units64)) return false;
  // units * 1000 * 512 — reject overflow.
  constexpr uint64_t kScale = 1000ULL * 512ULL;
  if (units64 > (UINT64_MAX / kScale)) return false;
  *out_bytes = units64 * kScale;
  return true;
}

bool IsPlausibleCelsius(SHORT c) {
  return c >= kTempMinC && c <= kTempMaxC;
}

HANDLE OpenPhysicalDrive(int index) {
  wchar_t path[64];
  swprintf_s(path, L"\\\\.\\PhysicalDrive%d", index);
  return CreateFileW(path, GENERIC_READ,
                     FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                     OPEN_EXISTING, 0, nullptr);
}

bool QueryDeviceTemperature(HANDLE disk, double* out_c) {
  if (disk == INVALID_HANDLE_VALUE || out_c == nullptr) return false;

  STORAGE_PROPERTY_QUERY query{};
  query.PropertyId = StorageDeviceTemperatureProperty;
  query.QueryType = PropertyStandardQuery;

  // Descriptor + a few STORAGE_TEMPERATURE_INFO entries.
  std::vector<uint8_t> buf(sizeof(STORAGE_TEMPERATURE_DATA_DESCRIPTOR) +
                           8 * sizeof(STORAGE_TEMPERATURE_INFO));
  DWORD bytes = 0;
  if (!DeviceIoControl(disk, IOCTL_STORAGE_QUERY_PROPERTY, &query,
                       sizeof(query), buf.data(),
                       static_cast<DWORD>(buf.size()), &bytes, nullptr) ||
      bytes < sizeof(STORAGE_TEMPERATURE_DATA_DESCRIPTOR)) {
    return false;
  }

  const auto* desc =
      reinterpret_cast<const STORAGE_TEMPERATURE_DATA_DESCRIPTOR*>(buf.data());
  if (desc->InfoCount == 0) return false;

  const size_t info_bytes =
      static_cast<size_t>(desc->InfoCount) * sizeof(STORAGE_TEMPERATURE_INFO);
  if (bytes <
      offsetof(STORAGE_TEMPERATURE_DATA_DESCRIPTOR, TemperatureInfo) +
          info_bytes) {
    return false;
  }

  // Prefer index 0 (composite) when plausible; else first plausible sensor.
  for (WORD i = 0; i < desc->InfoCount; ++i) {
    const STORAGE_TEMPERATURE_INFO& info = desc->TemperatureInfo[i];
    if (IsPlausibleCelsius(info.Temperature)) {
      *out_c = static_cast<double>(info.Temperature);
      return true;
    }
  }
  return false;
}

bool QueryPredictFailure(HANDLE disk, bool* out_smart_ok) {
  if (disk == INVALID_HANDLE_VALUE || out_smart_ok == nullptr) return false;

  STORAGE_PREDICT_FAILURE predict{};
  DWORD bytes = 0;
  if (!DeviceIoControl(disk, IOCTL_STORAGE_PREDICT_FAILURE, nullptr, 0,
                       &predict, sizeof(predict), &bytes, nullptr) ||
      bytes < sizeof(predict.PredictFailure)) {
    return false;
  }
  // PredictFailure != 0 → media failure predicted.
  *out_smart_ok = (predict.PredictFailure == 0);
  return true;
}

struct NvmeHealthFields {
  bool has_temp = false;
  double temp_c = 0.0;
  bool has_smart_ok = false;
  bool smart_ok = false;
  bool has_power_on_hours = false;
  uint64_t power_on_hours = 0;
  bool has_bytes_read = false;
  uint64_t bytes_read = 0;
  bool has_bytes_written = false;
  uint64_t bytes_written = 0;
};

bool QueryNvmeHealthLog(HANDLE disk, NvmeHealthFields* out) {
  if (disk == INVALID_HANDLE_VALUE || out == nullptr) return false;

  // Single buffer for query + protocol-specific data + log page (Microsoft
  // pattern: Working with NVMe drives).
  constexpr DWORD kLogSize = sizeof(NVME_HEALTH_INFO_LOG);
  const DWORD buffer_length =
      FIELD_OFFSET(STORAGE_PROPERTY_QUERY, AdditionalParameters) +
      sizeof(STORAGE_PROTOCOL_SPECIFIC_DATA) + kLogSize;

  std::vector<uint8_t> buffer(buffer_length, 0);
  auto* query = reinterpret_cast<STORAGE_PROPERTY_QUERY*>(buffer.data());
  auto* protocol_data =
      reinterpret_cast<STORAGE_PROTOCOL_SPECIFIC_DATA*>(
          query->AdditionalParameters);

  query->PropertyId = StorageDeviceProtocolSpecificProperty;
  query->QueryType = PropertyStandardQuery;

  protocol_data->ProtocolType = ProtocolTypeNvme;
  protocol_data->DataType = NVMeDataTypeLogPage;
  protocol_data->ProtocolDataRequestValue = NVME_LOG_PAGE_HEALTH_INFO;
  protocol_data->ProtocolDataRequestSubValue = 0;
  protocol_data->ProtocolDataRequestSubValue2 = 0;
  protocol_data->ProtocolDataRequestSubValue3 = 0;
  protocol_data->ProtocolDataRequestSubValue4 = 0;
  protocol_data->ProtocolDataOffset = sizeof(STORAGE_PROTOCOL_SPECIFIC_DATA);
  protocol_data->ProtocolDataLength = kLogSize;

  DWORD returned = 0;
  if (!DeviceIoControl(disk, IOCTL_STORAGE_QUERY_PROPERTY, buffer.data(),
                       buffer_length, buffer.data(), buffer_length, &returned,
                       nullptr) ||
      returned == 0) {
    return false;
  }

  auto* protocol_descr =
      reinterpret_cast<STORAGE_PROTOCOL_DATA_DESCRIPTOR*>(buffer.data());
  if (protocol_descr->Version != sizeof(STORAGE_PROTOCOL_DATA_DESCRIPTOR) ||
      protocol_descr->Size != sizeof(STORAGE_PROTOCOL_DATA_DESCRIPTOR)) {
    return false;
  }

  protocol_data = &protocol_descr->ProtocolSpecificData;
  if (protocol_data->ProtocolDataOffset < sizeof(STORAGE_PROTOCOL_SPECIFIC_DATA) ||
      protocol_data->ProtocolDataLength < sizeof(NVME_HEALTH_INFO_LOG)) {
    return false;
  }

  const auto* smart = reinterpret_cast<const NVME_HEALTH_INFO_LOG*>(
      reinterpret_cast<const UCHAR*>(protocol_data) +
      protocol_data->ProtocolDataOffset);

  // CriticalWarning == 0 → no critical SMART warnings.
  out->has_smart_ok = true;
  out->smart_ok = (smart->CriticalWarning.AsUchar == 0);

  const USHORT kelvin = static_cast<USHORT>(
      (static_cast<USHORT>(smart->Temperature[1]) << 8) |
      static_cast<USHORT>(smart->Temperature[0]));
  // 0x0000 / 0xFFFF are invalid / not reported in common practice.
  if (kelvin != 0 && kelvin != 0xFFFF) {
    const int celsius = static_cast<int>(kelvin) - 273;
    if (celsius >= kTempMinC && celsius <= kTempMaxC) {
      out->has_temp = true;
      out->temp_c = static_cast<double>(celsius);
    }
  }

  uint64_t poh = 0;
  if (ReadNvmeU64(smart->PowerOnHours, &poh)) {
    out->has_power_on_hours = true;
    out->power_on_hours = poh;
  }

  uint64_t bytes_read = 0;
  if (NvmeDataUnitsToBytes(smart->DataUnitRead, &bytes_read)) {
    out->has_bytes_read = true;
    out->bytes_read = bytes_read;
  }

  uint64_t bytes_written = 0;
  if (NvmeDataUnitsToBytes(smart->DataUnitWritten, &bytes_written)) {
    out->has_bytes_written = true;
    out->bytes_written = bytes_written;
  }

  return out->has_temp || out->has_smart_ok || out->has_power_on_hours ||
         out->has_bytes_read || out->has_bytes_written;
}

void ApplyDiskSensors(HANDLE disk, ipc::HealthSample* out,
                      bool prefer_identity_fields) {
  if (out == nullptr) return;

  double temp_c = 0.0;
  if (!out->has_ssd_temp_c && QueryDeviceTemperature(disk, &temp_c)) {
    out->has_ssd_temp_c = true;
    out->ssd_temp_c = temp_c;
  }

  NvmeHealthFields nvme{};
  const bool nvme_ok = QueryNvmeHealthLog(disk, &nvme);
  if (nvme_ok) {
    if (!out->has_ssd_temp_c && nvme.has_temp) {
      out->has_ssd_temp_c = true;
      out->ssd_temp_c = nvme.temp_c;
    }
    if (prefer_identity_fields) {
      if (nvme.has_smart_ok && !out->has_disk_smart_ok) {
        out->has_disk_smart_ok = true;
        out->disk_smart_ok = nvme.smart_ok;
      }
      if (nvme.has_power_on_hours && !out->has_disk_power_on_hours) {
        out->has_disk_power_on_hours = true;
        out->disk_power_on_hours = nvme.power_on_hours;
      }
      if (nvme.has_bytes_read && !out->has_disk_total_bytes_read) {
        out->has_disk_total_bytes_read = true;
        out->disk_total_bytes_read = nvme.bytes_read;
      }
      if (nvme.has_bytes_written && !out->has_disk_total_bytes_written) {
        out->has_disk_total_bytes_written = true;
        out->disk_total_bytes_written = nvme.bytes_written;
      }
    }
  }

  if (prefer_identity_fields && !out->has_disk_smart_ok) {
    bool smart_ok = false;
    if (QueryPredictFailure(disk, &smart_ok)) {
      out->has_disk_smart_ok = true;
      out->disk_smart_ok = smart_ok;
    }
  }
}

}  // namespace

void SampleHardwareSensors(ipc::HealthSample* out) {
  if (out == nullptr) return;

  // CPU package temperature: intentionally unset.
  // CallNtPowerInformation thermal levels and ACPI thermal-zone enumeration
  // are not reliable public userspace package-temp sources without vendor
  // APIs / WMI heuristics. Prefer honest Not supported.

  // Motherboard / chassis fans: no documented Win32 path without vendor SDKs.
  // GPU FanRPM remains via SampleGpuD3dkmtTelemetry when the driver reports it.

  bool identity_assigned = false;
  int opened = 0;
  for (int i = 0; i < kMaxPhysicalDrives; ++i) {
    HANDLE disk = OpenPhysicalDrive(i);
    if (disk == INVALID_HANDLE_VALUE) {
      // Skip holes (access denied); stop after several consecutive misses
      // once at least one drive was opened.
      if (opened > 0) break;
      continue;
    }
    ++opened;

    // SMART / POH / lifetime I/O come from the first openable physical disk;
    // later drives only fill temperature when still missing.
    const bool prefer_identity = !identity_assigned;
    ApplyDiskSensors(disk, out, prefer_identity);
    if (prefer_identity) identity_assigned = true;
    CloseHandle(disk);

    if (out->has_ssd_temp_c && identity_assigned) break;
  }
}

}  // namespace pulse
