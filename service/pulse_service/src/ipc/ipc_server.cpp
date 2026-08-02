#include "ipc/ipc_server.hpp"

#include "collectors/event_log_channels.hpp"
#include "collectors/event_log_collector.hpp"
#include "diagnostics/service_identity.hpp"
#include "ipc/event_mapper.hpp"
#include "logging/logger.hpp"
#include "pulse/constants.hpp"
#include "pulse/version.hpp"
#include "pulse_build_info.hpp"
#include "windows/wevt_helpers.hpp"

#include <algorithm>
#include <chrono>
#include <sstream>

#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <TlHelp32.h>
#include <psapi.h>
#include <sddl.h>

namespace pulse {
namespace {

int64_t NowUnixMs() {
  using namespace std::chrono;
  return duration_cast<milliseconds>(system_clock::now().time_since_epoch())
      .count();
}

}  // namespace

IpcServer::IpcServer(std::wstring pipe_name, size_t live_queue_capacity,
                     uint32_t max_pipe_instances)
    : pipe_name_(std::move(pipe_name)),
      live_queue_capacity_(live_queue_capacity),
      max_pipe_instances_(max_pipe_instances == 0 ? 32 : max_pipe_instances) {}

IpcServer::~IpcServer() { Stop(); }

void IpcServer::SetRunMode(std::string mode) {
  run_mode_ = std::move(mode);
}

bool IpcServer::Start() {
  if (running_.exchange(true)) return true;
  service_start_unix_ms_ = NowUnixMs();
  service_start_tick_ms_ = GetTickCount64();
  EnsureHealthCollector();
  accept_thread_ = std::thread([this] { AcceptLoop(); });
  health_thread_running_ = true;
  health_thread_ = std::thread([this] { HealthPushLoop(); });
  Logger::Instance().Info(
      "IpcServer",
      "Listening on named pipe (max_instances=" +
          std::to_string(max_pipe_instances_) + ")");
  return true;
}

void IpcServer::Stop() {
  if (!running_.exchange(false)) return;

  health_thread_running_ = false;
  if (health_thread_.joinable()) {
    health_thread_.join();
  }

  StopLiveSubscribers();

  {
    std::lock_guard lock(health_mu_);
    health_collector_.Shutdown();
    health_collector_ready_ = false;
  }

  HANDLE h = CreateFileW(pipe_name_.c_str(), GENERIC_READ | GENERIC_WRITE, 0,
                         nullptr, OPEN_EXISTING, 0, nullptr);
  if (h != INVALID_HANDLE_VALUE) CloseHandle(h);

  if (accept_thread_.joinable()) accept_thread_.join();

  std::vector<std::shared_ptr<ClientConnection>> copy;
  {
    std::lock_guard lock(clients_mu_);
    copy = clients_;
    clients_.clear();
  }
  for (auto& c : copy) {
    c->alive = false;
    c->live_enabled = false;
    c->health_enabled = false;
    if (c->wake_event) {
      SetEvent(static_cast<HANDLE>(c->wake_event));
    }
    if (c->pipe_handle) {
      CancelIoEx(static_cast<HANDLE>(c->pipe_handle), nullptr);
      DisconnectNamedPipe(static_cast<HANDLE>(c->pipe_handle));
      CloseHandle(static_cast<HANDLE>(c->pipe_handle));
      c->pipe_handle = nullptr;
    }
    if (c->reader.joinable()) c->reader.join();
  }
  Logger::Instance().Info("IpcServer", "Stopped");
}

void* IpcServer::CreatePipeInstance() {
  PSECURITY_DESCRIPTOR sd = nullptr;
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorA(
          kPipeSddl, SDDL_REVISION_1, &sd, nullptr)) {
    Logger::Instance().Error("IpcServer", "Failed to parse pipe SDDL");
    return INVALID_HANDLE_VALUE;
  }
  SECURITY_ATTRIBUTES sa{};
  sa.nLength = sizeof(sa);
  sa.lpSecurityDescriptor = sd;
  sa.bInheritHandle = FALSE;

  HANDLE pipe = CreateNamedPipeW(
      pipe_name_.c_str(), PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED,
      PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT, max_pipe_instances_,
      64 * 1024, 64 * 1024, 0, &sa);
  LocalFree(sd);
  return pipe;
}

