#pragma once

#include <cstdint>
#include <string>
#include <utility>
#include <vector>

#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
#include <winevt.h>

namespace pulse {
namespace wevt {

/// RAII wrapper for EVT_HANDLE. Move-only; closes via EvtClose.
class EvtHandle {
 public:
  EvtHandle() = default;
  explicit EvtHandle(EVT_HANDLE handle) noexcept : handle_(handle) {}

  EvtHandle(const EvtHandle&) = delete;
  EvtHandle& operator=(const EvtHandle&) = delete;

  EvtHandle(EvtHandle&& other) noexcept : handle_(other.handle_) {
    other.handle_ = nullptr;
  }

  EvtHandle& operator=(EvtHandle&& other) noexcept {
    if (this != &other) {
      reset();
      handle_ = other.handle_;
      other.handle_ = nullptr;
    }
    return *this;
  }

  ~EvtHandle() { reset(); }

  void reset(EVT_HANDLE handle = nullptr) noexcept {
    if (handle_ != nullptr) {
      EvtClose(handle_);
    }
    handle_ = handle;
  }

  [[nodiscard]] EVT_HANDLE get() const noexcept { return handle_; }
  [[nodiscard]] explicit operator bool() const noexcept {
    return handle_ != nullptr;
  }

  /// Releases ownership without closing (rarely needed).
  EVT_HANDLE release() noexcept {
    return std::exchange(handle_, nullptr);
  }

 private:
  EVT_HANDLE handle_ = nullptr;
};

/// Converts UTF-16 to UTF-8. Empty input → empty output.
[[nodiscard]] std::string WideToUtf8(const wchar_t* value);
[[nodiscard]] std::string WideToUtf8(const std::wstring& value);

/// Formats a Win32 error code into a readable UTF-8 string.
[[nodiscard]] std::string FormatWin32Error(DWORD error_code);

/// FILETIME (UTC) → ISO-8601 UTC string ("YYYY-MM-DDTHH:MM:SS.sssZ").
[[nodiscard]] std::string FileTimeToIso8601Utc(const FILETIME& file_time);

/// FILETIME (UTC) → Unix epoch milliseconds. Returns 0 on failure.
[[nodiscard]] std::int64_t FileTimeToUnixMs(const FILETIME& file_time);

/// Reads one EVT_VARIANT string field safely (null / wrong type → empty).
[[nodiscard]] std::string VariantToUtf8String(const EVT_VARIANT& variant);

/// Probe channel readability via EvtOpenLog (does not read events).
/// Returns true when the log opens; closes the handle immediately.
[[nodiscard]] bool TryOpenChannel(const std::wstring& channel, DWORD* out_error);

/// Query a channel for events (newest first when reverse is true).
[[nodiscard]] EvtHandle QueryChannel(const std::wstring& channel,
                                     bool reverse_direction,
                                     DWORD* out_error);

/// Pull up to `max_events` event handles from an open query.
/// Each returned handle must be closed (wrapped in EvtHandle).
[[nodiscard]] std::vector<EvtHandle> NextEvents(EVT_HANDLE query,
                                                DWORD max_events,
                                                DWORD* out_error);

/// Create a render context for system properties.
[[nodiscard]] EvtHandle CreateSystemRenderContext(DWORD* out_error);

/// Render system property values for one event into a byte buffer.
/// On success, `*out_property_count` is the EVT_VARIANT count.
/// Returns false on failure; never throws.
[[nodiscard]] bool RenderSystemValues(EVT_HANDLE context,
                                       EVT_HANDLE event,
                                       std::vector<BYTE>* buffer,
                                       DWORD* out_property_count,
                                       DWORD* out_error);

/// Format the human-readable message for an event when metadata is available.
/// Returns empty string when formatting is unavailable (common, not fatal).
[[nodiscard]] std::string FormatEventMessage(EVT_HANDLE event,
                                             const std::wstring& provider_name);

/// Render the full Event XML (EvtRenderEventXml). Empty on failure.
[[nodiscard]] std::string RenderEventXml(EVT_HANDLE event);

/// GUID → canonical string (e.g. "{...}"); empty when null.
[[nodiscard]] std::string GuidToString(const GUID* guid);

/// SID → SDDL string; empty when null or conversion fails.
[[nodiscard]] std::string SidToString(PSID sid);

/// Best-effort process image basename for a live PID. Empty when unavailable.
/// Never invents a name — OpenProcess / QueryFullProcessImageName only.
[[nodiscard]] std::string TryProcessImageName(std::uint32_t process_id);

}  // namespace wevt
}  // namespace pulse
