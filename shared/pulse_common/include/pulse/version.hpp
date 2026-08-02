#pragma once

#include <cstdint>
#include <string>

namespace pulse {

struct VersionInfo {
  int major = 0;
  int minor = 2;
  int patch = 1;
  const char* label = "beta";

  std::string ToString() const {
    return std::to_string(major) + "." + std::to_string(minor) + "." +
           std::to_string(patch) + "-" + label;
  }
};

inline VersionInfo ServiceVersion() { return {}; }

inline VersionInfo ProtocolVersionInfo() {
  return VersionInfo{1, 0, 0, "v1"};
}

}  // namespace pulse
