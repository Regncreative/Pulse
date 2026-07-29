#include "logging/logger.hpp"

#include <chrono>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>

#define WIN32_LEAN_AND_MEAN
#include <Windows.h>

namespace pulse {
namespace {

const char* LevelName(LogLevel level) {
  switch (level) {
    case LogLevel::Debug:
      return "debug";
    case LogLevel::Info:
      return "info";
    case LogLevel::Warn:
      return "warn";
    case LogLevel::Error:
      return "error";
    case LogLevel::Fatal:
      return "fatal";
  }
  return "info";
}

std::string EscapeJson(const std::string& s) {
  std::string out;
  out.reserve(s.size());
  for (char c : s) {
    switch (c) {
      case '\\':
        out += "\\\\";
        break;
      case '"':
        out += "\\\"";
        break;
      case '\n':
        out += "\\n";
        break;
      case '\r':
        out += "\\r";
        break;
      case '\t':
        out += "\\t";
        break;
      default:
        out += c;
        break;
    }
  }
  return out;
}

std::string UtcTimestamp() {
  using clock = std::chrono::system_clock;
  const auto now = clock::now();
  const auto t = clock::to_time_t(now);
  std::tm tm{};
  gmtime_s(&tm, &t);
  const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                      now.time_since_epoch()) %
                  1000;
  std::ostringstream oss;
  oss << std::put_time(&tm, "%Y-%m-%dT%H:%M:%S") << '.' << std::setfill('0')
      << std::setw(3) << ms.count() << 'Z';
  return oss.str();
}

}  // namespace

Logger& Logger::Instance() {
  static Logger logger;
  return logger;
}

void Logger::SetLevel(LogLevel level) { level_ = level; }

void Logger::SetLogDirectory(const std::wstring& dir) {
  std::lock_guard lock(mu_);
  log_dir_ = dir;
  std::error_code ec;
  std::filesystem::create_directories(dir, ec);
}

void Logger::Log(LogLevel level, const std::string& component,
                 const std::string& message) {
  if (static_cast<int>(level) < static_cast<int>(level_)) return;
  std::ostringstream line;
  line << "{\"timestamp\":\"" << UtcTimestamp() << "\",\"level\":\""
       << LevelName(level) << "\",\"component\":\"" << EscapeJson(component)
       << "\",\"message\":\"" << EscapeJson(message) << "\"}";
  const std::string text = line.str();

  {
    std::lock_guard lock(mu_);
    std::fwrite(text.c_str(), 1, text.size(), stderr);
    std::fwrite("\n", 1, 1, stderr);
    std::fflush(stderr);

    if (!log_dir_.empty()) {
      using clock = std::chrono::system_clock;
      const auto t = clock::to_time_t(clock::now());
      std::tm tm{};
      gmtime_s(&tm, &t);
      std::ostringstream name;
      name << "pulse-service-" << std::put_time(&tm, "%Y-%m-%d") << ".jsonl";
      const auto path = std::filesystem::path(log_dir_) / name.str();
      std::ofstream f(path, std::ios::app | std::ios::binary);
      if (f) {
        f << text << '\n';
      }
    }
  }
}

void Logger::Debug(const std::string& c, const std::string& m) {
  Log(LogLevel::Debug, c, m);
}
void Logger::Info(const std::string& c, const std::string& m) {
  Log(LogLevel::Info, c, m);
}
void Logger::Warn(const std::string& c, const std::string& m) {
  Log(LogLevel::Warn, c, m);
}
void Logger::Error(const std::string& c, const std::string& m) {
  Log(LogLevel::Error, c, m);
}

}  // namespace pulse
