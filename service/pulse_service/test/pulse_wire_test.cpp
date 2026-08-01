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
  if (!EncodeEnvelope(snap, &snap_payload)) {
    std::cerr << "timeline encode failed\n";
    return 2;
  }
  Envelope snap_decoded;
  if (!DecodeEnvelope(snap_payload.data(), snap_payload.size(), &snap_decoded) ||
      !std::holds_alternative<TimelineSnapshot>(snap_decoded.body)) {
    std::cerr << "timeline decode failed\n";
    return 2;
  }
  assert(snap_decoded.request_id == 9);
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

  // R2 additive TimelineEvent fields roundtrip.
  TimelineEvent rich;
  rich.event_id = "System|99|41|2026-08-01T00:00:00Z";
  rich.has_process_id = true;
  rich.process_id = 1234;
  rich.process_name = "explorer.exe";
  rich.has_task = true;
  rich.task = 7;
  rich.has_opcode = true;
  rich.opcode = 1;
  rich.has_keywords = true;
  rich.keywords = 0x8000000000000011ULL;
  rich.user_sid = "S-1-5-18";
  rich.activity_id = "{11111111-2222-3333-4444-555555555555}";
  rich.related_activity_id = "{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}";
  rich.level_name = "Critical";
  rich.raw_xml =
      "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'/>";

  Envelope detail_env;
  detail_env.request_id = 11;
  detail_env.body = TimelineEventDetail{true, rich};
  std::vector<uint8_t> detail_payload;
  if (!EncodeEnvelope(detail_env, &detail_payload)) {
    std::cerr << "TimelineEventDetail encode failed\n";
    return 12;
  }
  Envelope detail_decoded;
  if (!DecodeEnvelope(detail_payload.data(), detail_payload.size(),
                      &detail_decoded) ||
      !std::holds_alternative<TimelineEventDetail>(detail_decoded.body)) {
    std::cerr << "TimelineEventDetail decode failed\n";
    return 12;
  }
  const auto& detail_out = std::get<TimelineEventDetail>(detail_decoded.body);
  if (!detail_out.found || !detail_out.event.has_process_id ||
      detail_out.event.process_id != 1234 ||
      detail_out.event.process_name != "explorer.exe" ||
      !detail_out.event.has_keywords ||
      detail_out.event.keywords != 0x8000000000000011ULL ||
      detail_out.event.raw_xml != rich.raw_xml) {
    std::cerr << "TimelineEventDetail fields mismatch\n";
    return 12;
  }

  GetTimelineEventDetail tl_detail_req;
  tl_detail_req.channel = "System";
  tl_detail_req.record_id = 99;
  Envelope tl_detail_req_env;
  tl_detail_req_env.request_id = 12;
  tl_detail_req_env.body = tl_detail_req;
  std::vector<uint8_t> tl_detail_req_payload;
  if (!EncodeEnvelope(tl_detail_req_env, &tl_detail_req_payload)) {
    std::cerr << "GetTimelineEventDetail encode failed\n";
    return 13;
  }
  Envelope tl_detail_req_decoded;
  if (!DecodeEnvelope(tl_detail_req_payload.data(),
                      tl_detail_req_payload.size(), &tl_detail_req_decoded) ||
      !std::holds_alternative<GetTimelineEventDetail>(
          tl_detail_req_decoded.body) ||
      std::get<GetTimelineEventDetail>(tl_detail_req_decoded.body).record_id !=
          99) {
    std::cerr << "GetTimelineEventDetail decode failed\n";
    return 13;
  }

  Envelope req;
  req.request_id = 8;
  req.body = GetTimelineSnapshot{100, "System"};
  std::vector<uint8_t> req_payload;
  assert(EncodeEnvelope(req, &req_payload));
  Envelope req_decoded;
  assert(DecodeEnvelope(req_payload.data(), req_payload.size(), &req_decoded));
  assert(std::holds_alternative<GetTimelineSnapshot>(req_decoded.body));
  assert(std::get<GetTimelineSnapshot>(req_decoded.body).limit == 100);

  // HealthSnapshot / HealthUpdate roundtrip (TASK-007 + issue #11).
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
  HealthVolume vol_c;
  vol_c.id = "C:";
  vol_c.mount_point = "C:\\";
  vol_c.label = "Windows";
  vol_c.file_system = "NTFS";
  vol_c.kind = HealthDriveKind::Fixed;
  vol_c.used_bytes = 200ull * 1024 * 1024 * 1024;
  vol_c.total_bytes = 512ull * 1024 * 1024 * 1024;
  vol_c.has_capacity = true;
  vol_c.included_in_summary = true;
  HealthVolume vol_d;
  vol_d.id = "D:";
  vol_d.mount_point = "D:\\";
  vol_d.kind = HealthDriveKind::Fixed;
  vol_d.used_bytes = 100ull * 1024 * 1024 * 1024;
  vol_d.total_bytes = 1000ull * 1024 * 1024 * 1024;
  vol_d.has_capacity = true;
  vol_d.included_in_summary = true;
  HealthVolume vol_z;
  vol_z.id = "Z:";
  vol_z.mount_point = "Z:\\";
  vol_z.kind = HealthDriveKind::Remote;
  vol_z.has_capacity = false;
  vol_z.included_in_summary = false;
  sample.volumes.push_back(vol_c);
  sample.volumes.push_back(vol_d);
  sample.volumes.push_back(vol_z);
  HealthPhysicalDisk disk0;
  disk0.id = "0 C:";
  disk0.name = "0 C:";
  disk0.has_read_bps = true;
  disk0.read_bps = 1048576.0;
  disk0.has_write_bps = true;
  disk0.write_bps = 524288.0;
  HealthPhysicalDisk disk1;
  disk1.id = "1 D:";
  disk1.name = "1 D:";
  disk1.has_read_bps = true;
  disk1.read_bps = 2048.0;
  sample.disks.push_back(disk0);
  sample.disks.push_back(disk1);
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
  if (!EncodeEnvelope(health_snap, &health_payload) || health_payload.empty()) {
    std::cerr << "health encode failed\n";
    return 3;
  }
  Envelope health_decoded;
  if (!DecodeEnvelope(health_payload.data(), health_payload.size(),
                      &health_decoded) ||
      !std::holds_alternative<HealthSnapshot>(health_decoded.body)) {
    std::cerr << "health decode failed\n";
    return 4;
  }
  assert(health_decoded.request_id == 11);
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
  // Release builds strip assert(); keep explicit checks for multi-volume fields.
  if (hs.sample.volumes.size() != 3 || hs.sample.volumes[0].id != "C:" ||
      hs.sample.volumes[0].kind != HealthDriveKind::Fixed ||
      !hs.sample.volumes[0].has_capacity ||
      !hs.sample.volumes[0].included_in_summary ||
      hs.sample.volumes[1].id != "D:" || hs.sample.volumes[2].id != "Z:" ||
      hs.sample.volumes[2].kind != HealthDriveKind::Remote ||
      hs.sample.volumes[2].has_capacity || hs.sample.disks.size() != 2 ||
      hs.sample.disks[0].id != "0 C:" || !hs.sample.disks[0].has_read_bps ||
      hs.sample.disks[1].id != "1 D:") {
    std::cerr << "health volumes/disks mismatch\n";
    return 5;
  }

  Envelope health_upd;
  health_upd.request_id = 0;
  health_upd.body = HealthUpdate{sample};

  std::vector<uint8_t> upd_payload;
  if (!EncodeEnvelope(health_upd, &upd_payload)) {
    std::cerr << "health update encode failed\n";
    return 6;
  }
  Envelope upd_decoded;
  if (!DecodeEnvelope(upd_payload.data(), upd_payload.size(), &upd_decoded) ||
      !std::holds_alternative<HealthUpdate>(upd_decoded.body)) {
    std::cerr << "health update decode failed\n";
    return 6;
  }
  assert(upd_decoded.request_id == 0);
  const auto& hu = std::get<HealthUpdate>(upd_decoded.body);
  assert(hu.sample.has_cpu_percent == true);
  assert(hu.sample.cpu_percent == 42.5);
  assert(hu.sample.has_gpu_percent == false);
  assert(hu.sample.net_download_bps == 125000.0);

  HealthProcessInventoryUpdate inv;
  inv.seq = 3;
  inv.full_resync = true;
  HealthProcessEntry inv_proc;
  inv_proc.pid = 55;
  inv_proc.name = "Pulse.exe";
  inv_proc.has_cpu_percent = true;
  inv_proc.cpu_percent = 1.5;
  inv_proc.has_create_time = true;
  inv_proc.create_time_unix_ms = 1700000000000ull;
  inv_proc.has_is_critical = true;
  inv_proc.is_critical = false;
  inv.upserts.push_back(inv_proc);
  inv.removed_pids.push_back(9);

  HealthUpdate with_inv;
  with_inv.sample = sample;
  with_inv.process_inventory = inv;
  Envelope inv_env;
  inv_env.request_id = 0;
  inv_env.body = with_inv;
  std::vector<uint8_t> inv_payload;
  if (!EncodeEnvelope(inv_env, &inv_payload)) {
    std::cerr << "inventory encode failed\n";
    return 7;
  }
  Envelope inv_decoded;
  if (!DecodeEnvelope(inv_payload.data(), inv_payload.size(), &inv_decoded) ||
      !std::holds_alternative<HealthUpdate>(inv_decoded.body)) {
    std::cerr << "inventory decode failed\n";
    return 7;
  }
  const auto& hu_inv = std::get<HealthUpdate>(inv_decoded.body);
  if (hu_inv.process_inventory.seq != 3 ||
      !hu_inv.process_inventory.full_resync ||
      hu_inv.process_inventory.upserts.size() != 1 ||
      hu_inv.process_inventory.upserts[0].pid != 55 ||
      hu_inv.process_inventory.upserts[0].name != "Pulse.exe" ||
      hu_inv.process_inventory.upserts[0].create_time_unix_ms !=
          1700000000000ull ||
      hu_inv.process_inventory.removed_pids.size() != 1 ||
      hu_inv.process_inventory.removed_pids[0] != 9) {
    std::cerr << "inventory fields mismatch\n";
    return 8;
  }

  ProcessDetails details;
  details.pid = 55;
  details.name = "Pulse.exe";
  details.path = "C:\\Pulse\\Pulse.exe";
  details.company = "Pulse";
  details.command_line = "Pulse.exe --ui";
  details.has_path = true;
  details.has_company = true;
  details.has_command_line = true;
  details.thread_count = 12;
  details.handle_count = 200;
  details.parent_pid = 4;
  details.has_parent_pid = true;
  details.parent_name = "System";
  details.has_parent_name = true;
  details.user = "NT AUTHORITY\\SYSTEM";
  details.has_user = true;
  details.integrity_level = "System";
  details.has_integrity_level = true;
  details.elevated = true;
  details.has_elevated = true;
  details.architecture = "x64";
  details.has_architecture = true;
  details.product_name = "Pulse";
  details.has_product_name = true;
  Envelope det_env;
  det_env.request_id = 12;
  det_env.body = details;
  std::vector<uint8_t> det_payload;
  if (!EncodeEnvelope(det_env, &det_payload)) {
    std::cerr << "ProcessDetails encode failed\n";
    return 9;
  }
  Envelope det_decoded;
  if (!DecodeEnvelope(det_payload.data(), det_payload.size(), &det_decoded) ||
      !std::holds_alternative<ProcessDetails>(det_decoded.body)) {
    std::cerr << "ProcessDetails decode failed\n";
    return 9;
  }
  const auto& det = std::get<ProcessDetails>(det_decoded.body);
  if (det.pid != 55 || det.company != "Pulse" || !det.has_command_line ||
      det.thread_count != 12 || det.parent_pid != 4 ||
      det.architecture != "x64" || det.product_name != "Pulse") {
    std::cerr << "ProcessDetails fields mismatch\n";
    return 10;
  }

  GetProcessDetails get_det;
  get_det.pid = 4242;
  Envelope get_proc_env;
  get_proc_env.request_id = 13;
  get_proc_env.body = get_det;
  std::vector<uint8_t> get_proc_payload;
  if (!EncodeEnvelope(get_proc_env, &get_proc_payload)) {
    std::cerr << "GetProcessDetails encode failed\n";
    return 11;
  }
  Envelope get_proc_decoded;
  if (!DecodeEnvelope(get_proc_payload.data(), get_proc_payload.size(),
                      &get_proc_decoded) ||
      !std::holds_alternative<GetProcessDetails>(get_proc_decoded.body) ||
      std::get<GetProcessDetails>(get_proc_decoded.body).pid != 4242) {
    std::cerr << "GetProcessDetails decode failed\n";
    return 11;
  }

  std::cout << "pulse_wire_tests OK\n";
  return 0;
}
