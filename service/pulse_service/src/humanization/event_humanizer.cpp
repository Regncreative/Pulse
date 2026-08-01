#include "humanization/event_humanizer.hpp"

#include <algorithm>
#include <cctype>
#include <string_view>

namespace pulse {
namespace {

struct HumanizationRule {
  std::uint16_t event_id = 0;
  /// Case-insensitive substring of provider_name; empty = match any provider.
  std::string_view provider_hint;
  std::string_view title;
  std::string_view summary;
  std::string_view recommendation;
  std::string_view category;
};

// Phase 4 catalog — Microsoft-documented Event IDs only.
// Keep titles aligned with event_intelligence Level 1 wording.
constexpr HumanizationRule kRules[] = {
    {10016, "DistributedCOM", "COM Permission Warning",
     "An application attempted to access a COM component without sufficient "
     "permissions.",
     "Usually harmless. No action is required unless applications are "
     "malfunctioning.",
     "COM"},

    {7036, "Service Control Manager", "Service State Changed",
     "A Windows service changed its running state.",
     "Normal operating system behavior.", "Service"},

    {7040, "Service Control Manager", "Service Configuration Changed",
     "Windows updated the startup configuration of a background service.", "",
     "Service"},

    {7023, "Service Control Manager", "Service Failed",
     "A Windows service reported an error and stopped or failed.",
     "Check the service name and recent software changes.", "Service"},

    {7031, "Service Control Manager", "Service Crashed",
     "A Windows service terminated unexpectedly and recovery was scheduled.",
     "Repeated crashes for the same service usually mean a deeper fault.",
     "Service"},

    {7034, "Service Control Manager", "Service Stopped Unexpectedly",
     "A Windows service terminated unexpectedly.",
     "Look for matching errors around the same time.", "Service"},

    {7045, "Service Control Manager", "New Service or Driver Installed",
     "Windows recorded that a service or driver was installed.", "", "Driver"},

    {12, "Kernel-General", "Windows Started",
     "Windows has started successfully.", "", "Boot"},

    {13, "Kernel-General", "Windows Shutdown", "Windows has shut down.", "",
     "Boot"},

    {6005, "EventLog", "Event Log Service Started",
     "The Windows Event Log service started.", "", "Boot"},

    {6006, "EventLog", "Event Log Service Stopped",
     "The Windows Event Log service stopped.", "", "Boot"},

    {1074, "User32", "Shutdown or Restart Initiated",
     "A user or application initiated a shutdown or restart.", "", "Boot"},

    {41, "Kernel-Power", "Windows Restarted Unexpectedly",
     "Windows rebooted without cleanly shutting down first.",
     "Check for a bug check dump and recent driver changes.", "Power"},

    {6008, "EventLog", "Previous Shutdown Was Unexpected",
     "The previous system shutdown was unexpected.",
     "Correlate with Kernel-Power 41 nearby.", "Power"},

    {42, "Kernel-Power", "Windows Entered Sleep",
     "The system is entering a sleep state.", "", "Power"},

    {107, "Kernel-Power", "Windows Resumed From Sleep",
     "The system has resumed from sleep.", "", "Power"},

    {1, "Power-Troubleshooter", "Windows Woke From Sleep",
     "Windows woke from sleep or hibernation.", "", "Power"},

    {158, "Time-Service", "Time Synchronization Stopped",
     "The Windows time synchronization provider stopped.",
     "Usually expected on systems without Hyper-V.", "Time"},

    {1001, "WER-SystemErrorReporting", "Windows Stopped Unexpectedly",
     "Windows recorded a bug check and may have saved a crash dump.",
     "Open the dump path from the event details when you need the faulting "
     "module.",
     "Crash"},

    {1001, "BugCheck", "Windows Stopped Unexpectedly",
     "Windows recorded a bug check (blue screen).",
     "Review the bug check code and recent driver changes.", "Crash"},

    {1000, "Application Error", "Application Crashed",
     "An application exited unexpectedly after a fault.",
     "Note the faulting application and module in the event details.", "Crash"},

    {1002, "Application Hang", "Application Stopped Responding",
     "Windows detected that an application stopped responding.",
     "If this repeats, check for updates to that application.", "Crash"},

    {1001, "Windows Error Reporting", "Windows Error Reporting Recorded a Problem",
     "Windows Error Reporting captured a problem report.", "", "Crash"},

    {19, "WindowsUpdateClient", "Windows Update Installed Successfully",
     "Windows successfully installed an update.", "", "Update"},

    {20, "WindowsUpdateClient", "Windows Update Installation Failed",
     "Windows failed to install an update.",
     "Retry the update or inspect the error code in the event details.",
     "Update"},

    {43, "WindowsUpdateClient", "Windows Update Installation Started",
     "Windows has started installing an update.", "", "Update"},

    {44, "WindowsUpdateClient", "Windows Update Download Started",
     "Windows Update started downloading an update.", "", "Update"},

    {400, "Kernel-PnP", "Device Configured",
     "Windows configured a Plug and Play device.", "", "Device"},

    {410, "Kernel-PnP", "Device Started",
     "Windows started a Plug and Play device.", "", "Device"},

    {411, "Kernel-PnP", "Device Failed to Start",
     "A Plug and Play device had a problem starting.",
     "Check Device Manager for the device in the event details.", "Device"},

    {7, "disk", "Storage Reported a Bad Block",
     "Windows reported that a storage device has a bad block.",
     "Back up important data and check drive health.", "Storage"},

    {51, "disk", "Storage Reported a Disk Error",
     "Windows detected an error on a storage device.",
     "Watch for repeats; persistent errors warrant a health check.", "Storage"},

    {4624, "Security-Auditing", "User Signed In",
     "A user account successfully signed in.", "", "Security"},

    {4634, "Security-Auditing", "User Signed Out",
     "A user account signed out.", "", "Security"},
};

bool ContainsIgnoreCase(std::string_view haystack, std::string_view needle) {
  if (needle.empty()) {
    return true;
  }
  if (haystack.size() < needle.size()) {
    return false;
  }
  auto pred = [](unsigned char a, unsigned char b) {
    return std::tolower(a) == std::tolower(b);
  };
  return std::search(haystack.begin(), haystack.end(), needle.begin(),
                     needle.end(), pred) != haystack.end();
}

const HumanizationRule* MatchRule(const EventRecord& record) {
  if (!record.event_id.has_value()) {
    return nullptr;
  }
  const auto id = *record.event_id;
  for (const auto& rule : kRules) {
    if (rule.event_id != id) {
      continue;
    }
    if (rule.provider_hint.empty() ||
        ContainsIgnoreCase(record.provider_name, rule.provider_hint)) {
      return &rule;
    }
  }
  return nullptr;
}

HumanizedEvent Fallback(const EventRecord& record) {
  HumanizedEvent out;
  out.severity = record.level;
  out.category = "General";
  out.title = record.provider_name.empty() ? "Windows Event"
                                           : record.provider_name;
  out.summary = record.message.empty() ? "No message available."
                                       : record.message;
  out.recommendation.clear();  // Never emit placeholder recommendation text.
  return out;
}

}  // namespace

HumanizedEvent EventHumanizer::Humanize(const EventRecord& record) const {
  const HumanizationRule* rule = MatchRule(record);
  if (rule == nullptr) {
    return Fallback(record);
  }

  HumanizedEvent out;
  out.title = std::string(rule->title);
  out.summary = std::string(rule->summary);
  out.recommendation = std::string(rule->recommendation);
  out.category = std::string(rule->category);
  out.severity = record.level;
  return out;
}

}  // namespace pulse
