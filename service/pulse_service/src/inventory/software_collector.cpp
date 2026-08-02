#include "inventory/software_collector.hpp"

#include "windows/wevt_helpers.hpp"

#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>

#include <algorithm>
#include <cctype>
#include <unordered_set>
#include <vector>

namespace pulse::inventory {
namespace {

constexpr wchar_t kUninstall64[] =
    L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall";
constexpr wchar_t kUninstall32[] =
    L"SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall";

bool LooksLikeProductCode(const std::wstring& key) {
  // {XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}
  if (key.size() != 38) return false;
  if (key[0] != L'{' || key[37] != L'}') return false;
  static const int dashes[] = {9, 14, 19, 24};
  for (int d : dashes) {
    if (key[static_cast<size_t>(d)] != L'-') return false;
  }
  for (size_t i = 1; i < 37; ++i) {
    if (i == 9 || i == 14 || i == 19 || i == 24) continue;
    const wchar_t c = key[i];
    const bool hex = (c >= L'0' && c <= L'9') || (c >= L'A' && c <= L'F') ||
                     (c >= L'a' && c <= L'f');
    if (!hex) return false;
  }
  return true;
}

std::string AsciiUpper(std::string s) {
  for (char& c : s) {
    c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
  }
  return s;
}

std::wstring ReadRegString(HKEY key, const wchar_t* value_name) {
  wchar_t buffer[1024]{};
  DWORD type = 0;
  DWORD size = sizeof(buffer);
  const LONG rc = RegQueryValueExW(key, value_name, nullptr, &type,
                                   reinterpret_cast<LPBYTE>(buffer), &size);
  if (rc != ERROR_SUCCESS || (type != REG_SZ && type != REG_EXPAND_SZ)) {
    return {};
  }
  return buffer;
}

DWORD ReadRegDword(HKEY key, const wchar_t* value_name, bool* present) {
  DWORD data = 0;
  DWORD type = 0;
  DWORD size = sizeof(data);
  const LONG rc = RegQueryValueExW(key, value_name, nullptr, &type,
                                   reinterpret_cast<LPBYTE>(&data), &size);
  if (rc != ERROR_SUCCESS || type != REG_DWORD) {
    if (present) *present = false;
    return 0;
  }
  if (present) *present = true;
  return data;
}

bool EnumerateUninstallHive(const wchar_t* uninstall_path,
                            const char* architecture, std::uint32_t cap,
                            std::unordered_set<std::string>* seen_ids,
                            std::vector<ipc::InventorySoftwareEntry>* out,
                            bool* truncated, bool* access_denied,
                            bool* open_failed) {
  HKEY root = nullptr;
  const LONG open_rc =
      RegOpenKeyExW(HKEY_LOCAL_MACHINE, uninstall_path, 0,
                    KEY_READ | KEY_ENUMERATE_SUB_KEYS, &root);
  if (open_rc == ERROR_ACCESS_DENIED) {
    *access_denied = true;
    return false;
  }
  if (open_rc != ERROR_SUCCESS) {
    // WOW6432Node may be absent on pure 32-bit Windows — not fatal.
    if (open_rc == ERROR_FILE_NOT_FOUND) {
      return true;
    }
    *open_failed = true;
    return false;
  }

  DWORD index = 0;
  wchar_t subkey_name[256];
  while (true) {
    if (out->size() >= cap) {
      *truncated = true;
      break;
    }
    DWORD name_len = static_cast<DWORD>(std::size(subkey_name));
    const LONG enum_rc =
        RegEnumKeyExW(root, index++, subkey_name, &name_len, nullptr, nullptr,
                      nullptr, nullptr);
    if (enum_rc == ERROR_NO_MORE_ITEMS) {
      break;
    }
    if (enum_rc != ERROR_SUCCESS) {
      continue;
    }

    HKEY sub = nullptr;
    if (RegOpenKeyExW(root, subkey_name, 0, KEY_READ, &sub) != ERROR_SUCCESS) {
      continue;
    }

    const std::wstring display_name_w = ReadRegString(sub, L"DisplayName");
    if (display_name_w.empty()) {
      RegCloseKey(sub);
      continue;
    }

    ipc::InventorySoftwareEntry entry;
    entry.display_name = wevt::WideToUtf8(display_name_w.c_str());
    entry.version = wevt::WideToUtf8(ReadRegString(sub, L"DisplayVersion").c_str());
    entry.publisher = wevt::WideToUtf8(ReadRegString(sub, L"Publisher").c_str());
    entry.install_date =
        wevt::WideToUtf8(ReadRegString(sub, L"InstallDate").c_str());
    entry.install_location =
        wevt::WideToUtf8(ReadRegString(sub, L"InstallLocation").c_str());
    entry.architecture = architecture;

    bool size_present = false;
    const DWORD size_kb = ReadRegDword(sub, L"EstimatedSize", &size_present);
    if (size_present) {
      entry.has_estimated_size = true;
      entry.estimated_size_bytes =
          static_cast<uint64_t>(size_kb) * 1024ull;
    }

    bool sys_present = false;
    const DWORD sys = ReadRegDword(sub, L"SystemComponent", &sys_present);
    entry.system_component = sys_present && sys != 0;

    const std::wstring key_w(subkey_name);
    if (LooksLikeProductCode(key_w)) {
      entry.id = AsciiUpper(wevt::WideToUtf8(key_w.c_str()));
    } else {
      entry.id = std::string("uninstall:") + architecture + ":" +
                 wevt::WideToUtf8(key_w.c_str());
    }

    RegCloseKey(sub);

    if (!seen_ids->insert(entry.id).second) {
      continue;
    }
    out->push_back(std::move(entry));
  }

  RegCloseKey(root);
  return true;
}

}  // namespace

SoftwareCollector::Result SoftwareCollector::Collect(std::uint32_t limit) {
  Result out;
  const std::uint32_t cap =
      limit == 0 ? kDefaultLimit : (limit > kDefaultLimit ? kDefaultLimit : limit);

  std::unordered_set<std::string> seen;
  bool truncated = false;
  bool access_denied = false;
  bool open_failed = false;
  bool any_hive_ok = false;

  if (EnumerateUninstallHive(kUninstall64, "x64", cap, &seen, &out.entries,
                             &truncated, &access_denied, &open_failed)) {
    any_hive_ok = true;
  }
  if (!truncated) {
    if (EnumerateUninstallHive(kUninstall32, "x86", cap, &seen, &out.entries,
                               &truncated, &access_denied, &open_failed)) {
      any_hive_ok = true;
    }
  } else {
    // Still try 32-bit only for honesty of truncation flag already set.
  }

  out.truncated = truncated;

  if (access_denied && out.entries.empty()) {
    out.status = ipc::InventoryStatus::AccessDenied;
    out.status_detail = "HKLM Uninstall registry access denied";
    return out;
  }
  if (!any_hive_ok && open_failed) {
    out.status = ipc::InventoryStatus::Error;
    out.status_detail = "Failed to open HKLM Uninstall registry keys";
    return out;
  }
  if (out.entries.empty() && !any_hive_ok) {
    out.status = ipc::InventoryStatus::Error;
    out.status_detail = "No Uninstall registry hives available";
    return out;
  }

  std::sort(out.entries.begin(), out.entries.end(),
            [](const ipc::InventorySoftwareEntry& a,
               const ipc::InventorySoftwareEntry& b) {
              return a.display_name < b.display_name;
            });

  if (out.truncated) {
    out.status = ipc::InventoryStatus::Partial;
    out.status_detail =
        "Software list truncated at collector limit; HKCU and Store apps omitted";
  } else {
    out.status = ipc::InventoryStatus::Available;
    out.status_detail =
        "Machine-wide Uninstall registry only; HKCU and Store apps omitted";
  }
  return out;
}

}  // namespace pulse::inventory