void IpcServer::AcceptLoop() {
  while (running_) {
    HANDLE pipe = static_cast<HANDLE>(CreatePipeInstance());
    if (pipe == INVALID_HANDLE_VALUE) {
      const DWORD gle = GetLastError();
      Logger::Instance().Error(
          "IpcServer",
          "CreateNamedPipe failed gle=" + std::to_string(gle) +
              " max_instances=" + std::to_string(max_pipe_instances_) +
              " (pipe slots exhausted if gle=231 ERROR_PIPE_BUSY)");
      Sleep(500);
      continue;
    }

    OVERLAPPED ov{};
    ov.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    const BOOL ok = ConnectNamedPipe(pipe, &ov);
    if (!ok) {
      const DWORD err = GetLastError();
      if (err == ERROR_IO_PENDING) {
        WaitForSingleObject(ov.hEvent, INFINITE);
      } else if (err != ERROR_PIPE_CONNECTED) {
        CloseHandle(ov.hEvent);
        CloseHandle(pipe);
        if (!running_) break;
        continue;
      }
    }
    CloseHandle(ov.hEvent);
    if (!running_) {
      CloseHandle(pipe);
      break;
    }

    // Custom deleter must never destroy a joinable std::thread — that calls
    // std::terminate() (0xc0000409 / FAST_FAIL_FATAL_APP_EXIT). The reader
    // thread holds the last shared_ptr and would otherwise delete itself.
    auto conn = std::shared_ptr<ClientConnection>(
        new ClientConnection(), [](ClientConnection* c) {
          if (c == nullptr) return;
          if (c->reader.joinable()) {
            if (c->reader.get_id() == std::this_thread::get_id()) {
              c->reader.detach();
            } else {
              c->alive = false;
              if (c->wake_event) {
                SetEvent(static_cast<HANDLE>(c->wake_event));
              }
              if (c->pipe_handle) {
                CancelIoEx(static_cast<HANDLE>(c->pipe_handle), nullptr);
              }
              c->reader.join();
            }
          }
          if (c->wake_event) {
            CloseHandle(static_cast<HANDLE>(c->wake_event));
            c->wake_event = nullptr;
          }
          delete c;
        });
    conn->pipe_handle = pipe;
    conn->queue_capacity = live_queue_capacity_;
    conn->wake_event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (conn->wake_event == nullptr) {
      Logger::Instance().Error("IpcServer", "CreateEvent for client wake failed");
      CloseHandle(pipe);
      continue;
    }
    conn->reader = std::thread([this, conn] { ClientReader(conn); });
    {
      std::lock_guard lock(clients_mu_);
      clients_.push_back(conn);
    }
    Logger::Instance().Info("IpcServer", "Client connected");
  }
}

bool IpcServer::WriteExact(void* pipe, const void* buffer, size_t size) {
  const auto* bytes = static_cast<const uint8_t*>(buffer);
  size_t sent = 0;
  while (sent < size) {
    DWORD written = 0;
    if (!WriteFile(static_cast<HANDLE>(pipe), bytes + sent,
                   static_cast<DWORD>(size - sent), &written, nullptr)) {
      return false;
    }
    if (written == 0) return false;
    sent += written;
  }
  return true;
}

bool IpcServer::WriteEnvelopeLocked(
    const std::shared_ptr<ClientConnection>& conn,
    const ipc::Envelope& env) {
  if (!conn || !conn->pipe_handle || !conn->alive) return false;
  std::lock_guard lock(conn->write_mu);
  std::vector<uint8_t> payload;
  if (!ipc::EncodeEnvelope(env, &payload)) {
    ++ipc_errors_;
    return false;
  }
  std::vector<uint8_t> frame;
  if (!ipc::EncodeFrame(payload, &frame)) {
    ++ipc_errors_;
    return false;
  }
  if (!WriteExact(conn->pipe_handle, frame.data(), frame.size())) {
    ++ipc_errors_;
    return false;
  }
  ++ipc_messages_sent_;
  ipc_bytes_sent_.fetch_add(frame.size());
  return true;
}

void IpcServer::EnqueueOutbound(const std::shared_ptr<ClientConnection>& conn,
                                ipc::Envelope env) {
  if (!conn || !conn->alive) return;
  {
    std::lock_guard lock(conn->queue_mu);
    // ADR-008 / doc 05: drop oldest on overflow so ingest never stalls and
    // clients keep receiving the newest live summaries.
    while (conn->outbound.size() >= conn->queue_capacity) {
      conn->outbound.pop_front();
      ++conn->dropped;
      ++live_events_dropped_;
      Logger::Instance().Warn("IpcServer",
                              "Live outbound queue full; dropped oldest event");
    }
    conn->outbound.push_back(std::move(env));
  }
  if (conn->wake_event) {
    SetEvent(static_cast<HANDLE>(conn->wake_event));
  }
}

void IpcServer::FlushOutbound(const std::shared_ptr<ClientConnection>& conn) {
  while (conn->alive) {
    ipc::Envelope env;
    {
      std::lock_guard lock(conn->queue_mu);
      if (conn->outbound.empty()) {
        return;
      }
      env = std::move(conn->outbound.front());
      conn->outbound.pop_front();
    }
    if (!WriteEnvelopeLocked(conn, env)) {
      Logger::Instance().Warn("IpcServer", "Failed to write queued envelope");
      conn->alive = false;
      return;
    }
  }
}

void IpcServer::StopLiveSubscribers() {
  std::lock_guard lock(live_mu_);
  for (auto& sub : live_subscribers_) {
    if (sub) {
      sub->Stop();
    }
  }
  live_subscribers_.clear();
  live_channels_label_.clear();
  live_subscriber_started_ = false;
}

