#pragma once

// Minimal protobuf wire codec for pulse.ipc.Envelope.
// Field numbers match shared/pulse_protocol/proto/pulse.proto.
// Replace with protoc-generated code when codegen is wired in CI.

#include <cstdint>
#include <string>
#include <variant>
#include <vector>

namespace pulse::ipc {

struct ClientHello {
  uint32_t protocol_version = 1;
  std::string client_name;
  std::string client_version;
};

struct ServerHello {
  uint32_t protocol_version = 1;
  std::string service_version;
};

struct Ping {
  uint64_t nonce = 0;
  int64_t unix_ms = 0;
};

struct Pong {
  uint64_t nonce = 0;
  int64_t unix_ms = 0;
  std::string service_version;
};

struct Heartbeat {
  int64_t unix_ms = 0;
};

struct ErrorResponse {
  int32_t code = 0;
  std::string message;
  std::string technical_detail;
  std::string component;
};

enum class Severity : int32_t {
  Unknown = 0,
  Info = 1,
  Warning = 2,
  Error = 3,
  Critical = 4,
  Verbose = 5,
};

enum class Importance : int32_t {
  Low = 0,
  Medium = 1,
  High = 2,
  Critical = 3,
};

struct TimelineEvent {
  std::string event_id;
  int64_t timestamp_unix_ms = 0;
  std::string timestamp_iso;
  Severity severity = Severity::Unknown;
  std::string channel;
  std::string provider_name;
  uint32_t win_event_id = 0;
  uint64_t record_id = 0;
  std::string computer_name;
  std::string summary;
  std::string technical_summary;
  std::string message;
  std::string title;
  std::string recommendation;
  bool action_required = false;
  Importance importance = Importance::Low;
  std::string category;
};

struct GetTimelineSnapshot {
  uint32_t limit = 100;
  std::string channel = "System";
};

struct TimelineSnapshot {
  std::vector<TimelineEvent> events;
  std::string channel;
  uint32_t requested_limit = 0;
  int64_t collected_unix_ms = 0;
};

struct StartLiveMonitoring {
  std::string channel = "System";
};

struct StopLiveMonitoring {};

struct HealthStaticInfo {
  std::string windows_edition;
  std::string windows_version;
  std::string cpu_model;
  std::string gpu_model;
  uint64_t installed_ram_bytes = 0;
  uint64_t primary_storage_bytes = 0;
  std::string active_network_adapter;
  uint32_t cpu_base_mhz = 0;
  uint32_t cpu_sockets = 0;
  uint32_t cpu_cores = 0;
  uint32_t cpu_logical_processors = 0;
  bool cpu_virtualization_enabled = false;
  uint64_t gpu_dedicated_bytes = 0;
  uint64_t gpu_shared_bytes = 0;
};

struct HealthProcessEntry {
  uint32_t pid = 0;
  std::string name;
  bool has_cpu_percent = false;
  double cpu_percent = 0.0;
  bool has_memory_bytes = false;
  uint64_t memory_bytes = 0;
  bool has_gpu_percent = false;
  double gpu_percent = 0.0;
  bool has_disk_bps = false;
  double disk_bps = 0.0;
  bool has_net_bps = false;
  double net_bps = 0.0;
  std::string path;
};

struct HealthSample {
  int64_t unix_ms = 0;
  bool has_cpu_percent = false;
  double cpu_percent = 0.0;
  uint64_t memory_used_bytes = 0;
  uint64_t memory_total_bytes = 0;
  bool has_gpu_percent = false;
  double gpu_percent = 0.0;
  bool has_net_download_bps = false;
  double net_download_bps = 0.0;
  bool has_net_upload_bps = false;
  double net_upload_bps = 0.0;
  bool has_disk_read_bps = false;
  double disk_read_bps = 0.0;
  bool has_disk_write_bps = false;
  double disk_write_bps = 0.0;
  uint64_t disk_used_bytes = 0;
  uint64_t disk_total_bytes = 0;
  uint64_t uptime_ms = 0;
  bool has_cpu_temp_c = false;
  double cpu_temp_c = 0.0;
  bool has_gpu_temp_c = false;
  double gpu_temp_c = 0.0;
  bool has_ssd_temp_c = false;
  double ssd_temp_c = 0.0;
  bool has_cpu_current_mhz = false;
  double cpu_current_mhz = 0.0;
  uint64_t memory_available_bytes = 0;
  bool has_memory_committed = false;
  uint64_t memory_committed_bytes = 0;
  uint64_t memory_commit_limit_bytes = 0;
  bool has_memory_cached = false;
  uint64_t memory_cached_bytes = 0;
  std::string ipv4;
  std::string ipv6;
  std::string gateway;
  std::string dns;
  std::vector<HealthProcessEntry> top_cpu;
  std::vector<HealthProcessEntry> top_memory;
  std::vector<HealthProcessEntry> top_gpu;
  std::vector<HealthProcessEntry> top_disk;
  std::vector<HealthProcessEntry> top_network;
  std::vector<double> cpu_core_percent;
};

struct GetHealthSnapshot {};

struct HealthSnapshot {
  HealthStaticInfo info;
  HealthSample sample;
};

struct HealthUpdate {
  HealthSample sample;
};

struct StartHealthMonitoring {};

struct StopHealthMonitoring {};

// --- Diagnostics (TASK-008) ---

struct GetDiagnosticsSnapshot {};

// Pipeline stage health: 0 = healthy, 1 = warning, 2 = error.
struct DiagnosticsSnapshot {
  std::string service_version;
  uint32_t protocol_version = 0;
  int64_t service_start_unix_ms = 0;
  uint64_t service_uptime_ms = 0;
  std::string run_mode;
  bool ipc_listening = false;

