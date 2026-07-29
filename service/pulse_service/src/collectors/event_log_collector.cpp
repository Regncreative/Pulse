#include "collectors/event_log_collector.hpp"

#include "logging/logger.hpp"
#include "windows/wevt_helpers.hpp"

#include <algorithm>
#include <iostream>
#include <optional>

#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
#include <winevt.h>

namespace pulse {
namespace {

EventLevel LevelFromVariant(const EVT_VARIANT& variant) {
  if (variant.Type == EvtVarTypeNull) {
    return EventLevel::Unknown;
  }
  if (variant.Type == EvtVarTypeByte) {
    switch (variant.ByteVal) {
      case 0:
        return EventLevel::LogAlways;
      case 1:
        return EventLevel::Critical;
      case 2:
        return EventLevel::Error;
      case 3:
        return EventLevel::Warning;
      case 4:
        return EventLevel::Information;
      case 5:
        return EventLevel::Verbose;
      default:
        return EventLevel::Unknown;
    }
  }
  return EventLevel::Unknown;
}

EventRecord ParseSystemProperties(const EVT_VARIANT* properties,
                                  DWORD property_count,
                                  EVT_HANDLE event_handle) {
  EventRecord record;

  auto at = [&](EVT_SYSTEM_PROPERTY_ID id) -> const EVT_VARIANT* {
    const auto index = static_cast<DWORD>(id);
    if (index >= property_count) {
      return nullptr;
    }
    return &properties[index];
  };

  std::wstring provider_wide;
  if (const EVT_VARIANT* provider = at(EvtSystemProviderName)) {
    record.provider_name = wevt::VariantToUtf8String(*provider);
    if (provider->Type == EvtVarTypeString && provider->StringVal != nullptr) {
      provider_wide = provider->StringVal;
    }
  }

  if (const EVT_VARIANT* id = at(EvtSystemEventID)) {
    if (id->Type == EvtVarTypeUInt16) {
      record.event_id = id->UInt16Val;
    }
  }

  if (const EVT_VARIANT* level = at(EvtSystemLevel)) {
    record.level = LevelFromVariant(*level);
  }

  if (const EVT_VARIANT* created = at(EvtSystemTimeCreated)) {
    if (created->Type == EvtVarTypeFileTime) {
      FILETIME ft{};
      ft.dwLowDateTime =
          static_cast<DWORD>(created->FileTimeVal & 0xFFFFFFFFull);
      ft.dwHighDateTime =
          static_cast<DWORD>((created->FileTimeVal >> 32) & 0xFFFFFFFFull);
      const std::string iso = wevt::FileTimeToIso8601Utc(ft);
      if (!iso.empty()) {
        record.timestamp_utc = iso;
      }
      const auto unix_ms = wevt::FileTimeToUnixMs(ft);
      if (unix_ms > 0) {
        record.timestamp_unix_ms = unix_ms;
      }
    }
  }

  if (const EVT_VARIANT* channel = at(EvtSystemChannel)) {
    record.channel = wevt::VariantToUtf8String(*channel);
  }

  if (const EVT_VARIANT* computer = at(EvtSystemComputer)) {
    record.computer_name = wevt::VariantToUtf8String(*computer);
  }

  if (const EVT_VARIANT* record_id = at(EvtSystemEventRecordId)) {
    if (record_id->Type == EvtVarTypeUInt64) {
      record.record_id = record_id->UInt64Val;
    }
  }

  // Best-effort message — missing publisher metadata is common and non-fatal.
  if (!provider_wide.empty()) {
    record.message = wevt::FormatEventMessage(event_handle, provider_wide);
  }

  return record;
}

const char* OrUnavailable(const std::string& value) {
  return value.empty() ? "(unavailable)" : value.c_str();
}

}  // namespace

CollectResult<std::vector<EventRecord>> EventLogCollector::CollectLatest(
    const std::wstring& channel,
    std::size_t limit) const {
  if (channel.empty()) {
    return CollectResult<std::vector<EventRecord>>::Failure(
        "Channel name is empty");
  }
  if (limit == 0) {
    return CollectResult<std::vector<EventRecord>>::Success({});
  }

  DWORD error = ERROR_SUCCESS;
  wevt::EvtHandle query =
      wevt::QueryChannel(channel, /*reverse_direction=*/true, &error);
  if (!query) {
    return CollectResult<std::vector<EventRecord>>::Failure(
        "EvtQuery failed for channel '" + wevt::WideToUtf8(channel) + "': " +
        wevt::FormatWin32Error(error));
  }

  wevt::EvtHandle context = wevt::CreateSystemRenderContext(&error);
  if (!context) {
    return CollectResult<std::vector<EventRecord>>::Failure(
        "EvtCreateRenderContext failed: " + wevt::FormatWin32Error(error));
  }

  std::vector<EventRecord> events;
  events.reserve(limit);

  // EvtQueryReverseDirection yields newest-first; collect until `limit`.
  while (events.size() < limit) {
    const DWORD batch_size = static_cast<DWORD>(
        std::min<std::size_t>(64, limit - events.size()));
    error = ERROR_SUCCESS;
    std::vector<wevt::EvtHandle> batch =
        wevt::NextEvents(query.get(), batch_size, &error);

    if (batch.empty()) {
      if (error == ERROR_NO_MORE_ITEMS || error == ERROR_TIMEOUT ||
          error == ERROR_SUCCESS) {
        break;
      }
      if (!events.empty()) {
        Logger::Instance().Warn(
            "EventLogCollector",
            "EvtNext ended early: " + wevt::FormatWin32Error(error));
        break;
      }
      return CollectResult<std::vector<EventRecord>>::Failure(
          "EvtNext failed: " + wevt::FormatWin32Error(error));
    }

    for (wevt::EvtHandle& event_handle : batch) {
      if (events.size() >= limit) {
        break;
      }

      std::vector<BYTE> buffer;
      DWORD render_error = ERROR_SUCCESS;
      DWORD property_count = 0;
      if (!wevt::RenderSystemValues(context.get(), event_handle.get(), &buffer,
                                    &property_count, &render_error)) {
        Logger::Instance().Warn(
            "EventLogCollector",
            "Skipping event — render failed: " +
                wevt::FormatWin32Error(render_error));
        continue;
      }

      if (property_count == 0 || buffer.size() < sizeof(EVT_VARIANT)) {
        Logger::Instance().Warn("EventLogCollector",
                                "Skipping event — empty render buffer");
        continue;
      }

      const auto* properties =
          reinterpret_cast<const EVT_VARIANT*>(buffer.data());

      try {
        events.push_back(ParseSystemProperties(properties, property_count,
                                               event_handle.get()));
      } catch (...) {
        Logger::Instance().Warn("EventLogCollector",
                                "Skipping event — unexpected parse failure");
      }
    }
  }

  Logger::Instance().Info(
      "EventLogCollector",
      "Collected " + std::to_string(events.size()) + " events from " +
          wevt::WideToUtf8(channel));

  return CollectResult<std::vector<EventRecord>>::Success(std::move(events));
}

std::optional<EventRecord> EventLogCollector::ParseEvtHandle(
    void* event_handle,
    void* system_render_context) {
  if (event_handle == nullptr || system_render_context == nullptr) {
    return std::nullopt;
  }

  std::vector<BYTE> buffer;
  DWORD render_error = ERROR_SUCCESS;
  DWORD property_count = 0;
  if (!wevt::RenderSystemValues(static_cast<EVT_HANDLE>(system_render_context),
                                static_cast<EVT_HANDLE>(event_handle), &buffer,
                                &property_count, &render_error)) {
    return std::nullopt;
  }
  if (property_count == 0 || buffer.size() < sizeof(EVT_VARIANT)) {
    return std::nullopt;
  }

  const auto* properties = reinterpret_cast<const EVT_VARIANT*>(buffer.data());
  try {
    return ParseSystemProperties(properties, property_count,
                                 static_cast<EVT_HANDLE>(event_handle));
  } catch (...) {
    return std::nullopt;
  }
}

void EventLogCollector::PrintToConsole(const std::vector<EventRecord>& events) {
  // Prefer UTF-8 so localized Event Log messages render correctly.
  SetConsoleOutputCP(CP_UTF8);

  std::cout
      << "\n========== Event Log Collector (System, newest first) ==========\n"
      << "Count: " << events.size() << "\n\n";

  std::size_t index = 0;
  for (const EventRecord& e : events) {
    ++index;
    std::cout << "--- #" << index << " ---\n"
              << "Timestamp : "
              << (e.timestamp_utc ? *e.timestamp_utc : "(unavailable)") << "\n"
              << "Provider  : " << OrUnavailable(e.provider_name) << "\n"
              << "Event ID  : "
              << (e.event_id ? std::to_string(*e.event_id) : "(unavailable)")
              << "\n"
              << "Level     : " << EventLevelName(e.level) << "\n"
              << "Channel   : " << OrUnavailable(e.channel) << "\n"
              << "Computer  : " << OrUnavailable(e.computer_name) << "\n"
              << "Message   : " << OrUnavailable(e.message) << "\n\n";
  }

  std::cout
      << "================================================================\n\n";
}

}  // namespace pulse
