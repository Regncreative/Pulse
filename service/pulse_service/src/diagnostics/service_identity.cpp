#include "diagnostics/service_identity.hpp"

#include "pulse/constants.hpp"
#include "windows/wevt_helpers.hpp"

#include <mutex>
#include <string>
#include <vector>

#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
#include <bcrypt.h>

#pragma comment(lib, "bcrypt.lib")

namespace pulse {
namespace diagnostics {
namespace {

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return {};
  const int n = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(),
                                    static_cast<int>(utf8.size()), nullptr, 0);
  if (n <= 0) return {};
  std::wstring out(static_cast<size_t>(n), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()),
                      out.data(), n);
  return out;
}

std::wstring NormalizePathWide(const std::wstring& path) {
  if (path.empty()) return {};
  wchar_t buf[MAX_PATH * 4];
  const DWORD n = GetFullPathNameW(
      path.c_str(), static_cast<DWORD>(sizeof(buf) / sizeof(buf[0])), buf,
      nullptr);
  if (n == 0 || n >= (sizeof(buf) / sizeof(buf[0]))) return path;
  return std::wstring(buf, n);
}

std::wstring ExeFromImagePath(const std::wstring& image_path) {
  std::wstring s = image_path;
  while (!s.empty() && (s.front() == L' ' || s.front() == L'\t')) {
    s.erase(s.begin());
  }
  if (s.empty()) return {};

  std::wstring path;
  if (s.front() == L'"') {
    const auto end = s.find(L'"', 1);
    if (end == std::wstring::npos || end <= 1) return {};
    path = s.substr(1, end - 1);
  } else {
    const auto space = s.find(L' ');
    path = space == std::wstring::npos ? s : s.substr(0, space);
  }
  return path;
}

std::string ComputeFileSha256Hex(const std::wstring& path) {
  HANDLE file =
      CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                  nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return {};

  BCRYPT_ALG_HANDLE alg = nullptr;
  BCRYPT_HASH_HANDLE hash = nullptr;
  std::string result;
  DWORD obj_len = 0;
  DWORD data_len = 0;
  DWORD hash_len = 0;

  auto cleanup = [&]() {
    if (hash) BCryptDestroyHash(hash);
    if (alg) BCryptCloseAlgorithmProvider(alg, 0);
    CloseHandle(file);
  };

  if (BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, nullptr, 0) !=
      0) {
    cleanup();
    return {};
  }
  if (BCryptGetProperty(alg, BCRYPT_OBJECT_LENGTH,
                        reinterpret_cast<PUCHAR>(&obj_len), sizeof(obj_len),
                        &data_len, 0) != 0 ||
      BCryptGetProperty(alg, BCRYPT_HASH_LENGTH,
                        reinterpret_cast<PUCHAR>(&hash_len), sizeof(hash_len),
                        &data_len, 0) != 0) {
    cleanup();
    return {};
  }

  std::vector<UCHAR> obj(obj_len);
  std::vector<UCHAR> digest(hash_len);
  if (BCryptCreateHash(alg, &hash, obj.data(), obj_len, nullptr, 0, 0) != 0) {
    cleanup();
    return {};
  }

  std::vector<UCHAR> chunk(64 * 1024);
  for (;;) {
    DWORD read = 0;
    if (!ReadFile(file, chunk.data(), static_cast<DWORD>(chunk.size()), &read,
                  nullptr)) {
      cleanup();
      return {};
    }
    if (read == 0) break;
    if (BCryptHashData(hash, chunk.data(), read, 0) != 0) {
      cleanup();
      return {};
    }
  }

  if (BCryptFinishHash(hash, digest.data(), hash_len, 0) != 0) {
    cleanup();
    return {};
  }

  static constexpr char kHex[] = "0123456789abcdef";
  result.reserve(static_cast<size_t>(hash_len) * 2);
  for (DWORD i = 0; i < hash_len; ++i) {
    result.push_back(kHex[(digest[i] >> 4) & 0xF]);
    result.push_back(kHex[digest[i] & 0xF]);
  }
  cleanup();
  return result;
}

}  // namespace

std::string ExecutablePath() {
  wchar_t path[MAX_PATH * 4];
  const DWORD cap = static_cast<DWORD>(sizeof(path) / sizeof(path[0]));
  const DWORD n = GetModuleFileNameW(nullptr, path, cap);
  if (n == 0 || n >= cap) return {};
  return wevt::WideToUtf8(std::wstring(path, n));
}

std::string BinarySha256Hex() {
  static std::once_flag once;
  static std::string cached;
  std::call_once(once, [] {
    wchar_t path[MAX_PATH * 4];
    const DWORD cap = static_cast<DWORD>(sizeof(path) / sizeof(path[0]));
    const DWORD n = GetModuleFileNameW(nullptr, path, cap);
    if (n == 0 || n >= cap) return;
    cached = ComputeFileSha256Hex(std::wstring(path, n));
  });
  return cached;
}

