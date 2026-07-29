#pragma once

#include <mutex>
#include <string>

namespace pulse {

enum class LogLevel { Debug, Info, Warn, Error, Fatal };

class Logger {
 public:
  static Logger& Instance();

  void SetLevel(LogLevel level);
  void SetLogDirectory(const std::wstring& dir);
  void Log(LogLevel level, const std::string& component, const std::string& message);

  void Debug(const std::string& component, const std::string& message);
  void Info(const std::string& component, const std::string& message);
  void Warn(const std::string& component, const std::string& message);
  void Error(const std::string& component, const std::string& message);

 private:
  Logger() = default;
  LogLevel level_ = LogLevel::Info;
  std::wstring log_dir_;
  std::mutex mu_;
};

}  // namespace pulse