void IpcServer::EnsureLiveSubscriber() {
  std::lock_guard lock(live_mu_);
  if (live_subscriber_started_) {
    return;
  }

  const std::vector<std::wstring> channels = AccessibleDiagnosticsChannels();
  if (channels.empty()) {
    Logger::Instance().Error(
        "IpcServer", "No accessible Event Log channels for live monitoring");
    return;
  }

  std::ostringstream label;
  for (const std::wstring& channel : channels) {
    auto sub = std::make_unique<EventLogSubscriber>();
    const bool ok = sub->Start(
        channel, [this](EventRecord record) { OnLiveEventRecord(std::move(record)); });
    if (!ok) {
      Logger::Instance().Warn(
          "IpcServer",
          "Live subscribe skipped for " + wevt::WideToUtf8(channel));
      continue;
    }
    if (!label.str().empty()) {
      label << ',';
    }
    label << wevt::WideToUtf8(channel);
    live_subscribers_.push_back(std::move(sub));
  }

  live_channels_label_ = label.str();
  live_subscriber_started_ = !live_subscribers_.empty();
  if (!live_subscriber_started_) {
    Logger::Instance().Error("IpcServer",
                             "Failed to start any live Event Log subscriber");
  } else {
    Logger::Instance().Info(
        "IpcServer",
        "Live Event Log subscribers active on: " + live_channels_label_);
  }
}

void IpcServer::OnLiveEventRecord(EventRecord record) {
  Logger::Instance().Debug(
      "IpcServer",
      std::string("Event Received record_id=") +
          (record.record_id ? std::to_string(*record.record_id) : "0") +
          " event_id=" +
          (record.event_id ? std::to_string(*record.event_id) : "0"));
  const ipc::TimelineEvent event = ToTimelineEvent(record);
  PushLiveEvent(event);
}

void IpcServer::PushLiveEvent(const ipc::TimelineEvent& event) {
  {
    std::lock_guard lock(last_live_mu_);
    last_live_event_unix_ms_ = event.timestamp_unix_ms != 0
                                   ? event.timestamp_unix_ms
                                   : NowUnixMs();
    last_live_event_title_ =
        !event.title.empty()
            ? event.title
            : (!event.summary.empty() ? event.summary : event.message);
  }
  ++live_events_pushed_;

  ipc::Envelope push;
  push.request_id = 0;
  push.body = event;

  std::vector<std::shared_ptr<ClientConnection>> targets;
  {
    std::lock_guard lock(clients_mu_);
    for (auto& c : clients_) {
      if (c && c->alive && c->live_enabled) {
        targets.push_back(c);
      }
    }
  }

  Logger::Instance().Debug(
      "IpcServer",
      std::string("IPC Push clients=") +
          std::to_string(targets.size()) +
          " win_event_id=" + std::to_string(event.win_event_id));

  // Enqueue only — never WriteFile from the Wevtapi callback thread.
  // Concurrent WriteFile + ReadFile on a duplex named pipe disconnects the client.
  for (auto& c : targets) {
    EnqueueOutbound(c, push);
  }
}

void IpcServer::EnableLiveForClient(
    const std::shared_ptr<ClientConnection>& conn) {
  if (!conn) return;
  conn->live_enabled = true;
  EnsureLiveSubscriber();
  Logger::Instance().Info("IpcServer",
                          "EvtSubscribe Active (client live enabled)");
}

void IpcServer::DisableLiveForClient(
    const std::shared_ptr<ClientConnection>& conn) {
  if (!conn) return;
  conn->live_enabled = false;
}

void IpcServer::EnsureHealthCollector() {
  std::lock_guard lock(health_mu_);
  if (health_collector_ready_) return;
  health_collector_ready_ = health_collector_.Initialize();
}

void IpcServer::EnableHealthForClient(
    const std::shared_ptr<ClientConnection>& conn) {
  if (!conn) return;
  EnsureHealthCollector();
  conn->health_enabled = true;
}

void IpcServer::DisableHealthForClient(
    const std::shared_ptr<ClientConnection>& conn) {
  if (!conn) return;
  conn->health_enabled = false;
}

void IpcServer::PushHealthUpdate(const ipc::HealthUpdate& update) {
  ipc::Envelope push;
  push.request_id = 0;
  push.body = update;

  std::vector<std::shared_ptr<ClientConnection>> targets;
  {
    std::lock_guard lock(clients_mu_);
    for (auto& c : clients_) {
      if (c && c->alive && c->health_enabled) {
        targets.push_back(c);
      }
    }
  }
  for (auto& c : targets) {
    EnqueueOutbound(c, push);
  }
}

void IpcServer::HealthPushLoop() {
  // Do not CollectSample until a client enables health. Priming here under
  // LocalService previously raced IPC and contributed to service crashes.
  while (health_thread_running_ && running_) {
    bool any = false;
    {
      std::lock_guard lock(clients_mu_);
      for (auto& c : clients_) {
        if (c && c->alive && c->health_enabled) {
          any = true;
          break;
        }
      }
    }

    if (any) {
      ipc::HealthUpdate update;
      {
        std::lock_guard lock(health_mu_);
        if (health_collector_ready_) {
          update = health_collector_.CollectHealthUpdate();
        }
      }
      PushHealthUpdate(update);
    }

    for (int i = 0; i < 10 && health_thread_running_ && running_; ++i) {
      Sleep(100);
    }
  }
}

