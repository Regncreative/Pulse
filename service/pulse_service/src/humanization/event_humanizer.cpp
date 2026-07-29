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

// Phase 1 catalog — append new rows only; matching stays in MatchRule.
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

    {12, "Kernel-General", "Windows Started",
     "Windows has started successfully.", "", "Boot"},

    {13, "Kernel-General", "Windows Shutdown", "Windows has shut down.", "",
     "Boot"},

    {158, "Time-Service", "Time Synchronization Stopped",
     "The Windows time synchronization provider stopped.",
     "Usually expected on systems without Hyper-V.", "Time"},
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
