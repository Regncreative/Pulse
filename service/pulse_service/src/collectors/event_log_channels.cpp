#include "collectors/event_log_channels.hpp"

#include "logging/logger.hpp"
#include "windows/wevt_helpers.hpp"

namespace pulse {
namespace {

const std::vector<EventLogChannelSpec>& Catalog() {
  // Paths are Microsoft Event Log channel names (Wevtapi).
  // Security is ProbeOpen — LocalService often cannot read it.
  static const std::vector<EventLogChannelSpec> kCatalog = {
      {L"System", EventLogChannelKind::Required, "System"},
      {L"Application", EventLogChannelKind::Optional, "Application"},
      {L"Setup", EventLogChannelKind::Optional, "Setup"},
      {L"Microsoft-Windows-WindowsUpdateClient/Operational",
       EventLogChannelKind::Optional, "WindowsUpdateClient/Operational"},
      {L"Microsoft-Windows-Kernel-PnP/Configuration",
       EventLogChannelKind::Optional, "Kernel-PnP/Configuration"},
      {L"Microsoft-Windows-Kernel-Power/Thermal-Operational",
       EventLogChannelKind::Optional, "Kernel-Power/Thermal-Operational"},
      {L"Microsoft-Windows-Kernel-Boot/Operational",
       EventLogChannelKind::Optional, "Kernel-Boot/Operational"},
      {L"Security", EventLogChannelKind::ProbeOpen, "Security"},
  };
  return kCatalog;
}

}  // namespace

const std::vector<EventLogChannelSpec>& DiagnosticsChannelCatalog() {
  return Catalog();
}

bool IsDiagnosticsChannelRequest(const std::string& channel) {
  if (channel.empty()) {
    return true;
  }
  // Historical clients send "System"; Phase 4 treats that as the diagnostics set.
  return channel == "System" || channel == "*" || channel == "Diagnostics";
}

bool IsEventLogChannelAccessible(const std::wstring& channel,
                                 EventLogChannelKind kind,
                                 std::string* out_detail) {
  if (channel.empty()) {
    if (out_detail != nullptr) {
      *out_detail = "empty channel name";
    }
    return false;
  }

  // Security (and similar): probe EvtOpenLog under LocalService before
  // EvtQuery/EvtSubscribe so access-denied is documented without a hard fail.
  if (kind == EventLogChannelKind::ProbeOpen) {
    DWORD error = ERROR_SUCCESS;
    if (!wevt::TryOpenChannel(channel, &error)) {
      if (out_detail != nullptr) {
        *out_detail = "EvtOpenLog failed: " + wevt::FormatWin32Error(error);
      }
      return false;
    }
    if (out_detail != nullptr) {
      out_detail->clear();
    }
    return true;
  }

  // Required / Optional: include in the attempt list. CollectLatest /
  // EvtSubscribe report missing or denied channels at use time.
  if (out_detail != nullptr) {
    out_detail->clear();
  }
  return true;
}

std::vector<std::wstring> AccessibleDiagnosticsChannels() {
  std::vector<std::wstring> accessible;
  accessible.reserve(Catalog().size());

  for (const EventLogChannelSpec& spec : Catalog()) {
    std::string detail;
    if (IsEventLogChannelAccessible(spec.path, spec.kind, &detail)) {
      accessible.push_back(spec.path);
      Logger::Instance().Debug(
          "EventLogChannels",
          std::string("Channel queued: ") +
              (spec.label != nullptr ? spec.label : "(unnamed)"));
    } else {
      const char* label = spec.label != nullptr ? spec.label : "(unnamed)";
      Logger::Instance().Warn(
          "EventLogChannels",
          std::string("Skipping channel: ") + label + " — " + detail);
    }
  }

  return accessible;
}

}  // namespace pulse