void IpcServer::HandleEnvelope(const std::shared_ptr<ClientConnection>& conn,
                               const ipc::Envelope& env) {
  ++ipc_messages_received_;

  if (std::holds_alternative<ipc::ClientHello>(env.body)) {
    const auto& hello = std::get<ipc::ClientHello>(env.body);
    Logger::Instance().Info(
        "IpcServer",
        "ClientHello from " + hello.client_name + " v" + hello.client_version);
    if (hello.protocol_version != kProtocolVersion) {
      ipc::Envelope err;
      err.request_id = env.request_id;
      err.body = ipc::ErrorResponse{
          static_cast<int32_t>(5), "Incompatible protocol version",
          "client=" + std::to_string(hello.protocol_version) +
              " server=" + std::to_string(kProtocolVersion),
          "IpcServer"};
      WriteEnvelopeLocked(conn, err);
      return;
    }
    ipc::Envelope reply;
    reply.request_id = env.request_id;
    reply.body = ipc::ServerHello{kProtocolVersion, kServiceVersion};
    WriteEnvelopeLocked(conn, reply);
    return;
  }

  if (std::holds_alternative<ipc::Ping>(env.body)) {
    const auto& ping = std::get<ipc::Ping>(env.body);
    ipc::Envelope reply;
    reply.request_id = env.request_id;
    reply.body = ipc::Pong{ping.nonce, NowUnixMs(), kServiceVersion};
    WriteEnvelopeLocked(conn, reply);
    return;
  }

  if (std::holds_alternative<ipc::GetTimelineSnapshot>(env.body)) {
    Logger::Instance().Info("IpcServer", "Request Snapshot received");
    const auto& req = std::get<ipc::GetTimelineSnapshot>(env.body);
    uint32_t limit = req.limit == 0 ? 100 : req.limit;
    if (limit > 500) {
      limit = 500;
    }

    EventLogCollector collector;
    CollectResult<std::vector<EventRecord>> collected =
        CollectResult<std::vector<EventRecord>>::Failure("uninitialized");
    std::string snapshot_channel;

    if (IsDiagnosticsChannelRequest(req.channel)) {
      const std::vector<std::wstring> channels =
          AccessibleDiagnosticsChannels();
      if (channels.empty()) {
        ipc::Envelope err;
        err.request_id = env.request_id;
        err.body = ipc::ErrorResponse{
            3, "No accessible Event Log channels for diagnostics snapshot",
            "LocalService may lack channel rights", "EventLogChannels"};
        WriteEnvelopeLocked(conn, err);
        return;
      }
      collected = collector.CollectLatestMulti(channels, limit);
      std::ostringstream label;
      for (std::size_t i = 0; i < channels.size(); ++i) {
        if (i > 0) {
          label << ',';
        }
        label << wevt::WideToUtf8(channels[i]);
      }
      snapshot_channel = label.str();
    } else {
      // Explicit single-channel request (UTF-8 channel name from client).
      const std::wstring wide(req.channel.begin(), req.channel.end());
      collected = collector.CollectLatest(wide, limit);
      snapshot_channel = req.channel;
    }

    if (!collected) {
      ipc::Envelope err;
      err.request_id = env.request_id;
      err.body = ipc::ErrorResponse{3, "Failed to collect Event Log snapshot",
                                    collected.error(), "EventLogCollector"};
      WriteEnvelopeLocked(conn, err);
      return;
    }

    ipc::TimelineSnapshot snapshot;
    snapshot.channel = std::move(snapshot_channel);
    snapshot.requested_limit = limit;
    snapshot.collected_unix_ms = NowUnixMs();
    snapshot.events.reserve(collected.value().size());
    for (const auto& record : collected.value()) {
      snapshot.events.push_back(ToTimelineEvent(record));
    }

    ipc::Envelope reply;
    reply.request_id = env.request_id;
    reply.body = std::move(snapshot);
    if (!WriteEnvelopeLocked(conn, reply)) {
      Logger::Instance().Error("IpcServer", "Failed to write TimelineSnapshot");
      return;
    }
    Logger::Instance().Info(
        "IpcServer",
        "TimelineSnapshot events=" + std::to_string(collected.value().size()) +
            " channel=" + snapshot_channel);

    // Live subscribe is explicit (StartLiveMonitoring) so snapshot always
    // completes before live pushes are enabled for this client.
    return;
  }

  if (std::holds_alternative<ipc::GetInventoryDomain>(env.body)) {
    const auto& req = std::get<ipc::GetInventoryDomain>(env.body);
    inventory::CollectRequest creq;
    creq.domain = req.domain;
    creq.force_refresh = req.force_refresh;
    creq.since_generation = req.since_generation;
    creq.limit = req.limit;
    ipc::Envelope reply;
    reply.request_id = env.request_id;
    reply.body = inventory_engine_.GetDomain(creq);
    WriteEnvelopeLocked(conn, reply);
    return;
  }

  if (std::holds_alternative<ipc::GetTimelineEventDetail>(env.body)) {
    const auto& req = std::get<ipc::GetTimelineEventDetail>(env.body);
    if (req.channel.empty() || req.record_id == 0) {
      ipc::Envelope err;
      err.request_id = env.request_id;
      err.body = ipc::ErrorResponse{
          2, "channel and record_id are required",
          "GetTimelineEventDetail", "IpcServer"};
      WriteEnvelopeLocked(conn, err);
      return;
    }

    EventLogCollector collector;
    const std::wstring wide(req.channel.begin(), req.channel.end());
    auto collected = collector.CollectByRecordId(wide, req.record_id, true);
    if (!collected) {
      ipc::Envelope err;
      err.request_id = env.request_id;
      err.body = ipc::ErrorResponse{
          3, "Failed to load Event Log detail", collected.error(),
          "EventLogCollector"};
      WriteEnvelopeLocked(conn, err);
      return;
    }

    ipc::TimelineEventDetail detail;
    if (!collected.value().has_value()) {
      detail.found = false;
    } else {
      detail.found = true;
      detail.event = ToTimelineEvent(*collected.value());
    }

    ipc::Envelope reply;
    reply.request_id = env.request_id;
    reply.body = std::move(detail);
    WriteEnvelopeLocked(conn, reply);
    return;
  }

  if (std::holds_alternative<ipc::StartLiveMonitoring>(env.body)) {
    Logger::Instance().Info("IpcServer", "StartLiveMonitoring received");
    const auto& req = std::get<ipc::StartLiveMonitoring>(env.body);
    // Phase 4: default diagnostics set. Explicit non-default channel names are
    // reserved; clients historically send "System".
    if (!req.channel.empty() && !IsDiagnosticsChannelRequest(req.channel)) {
      ipc::Envelope err;
      err.request_id = env.request_id;
      err.body = ipc::ErrorResponse{
          2,
          "Live monitoring uses the diagnostics Event Log channel set",
          "requested=" + req.channel, "IpcServer"};
      WriteEnvelopeLocked(conn, err);
      return;
    }
    EnableLiveForClient(conn);
    ipc::Envelope ack;
    ack.request_id = env.request_id;
    ack.body = ipc::ErrorResponse{0, "Live monitoring started", "", "IpcServer"};
    WriteEnvelopeLocked(conn, ack);
    return;
  }

  if (std::holds_alternative<ipc::StopLiveMonitoring>(env.body)) {
    DisableLiveForClient(conn);
    ipc::Envelope ack;
    ack.request_id = env.request_id;
    ack.body = ipc::ErrorResponse{0, "Live monitoring stopped", "", "IpcServer"};
    WriteEnvelopeLocked(conn, ack);
    return;
  }

  if (std::holds_alternative<ipc::GetHealthSnapshot>(env.body)) {
    Logger::Instance().Info("IpcServer", "GetHealthSnapshot");
    EnsureHealthCollector();
    ipc::HealthSnapshot snapshot;
    {
      std::lock_guard lock(health_mu_);
      snapshot.info = health_collector_.CollectStatic();
      snapshot.sample = health_collector_.CollectSample();
    }
    ipc::Envelope reply;
    reply.request_id = env.request_id;
    reply.body = std::move(snapshot);
    WriteEnvelopeLocked(conn, reply);
    // Do not auto-enable health pushes here — clients must call
    // StartHealthMonitoring explicitly (mirrors TimelineSnapshot / live).
    return;
  }

  if (std::holds_alternative<ipc::StartHealthMonitoring>(env.body)) {
    Logger::Instance().Info("IpcServer", "StartHealthMonitoring");
    EnableHealthForClient(conn);
    ipc::Envelope ack;
    ack.request_id = env.request_id;
    ack.body = ipc::ErrorResponse{0, "Health monitoring started", "", "IpcServer"};
    WriteEnvelopeLocked(conn, ack);
    return;
  }

  if (std::holds_alternative<ipc::StopHealthMonitoring>(env.body)) {
    DisableHealthForClient(conn);
    ipc::Envelope ack;
    ack.request_id = env.request_id;
    ack.body = ipc::ErrorResponse{0, "Health monitoring stopped", "", "IpcServer"};
    WriteEnvelopeLocked(conn, ack);
    return;
  }

  if (std::holds_alternative<ipc::GetProcessDetails>(env.body)) {
    const auto& req = std::get<ipc::GetProcessDetails>(env.body);
    EnsureHealthCollector();
    ipc::ProcessDetails details;
    {
      std::lock_guard lock(health_mu_);
      details = health_collector_.QueryProcessDetails(req.pid);
    }
    ipc::Envelope reply;
    reply.request_id = env.request_id;
    reply.body = std::move(details);
    WriteEnvelopeLocked(conn, reply);
    return;
  }

  if (std::holds_alternative<ipc::GetDiagnosticsSnapshot>(env.body)) {
    Logger::Instance().Info("IpcServer", "GetDiagnosticsSnapshot");
    ipc::Envelope reply;
    reply.request_id = env.request_id;
    reply.body = BuildDiagnosticsSnapshot();
    WriteEnvelopeLocked(conn, reply);
    return;
  }

  if (std::holds_alternative<ipc::InjectDiagnosticsTestEvent>(env.body)) {
    Logger::Instance().Info("IpcServer", "InjectDiagnosticsTestEvent");
    // Ensure the requesting client receives the synthetic push.
    EnableLiveForClient(conn);
    InjectTestEvent();
    ipc::Envelope ack;
    ack.request_id = env.request_id;
    ack.body = ipc::ErrorResponse{0, "Diagnostics test event injected", "",
                                  "IpcServer"};
    WriteEnvelopeLocked(conn, ack);
    return;
  }

  if (std::holds_alternative<ipc::Heartbeat>(env.body)) {
    return;
  }

  ++ipc_errors_;
  ipc::Envelope err;
  err.request_id = env.request_id;
  err.body = ipc::ErrorResponse{1, "Unsupported message", "", "IpcServer"};
  WriteEnvelopeLocked(conn, err);
}

