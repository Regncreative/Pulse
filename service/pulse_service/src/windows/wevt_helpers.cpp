#include "windows/wevt_helpers.hpp"

#include <algorithm>
#include <cstdio>
#include <mutex>
#include <sstream>
#include <unordered_map>

namespace pulse {
namespace wevt {
namespace {

constexpr DWORD kRenderChunk = 4096;

[[nodiscard]] std::string SanitizeUtf8(std::string input) {
  std::string out;
  out.reserve(input.size());
  const auto* p = reinterpret_cast<const unsigned char*>(input.data());
  const auto* end = p + input.size();
  while (p < end) {
    const unsigned char c = *p;
    if (c <= 0x7F) {
      if (c == '\t' || c == '\n' || c == '\r' || c >= 0x20) {
        out.push_back(static_cast<char>(c));
      } else {
        out.push_back(' ');
      }
      ++p;
      continue;
    }
    int need = 0;
    if ((c & 0xE0) == 0xC0) {
      need = 1;
    } else if ((c & 0xF0) == 0xE0) {
      need = 2;
    } else if ((c & 0xF8) == 0xF0) {
      need = 3;
    } else {
      out.append("\xEF\xBF\xBD");  // U+FFFD
      ++p;
      continue;
    }
    if (p + need >= end) {
      out.append("\xEF\xBF\xBD");
      break;
    }
    bool ok = true;
    for (int i = 1; i <= need; ++i) {
      if ((p[i] & 0xC0) != 0x80) {
        ok = false;
        break;
      }
    }
    if (!ok) {
      out.append("\xEF\xBF\xBD");
      ++p;
      continue;
    }
    out.append(reinterpret_cast<const char*>(p), static_cast<size_t>(need + 1));
    p += need + 1;
  }
  return out;
}

[[nodiscard]] std::string AnsiToUtf8(const char* value) {
  if (value == nullptr || value[0] == '\0') {
    return {};
  }
  const int wide_needed =
      MultiByteToWideChar(CP_ACP, 0, value, -1, nullptr, 0);
  if (wide_needed <= 1) {
    return SanitizeUtf8(std::string(value));
  }
  std::wstring wide(static_cast<size_t>(wide_needed - 1), L'\0');
  MultiByteToWideChar(CP_ACP, 0, value, -1, wide.data(), wide_needed);
  return WideToUtf8(wide);
}

/// Cache EvtOpenPublisherMetadata — opening per event made 100-event snapshots
/// take >30s and trip the Flutter IPC timeout.
class PublisherMetadataCache {
 public:
  EVT_HANDLE Get(const std::wstring& provider_name) {
    std::lock_guard<std::mutex> lock(mutex_);
    const auto it = cache_.find(provider_name);
    if (it != cache_.end()) {
      return it->second.get();
    }
    EVT_HANDLE raw = EvtOpenPublisherMetadata(
        nullptr, provider_name.c_str(), nullptr, 0, 0);
    if (raw == nullptr) {
      return nullptr;
    }
    auto [inserted, _] =
        cache_.emplace(provider_name, EvtHandle{raw});
    return inserted->second.get();
  }

