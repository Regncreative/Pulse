#include "inventory/storage_collector.hpp"

#include "windows/wevt_helpers.hpp"

#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
#include <SetupAPI.h>
#include <cfgmgr32.h>
#include <winioctl.h>

#include <cstring>
#include <string>
#include <vector>

#pragma comment(lib, "setupapi.lib")
#pragma comment(lib, "cfgmgr32.lib")

namespace pulse::inventory {
namespace {

// GUID_DEVINTERFACE_DISK — defined without INITGUID to avoid ntddstor.h /
// poclass.h multiple-definition conflicts under MSVC (mirrors
// battery_collector.cpp's kBatteryDeviceInterface pattern).
// {53f56307-b6bf-11d0-94f2-00a0c91efb8b}
constexpr GUID kDiskDeviceInterface = {
    0x53f56307,
    0xb6bf,
    0x11d0,
    {0x94, 0xf2, 0x00, 0xa0, 0xc9, 0x1e, 0xfb, 0x8b}};

std::string TrimCopy(std::string s) {
  while (!s.empty() &&
         (s.back() == ' ' || s.back() == '\t' || s.back() == '\0')) {
    s.pop_back();
  }
  size_t i = 0;
  while (i < s.size() && (s[i] == ' ' || s[i] == '\t')) ++i;
  return s.substr(i);
}

std::string StorageBusTypeName(STORAGE_BUS_TYPE bus) {
  switch (bus) {
    case BusTypeScsi: return "SCSI";
    case BusTypeAtapi: return "ATAPI";
    case BusTypeAta: return "ATA";
    case BusType1394: return "IEEE1394";
    case BusTypeSsa: return "SSA";
    case BusTypeFibre: return "Fibre Channel";
    case BusTypeUsb: return "USB";
    case BusTypeRAID: return "RAID";
    case BusTypeiScsi: return "iSCSI";
    case BusTypeSas: return "SAS";
    case BusTypeSata: return "SATA";
    case BusTypeSd: return "SD";
    case BusTypeMmc: return "MMC";
    case BusTypeVirtual: return "Virtual";
    case BusTypeFileBackedVirtual: return "File-Backed Virtual";
    case BusTypeSpaces: return "Storage Spaces";
    case BusTypeNvme: return "NVMe";
    default: return "";
  }
}

std::string ReadRegistryPropertyString(HDEVINFO set, SP_DEVINFO_DATA* info,
                                       DWORD property) {
  wchar_t buffer[1024]{};
  DWORD type = 0;
  DWORD needed = 0;
  if (!SetupDiGetDeviceRegistryPropertyW(
          set, info, property, &type, reinterpret_cast<PBYTE>(buffer),
          sizeof(buffer), &needed)) {
    return {};
  }
  if (type == REG_SZ || type == REG_EXPAND_SZ || type == REG_MULTI_SZ) {
    return wevt::WideToUtf8(buffer);
  }
  return {};
}

std::string ReadInstanceId(HDEVINFO set, SP_DEVINFO_DATA* info) {
  wchar_t buffer[512]{};
  DWORD needed = 0;
  if (SetupDiGetDeviceInstanceIdW(set, info, buffer, 512, &needed)) {
    return wevt::WideToUtf8(buffer);
  }
  WCHAR cm_id[MAX_DEVICE_ID_LEN]{};
  if (CM_Get_Device_IDW(info->DevInst, cm_id, MAX_DEVICE_ID_LEN, 0) ==
      CR_SUCCESS) {
    return wevt::WideToUtf8(cm_id);
  }
  return {};
}

/// IOCTL enrichment for one open disk handle. Returns true if any field was
/// populated (i.e. the handle could be queried at all).
bool EnrichViaIoctl(HANDLE disk, ipc::InventoryStorageEntry* entry) {
  bool any = false;

  STORAGE_PROPERTY_QUERY device_query{};
  device_query.PropertyId = StorageDeviceProperty;
  device_query.QueryType = PropertyStandardQuery;
  std::vector<uint8_t> device_buf(4096);
  DWORD device_bytes = 0;
  bool removable_media = false;
  if (DeviceIoControl(disk, IOCTL_STORAGE_QUERY_PROPERTY, &device_query,
                      sizeof(device_query), device_buf.data(),
                      static_cast<DWORD>(device_buf.size()), &device_bytes,
                      nullptr) &&
      device_bytes >= sizeof(STORAGE_DEVICE_DESCRIPTOR)) {
    const auto* desc =
        reinterpret_cast<const STORAGE_DEVICE_DESCRIPTOR*>(device_buf.data());
    any = true;

    auto read_offset_string = [&](DWORD offset) -> std::string {
      if (offset == 0 || offset >= device_buf.size()) return {};
      const auto* s = reinterpret_cast<const char*>(device_buf.data() + offset);
      const size_t max_len = device_buf.size() - offset;
      return TrimCopy(std::string(s, strnlen(s, max_len)));
    };

    const std::string vendor = read_offset_string(desc->VendorIdOffset);
    const std::string product = read_offset_string(desc->ProductIdOffset);
    const std::string revision = read_offset_string(desc->ProductRevisionOffset);
    const std::string serial = read_offset_string(desc->SerialNumberOffset);

    if (!vendor.empty()) entry->vendor = vendor;
    if (!product.empty()) entry->model = product;
    if (!revision.empty()) entry->firmware_revision = revision;
    if (!serial.empty()) entry->serial_number = serial;

    const std::string bus_name = StorageBusTypeName(desc->BusType);
    if (!bus_name.empty()) entry->bus_type = bus_name;

    removable_media = desc->RemovableMedia != FALSE;
    entry->is_removable = removable_media;
    entry->has_is_removable = true;
  }

  STORAGE_DEVICE_NUMBER device_number{};
  DWORD number_bytes = 0;
  if (DeviceIoControl(disk, IOCTL_STORAGE_GET_DEVICE_NUMBER, nullptr, 0,
                      &device_number, sizeof(device_number), &number_bytes,
                      nullptr) &&
      number_bytes >= sizeof(device_number)) {
    any = true;
    entry->physical_drive_number =
        static_cast<uint32_t>(device_number.DeviceNumber);
    entry->has_physical_drive_number = true;
    entry->device_path =
        "\\\\.\\PhysicalDrive" + std::to_string(device_number.DeviceNumber);
  }

  GET_LENGTH_INFORMATION length_info{};
  DWORD length_bytes = 0;
  if (DeviceIoControl(disk, IOCTL_DISK_GET_LENGTH_INFO, nullptr, 0,
                      &length_info, sizeof(length_info), &length_bytes,
                      nullptr) &&
      length_bytes >= sizeof(length_info)) {
    any = true;
    entry->size_bytes = static_cast<uint64_t>(length_info.Length.QuadPart);
    entry->has_size_bytes = true;
  }

  DISK_GEOMETRY_EX geometry{};
  DWORD geometry_bytes = 0;
  if (DeviceIoControl(disk, IOCTL_DISK_GET_DRIVE_GEOMETRY_EX, nullptr, 0,
                      &geometry, sizeof(geometry), &geometry_bytes, nullptr) &&
      geometry_bytes >= sizeof(DISK_GEOMETRY)) {
    any = true;
    entry->sector_size_bytes = geometry.Geometry.BytesPerSector;
    entry->has_sector_size_bytes = true;
  }

  STORAGE_PROPERTY_QUERY seek_query{};
  seek_query.PropertyId = StorageDeviceSeekPenaltyProperty;
  seek_query.QueryType = PropertyStandardQuery;
  DEVICE_SEEK_PENALTY_DESCRIPTOR seek_desc{};
  DWORD seek_bytes = 0;
  bool has_seek_penalty = false;
  bool incurs_seek_penalty = true;
  if (DeviceIoControl(disk, IOCTL_STORAGE_QUERY_PROPERTY, &seek_query,
                      sizeof(seek_query), &seek_desc, sizeof(seek_desc),
                      &seek_bytes, nullptr) &&
      seek_bytes >= sizeof(seek_desc)) {
    any = true;
    has_seek_penalty = true;
    incurs_seek_penalty = seek_desc.IncursSeekPenalty != FALSE;
  }

  if (removable_media) {
    entry->media_type = "Removable";
  } else if (has_seek_penalty) {
    entry->media_type = incurs_seek_penalty ? "HDD" : "SSD";
  } else {
    entry->media_type = "Unknown";
  }

  STORAGE_PROPERTY_QUERY trim_query{};
  trim_query.PropertyId = StorageDeviceTrimProperty;
  trim_query.QueryType = PropertyStandardQuery;
  DEVICE_TRIM_DESCRIPTOR trim_desc{};
  DWORD trim_bytes = 0;
  if (DeviceIoControl(disk, IOCTL_STORAGE_QUERY_PROPERTY, &trim_query,
                      sizeof(trim_query), &trim_desc, sizeof(trim_desc),
                      &trim_bytes, nullptr) &&
      trim_bytes >= sizeof(trim_desc)) {
    any = true;
    entry->trim_supported = trim_desc.TrimEnabled != FALSE;
    entry->has_trim_supported = true;
  }

  std::vector<uint8_t> layout_buf(4096);
  DWORD layout_bytes = 0;
  if (DeviceIoControl(disk, IOCTL_DISK_GET_DRIVE_LAYOUT_EX, nullptr, 0,
                      layout_buf.data(), static_cast<DWORD>(layout_buf.size()),
                      &layout_bytes, nullptr) &&
      layout_bytes >= sizeof(DRIVE_LAYOUT_INFORMATION_EX)) {
    any = true;
    const auto* layout =
        reinterpret_cast<const DRIVE_LAYOUT_INFORMATION_EX*>(layout_buf.data());
    switch (layout->PartitionStyle) {
      case PARTITION_STYLE_GPT:
        entry->partition_style = "GPT";
        break;
      case PARTITION_STYLE_MBR:
        entry->partition_style = "MBR";
        break;
      case PARTITION_STYLE_RAW:
        entry->partition_style = "RAW";
        break;
      default:
        break;
    }
  }

  return any;
}

}  // namespace

StorageCollector::Result StorageCollector::Collect(std::uint32_t limit) {
  Result out;
  const std::uint32_t cap =
      limit == 0 ? kDefaultLimit : (limit > kDefaultLimit ? kDefaultLimit : limit);

  GUID iface = kDiskDeviceInterface;
  const HDEVINFO set = SetupDiGetClassDevsW(
      &iface, nullptr, nullptr, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
  if (set == INVALID_HANDLE_VALUE) {
    const DWORD err = GetLastError();
    if (err == ERROR_ACCESS_DENIED) {
      out.status = ipc::InventoryStatus::AccessDenied;
      out.status_detail = "SetupDiGetClassDevsW(GUID_DEVINTERFACE_DISK) access denied";
    } else {
      out.status = ipc::InventoryStatus::Error;
      out.status_detail = "SetupDiGetClassDevsW(GUID_DEVINTERFACE_DISK) failed";
    }
    return out;
  }

  bool any_ioctl = false;
  bool any_ioctl_attempt_failed = false;

  SP_DEVICE_INTERFACE_DATA iface_data{};
  iface_data.cbSize = sizeof(iface_data);
  for (DWORD index = 0;
       SetupDiEnumDeviceInterfaces(set, nullptr, &iface, index, &iface_data);
       ++index) {
    if (out.entries.size() >= cap) {
      out.truncated = true;
      break;
    }

    DWORD needed = 0;
    SetupDiGetDeviceInterfaceDetailW(set, &iface_data, nullptr, 0, &needed,
                                     nullptr);
    if (needed == 0) continue;

    std::vector<BYTE> detail_buf(needed);
    auto* detail =
        reinterpret_cast<SP_DEVICE_INTERFACE_DETAIL_DATA_W*>(detail_buf.data());
    detail->cbSize = sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA_W);
    SP_DEVINFO_DATA info{};
    info.cbSize = sizeof(info);
    if (!SetupDiGetDeviceInterfaceDetailW(set, &iface_data, detail, needed,
                                          nullptr, &info)) {
      continue;
    }

    const std::string instance_id = ReadInstanceId(set, &info);
    if (instance_id.empty()) continue;

    ipc::InventoryStorageEntry entry;
    entry.id = instance_id;
    entry.description = ReadRegistryPropertyString(set, &info, SPDRP_FRIENDLYNAME);
    if (entry.description.empty()) {
      entry.description = ReadRegistryPropertyString(set, &info, SPDRP_DEVICEDESC);
    }
    entry.manufacturer = ReadRegistryPropertyString(set, &info, SPDRP_MFG);

    const HANDLE disk = CreateFileW(detail->DevicePath, GENERIC_READ,
                                    FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                                    OPEN_EXISTING, 0, nullptr);
    if (disk != INVALID_HANDLE_VALUE) {
      if (EnrichViaIoctl(disk, &entry)) {
        any_ioctl = true;
      } else {
        any_ioctl_attempt_failed = true;
      }
      CloseHandle(disk);
    } else {
      any_ioctl_attempt_failed = true;
    }

    out.entries.push_back(std::move(entry));
  }

  SetupDiDestroyDeviceInfoList(set);

  if (out.entries.empty()) {
    out.status = ipc::InventoryStatus::Unsupported;
    out.status_detail = "No GUID_DEVINTERFACE_DISK devices present";
    return out;
  }

  if (out.truncated || !any_ioctl || any_ioctl_attempt_failed) {
    out.status = ipc::InventoryStatus::Partial;
    if (out.truncated) {
      out.status_detail = "Storage list truncated at collector limit";
    } else if (!any_ioctl) {
      out.status_detail =
          "Disk devices listed; IOCTL_STORAGE_QUERY_PROPERTY unavailable";
    } else {
      out.status_detail =
          "Storage inventory partial (some disks missing IOCTL enrichment)";
    }
  } else {
    out.status = ipc::InventoryStatus::Available;
    out.status_detail =
        "GUID_DEVINTERFACE_DISK devices with IOCTL_STORAGE_QUERY_PROPERTY";
  }
  return out;
}

}  // namespace pulse::inventory