void IpcServer::ClientReader(std::shared_ptr<ClientConnection> conn) {
  std::vector<uint8_t> buffer;
  buffer.reserve(4096);
  uint8_t temp[4096];

  while (conn->alive && running_) {
    // Drain live pushes on this thread so WriteFile never races ReadFile.
    FlushOutbound(conn);
    if (!conn->alive) {
      break;
    }

    DWORD avail = 0;
    if (!PeekNamedPipe(static_cast<HANDLE>(conn->pipe_handle), nullptr, 0,
                       nullptr, &avail, nullptr)) {
      break;
    }

    if (avail == 0) {
      if (conn->wake_event) {
        WaitForSingleObject(static_cast<HANDLE>(conn->wake_event), 50);
      } else {
        Sleep(50);
      }
      continue;
    }

    const DWORD to_read =
        avail > sizeof(temp) ? static_cast<DWORD>(sizeof(temp)) : avail;
    DWORD read = 0;
    if (!ReadFile(static_cast<HANDLE>(conn->pipe_handle), temp, to_read, &read,
                  nullptr)) {
      break;
    }
    if (read == 0) break;
    buffer.insert(buffer.end(), temp, temp + read);
    ipc_bytes_received_.fetch_add(read);

    while (true) {
      std::vector<uint8_t> payload;
      size_t consumed = 0;
      std::string error;
      if (!ipc::TryDecodeFrame(buffer.data(), buffer.size(), &payload, &consumed,
                               &error)) {
        if (!error.empty()) {
          Logger::Instance().Warn("IpcServer", error);
          conn->alive = false;
        }
        break;
      }
      buffer.erase(buffer.begin(),
                   buffer.begin() + static_cast<std::ptrdiff_t>(consumed));
      ipc::Envelope env;
      if (!ipc::DecodeEnvelope(payload.data(), payload.size(), &env)) {
        Logger::Instance().Warn("IpcServer", "Failed to decode envelope");
        continue;
      }
      HandleEnvelope(conn, env);
      FlushOutbound(conn);
    }
  }

  conn->alive = false;
  conn->live_enabled = false;
  conn->health_enabled = false;
  if (conn->pipe_handle) {
    DisconnectNamedPipe(static_cast<HANDLE>(conn->pipe_handle));
    CloseHandle(static_cast<HANDLE>(conn->pipe_handle));
    conn->pipe_handle = nullptr;
  }

  {
    std::lock_guard lock(clients_mu_);
    clients_.erase(std::remove_if(clients_.begin(), clients_.end(),
                                  [&](const std::shared_ptr<ClientConnection>& c) {
                                    return c.get() == conn.get();
                                  }),
                   clients_.end());
  }
  Logger::Instance().Info("IpcServer", "Client disconnected");

  // Drop the last shared_ptr from this thread only after the connection is
  // erased. The deleter detaches when destroy runs on the reader thread.
  conn.reset();
}

