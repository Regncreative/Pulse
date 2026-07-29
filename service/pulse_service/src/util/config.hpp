#pragma once

#include <string>

namespace pulse {

struct ServiceConfig {
  bool event_log_enabled = false;  // TASK-001: no Event Log yet
  size_t live_queue_capacity = 1000;
  uint32_t max_connections = 4;
  std::wstring pipe_name = L"\\\\.\\pipe\\PulseService";
  std::wstring data_dir;
  std::wstring log_dir;
  std::string log_level = "info";
};

bool LoadConfig(const std::wstring& path, ServiceConfig* out, std::string* error);
ServiceConfig DefaultConfig();
std::wstring DefaultProgramDataPulseDir();
bool EnsureDataDirectories(const ServiceConfig& config, std::string* error);
bool WriteDefaultConfigIfMissing(const std::wstring& path, std::string* error);

}  // namespace pulse
