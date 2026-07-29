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
constexpr IntelligenceRule kRules[] = {
    {10016, "DistributedCOM", "COM Permission Warning",
     "An application attempted to access a COM component without sufficient "
     "permissions.",
     "Usually harmless unless an application is failing to start.", false,
     Importance::Low, InsightCategory::Com},

    {7040, "Service Control Manager", "Windows Service Configuration Changed",
     "Windows updated the startup configuration of a background service.", "",
     false, Importance::Low, InsightCategory::Service},

    {7036, "Service Control Manager", "Windows Service State Changed",
     "A Windows service started, stopped, or changed its running state.", "",
     false, Importance::Low, InsightCategory::Service},

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

    {12, "Kernel-General", "Windows Started",
     "Windows has started successfully.", "", false, Importance::Low,
     InsightCategory::Boot},

    {13, "Kernel-General", "Windows Shutdown", "Windows has shut down.", "",
     false, Importance::Low, InsightCategory::Boot},

    {158, "Time-Service", "Time Synchronization Stopped",
     "The Windows time synchronization provider stopped.",
     "Usually expected on systems without Hyper-V.", false, Importance::Low,
     InsightCategory::Time},
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