void IpcServer::FillServiceProcessMetrics(ipc::DiagnosticsSnapshot* out) {
  if (!out) return;
  out->service_pid = GetCurrentProcessId();
  HANDLE proc = GetCurrentProcess();

  PROCESS_MEMORY_COUNTERS_EX pmc{};
  pmc.cb = sizeof(pmc);
  if (GetProcessMemoryInfo(proc,
                           reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&pmc),
                           sizeof(pmc))) {
    out->working_set_bytes = pmc.WorkingSetSize;
  }

  DWORD handles = 0;
  if (GetProcessHandleCount(proc, &handles)) {
    out->handle_count = handles;
  }

  // Thread count via Toolhelp snapshot of current process.
  HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
  if (snap != INVALID_HANDLE_VALUE) {
    THREADENTRY32 te{};
    te.dwSize = sizeof(te);
    uint32_t threads = 0;
    const DWORD pid = out->service_pid;
    if (Thread32First(snap, &te)) {
      do {
        if (te.th32OwnerProcessID == pid) ++threads;
      } while (Thread32Next(snap, &te));
    }
    CloseHandle(snap);
    out->thread_count = threads;
  }

  FILETIME create{}, exit_t{}, kernel{}, user{};
  if (!GetProcessTimes(proc, &create, &exit_t, &kernel, &user)) {
    return;
  }
  auto file_time_u64 = [](const FILETIME& ft) -> uint64_t {
    return (static_cast<uint64_t>(ft.dwHighDateTime) << 32) | ft.dwLowDateTime;
  };
  const uint64_t cpu_100ns = file_time_u64(kernel) + file_time_u64(user);
  const uint64_t now_tick = GetTickCount64();
  if (have_proc_cpu_baseline_ && now_tick > prev_proc_cpu_tick_ms_ &&
      cpu_100ns >= prev_proc_cpu_100ns_) {
    const double dt_s =
        static_cast<double>(now_tick - prev_proc_cpu_tick_ms_) / 1000.0;
    SYSTEM_INFO si{};
    GetSystemInfo(&si);
    const double logical = static_cast<double>(
        (std::max)(1u, static_cast<unsigned>(si.dwNumberOfProcessors)));
    const uint64_t delta = cpu_100ns - prev_proc_cpu_100ns_;
    out->cpu_percent =
        (static_cast<double>(delta) / 10'000'000.0) / dt_s / logical * 100.0;
    out->has_cpu_percent = true;
  }
  prev_proc_cpu_100ns_ = cpu_100ns;
  prev_proc_cpu_tick_ms_ = now_tick;
  have_proc_cpu_baseline_ = true;
}

