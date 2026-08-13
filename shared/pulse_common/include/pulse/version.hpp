#pragma once

#include <cstdint>
#include <string>

namespace pulse {

struct VersionInfo {
  int major = 1;
  int minor = 1;
  int patch = 0;
  /// Optional prerelease / channel label (empty for stable).
  const char* label = "";

  std::string ToString() const {
    std::string s = std::to_string(major) + "." + std::to_string(minor) + "." +
                    std::to_string(patch);
    if (label != nullptr && label[0] != '\0') {
      s.push_back('-');
      s += label;
    }
    return s;
  }
};

inline VersionInfo ServiceVersion() { return {}; }

inline VersionInfo ProtocolVersionInfo() {
  return VersionInfo{1, 0, 0, "v1"};
}

}  // namespace pulse