  bool live_subscribed = false;
  std::string live_channel;
  uint64_t live_events_pushed = 0;
  uint64_t live_events_dropped = 0;
  uint64_t live_subscriber_reconnects = 0;
  int64_t last_live_event_unix_ms = 0;
  std::string last_live_event_title;
  uint32_t live_queue_depth = 0;
  uint32_t live_queue_capacity = 0;

  uint64_t ipc_messages_received = 0;
  uint64_t ipc_messages_sent = 0;
  uint64_t ipc_errors = 0;
  uint32_t connected_clients = 0;

  uint32_t service_pid = 0;
  bool has_cpu_percent = false;
  double cpu_percent = 0.0;
  uint64_t working_set_bytes = 0;
  uint32_t thread_count = 0;
  uint32_t handle_count = 0;

  int32_t stage_event_log = 0;
  int32_t stage_collector = 0;
  int32_t stage_intelligence = 0;
  int32_t stage_ipc = 0;
  std::string stage_detail;

  std::string windows_edition;
  std::string windows_version;
};

struct InjectDiagnosticsTestEvent {};

struct Envelope {
  uint64_t request_id = 0;
  std::variant<std::monostate, ClientHello, ServerHello, Ping, Pong, Heartbeat,
               GetTimelineSnapshot, TimelineSnapshot, TimelineEvent,
               StartLiveMonitoring, StopLiveMonitoring, GetHealthSnapshot,
               HealthSnapshot, HealthUpdate, StartHealthMonitoring,
               StopHealthMonitoring, GetDiagnosticsSnapshot,
               DiagnosticsSnapshot, InjectDiagnosticsTestEvent, ErrorResponse>
      body;
};

bool EncodeEnvelope(const Envelope& env, std::vector<uint8_t>* out);
bool DecodeEnvelope(const uint8_t* data, size_t len, Envelope* out);

// Frame: magic(4) + length(4 LE) + payload
bool EncodeFrame(const std::vector<uint8_t>& payload, std::vector<uint8_t>* out);
bool TryDecodeFrame(const uint8_t* data, size_t len, std::vector<uint8_t>* payload,
                    size_t* consumed_bytes, std::string* error);

}  // namespace pulse::ipc
