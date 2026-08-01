#pragma once

#include <string>
#include <vector>

namespace pulse {

/// How Pulse treats an Event Log channel under LocalService.
enum class EventLogChannelKind {
  /// Always attempt; failure for System is fatal to the multi-channel snapshot.
  Required,
  /// Attempt EvtQuery; skip + log on failure (channel missing or access denied).
  Optional,
  /// Probe with EvtOpenLog first (Security often fails under LocalService).
  ProbeOpen,
};

struct EventLogChannelSpec {
  const wchar_t* path = nullptr;
  EventLogChannelKind kind = EventLogChannelKind::Optional;
  /// Short UTF-8 label for logs / diagnostics (not the wire channel field).
  const char* label = nullptr;
};

/// Diagnostics Timeline channels (ADR-007: Event Log only).
/// Order is stable for logging; accessibility decides which are used at runtime.
[[nodiscard]] const std::vector<EventLogChannelSpec>& DiagnosticsChannelCatalog();

/// True when the client asked for the default multi-channel diagnostics set.
[[nodiscard]] bool IsDiagnosticsChannelRequest(const std::string& channel);

/// Returns channels that are readable right now (EvtOpenLog / light probe).
/// Never invents channels — only catalog entries that open successfully.
[[nodiscard]] std::vector<std::wstring> AccessibleDiagnosticsChannels();

/// Probe a single channel path. Returns false when inaccessible.
[[nodiscard]] bool IsEventLogChannelAccessible(const std::wstring& channel,
                                                EventLogChannelKind kind,
                                                std::string* out_detail);

}  // namespace pulse
