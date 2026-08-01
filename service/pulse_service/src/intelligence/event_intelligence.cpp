#include "intelligence/event_intelligence.hpp"

#include <algorithm>
#include <cctype>
#include <string_view>

namespace pulse {
namespace {

struct IntelligenceRule {
  std::uint32_t event_id = 0;
  /// Case-insensitive substring of provider_name; empty = any provider.
  std::string_view provider_hint;
  std::string_view title;
  std::string_view summary;
  /// Empty string = omit recommendation in UI.
  std::string_view recommendation;
  bool action_required = false;
  Importance importance = Importance::Low;
  InsightCategory category = InsightCategory::General;
};

// Append-only catalog. Matching logic stays in MatchRule.
// Event IDs are Microsoft-documented (Wevtapi / Event Viewer / Learn).
// More specific provider hints are listed before broader ones for the same ID.
constexpr IntelligenceRule kRules[] = {
    // --- COM / existing ---
    {10016, "DistributedCOM", "COM Permission Warning",
     "An application attempted to access a COM component without sufficient "
     "permissions.",
     "Usually harmless unless an application is failing to start.", false,
     Importance::Low, InsightCategory::Com},

    // --- Service Control Manager ---
    {7040, "Service Control Manager", "Windows Service Configuration Changed",
     "Windows updated the startup configuration of a background service.", "",
     false, Importance::Low, InsightCategory::Service},

    {7036, "Service Control Manager", "Windows Service State Changed",
     "A Windows service started, stopped, or changed its running state.", "",
     false, Importance::Low, InsightCategory::Service},

    {7023, "Service Control Manager", "Windows Service Failed",
     "A Windows service reported an error and stopped or failed to complete "
     "its operation.",
     "Check the service name in the event details and recent application or "
     "driver changes.",
     true, Importance::High, InsightCategory::Service},

    {7031, "Service Control Manager", "Windows Service Crashed",
     "A Windows service terminated unexpectedly and Windows scheduled a "
     "recovery action.",
     "Repeated crashes for the same service usually mean a deeper fault.", true,
     Importance::High, InsightCategory::Service},

    {7034, "Service Control Manager", "Windows Service Stopped Unexpectedly",
     "A Windows service terminated unexpectedly.",
     "Look for matching application or driver errors around the same time.",
     true, Importance::High, InsightCategory::Service},

    {7045, "Service Control Manager", "New Service or Driver Installed",
     "Windows recorded that a service or driver was installed on this system.",
     "", false, Importance::Medium, InsightCategory::Driver},

    // --- Network / HTTP (existing) ---
    {4266, "Tcpip", "Temporary UDP Port Allocation Failed",
     "Windows could not allocate a temporary UDP port because the ephemeral "
     "port range is exhausted.",
     "Identify which process is holding UDP ports (for example with "
     "netstat). Reboot may temporarily clear the issue.",
     true, Importance::High, InsightCategory::Network},

    {4231, "Tcpip", "Temporary TCP Port Allocation Failed",
     "Windows could not allocate a temporary TCP port because the ephemeral "
     "port range is exhausted.",
     "Identify which process is holding TCP ports. This often breaks "
     "outbound network connections until ports are freed.",
     true, Importance::High, InsightCategory::Network},

    {114, "HttpService", "HTTP Service Endpoint Removed",
     "An HTTP URL endpoint was removed from the Windows HTTP service.", "",
     false, Importance::Low, InsightCategory::Http},

    {32, "HttpService", "HTTP Service Endpoint Removed",
     "An HTTP URL endpoint was removed from the Windows HTTP service.", "",
     false, Importance::Low, InsightCategory::Http},

    // --- Boot / shutdown ---
    {12, "Kernel-General", "Windows Started",
     "Windows has started successfully.", "", false, Importance::Low,
     InsightCategory::Boot},

    {13, "Kernel-General", "Windows Shutdown", "Windows has shut down.", "",
     false, Importance::Low, InsightCategory::Boot},

    {6005, "EventLog", "Event Log Service Started",
     "The Windows Event Log service started (typical at boot).", "", false,
     Importance::Low, InsightCategory::Boot},

    {6006, "EventLog", "Event Log Service Stopped",
     "The Windows Event Log service stopped (typical during a clean shutdown).",
     "", false, Importance::Low, InsightCategory::Boot},

    {1074, "User32", "Shutdown or Restart Initiated",
     "A user or application initiated a shutdown or restart.", "", false,
     Importance::Low, InsightCategory::Boot},

    // --- Unexpected power / dirty shutdown ---
    {41, "Kernel-Power", "Windows Restarted Unexpectedly",
     "Windows rebooted without cleanly shutting down first. This can happen "
     "after a crash, hang, or sudden power loss.",
     "Check for a matching bug check (Event ID 1001) and recent driver or "
     "hardware changes.",
     true, Importance::Critical, InsightCategory::Power},

    {6008, "EventLog", "Previous Shutdown Was Unexpected",
     "Windows recorded that the previous system shutdown was unexpected.",
     "Correlate with Kernel-Power 41 and any bug check events nearby.", true,
     Importance::High, InsightCategory::Power},

    // --- Sleep / wake (Microsoft-documented System log events) ---
    {42, "Kernel-Power", "Windows Entered Sleep",
     "The system is entering a sleep state.", "", false, Importance::Low,
     InsightCategory::Power},

    {107, "Kernel-Power", "Windows Resumed From Sleep",
     "The system has resumed from sleep.", "", false, Importance::Low,
     InsightCategory::Power},

    {1, "Power-Troubleshooter", "Windows Woke From Sleep",
     "Windows woke from sleep or hibernation.", "", false, Importance::Low,
     InsightCategory::Power},

    // --- Time (existing) ---
    {158, "Time-Service", "Time Synchronization Stopped",
     "The Windows time synchronization provider stopped.",
     "Usually expected on systems without Hyper-V.", false, Importance::Low,
     InsightCategory::Time},

    // --- Crash / BSOD / application faults ---
    // Prefer specific bugcheck providers before generic WER 1001.
    {1001, "WER-SystemErrorReporting", "Windows Stopped Unexpectedly",
     "Windows recorded a bug check (blue screen) and may have saved a crash "
     "dump.",
     "Open the dump path from the event details in a debugger when you need "
     "the faulting module.",
     true, Importance::Critical, InsightCategory::Crash},

    {1001, "BugCheck", "Windows Stopped Unexpectedly",
     "Windows recorded a bug check (blue screen).",
     "Review the bug check code and recent driver changes.", true,
     Importance::Critical, InsightCategory::Crash},

    {1000, "Application Error", "Application Crashed",
     "An application exited unexpectedly after a fault.",
     "Note the faulting application and module in the event details.", true,
     Importance::High, InsightCategory::Crash},

    {1002, "Application Hang", "Application Stopped Responding",
     "Windows detected that an application stopped responding.",
     "If this repeats for the same app, check for updates or conflicting "
     "extensions.",
     false, Importance::Medium, InsightCategory::Crash},

    {1001, "Windows Error Reporting", "Windows Error Reporting Recorded a Problem",
     "Windows Error Reporting captured a problem report for an application or "
     "component.",
     "", false, Importance::Medium, InsightCategory::Crash},

    // --- Windows Update ---
    {19, "WindowsUpdateClient", "Windows Update Installed Successfully",
     "Windows successfully installed an update.", "", false, Importance::Low,
     InsightCategory::Update},

    {20, "WindowsUpdateClient", "Windows Update Installation Failed",
     "Windows failed to install an update. The event message includes an error "
     "code.",
     "Retry the update or inspect the HRESULT in the event details.", true,
     Importance::High, InsightCategory::Update},

    {43, "WindowsUpdateClient", "Windows Update Installation Started",
     "Windows has started installing an update.", "", false, Importance::Low,
     InsightCategory::Update},

    {44, "WindowsUpdateClient", "Windows Update Download Started",
     "Windows Update started downloading an update.", "", false,
     Importance::Low, InsightCategory::Update},

    // --- Device / Plug and Play ---
    {400, "Kernel-PnP", "Device Configured",
     "Windows configured a Plug and Play device.", "", false, Importance::Low,
     InsightCategory::Device},

    {410, "Kernel-PnP", "Device Started",
     "Windows started a Plug and Play device.", "", false, Importance::Low,
     InsightCategory::Device},

    {411, "Kernel-PnP", "Device Failed to Start",
     "A Plug and Play device had a problem starting.",
     "Check Device Manager for the device instance in the event details.", true,
     Importance::Medium, InsightCategory::Device},

    // --- Storage (classic disk provider events) ---
    {7, "disk", "Storage Reported a Bad Block",
     "Windows reported that a storage device has a bad block.",
     "Back up important data and check the drive health tools for that disk.",
     true, Importance::High, InsightCategory::Storage},

    {51, "disk", "Storage Reported a Disk Error",
     "Windows detected an error on a storage device during an I/O operation.",
     "Watch for repeats; persistent errors warrant a drive health check.", true,
     Importance::High, InsightCategory::Storage},

    // --- Security (only present when Security channel is readable) ---
    {4624, "Security-Auditing", "User Signed In",
     "A user account successfully signed in.", "", false, Importance::Low,
     InsightCategory::Security},

    {4634, "Security-Auditing", "User Signed Out",
     "A user account signed out (logon session ended).", "", false,
     Importance::Low, InsightCategory::Security},
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

const IntelligenceRule* MatchRule(const ipc::TimelineEvent& event) {
  if (event.win_event_id == 0) {
    return nullptr;
  }
  for (const auto& rule : kRules) {
    if (rule.event_id != event.win_event_id) {
      continue;
    }
    if (rule.provider_hint.empty() ||
        ContainsIgnoreCase(event.provider_name, rule.provider_hint)) {
      return &rule;
    }
  }
  return nullptr;
}

Importance ImportanceFromSeverity(ipc::Severity severity) {
  switch (severity) {
    case ipc::Severity::Critical:
      return Importance::Critical;
    case ipc::Severity::Error:
      return Importance::High;
    case ipc::Severity::Warning:
      return Importance::Medium;
    case ipc::Severity::Info:
    case ipc::Severity::Verbose:
    case ipc::Severity::Unknown:
    default:
      return Importance::Low;
  }
}

std::string TruncateMessage(std::string_view message, std::size_t max_len) {
  if (message.empty()) {
    return "A Windows event was recorded.";
  }
  // Prefer first line for card-friendly fallback summaries.
  const auto newline = message.find('\n');
  std::string_view first =
      newline == std::string_view::npos ? message : message.substr(0, newline);
  while (!first.empty() &&
         (first.back() == '\r' || first.back() == ' ' || first.back() == '\t')) {
    first.remove_suffix(1);
  }
  if (first.size() <= max_len) {
    return std::string(first);
  }
  return std::string(first.substr(0, max_len - 1)) + "...";
}

std::string FriendlyProviderTitle(std::string_view provider) {
  if (provider.empty()) {
    return "Windows Event";
  }
  // Never leave raw provider as-is when we can soften common prefixes.
  constexpr std::string_view kPrefix = "Microsoft-Windows-";
  if (provider.size() > kPrefix.size() &&
      ContainsIgnoreCase(provider.substr(0, kPrefix.size()), kPrefix)) {
    return std::string(provider.substr(kPrefix.size())) + " Event";
  }
  return std::string(provider);
}

EventInsight Fallback(const ipc::TimelineEvent& event) {
  EventInsight out;
  out.title = FriendlyProviderTitle(event.provider_name);
  out.summary = TruncateMessage(event.message, 180);
  out.recommendation.clear();
  out.action_required = false;
  out.importance = ImportanceFromSeverity(event.severity);
  out.category = InsightCategory::General;
  return out;
}

}  // namespace

const char* ImportanceName(Importance value) {
  switch (value) {
    case Importance::Low:
      return "Low";
    case Importance::Medium:
      return "Medium";
    case Importance::High:
      return "High";
    case Importance::Critical:
      return "Critical";
  }
  return "Low";
}

const char* InsightCategoryName(InsightCategory value) {
  switch (value) {
    case InsightCategory::General:
      return "General";
    case InsightCategory::Service:
      return "Service";
    case InsightCategory::Network:
      return "Network";
    case InsightCategory::Com:
      return "COM";
    case InsightCategory::Boot:
      return "Boot";
    case InsightCategory::Time:
      return "Time";
    case InsightCategory::Http:
      return "HTTP";
    case InsightCategory::Crash:
      return "Crash";
    case InsightCategory::Power:
      return "Power";
    case InsightCategory::Update:
      return "Update";
    case InsightCategory::Device:
      return "Device";
    case InsightCategory::Driver:
      return "Driver";
    case InsightCategory::Security:
      return "Security";
    case InsightCategory::Storage:
      return "Storage";
  }
  return "General";
}

EventInsight EventIntelligence::Analyze(const ipc::TimelineEvent& event) const {
  const IntelligenceRule* rule = MatchRule(event);
  if (rule == nullptr) {
    return Fallback(event);
  }

  EventInsight out;
  out.title = std::string(rule->title);
  out.summary = std::string(rule->summary);
  out.recommendation = std::string(rule->recommendation);
  out.action_required = rule->action_required;
  out.importance = rule->importance;
  out.category = rule->category;
  return out;
}

}  // namespace pulse
