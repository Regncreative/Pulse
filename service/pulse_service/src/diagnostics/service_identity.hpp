#pragma once

#include <string>

namespace pulse {
namespace diagnostics {

/// Absolute path of the running PulseService.exe (GetModuleFileNameW).
[[nodiscard]] std::string ExecutablePath();

/// Cached SHA-256 hex of the running binary (BCrypt). Empty on failure.
[[nodiscard]] std::string BinarySha256Hex();

/// SCM ImagePath exe for PulseService when installed; empty otherwise.
[[nodiscard]] std::string InstalledServiceExePath();

/// SCM current state label: NotInstalled / Stopped / StartPending / …
[[nodiscard]] std::string ScmStateLabel();

/// SCM start type: Automatic / Manual / Disabled / Boot / System / Unknown /
/// NotInstalled.
[[nodiscard]] std::string ScmStartupTypeLabel();

/// Case-insensitive path compare after GetFullPathNameW normalization.
[[nodiscard]] bool PathsMatch(const std::string& a, const std::string& b);

}  // namespace diagnostics
}  // namespace pulse
