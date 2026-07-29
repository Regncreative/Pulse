#pragma once

#include <string>

namespace pulse {

enum class ErrorCode : int {
  Ok = 0,
  Unknown = 1,
  IpcProtocol = 2,
  IpcTimeout = 3,
  IpcDisconnected = 4,
  IncompatibleVersion = 5,
  ConfigInvalid = 6,
  Internal = 99,
};

inline const char* ErrorCodeName(ErrorCode code) {
  switch (code) {
    case ErrorCode::Ok:
      return "OK";
    case ErrorCode::IpcProtocol:
      return "IPC_PROTOCOL";
    case ErrorCode::IpcTimeout:
      return "IPC_TIMEOUT";
    case ErrorCode::IpcDisconnected:
      return "IPC_DISCONNECTED";
    case ErrorCode::IncompatibleVersion:
      return "INCOMPATIBLE_VERSION";
    case ErrorCode::ConfigInvalid:
      return "CONFIG_INVALID";
    case ErrorCode::Internal:
      return "INTERNAL";
    default:
      return "UNKNOWN";
  }
}

struct ErrorInfo {
  ErrorCode code = ErrorCode::Unknown;
  std::string message;
  std::string technical_detail;
  std::string component;
};

}  // namespace pulse