std::string InstalledServiceExePath() {
  SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
  if (!scm) return {};

  const std::wstring name = Utf8ToWide(kServiceName);
  SC_HANDLE svc =
      OpenServiceW(scm, name.c_str(), SERVICE_QUERY_CONFIG);
  if (!svc) {
    CloseServiceHandle(scm);
    return {};
  }

  DWORD needed = 0;
  QueryServiceConfigW(svc, nullptr, 0, &needed);
  if (needed == 0 || needed > 64 * 1024) {
    CloseServiceHandle(svc);
    CloseServiceHandle(scm);
    return {};
  }

  std::vector<uint8_t> buffer(needed);
  auto* config = reinterpret_cast<QUERY_SERVICE_CONFIGW*>(buffer.data());
  if (!QueryServiceConfigW(svc, config, needed, &needed)) {
    CloseServiceHandle(svc);
    CloseServiceHandle(scm);
    return {};
  }

  std::string path;
  if (config->lpBinaryPathName) {
    path = wevt::WideToUtf8(ExeFromImagePath(config->lpBinaryPathName));
  }
  CloseServiceHandle(svc);
  CloseServiceHandle(scm);
  return path;
}

std::string ScmStateLabel() {
  SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
  if (!scm) return "Unknown";

  const std::wstring name = Utf8ToWide(kServiceName);
  SC_HANDLE svc =
      OpenServiceW(scm, name.c_str(), SERVICE_QUERY_STATUS);
  if (!svc) {
    const DWORD err = GetLastError();
    CloseServiceHandle(scm);
    if (err == ERROR_SERVICE_DOES_NOT_EXIST) return "NotInstalled";
    return "Unknown";
  }

  SERVICE_STATUS_PROCESS ssp{};
  DWORD bytes = 0;
  std::string label = "Unknown";
  if (QueryServiceStatusEx(svc, SC_STATUS_PROCESS_INFO,
                           reinterpret_cast<LPBYTE>(&ssp), sizeof(ssp),
                           &bytes)) {
    switch (ssp.dwCurrentState) {
      case SERVICE_STOPPED:
        label = "Stopped";
        break;
      case SERVICE_START_PENDING:
        label = "StartPending";
        break;
      case SERVICE_STOP_PENDING:
        label = "StopPending";
        break;
      case SERVICE_RUNNING:
        label = "Running";
        break;
      case SERVICE_CONTINUE_PENDING:
        label = "ContinuePending";
        break;
      case SERVICE_PAUSE_PENDING:
        label = "PausePending";
        break;
      case SERVICE_PAUSED:
        label = "Paused";
        break;
      default:
        label = "Unknown";
        break;
    }
  }
  CloseServiceHandle(svc);
  CloseServiceHandle(scm);
  return label;
}

std::string ScmStartupTypeLabel() {
  SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
  if (!scm) return "Unknown";

  const std::wstring name = Utf8ToWide(kServiceName);
  SC_HANDLE svc =
      OpenServiceW(scm, name.c_str(), SERVICE_QUERY_CONFIG);
  if (!svc) {
    const DWORD err = GetLastError();
    CloseServiceHandle(scm);
    if (err == ERROR_SERVICE_DOES_NOT_EXIST) return "NotInstalled";
    return "Unknown";
  }

  DWORD needed = 0;
  QueryServiceConfigW(svc, nullptr, 0, &needed);
  if (needed == 0 || needed > 64 * 1024) {
    CloseServiceHandle(svc);
    CloseServiceHandle(scm);
    return "Unknown";
  }

  std::vector<uint8_t> buffer(needed);
  auto* config = reinterpret_cast<QUERY_SERVICE_CONFIGW*>(buffer.data());
  std::string label = "Unknown";
  if (QueryServiceConfigW(svc, config, needed, &needed)) {
    switch (config->dwStartType) {
      case SERVICE_BOOT_START:
        label = "Boot";
        break;
      case SERVICE_SYSTEM_START:
        label = "System";
        break;
      case SERVICE_AUTO_START:
        label = "Automatic";
        break;
      case SERVICE_DEMAND_START:
        label = "Manual";
        break;
      case SERVICE_DISABLED:
        label = "Disabled";
        break;
      default:
        label = "Unknown";
        break;
    }
  }
  CloseServiceHandle(svc);
  CloseServiceHandle(scm);
  return label;
}

bool PathsMatch(const std::string& a, const std::string& b) {
  if (a.empty() || b.empty()) return false;
  const std::wstring wa = NormalizePathWide(Utf8ToWide(a));
  const std::wstring wb = NormalizePathWide(Utf8ToWide(b));
  if (wa.empty() || wb.empty()) return false;
  return _wcsicmp(wa.c_str(), wb.c_str()) == 0;
}

}  // namespace diagnostics
}  // namespace pulse