 private:
  std::mutex mutex_;
  std::unordered_map<std::wstring, EvtHandle> cache_;
};

PublisherMetadataCache& SharedPublisherCache() {
  static PublisherMetadataCache cache;
  return cache;
}

}  // namespace

std::string WideToUtf8(const wchar_t* value) {
  if (value == nullptr || value[0] == L'\0') {
    return {};
  }
  // Prefer strict UTF-8; fall back + sanitize if Event Log text has bad
  // surrogates (Flutter utf8.decode would otherwise fail the snapshot).
  const DWORD flags = WC_ERR_INVALID_CHARS;
  int needed = WideCharToMultiByte(CP_UTF8, flags, value, -1, nullptr, 0,
                                   nullptr, nullptr);
  if (needed <= 1) {
    needed = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0, nullptr,
                                 nullptr);
    if (needed <= 1) {
      return {};
    }
    std::string out(static_cast<size_t>(needed - 1), '\0');
    WideCharToMultiByte(CP_UTF8, 0, value, -1, out.data(), needed, nullptr,
                        nullptr);
    return SanitizeUtf8(out);
  }
  std::string out(static_cast<size_t>(needed - 1), '\0');
  WideCharToMultiByte(CP_UTF8, flags, value, -1, out.data(), needed, nullptr,
                      nullptr);
  return out;
}

std::string WideToUtf8(const std::wstring& value) {
  return WideToUtf8(value.c_str());
}

std::string FormatWin32Error(DWORD error_code) {
  wchar_t* buffer = nullptr;
  const DWORD flags = FORMAT_MESSAGE_ALLOCATE_BUFFER |
                      FORMAT_MESSAGE_FROM_SYSTEM |
                      FORMAT_MESSAGE_IGNORE_INSERTS;
  const DWORD length = FormatMessageW(
      flags, nullptr, error_code, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
      reinterpret_cast<LPWSTR>(&buffer), 0, nullptr);

  std::ostringstream oss;
  oss << "Win32 error " << error_code;
  if (length > 0 && buffer != nullptr) {
    std::wstring message(buffer, length);
    while (!message.empty() &&
           (message.back() == L'\r' || message.back() == L'\n' ||
            message.back() == L' ')) {
      message.pop_back();
    }
    oss << ": " << WideToUtf8(message);
  }
  if (buffer != nullptr) {
    LocalFree(buffer);
  }
  return oss.str();
}

std::string FileTimeToIso8601Utc(const FILETIME& file_time) {
  SYSTEMTIME utc{};
  if (!FileTimeToSystemTime(&file_time, &utc)) {
    return {};
  }
  char buffer[40] = {};
  // Milliseconds from FILETIME: 100-ns ticks → ms within the second.
  ULARGE_INTEGER ticks{};
  ticks.LowPart = file_time.dwLowDateTime;
  ticks.HighPart = file_time.dwHighDateTime;
  const unsigned ms =
      static_cast<unsigned>((ticks.QuadPart / 10000ULL) % 1000ULL);

  std::snprintf(buffer, sizeof(buffer),
                "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ", utc.wYear, utc.wMonth,
                utc.wDay, utc.wHour, utc.wMinute, utc.wSecond, ms);
  return std::string(buffer);
}

std::int64_t FileTimeToUnixMs(const FILETIME& file_time) {
  ULARGE_INTEGER ticks{};
  ticks.LowPart = file_time.dwLowDateTime;
  ticks.HighPart = file_time.dwHighDateTime;
  constexpr ULONGLONG kEpochDiff = 116444736000000000ULL;
  if (ticks.QuadPart < kEpochDiff) {
    return 0;
  }
  return static_cast<std::int64_t>((ticks.QuadPart - kEpochDiff) / 10000ULL);
}

std::string VariantToUtf8String(const EVT_VARIANT& variant) {
  if (variant.Type == EvtVarTypeNull) {
    return {};
  }
  if (variant.Type == EvtVarTypeString && variant.StringVal != nullptr) {
    return WideToUtf8(variant.StringVal);
  }
  if (variant.Type == EvtVarTypeAnsiString && variant.AnsiStringVal != nullptr) {
    return AnsiToUtf8(variant.AnsiStringVal);
  }
  return {};
}

EvtHandle QueryChannel(const std::wstring& channel, bool reverse_direction,
                       DWORD* out_error) {
  DWORD flags = EvtQueryChannelPath;
  if (reverse_direction) {
    flags |= EvtQueryReverseDirection;
  } else {
    flags |= EvtQueryForwardDirection;
  }

  EVT_HANDLE raw =
      EvtQuery(nullptr, channel.c_str(), L"*", flags);
  if (raw == nullptr) {
    if (out_error != nullptr) {
      *out_error = GetLastError();
    }
    return EvtHandle{};
  }
  if (out_error != nullptr) {
    *out_error = ERROR_SUCCESS;
  }
  return EvtHandle{raw};
}

std::vector<EvtHandle> NextEvents(EVT_HANDLE query, DWORD max_events,
                                  DWORD* out_error) {
  std::vector<EvtHandle> result;
  if (query == nullptr || max_events == 0) {
    if (out_error != nullptr) {
      *out_error = ERROR_INVALID_PARAMETER;
    }
    return result;
  }

  std::vector<EVT_HANDLE> batch(max_events, nullptr);
  DWORD returned = 0;
  if (!EvtNext(query, max_events, batch.data(), INFINITE, 0, &returned)) {
    const DWORD err = GetLastError();
    if (out_error != nullptr) {
      *out_error = err;
    }
    // ERROR_NO_MORE_ITEMS / ERROR_TIMEOUT are normal end-of-results.
    return result;
  }

  if (out_error != nullptr) {
    *out_error = ERROR_SUCCESS;
  }
  result.reserve(returned);
  for (DWORD i = 0; i < returned; ++i) {
    result.emplace_back(batch[i]);
    batch[i] = nullptr;
  }
  return result;
}

EvtHandle CreateSystemRenderContext(DWORD* out_error) {
  EVT_HANDLE raw =
      EvtCreateRenderContext(0, nullptr, EvtRenderContextSystem);
  if (raw == nullptr) {
    if (out_error != nullptr) {
      *out_error = GetLastError();
    }
    return EvtHandle{};
  }
  if (out_error != nullptr) {
    *out_error = ERROR_SUCCESS;
  }
  return EvtHandle{raw};
}

bool RenderSystemValues(EVT_HANDLE context, EVT_HANDLE event,
                        std::vector<BYTE>* buffer, DWORD* out_property_count,
                        DWORD* out_error) {
  if (buffer == nullptr || context == nullptr || event == nullptr) {
    if (out_error != nullptr) {
      *out_error = ERROR_INVALID_PARAMETER;
    }
    return false;
  }

  buffer->resize(kRenderChunk);
  DWORD used = 0;
  DWORD property_count = 0;
  if (EvtRender(context, event, EvtRenderEventValues,
                static_cast<DWORD>(buffer->size()), buffer->data(), &used,
                &property_count)) {
    buffer->resize(used);
    if (out_property_count != nullptr) {
      *out_property_count = property_count;
    }
    if (out_error != nullptr) {
      *out_error = ERROR_SUCCESS;
    }
    return true;
  }

  DWORD err = GetLastError();
  if (err == ERROR_INSUFFICIENT_BUFFER) {
    buffer->resize((std::max)(used, kRenderChunk));
    used = 0;
    property_count = 0;
    if (EvtRender(context, event, EvtRenderEventValues,
                  static_cast<DWORD>(buffer->size()), buffer->data(), &used,
                  &property_count)) {
      buffer->resize(used);
      if (out_property_count != nullptr) {
        *out_property_count = property_count;
      }
      if (out_error != nullptr) {
        *out_error = ERROR_SUCCESS;
      }
      return true;
    }
    err = GetLastError();
  }

  if (out_error != nullptr) {
    *out_error = err;
  }
  return false;
}

std::string FormatEventMessage(EVT_HANDLE event,
                               const std::wstring& provider_name) {
  if (event == nullptr || provider_name.empty()) {
    return {};
  }

  EVT_HANDLE metadata = SharedPublisherCache().Get(provider_name);
  if (metadata == nullptr) {
    return {};
  }

  DWORD used = 0;
  EvtFormatMessage(metadata, event, 0, 0, nullptr, EvtFormatMessageEvent, 0,
                   nullptr, &used);
  if (used == 0) {
    return {};
  }

  std::wstring buffer(used, L'\0');
  if (!EvtFormatMessage(metadata, event, 0, 0, nullptr, EvtFormatMessageEvent,
                        used, buffer.data(), &used)) {
    return {};
  }

  // EvtFormatMessage includes the terminating null in `used`.
  if (used > 0 && buffer[used - 1] == L'\0') {
    buffer.resize(used - 1);
  } else {
    buffer.resize(used);
  }

  // Keep line breaks for the details panel; sanitize for UTF-8 safety.
  return SanitizeUtf8(WideToUtf8(buffer));
}

}  // namespace wevt
}  // namespace pulse
