#pragma once

#include "collector/collector.hpp"
#include "ipc/ipc_server.hpp"
#include "util/config.hpp"

#include <atomic>
#include <memory>
#include <string>

namespace pulse {

class ServiceCore {
 public:
  bool Initialize(const ServiceConfig& config);
  bool Start();
  void Stop();
  bool IsRunning() const { return running_; }
  void SetRunMode(std::string mode);

 private:
  ServiceConfig config_;
  std::unique_ptr<Collector> collector_;
  std::unique_ptr<IpcServer> ipc_;
  std::atomic<bool> running_{false};
};

int RunConsoleMode(int argc, wchar_t** argv);
int RunServiceMode();
int InstallService();
int UninstallService();

}  // namespace pulse
