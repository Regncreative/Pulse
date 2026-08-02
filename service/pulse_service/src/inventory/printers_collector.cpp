#include "inventory/printers_collector.hpp"

#include "windows/wevt_helpers.hpp"

#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
#include <winspool.h>

#include <vector>

#pragma comment(lib, "winspool.lib")

namespace pulse::inventory {

PrintersCollector::Result PrintersCollector::Collect(std::uint32_t limit) {
  Result out;
  const std::uint32_t cap =
      limit == 0 ? kDefaultLimit : (limit > kDefaultLimit ? kDefaultLimit : limit);

  DWORD needed = 0;
  DWORD returned = 0;
  const DWORD flags = PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS;
  EnumPrintersW(flags, nullptr, 2, nullptr, 0, &needed, &returned);
  const DWORD err = GetLastError();
  if (err == ERROR_ACCESS_DENIED) {
    out.status = ipc::InventoryStatus::AccessDenied;
    out.status_detail = "EnumPrintersW access denied";
    return out;
  }
  if (needed == 0) {
    // No printers installed is a valid empty catalog.
    out.status = ipc::InventoryStatus::Available;
    out.status_detail = "No local or connected printers";
    return out;
  }
  if (err != ERROR_INSUFFICIENT_BUFFER && err != ERROR_SUCCESS) {
    out.status = ipc::InventoryStatus::Error;
    out.status_detail = "EnumPrintersW failed";
    return out;
  }

  std::vector<BYTE> buffer(needed);
  if (!EnumPrintersW(flags, nullptr, 2, buffer.data(), needed, &needed,
                     &returned)) {
    const DWORD fail = GetLastError();
    if (fail == ERROR_ACCESS_DENIED) {
      out.status = ipc::InventoryStatus::AccessDenied;
      out.status_detail = "EnumPrintersW access denied";
      return out;
    }
    out.status = ipc::InventoryStatus::Error;
    out.status_detail = "EnumPrintersW failed";
    return out;
  }

  const auto* info = reinterpret_cast<const PRINTER_INFO_2W*>(buffer.data());
  out.entries.reserve(returned);
  for (DWORD i = 0; i < returned; ++i) {
    if (out.entries.size() >= cap) {
      out.truncated = true;
      break;
    }
    const PRINTER_INFO_2W& row = info[i];
    if (row.pPrinterName == nullptr || row.pPrinterName[0] == L'\0') {
      continue;
    }
    ipc::InventoryPrinterEntry entry;
    entry.id = wevt::WideToUtf8(row.pPrinterName);
    if (row.pPortName != nullptr) {
      entry.port_name = wevt::WideToUtf8(row.pPortName);
    }
    if (row.pDriverName != nullptr) {
      entry.driver_name = wevt::WideToUtf8(row.pDriverName);
    }
    if (row.pLocation != nullptr) {
      entry.location = wevt::WideToUtf8(row.pLocation);
    }
    if (row.pComment != nullptr) {
      entry.comment = wevt::WideToUtf8(row.pComment);
    }
    entry.attributes = row.Attributes;
    entry.has_attributes = true;
    entry.is_shared = (row.Attributes & PRINTER_ATTRIBUTE_SHARED) != 0;
    entry.is_default = (row.Attributes & PRINTER_ATTRIBUTE_DEFAULT) != 0;
    entry.is_network = (row.Attributes & PRINTER_ATTRIBUTE_NETWORK) != 0;
    out.entries.push_back(std::move(entry));
  }

  if (out.truncated) {
    out.status = ipc::InventoryStatus::Partial;
    out.status_detail = "Printer list truncated at collector limit";
  } else {
    out.status = ipc::InventoryStatus::Available;
    out.status_detail = "Local and connected printers via EnumPrintersW";
  }
  return out;
}

}  // namespace pulse::inventory
