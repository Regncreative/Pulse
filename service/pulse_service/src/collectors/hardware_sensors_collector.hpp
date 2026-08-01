#pragma once

#include "pulse_wire.hpp"

namespace pulse {

/// Phase 3 hardware sensors (read-only, documented Win32 Storage IOCTLs).
///
/// Populates HealthSample SSD/NVMe temperature and optional SMART-ish fields
/// when the corresponding IOCTL succeeds. Leaves has_* false otherwise.
///
/// Does **not** sample GPU telemetry — that remains in SampleGpuD3dkmtTelemetry.
/// Does **not** invent CPU package temperature — no reliable public userspace
/// package-temp API without vendor/WMI heuristics.
void SampleHardwareSensors(ipc::HealthSample* out);

}  // namespace pulse