void IpcServer::FillIpcThroughputRates(ipc::DiagnosticsSnapshot* out) {
  if (!out) return;
  const uint64_t msgs =
      out->ipc_messages_received + out->ipc_messages_sent;
  const uint64_t bytes = out->ipc_bytes_received + out->ipc_bytes_sent;
  const uint64_t now_tick = GetTickCount64();

  std::lock_guard lock(ipc_rate_mu_);
  if (have_ipc_rate_baseline_ && now_tick > prev_ipc_rate_tick_ms_) {
    const double dt_s =
        static_cast<double>(now_tick - prev_ipc_rate_tick_ms_) / 1000.0;
    if (dt_s > 0.0 && msgs >= prev_ipc_msgs_total_ &&
        bytes >= prev_ipc_bytes_total_) {
      out->ipc_messages_per_sec =
          static_cast<double>(msgs - prev_ipc_msgs_total_) / dt_s;
      out->has_ipc_messages_per_sec = true;
      out->ipc_bytes_per_sec =
          static_cast<double>(bytes - prev_ipc_bytes_total_) / dt_s;
      out->has_ipc_bytes_per_sec = true;
    }
  }
  prev_ipc_msgs_total_ = msgs;
  prev_ipc_bytes_total_ = bytes;
  prev_ipc_rate_tick_ms_ = now_tick;
  have_ipc_rate_baseline_ = true;
}

