#include "pulse_wire.hpp"

#include <cassert>
#include <iostream>

int main() {
  using namespace pulse::ipc;

  Envelope ping;
  ping.request_id = 42;
  ping.body = Ping{7, 123456789};

  std::vector<uint8_t> payload;
  assert(EncodeEnvelope(ping, &payload));

  Envelope decoded;
  assert(DecodeEnvelope(payload.data(), payload.size(), &decoded));
  assert(decoded.request_id == 42);
  assert(std::holds_alternative<Ping>(decoded.body));
  assert(std::get<Ping>(decoded.body).nonce == 7);

  std::vector<uint8_t> frame;
  assert(EncodeFrame(payload, &frame));
  std::vector<uint8_t> frame_payload;
  size_t consumed = 0;
  std::string err;
  assert(TryDecodeFrame(frame.data(), frame.size(), &frame_payload, &consumed, &err));
  assert(consumed == frame.size());
  assert(frame_payload == payload);

  // Oversized length should fail.
  std::vector<uint8_t> bad = {'P', 'U', 'L', 'S', 0xFF, 0xFF, 0xFF, 0x7F};
  assert(!TryDecodeFrame(bad.data(), bad.size(), &frame_payload, &consumed, &err));

  // Historical TimelineSnapshot roundtrip (TASK-002.2).
  TimelineEvent ev;
  ev.event_id = "System|42|7036|2026-07-27T12:00:00Z";
  ev.timestamp_unix_ms = 1722081600000;
  ev.timestamp_iso = "2026-07-27T12:00:00Z";
  ev.severity = Severity::Info;
  ev.channel = "System";
  ev.provider_name = "Service Control Manager";
  ev.win_event_id = 7036;
  ev.record_id = 42;
  ev.computer_name = "DESKTOP";
  ev.summary = "The Windows Update service entered the running state.";
  ev.technical_summary = "Service Control Manager Event ID 7036 · System";
  ev.message = "The Windows Update service entered the running state.";
  ev.title = "Service State Changed";
  ev.recommendation = "Normal operating system behavior.";
  ev.action_required = false;
  ev.importance = Importance::Low;
  ev.category = "Service";

  Envelope snap;
  snap.request_id = 9;
  snap.body = TimelineSnapshot{{ev}, "System", 100, 1722081601000};

  std::vector<uint8_t> snap_payload;
  assert(EncodeEnvelope(snap, &snap_payload));
  Envelope snap_decoded;
  assert(DecodeEnvelope(snap_payload.data(), snap_payload.size(), &snap_decoded));
  assert(snap_decoded.request_id == 9);
  assert(std::holds_alternative<TimelineSnapshot>(snap_decoded.body));
  const auto& out = std::get<TimelineSnapshot>(snap_decoded.body);
  assert(out.channel == "System");
  assert(out.requested_limit == 100);
  assert(out.events.size() == 1);
  assert(out.events[0].win_event_id == 7036);
  assert(out.events[0].summary == ev.summary);
  assert(out.events[0].title == ev.title);
  assert(out.events[0].recommendation == ev.recommendation);
  assert(out.events[0].action_required == ev.action_required);
  assert(out.events[0].importance == ev.importance);
  assert(out.events[0].category == ev.category);

  Envelope req;
  req.request_id = 8;
  req.body = GetTimelineSnapshot{100, "System"};
  std::vector<uint8_t> req_payload;
  assert(EncodeEnvelope(req, &req_payload));
  Envelope req_decoded;
  assert(DecodeEnvelope(req_payload.data(), req_payload.size(), &req_decoded));
  assert(std::holds_alternative<GetTimelineSnapshot>(req_decoded.body));
  assert(std::get<GetTimelineSnapshot>(req_decoded.body).limit == 100);

  // HealthSnapshot / HealthUpdate roundtrip (TASK-007).
  HealthSample sample;
  sample.unix_ms = 1722081602000;
  sample.has_cpu_percent = true;
  sample.cpu_percent = 42.5;
  sample.memory_used_bytes = 8ull * 1024 * 1024 * 1024;
  sample.memory_total_bytes = 16ull * 1024 * 1024 * 1024;
  sample.has_gpu_percent = false;  // unsupported sensor
  sample.gpu_percent = 0.0;
  sample.has_net_download_bps = true;
  sample.net_download_bps = 125000.0;
  sample.has_net_upload_bps = true;
  sample.net_upload_bps = 32000.0;
  sample.has_disk_read_bps = true;
  sample.disk_read_bps = 1048576.0;
  sample.has_disk_write_bps = true;
  sample.disk_write_bps = 524288.0;
  sample.disk_used_bytes = 200ull * 1024 * 1024 * 1024;
  sample.disk_total_bytes = 512ull * 1024 * 1024 * 1024;
  sample.uptime_ms = 3600000;
  sample.has_cpu_temp_c = true;
  sample.cpu_temp_c = 58.25;
  sample.has_gpu_temp_c = false;
  sample.gpu_temp_c = 0.0;
  sample.has_ssd_temp_c = false;
  sample.ssd_temp_c = 0.0;
  sample.has_cpu_current_mhz = true;
  sample.cpu_current_mhz = 4200.0;
  sample.memory_available_bytes = 8ull * 1024 * 1024 * 1024;
  sample.has_memory_committed = true;
  sample.memory_committed_bytes = 10ull * 1024 * 1024 * 1024;
  sample.memory_commit_limit_bytes = 20ull * 1024 * 1024 * 1024;
  sample.has_memory_cached = true;
  sample.memory_cached_bytes = 2ull * 1024 * 1024 * 1024;
  sample.ipv4 = "192.168.1.10";
  sample.ipv6 = "fe80::1";
  sample.gateway = "192.168.1.1";
  sample.dns = "1.1.1.1";
  HealthProcessEntry proc;
  proc.pid = 4242;
  proc.name = "chrome.exe";
  proc.has_cpu_percent = true;
  proc.cpu_percent = 12.25;
  sample.top_cpu.push_back(proc);

  HealthStaticInfo info;
  info.windows_edition = "Windows 11 Pro";
  info.windows_version = "10.0.26100";
  info.cpu_model = "AMD Ryzen 7";
  info.gpu_model = "NVIDIA RTX";
  info.installed_ram_bytes = 16ull * 1024 * 1024 * 1024;
  info.primary_storage_bytes = 512ull * 1024 * 1024 * 1024;
  info.active_network_adapter = "Ethernet";
  info.cpu_base_mhz = 3700;
  info.cpu_sockets = 1;
  info.cpu_cores = 8;
  info.cpu_logical_processors = 16;
  info.cpu_virtualization_enabled = true;
  info.gpu_dedicated_bytes = 12ull * 1024 * 1024 * 1024;
  info.gpu_shared_bytes = 16ull * 1024 * 1024 * 1024;

  Envelope health_snap;
  health_snap.request_id = 11;
  health_snap.body = HealthSnapshot{info, sample};

  std::vector<uint8_t> health_payload;
  assert(EncodeEnvelope(health_snap, &health_payload));
  Envelope health_decoded;
  assert(DecodeEnvelope(health_payload.data(), health_payload.size(), &health_decoded));
  assert(health_decoded.request_id == 11);
  assert(std::holds_alternative<HealthSnapshot>(health_decoded.body));
  const auto& hs = std::get<HealthSnapshot>(health_decoded.body);
  assert(hs.info.windows_edition == "Windows 11 Pro");
  assert(hs.info.cpu_model == "AMD Ryzen 7");
  assert(hs.info.installed_ram_bytes == 16ull * 1024 * 1024 * 1024);
  assert(hs.sample.has_cpu_percent == true);
  assert(hs.sample.cpu_percent == 42.5);
  assert(hs.sample.has_gpu_percent == false);
  assert(hs.sample.memory_used_bytes == 8ull * 1024 * 1024 * 1024);
  assert(hs.sample.has_cpu_temp_c == true);
  assert(hs.sample.cpu_temp_c == 58.25);
  assert(hs.sample.has_ssd_temp_c == false);
  assert(hs.info.cpu_base_mhz == 3700);
  assert(hs.info.cpu_cores == 8);
  assert(hs.info.cpu_virtualization_enabled == true);
  assert(hs.info.gpu_dedicated_bytes == 12ull * 1024 * 1024 * 1024);
  assert(hs.sample.has_cpu_current_mhz == true);
  assert(hs.sample.cpu_current_mhz == 4200.0);
  assert(hs.sample.ipv4 == "192.168.1.10");
  assert(hs.sample.top_cpu.size() == 1);
  assert(hs.sample.top_cpu[0].pid == 4242);
  assert(hs.sample.top_cpu[0].name == "chrome.exe");
  assert(hs.sample.top_cpu[0].cpu_percent == 12.25);

  Envelope health_upd;
  health_upd.request_id = 0;
  health_upd.body = HealthUpdate{sample};

  std::vector<uint8_t> upd_payload;
  assert(EncodeEnvelope(health_upd, &upd_payload));
  Envelope upd_decoded;
  assert(DecodeEnvelope(upd_payload.data(), upd_payload.size(), &upd_decoded));
  assert(upd_decoded.request_id == 0);
  assert(std::holds_alternative<HealthUpdate>(upd_decoded.body));
  const auto& hu = std::get<HealthUpdate>(upd_decoded.body);
  assert(hu.sample.has_cpu_percent == true);
  assert(hu.sample.cpu_percent == 42.5);
  assert(hu.sample.has_gpu_percent == false);
  assert(hu.sample.net_download_bps == 125000.0);

  std::cout << "pulse_wire_tests OK\n";
  return 0;
}
