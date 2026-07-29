#include "ipc/event_mapper.hpp"

#include "intelligence/event_intelligence.hpp"

#include <sstream>

namespace pulse {
namespace {

const EventIntelligence& SharedIntelligence() {
  static const EventIntelligence kEngine;
  return kEngine;
}

std::string BuildStableId(const EventRecord& record) {
  std::ostringstream oss;
  oss << (record.channel.empty() ? "System" : record.channel) << '|'
      << (record.record_id ? std::to_string(*record.record_id) : "0") << '|'
      << (record.event_id ? std::to_string(*record.event_id) : "0") << '|'
      << (record.timestamp_utc ? *record.timestamp_utc : "unknown");
  return oss.str();
}

void ApplyInsight(ipc::TimelineEvent* out, const EventInsight& insight) {
  out->title = insight.title;
  out->summary = insight.summary;
  out->recommendation = insight.recommendation;
  out->action_required = insight.action_required;
  out->importance =
      static_cast<ipc::Importance>(static_cast<std::int32_t>(insight.importance));
  out->category = InsightCategoryName(insight.category);
}

}  // namespace

ipc::Severity ToIpcSeverity(EventLevel level) {
  switch (level) {
    case EventLevel::LogAlways:
    case EventLevel::Information:
      return ipc::Severity::Info;
    case EventLevel::Warning:
      return ipc::Severity::Warning;
    case EventLevel::Error:
      return ipc::Severity::Error;
    case EventLevel::Critical:
      return ipc::Severity::Critical;
    case EventLevel::Verbose:
      return ipc::Severity::Verbose;
    case EventLevel::Unknown:
    default:
      return ipc::Severity::Unknown;
  }
}

ipc::TimelineEvent ToTimelineEvent(const EventRecord& record) {
  ipc::TimelineEvent out;
  out.event_id = BuildStableId(record);
  out.timestamp_iso = record.timestamp_utc.value_or("");
  out.timestamp_unix_ms = record.timestamp_unix_ms.value_or(0);
  out.severity = ToIpcSeverity(record.level);
  out.channel = record.channel.empty() ? "System" : record.channel;
  out.provider_name = record.provider_name;
  out.win_event_id = record.event_id.value_or(0);
  out.record_id = record.record_id.value_or(0);
  out.computer_name = record.computer_name;
  out.message = record.message;

  const EventInsight insight = SharedIntelligence().Analyze(out);
  ApplyInsight(&out, insight);

  std::ostringstream tech;
  if (!out.provider_name.empty()) {
    tech << out.provider_name;
  } else {
    tech << "Unknown provider";
  }
  if (out.win_event_id != 0) {
    tech << " Event ID " << out.win_event_id;
  }
  tech << " · " << out.channel;
  if (!out.category.empty()) {
    tech << " · " << out.category;
  }
  out.technical_summary = tech.str();

  return out;
}

}  // namespace pulse
