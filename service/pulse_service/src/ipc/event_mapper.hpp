#pragma once

#include "models/event_record.hpp"
#include "pulse_wire.hpp"

namespace pulse {

/// Maps collector EventRecord → IPC TimelineEvent. No Win32 / Wevtapi here.
[[nodiscard]] ipc::TimelineEvent ToTimelineEvent(const EventRecord& record);

[[nodiscard]] ipc::Severity ToIpcSeverity(EventLevel level);

}  // namespace pulse
