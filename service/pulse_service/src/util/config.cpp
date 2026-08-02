#include "util/config.hpp"

#include "pulse/constants.hpp"

#include <filesystem>
#include <fstream>
#include <sstream>

#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <ShlObj.h>

namespace pulse {
namespace {

std::wstring Widen(const std::string& s) {
  if (s.empty()) return {};
  const int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                                    nullptr, 0);
  std::wstring out(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), out.data(), n);
  return out;
}

bool ExtractString(const std::string& json, const std::string& key, std::string* value) {
  const std::string pattern = "\"" + key + "\"";
  const auto pos = json.find(pattern);
  if (pos == std::string::npos) return false;
  const auto colon = json.find(':', pos);
  if (colon == std::string::npos) return false;
  const auto q1 = json.find('"', colon);
  if (q1 == std::string::npos) return false;
  const auto q2 = json.find('"', q1 + 1);
  if (q2 == std::string::npos) return false;
  *value = json.substr(q1 + 1, q2 - q1 - 1);
  return true;
}

bool ExtractBool(const std::string& json, const std::string& key, bool* value) {
  const std::string pattern = "\"" + key + "\"";
  const auto pos = json.find(pattern);
  if (pos == std::string::npos) return false;
  const auto colon = json.find(':', pos);
  if (colon == std::string::npos) return false;
  if (json.find("true", colon) < json.find(',', colon) &&
      json.find("true", colon) != std::string::npos) {
    *value = true;
    return true;
  }
  if (json.find("false", colon) != std::string::npos) {
    *value = false;
    return true;
  }
  return false;
}

}  // namespace

std::wstring DefaultProgramDataPulseDir() {
  PWSTR path = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_ProgramData, 0, nullptr, &path))) {
    return L"C:\\ProgramData\\Pulse";
  }
  std::wstring root(path);
  CoTaskMemFree(path);
  return root + L"\\Pulse";
}

ServiceConfig DefaultConfig() {
  ServiceConfig c;
  c.data_dir = DefaultProgramDataPulseDir() + L"\\data";
  c.log_dir = DefaultProgramDataPulseDir() + L"\\logs";
  c.event_log_enabled = false;
  return c;
}

bool EnsureDataDirectories(const ServiceConfig& config, std::string* error) {
  std::error_code ec;
  std::filesystem::create_directories(config.data_dir, ec);
  if (ec) {
    if (error) *error = "failed to create data dir";
    return false;
  }
  std::filesystem::create_directories(config.log_dir, ec);
  if (ec) {
    if (error) *error = "failed to create log dir";
    return false;
  }
  std::filesystem::create_directories(DefaultProgramDataPulseDir(), ec);
  return true;
}

bool WriteDefaultConfigIfMissing(const std::wstring& path, std::string* error) {
  if (std::filesystem::exists(path)) return true;
  std::error_code ec;
  std::filesystem::create_directories(std::filesystem::path(path).parent_path(), ec);
  std::ofstream f(path, std::ios::binary);
  if (!f) {
    if (error) *error = "failed to write default config";
    return false;
  }
  f << R"({
  "version": 1,
  "sources": {
    "event_log": { "enabled": false }
  },
  "ipc": {
    "pipe_name": "\\\\.\\pipe\\PulseService",
    "max_pipe_instances": 32,
    "live_queue_capacity": 1000
  },
  "logging": {
    "level": "info"
  }
}
)";
  return true;
}

bool LoadConfig(const std::wstring& path, ServiceConfig* out, std::string* error) {
  *out = DefaultConfig();
  if (!std::filesystem::exists(path)) {
    return WriteDefaultConfigIfMissing(path, error);
  }
  std::ifstream f(path, std::ios::binary);
  if (!f) {
    if (error) *error = "cannot open config";
    return false;
  }
  std::ostringstream ss;
  ss << f.rdbuf();
  const std::string json = ss.str();

  bool enabled = false;
  if (ExtractBool(json, "enabled", &enabled)) {
    // First "enabled" in file is event_log in our default layout.
    out->event_log_enabled = enabled;
  }
  // TASK-001: force Event Log off regardless of config.
  out->event_log_enabled = false;

  std::string level;
  if (ExtractString(json, "level", &level)) {
    out->log_level = level;
  }
  std::string pipe;
  if (ExtractString(json, "pipe_name", &pipe)) {
    // JSON escapes backslashes; accept both forms.
    std::string normalized;
    for (size_t i = 0; i < pipe.size(); ++i) {
      if (pipe[i] == '\\' && i + 1 < pipe.size() && pipe[i + 1] == '\\') {
        normalized.push_back('\\');
        ++i;
      } else {
        normalized.push_back(pipe[i]);
      }
    }
    out->pipe_name = Widen(normalized);
  }

  // Prefer max_pipe_instances; accept legacy max_connections key.
  auto parse_u32 = [&](const char* key, uint32_t* dest) {
    const std::string pattern = std::string("\"") + key + "\"";
    const auto pos = json.find(pattern);
    if (pos == std::string::npos) return;
    const auto colon = json.find(':', pos);
    if (colon == std::string::npos) return;
    size_t i = colon + 1;
    while (i < json.size() && (json[i] == ' ' || json[i] == '\t')) ++i;
    if (i >= json.size() || json[i] < '0' || json[i] > '9') return;
    uint32_t v = 0;
    while (i < json.size() && json[i] >= '0' && json[i] <= '9') {
      v = v * 10u + static_cast<uint32_t>(json[i] - '0');
      ++i;
    }
    if (v > 0) *dest = v;
  };
  parse_u32("max_pipe_instances", &out->max_pipe_instances);
  parse_u32("max_connections", &out->max_pipe_instances);
  if (out->max_pipe_instances < 2) out->max_pipe_instances = 2;
  if (out->max_pipe_instances > 64) out->max_pipe_instances = 64;

  return true;
}

}  // namespace pulse