ipc::DiagnosticsSnapshot IpcServer::BuildDiagnosticsSnapshot() {
  ipc::DiagnosticsSnapshot snap;
  snap.service_version = kServiceVersion;
  snap.protocol_version = kProtocolVersion;
  snap.service_start_unix_ms = service_start_unix_ms_;
  snap.service_uptime_ms =
      service_start_tick_ms_ == 0
          ? 0
          : (GetTickCount64() - service_start_tick_ms_);
  snap.run_mode = run_mode_;
  snap.ipc_listening = running_.load();

  snap.executable_path = diagnostics::ExecutablePath();
  snap.build_version = ServiceVersion().ToString();
  snap.git_commit = build_info::kGitCommit;
  snap.binary_sha256 = diagnostics::BinarySha256Hex();
  snap.install_path = diagnostics::InstalledServiceExePath();
  if (!snap.install_path.empty() && !snap.executable_path.empty()) {
    snap.has_paths_match = true;
    snap.paths_match =
        diagnostics::PathsMatch(snap.executable_path, snap.install_path);
  }
  snap.scm_state = diagnostics::ScmStateLabel();
  snap.scm_startup_type = diagnostics::ScmStartupTypeLabel();

  bool any_live = false;
  bool any_health = false;
  uint32_t clients = 0;
  uint32_t queue_depth = 0;
  {
    std::lock_guard lock(clients_mu_);
    for (auto& c : clients_) {
      if (!c || !c->alive) continue;
      ++clients;
      if (c->live_enabled) any_live = true;
      if (c->health_enabled) any_health = true;
      std::lock_guard qlock(c->queue_mu);
      queue_depth += static_cast<uint32_t>(c->outbound.size());
    }
  }
  snap.connected_clients = clients;
  snap.live_queue_depth = queue_depth;
  snap.live_queue_capacity = static_cast<uint32_t>(live_queue_capacity_);

  {
    std::lock_guard lock(live_mu_);
    uint64_t reconnects = 0;
    bool any_running = false;
    for (const auto& sub : live_subscribers_) {
      if (!sub) {
        continue;
      }
      if (sub->running()) {
        any_running = true;
      }
      reconnects += sub->reconnect_count();
    }
    snap.live_subscribed = any_running;
    snap.live_channel = live_subscriber_started_ ? live_channels_label_ : "";
    snap.live_subscriber_reconnects = reconnects;
  }
  if (any_live && !snap.live_subscribed) {
    // Client asked for live but subscriber failed.
  }

  snap.live_events_pushed = live_events_pushed_.load();
  snap.live_events_dropped = live_events_dropped_.load();
  {
    std::lock_guard lock(last_live_mu_);
    snap.last_live_event_unix_ms = last_live_event_unix_ms_;
    snap.last_live_event_title = last_live_event_title_;
  }

  snap.ipc_messages_received = ipc_messages_received_.load();
  snap.ipc_messages_sent = ipc_messages_sent_.load();
  snap.ipc_errors = ipc_errors_.load();
  snap.ipc_bytes_received = ipc_bytes_received_.load();
  snap.ipc_bytes_sent = ipc_bytes_sent_.load();
  FillIpcThroughputRates(&snap);

  FillServiceProcessMetrics(&snap);

  // Collectors — health sample rate is documented ~1 Hz when monitoring is on.
  snap.health_monitoring_active = any_health;
  snap.health_sample_rate_hz = any_health ? 1.0 : 0.0;

  EnsureHealthCollector();
  {
    std::lock_guard lock(health_mu_);
    if (health_collector_ready_) {
      const auto info = health_collector_.CollectStatic();
      snap.windows_edition = info.windows_edition;
      snap.windows_version = info.windows_version;
      snap.network_etw_running = health_collector_.network_etw_running();
      snap.network_etw_last_error = health_collector_.network_etw_last_error();
    }
  }

  // Pipeline stages: 0 healthy, 1 warning, 2 error
  if (!snap.live_subscribed && any_live) {
    snap.stage_event_log = 2;
    snap.stage_event_log_detail =
        "Live Event Log subscription is not running";
    snap.stage_detail = snap.stage_event_log_detail;
  } else if (!snap.live_subscribed) {
    snap.stage_event_log = 1;
    snap.stage_event_log_detail =
        "Event Log subscription starts when a client enables live monitoring";
    snap.stage_detail = snap.stage_event_log_detail;
  } else {
    snap.stage_event_log = 0;
    snap.stage_event_log_detail =
        "Subscribed: " +
        (snap.live_channel.empty() ? std::string("channels active")
                                   : snap.live_channel);
  }

  if (snap.stage_event_log == 2) {
    snap.stage_collector = 2;
    snap.stage_collector_detail = "Collector idle — Event Log subscribe failed";
  } else if (snap.live_subscribed) {
    snap.stage_collector = 0;
    snap.stage_collector_detail =
        "Live Event Log collector running; health sample rate " +
        std::to_string(static_cast<int>(snap.health_sample_rate_hz)) + " Hz" +
        (any_health ? " (active)" : " (idle until health monitoring)");
  } else {
    snap.stage_collector = 1;
    snap.stage_collector_detail =
        "Collector waiting for live monitoring; health ETW " +
        std::string(snap.network_etw_running ? "running" : "stopped");
  }

  snap.stage_intelligence = 0;
  snap.stage_intelligence_detail =
      "Humanizer + intelligence applied in-process on Event Log records";

  if (!snap.ipc_listening) {
    snap.stage_ipc = 2;
    snap.stage_ipc_detail = "Named pipe not listening";
  } else if (snap.live_events_dropped > 0 ||
             (snap.live_queue_capacity > 0 &&
              snap.live_queue_depth > snap.live_queue_capacity / 2)) {
    snap.stage_ipc = 1;
    snap.stage_ipc_detail =
        "IPC outbound queue pressure or dropped live events";
    if (snap.stage_detail.empty()) {
      snap.stage_detail = snap.stage_ipc_detail;
    }
  } else {
    snap.stage_ipc = 0;
    snap.stage_ipc_detail =
        "Named pipe listening; clients=" + std::to_string(snap.connected_clients);
  }

  return snap;
}

void IpcServer::InjectTestEvent() {
  EnsureLiveSubscriber();
  ipc::TimelineEvent event;
  const int64_t now = NowUnixMs();
  event.event_id = "pulse-diagnostics-test-" + std::to_string(now);
  event.timestamp_unix_ms = now;
  event.timestamp_iso = "";
  event.severity = ipc::Severity::Info;
  event.channel = "Pulse";
  event.provider_name = "Pulse.Diagnostics";
  event.win_event_id = 0;
  event.record_id = 0;
  event.computer_name = "";
  event.title = "Diagnostics test event";
  event.summary =
      "Synthetic event generated from Pulse Diagnostics. "
      "This was not written to the Windows Event Log.";
  event.technical_summary =
      "InjectDiagnosticsTestEvent — UI/pipeline verification only.";
  event.message = event.summary;
  event.recommendation =
      "If this appears on Timeline, live IPC push is working.";
  event.action_required = false;
  event.importance = ipc::Importance::Low;
  event.category = "diagnostics";
  PushLiveEvent(event);
}

}  // namespace pulse
