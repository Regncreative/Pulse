#include "collectors/network_etw_engine.hpp"

#include "logging/logger.hpp"

#include <cstring>
#include <vector>

#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
#include <evntcons.h>
#include <evntrace.h>

namespace pulse {
namespace {

constexpr wchar_t kSessionName[] = L"PulseHealthNet";
constexpr size_t kMaxPacketBytes = 64ull * 1024ull * 1024ull;

// Microsoft-Windows-Kernel-Network
// {7dd42a49-5329-4832-8dfd-43d979153a88}
constexpr GUID kKernelNetworkProvider = {
    0x7dd42a49,
    0x5329,
    0x4832,
    {0x8d, 0xfd, 0x43, 0xd9, 0x79, 0x15, 0x3a, 0x88}};

// Microsoft-Windows-TCPIP — fallback when Kernel-Network enable fails.
// {2f07e2ee-15db-40f1-90ef-9d7ba282188a}
constexpr GUID kTcpIpProvider = {
    0x2f07e2ee,
    0x15db,
    0x40f1,
    {0x90, 0xef, 0x9d, 0x7b, 0xa2, 0x82, 0x18, 0x8a}};

// Common keyword bits for IPv4 / IPv6 traffic on Kernel-Network.
constexpr ULONGLONG kKeywordIpv4 = 0x10;
constexpr ULONGLONG kKeywordIpv6 = 0x20;
constexpr ULONGLONG kKeywordSendRecv = kKeywordIpv4 | kKeywordIpv6;

enum class NetDirection { Send, Recv, Unknown };

NetDirection ClassifyDirection(USHORT id, UCHAR opcode) {
  // Prefer EventDescriptor.Id (manifest Event ID). Opcode often mirrors Id
  // for Kernel-Network send/recv; classic TcpIp uses the same numeric values.
  switch (id) {
    case 10:  // TCPv4 send
    case 26:  // TCPv6 send
    case 42:  // UDPv4 send
    case 58:  // UDPv6 send
      return NetDirection::Send;
    case 11:  // TCPv4 recv
    case 27:  // TCPv6 recv
    case 43:  // UDPv4 recv
    case 59:  // UDPv6 recv
      return NetDirection::Recv;
    default:
      break;
  }
  switch (opcode) {
    case EVENT_TRACE_TYPE_SEND:     // 10
    case 26:                        // SendIPV6 (classic)
      return NetDirection::Send;
    case EVENT_TRACE_TYPE_RECEIVE:  // 11
    case 27:                        // RecvIPV6 (classic)
      return NetDirection::Recv;
    default:
      return NetDirection::Unknown;
  }
}

std::vector<uint8_t> MakePropertiesBuffer() {
  const size_t name_bytes = (wcslen(kSessionName) + 1) * sizeof(wchar_t);
  const size_t total = sizeof(EVENT_TRACE_PROPERTIES) + name_bytes;
  std::vector<uint8_t> buf(total, 0);
  auto* props = reinterpret_cast<EVENT_TRACE_PROPERTIES*>(buf.data());
  props->Wnode.BufferSize = static_cast<ULONG>(total);
  props->Wnode.Flags = WNODE_FLAG_TRACED_GUID;
  props->Wnode.ClientContext = 1;  // QPC
  props->LogFileMode = EVENT_TRACE_REAL_TIME_MODE;
  props->LoggerNameOffset = sizeof(EVENT_TRACE_PROPERTIES);
  props->BufferSize = 64;  // KB
  props->MinimumBuffers = 4;
  props->MaximumBuffers = 64;
  memcpy(buf.data() + props->LoggerNameOffset, kSessionName, name_bytes);
  return buf;
}

void BestEffortStopOrphanSession() {
  auto buf = MakePropertiesBuffer();
  auto* props = reinterpret_cast<EVENT_TRACE_PROPERTIES*>(buf.data());
  ControlTraceW(0, kSessionName, props, EVENT_TRACE_CONTROL_STOP);
}

void WINAPI EventRecordCallback(EVENT_RECORD* record) {
  if (record == nullptr || record->UserContext == nullptr) return;
  auto* self = static_cast<NetworkEtwEngine*>(record->UserContext);

  const USHORT id = record->EventHeader.EventDescriptor.Id;
  const UCHAR opcode = record->EventHeader.EventDescriptor.Opcode;
  const NetDirection dir = ClassifyDirection(id, opcode);
  if (dir == NetDirection::Unknown) return;

  uint32_t pid = record->EventHeader.ProcessId;
  uint32_t size = 0;

  const auto* user = static_cast<const uint8_t*>(record->UserData);
  const USHORT user_len = record->UserDataLength;
  if (user != nullptr && user_len >= 8) {
    uint32_t ud_pid = 0;
    uint32_t ud_size = 0;
    memcpy(&ud_pid, user, sizeof(ud_pid));
    memcpy(&ud_size, user + 4, sizeof(ud_size));
    if (pid == 0) pid = ud_pid;
    size = ud_size;
  }

  if (pid == 0 || size == 0 || size > kMaxPacketBytes) return;

  self->AddBytes(pid, size, dir == NetDirection::Send);
}

}  // namespace

NetworkEtwEngine::NetworkEtwEngine() = default;

NetworkEtwEngine::~NetworkEtwEngine() { Stop(); }

std::string NetworkEtwEngine::last_error() const {
  std::lock_guard lock(mu_);
  return last_error_;
}

void NetworkEtwEngine::SetError(const std::string& message,
                                unsigned long win32_error) {
  if (win32_error != 0) {
    last_error_ = message + " win32=" + std::to_string(win32_error);
  } else {
    last_error_ = message;
  }
}

void NetworkEtwEngine::AddBytes(uint32_t pid, uint32_t size, bool is_send) {
  std::lock_guard lock(mu_);
  auto& slot = by_pid_[pid];
  if (is_send) {
    slot.send_bytes += size;
  } else {
    slot.recv_bytes += size;
  }
}

void NetworkEtwEngine::Snapshot(
    std::unordered_map<uint32_t, NetworkPidBytes>* out) {
  if (out == nullptr) return;
  std::lock_guard lock(mu_);
  *out = by_pid_;
}

bool NetworkEtwEngine::StartSessionLocked() {
  BestEffortStopOrphanSession();

  auto props_buf = MakePropertiesBuffer();
  auto* props = reinterpret_cast<EVENT_TRACE_PROPERTIES*>(props_buf.data());

  TRACEHANDLE session = 0;
  ULONG status = StartTraceW(&session, kSessionName, props);
  if (status != ERROR_SUCCESS) {
    SetError("StartTraceW(PulseHealthNet) failed", status);
    Logger::Instance().Warn("NetworkEtw", last_error_);
    return false;
  }
  session_handle_ = static_cast<uint64_t>(session);

  status = EnableTraceEx2(
      session, &kKernelNetworkProvider, EVENT_CONTROL_CODE_ENABLE_PROVIDER,
      TRACE_LEVEL_INFORMATION, kKeywordSendRecv, 0, 0, nullptr);
  if (status != ERROR_SUCCESS) {
    status = EnableTraceEx2(
        session, &kKernelNetworkProvider, EVENT_CONTROL_CODE_ENABLE_PROVIDER,
        TRACE_LEVEL_VERBOSE, 0xFFFFFFFFFFFFFFFFull, 0, 0, nullptr);
  }
  bool any_provider = (status == ERROR_SUCCESS);
  if (!any_provider) {
    Logger::Instance().Warn(
        "NetworkEtw",
        "EnableTraceEx2(Kernel-Network) failed win32=" +
            std::to_string(status) + "; trying Microsoft-Windows-TCPIP");
  }

  // Always attempt TCPIP as well (or as fallback). SendPath|ReceivePath
  // keywords from the public provider manifest (0x1|0x2 << 32).
  constexpr ULONGLONG kTcpIpSendRecv =
      (0x1ull << 32) | (0x2ull << 32);
  ULONG tcp_status = EnableTraceEx2(
      session, &kTcpIpProvider, EVENT_CONTROL_CODE_ENABLE_PROVIDER,
      TRACE_LEVEL_INFORMATION, kTcpIpSendRecv, 0, 0, nullptr);
  if (tcp_status != ERROR_SUCCESS) {
    tcp_status = EnableTraceEx2(
        session, &kTcpIpProvider, EVENT_CONTROL_CODE_ENABLE_PROVIDER,
        TRACE_LEVEL_VERBOSE, 0xFFFFFFFFFFFFFFFFull, 0, 0, nullptr);
  }
  if (tcp_status == ERROR_SUCCESS) {
    any_provider = true;
  }

  if (!any_provider) {
    SetError("EnableTraceEx2 failed for Kernel-Network and TCPIP",
             tcp_status != ERROR_SUCCESS ? tcp_status : status);
    Logger::Instance().Warn("NetworkEtw", last_error_);
    auto stop_buf = MakePropertiesBuffer();
    ControlTraceW(session, nullptr,
                  reinterpret_cast<EVENT_TRACE_PROPERTIES*>(stop_buf.data()),
                  EVENT_TRACE_CONTROL_STOP);
    session_handle_ = UINT64_MAX;
    return false;
  }

  last_error_.clear();
  Logger::Instance().Info("NetworkEtw",
                          "PulseHealthNet session started with provider(s)");
  return true;
}

void NetworkEtwEngine::StopSessionLocked() {
  if (session_handle_ != UINT64_MAX) {
    auto buf = MakePropertiesBuffer();
    auto* props = reinterpret_cast<EVENT_TRACE_PROPERTIES*>(buf.data());
    ControlTraceW(static_cast<TRACEHANDLE>(session_handle_), kSessionName,
                  props, EVENT_TRACE_CONTROL_STOP);
    session_handle_ = UINT64_MAX;
  } else {
    BestEffortStopOrphanSession();
  }
}

void NetworkEtwEngine::TraceThreadMain() {
  EVENT_TRACE_LOGFILEW log{};
  log.LoggerName = const_cast<LPWSTR>(kSessionName);
  log.ProcessTraceMode =
      PROCESS_TRACE_MODE_REAL_TIME | PROCESS_TRACE_MODE_EVENT_RECORD;
  log.EventRecordCallback = EventRecordCallback;
  log.Context = this;

  const TRACEHANDLE consumer = OpenTraceW(&log);
  if (consumer == INVALID_PROCESSTRACE_HANDLE) {
    const DWORD err = GetLastError();
    {
      std::lock_guard lock(mu_);
      SetError("OpenTraceW(PulseHealthNet) failed", err);
      Logger::Instance().Warn("NetworkEtw", last_error_);
      StopSessionLocked();
    }
    running_.store(false);
    return;
  }

  {
    std::lock_guard lock(mu_);
    consumer_handle_ = static_cast<uint64_t>(consumer);
  }

  TRACEHANDLE handles[1] = {consumer};
  const ULONG status = ProcessTrace(handles, 1, nullptr, nullptr);
  if (status != ERROR_SUCCESS && status != ERROR_CANCELLED &&
      !stop_requested_.load()) {
    std::lock_guard lock(mu_);
    SetError("ProcessTrace ended unexpectedly", status);
    Logger::Instance().Warn("NetworkEtw", last_error_);
  }

  CloseTrace(consumer);
  {
    std::lock_guard lock(mu_);
    consumer_handle_ = UINT64_MAX;
  }
  running_.store(false);
}

bool NetworkEtwEngine::Start() {
  if (running_.load()) return true;

  if (consumer_thread_.joinable()) {
    consumer_thread_.join();
  }

  {
    std::lock_guard lock(mu_);
    by_pid_.clear();
    stop_requested_.store(false);
    if (!StartSessionLocked()) {
      running_.store(false);
      return false;
    }
  }

  running_.store(true);
  consumer_thread_ = std::thread([this] { TraceThreadMain(); });

  Logger::Instance().Info(
      "NetworkEtw",
      "PulseHealthNet session started (Microsoft-Windows-Kernel-Network)");
  return true;
}

void NetworkEtwEngine::Stop() {
  stop_requested_.store(true);

  {
    std::lock_guard lock(mu_);
    StopSessionLocked();
  }

  if (consumer_thread_.joinable()) {
    consumer_thread_.join();
  }

  {
    std::lock_guard lock(mu_);
    if (consumer_handle_ != UINT64_MAX) {
      CloseTrace(static_cast<TRACEHANDLE>(consumer_handle_));
      consumer_handle_ = UINT64_MAX;
    }
    by_pid_.clear();
  }
  running_.store(false);
}

}  // namespace pulse
