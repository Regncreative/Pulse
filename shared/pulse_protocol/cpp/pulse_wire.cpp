#include "pulse_wire.hpp"

#include "pulse/constants.hpp"

#include <cstring>

namespace pulse::ipc {
namespace {

void WriteVarint(uint64_t v, std::vector<uint8_t>* out) {
  while (v >= 0x80) {
    out->push_back(static_cast<uint8_t>(v | 0x80));
    v >>= 7;
  }
  out->push_back(static_cast<uint8_t>(v));
}

bool ReadVarint(const uint8_t*& p, const uint8_t* end, uint64_t* out) {
  uint64_t result = 0;
  int shift = 0;
  while (p < end && shift < 64) {
    const uint8_t b = *p++;
    result |= static_cast<uint64_t>(b & 0x7F) << shift;
    if ((b & 0x80) == 0) {
      *out = result;
      return true;
    }
    shift += 7;
  }
  return false;
}

void WriteTag(uint32_t field, uint32_t wire, std::vector<uint8_t>* out) {
  WriteVarint((static_cast<uint64_t>(field) << 3) | wire, out);
}

void WriteString(uint32_t field, const std::string& s, std::vector<uint8_t>* out) {
  WriteTag(field, 2, out);
  WriteVarint(s.size(), out);
  out->insert(out->end(), s.begin(), s.end());
}

void WriteU64(uint32_t field, uint64_t v, std::vector<uint8_t>* out) {
  WriteTag(field, 0, out);
  WriteVarint(v, out);
}

void WriteI64(uint32_t field, int64_t v, std::vector<uint8_t>* out) {
  WriteU64(field, static_cast<uint64_t>(v), out);
}

void WriteU32(uint32_t field, uint32_t v, std::vector<uint8_t>* out) {
  WriteU64(field, v, out);
}

void WriteI32(uint32_t field, int32_t v, std::vector<uint8_t>* out) {
  WriteU64(field, static_cast<uint64_t>(static_cast<uint32_t>(v)), out);
}

void WriteBool(uint32_t field, bool v, std::vector<uint8_t>* out) {
  WriteU64(field, v ? 1u : 0u, out);
}

void WriteDouble(uint32_t field, double v, std::vector<uint8_t>* out) {
  WriteTag(field, 1, out);
  uint64_t bits = 0;
  static_assert(sizeof(double) == 8, "double must be IEEE754 binary64");
  std::memcpy(&bits, &v, sizeof(bits));
  for (int i = 0; i < 8; ++i) {
    out->push_back(static_cast<uint8_t>((bits >> (i * 8)) & 0xFF));
  }
}

bool ReadDouble(const uint8_t*& p, const uint8_t* end, double* out) {
  if (p + 8 > end) return false;
  uint64_t bits = 0;
  for (int i = 0; i < 8; ++i) {
    bits |= static_cast<uint64_t>(p[i]) << (i * 8);
  }
  p += 8;
  std::memcpy(out, &bits, sizeof(*out));
  return true;
}

void WriteBytesField(uint32_t field, const std::vector<uint8_t>& bytes,
                     std::vector<uint8_t>* out) {
  WriteTag(field, 2, out);
  WriteVarint(bytes.size(), out);
  out->insert(out->end(), bytes.begin(), bytes.end());
}

std::vector<uint8_t> EncodeClientHello(const ClientHello& m) {
  std::vector<uint8_t> out;
  WriteU32(1, m.protocol_version, &out);
  WriteString(2, m.client_name, &out);
  WriteString(3, m.client_version, &out);
  return out;
}

std::vector<uint8_t> EncodeServerHello(const ServerHello& m) {
  std::vector<uint8_t> out;
  WriteU32(1, m.protocol_version, &out);
  WriteString(2, m.service_version, &out);
  return out;
}

std::vector<uint8_t> EncodePing(const Ping& m) {
  std::vector<uint8_t> out;
  WriteU64(1, m.nonce, &out);
  WriteI64(2, m.unix_ms, &out);
  return out;
}

std::vector<uint8_t> EncodePong(const Pong& m) {
  std::vector<uint8_t> out;
  WriteU64(1, m.nonce, &out);
  WriteI64(2, m.unix_ms, &out);
  WriteString(3, m.service_version, &out);
  return out;
}

std::vector<uint8_t> EncodeHeartbeat(const Heartbeat& m) {
  std::vector<uint8_t> out;
  WriteI64(1, m.unix_ms, &out);
  return out;
}

std::vector<uint8_t> EncodeError(const ErrorResponse& m) {
  std::vector<uint8_t> out;
  WriteI32(1, m.code, &out);
  WriteString(2, m.message, &out);
  WriteString(3, m.technical_detail, &out);
  WriteString(4, m.component, &out);
  return out;
}

std::vector<uint8_t> EncodeTimelineEvent(const TimelineEvent& m) {
  std::vector<uint8_t> out;
  WriteString(1, m.event_id, &out);
  WriteI64(2, m.timestamp_unix_ms, &out);
  WriteString(3, m.timestamp_iso, &out);
  WriteI32(4, static_cast<int32_t>(m.severity), &out);
  WriteString(5, m.channel, &out);
  WriteString(6, m.provider_name, &out);
  WriteU32(7, m.win_event_id, &out);
  WriteU64(8, m.record_id, &out);
  WriteString(9, m.computer_name, &out);
  WriteString(10, m.summary, &out);
  WriteString(11, m.technical_summary, &out);
  WriteString(12, m.message, &out);
  WriteString(13, m.title, &out);
  WriteString(14, m.recommendation, &out);
  WriteU32(15, m.action_required ? 1u : 0u, &out);
  WriteI32(16, static_cast<int32_t>(m.importance), &out);
  WriteString(17, m.category, &out);
  return out;
}

std::vector<uint8_t> EncodeGetTimelineSnapshot(const GetTimelineSnapshot& m) {
  std::vector<uint8_t> out;
  WriteU32(1, m.limit, &out);
  WriteString(2, m.channel, &out);
  return out;
}

std::vector<uint8_t> EncodeTimelineSnapshot(const TimelineSnapshot& m) {
  std::vector<uint8_t> out;
  for (const auto& event : m.events) {
    WriteBytesField(1, EncodeTimelineEvent(event), &out);
  }
  WriteString(2, m.channel, &out);
  WriteU32(3, m.requested_limit, &out);
  WriteI64(4, m.collected_unix_ms, &out);
  return out;
}

std::vector<uint8_t> EncodeStartLiveMonitoring(const StartLiveMonitoring& m) {
  std::vector<uint8_t> out;
  WriteString(1, m.channel, &out);
  return out;
}

std::vector<uint8_t> EncodeStopLiveMonitoring(const StopLiveMonitoring&) {
  return {};
}

std::vector<uint8_t> EncodeHealthProcessEntry(const HealthProcessEntry& m) {
  std::vector<uint8_t> out;
  WriteU32(1, m.pid, &out);
  WriteString(2, m.name, &out);
  WriteBool(3, m.has_cpu_percent, &out);
  WriteDouble(4, m.cpu_percent, &out);
  WriteBool(5, m.has_memory_bytes, &out);
  WriteU64(6, m.memory_bytes, &out);
  WriteBool(7, m.has_gpu_percent, &out);
  WriteDouble(8, m.gpu_percent, &out);
  WriteBool(9, m.has_disk_bps, &out);
  WriteDouble(10, m.disk_bps, &out);
  WriteBool(11, m.has_net_bps, &out);
  WriteDouble(12, m.net_bps, &out);
  WriteString(13, m.path, &out);
  return out;
}

std::vector<uint8_t> EncodeHealthStaticInfo(const HealthStaticInfo& m) {
  std::vector<uint8_t> out;
  WriteString(1, m.windows_edition, &out);
  WriteString(2, m.windows_version, &out);
  WriteString(3, m.cpu_model, &out);
  WriteString(4, m.gpu_model, &out);
  WriteU64(5, m.installed_ram_bytes, &out);
  WriteU64(6, m.primary_storage_bytes, &out);
  WriteString(7, m.active_network_adapter, &out);
  WriteU32(8, m.cpu_base_mhz, &out);
  WriteU32(9, m.cpu_sockets, &out);
  WriteU32(10, m.cpu_cores, &out);
  WriteU32(11, m.cpu_logical_processors, &out);
  WriteBool(12, m.cpu_virtualization_enabled, &out);
  WriteU64(13, m.gpu_dedicated_bytes, &out);
  WriteU64(14, m.gpu_shared_bytes, &out);
  return out;
}

std::vector<uint8_t> EncodeHealthSample(const HealthSample& m) {
  std::vector<uint8_t> out;
  WriteI64(1, m.unix_ms, &out);
  WriteBool(2, m.has_cpu_percent, &out);
  WriteDouble(3, m.cpu_percent, &out);
  WriteU64(4, m.memory_used_bytes, &out);
  WriteU64(5, m.memory_total_bytes, &out);
  WriteBool(6, m.has_gpu_percent, &out);
  WriteDouble(7, m.gpu_percent, &out);
  WriteBool(8, m.has_net_download_bps, &out);
  WriteDouble(9, m.net_download_bps, &out);
  WriteBool(10, m.has_net_upload_bps, &out);
  WriteDouble(11, m.net_upload_bps, &out);
  WriteBool(12, m.has_disk_read_bps, &out);
  WriteDouble(13, m.disk_read_bps, &out);
  WriteBool(14, m.has_disk_write_bps, &out);
  WriteDouble(15, m.disk_write_bps, &out);
  WriteU64(16, m.disk_used_bytes, &out);
  WriteU64(17, m.disk_total_bytes, &out);
  WriteU64(18, m.uptime_ms, &out);
  WriteBool(19, m.has_cpu_temp_c, &out);
  WriteDouble(20, m.cpu_temp_c, &out);
  WriteBool(21, m.has_gpu_temp_c, &out);
  WriteDouble(22, m.gpu_temp_c, &out);
  WriteBool(23, m.has_ssd_temp_c, &out);
  WriteDouble(24, m.ssd_temp_c, &out);
  WriteBool(25, m.has_cpu_current_mhz, &out);
  WriteDouble(26, m.cpu_current_mhz, &out);
  WriteU64(27, m.memory_available_bytes, &out);
  WriteBool(28, m.has_memory_committed, &out);
  WriteU64(29, m.memory_committed_bytes, &out);
  WriteU64(30, m.memory_commit_limit_bytes, &out);
  WriteBool(31, m.has_memory_cached, &out);
  WriteU64(32, m.memory_cached_bytes, &out);
  WriteString(33, m.ipv4, &out);
  WriteString(34, m.ipv6, &out);
  WriteString(35, m.gateway, &out);
  WriteString(36, m.dns, &out);
  for (const auto& e : m.top_cpu) {
    WriteBytesField(37, EncodeHealthProcessEntry(e), &out);
  }
  for (const auto& e : m.top_memory) {
    WriteBytesField(38, EncodeHealthProcessEntry(e), &out);
  }
  for (const auto& e : m.top_gpu) {
    WriteBytesField(39, EncodeHealthProcessEntry(e), &out);
  }
  for (const auto& e : m.top_disk) {
    WriteBytesField(40, EncodeHealthProcessEntry(e), &out);
  }
  for (const auto& e : m.top_network) {
    WriteBytesField(41, EncodeHealthProcessEntry(e), &out);
  }
  for (double core : m.cpu_core_percent) {
    WriteDouble(42, core, &out);
  }
  return out;
}

std::vector<uint8_t> EncodeGetHealthSnapshot(const GetHealthSnapshot&) {
  return {};
}

std::vector<uint8_t> EncodeHealthSnapshot(const HealthSnapshot& m) {
  std::vector<uint8_t> out;
  WriteBytesField(1, EncodeHealthStaticInfo(m.info), &out);
  WriteBytesField(2, EncodeHealthSample(m.sample), &out);
  return out;
}

std::vector<uint8_t> EncodeHealthUpdate(const HealthUpdate& m) {
  std::vector<uint8_t> out;
  WriteBytesField(1, EncodeHealthSample(m.sample), &out);
  return out;
}

std::vector<uint8_t> EncodeStartHealthMonitoring(const StartHealthMonitoring&) {
  return {};
}

std::vector<uint8_t> EncodeStopHealthMonitoring(const StopHealthMonitoring&) {
  return {};
}

std::vector<uint8_t> EncodeGetDiagnosticsSnapshot(const GetDiagnosticsSnapshot&) {
  return {};
}

std::vector<uint8_t> EncodeDiagnosticsSnapshot(const DiagnosticsSnapshot& m) {
  std::vector<uint8_t> out;
  WriteString(1, m.service_version, &out);
  WriteU32(2, m.protocol_version, &out);
  WriteI64(3, m.service_start_unix_ms, &out);
  WriteU64(4, m.service_uptime_ms, &out);
  WriteString(5, m.run_mode, &out);
  WriteBool(6, m.ipc_listening, &out);

  WriteBool(7, m.live_subscribed, &out);
  WriteString(8, m.live_channel, &out);
  WriteU64(9, m.live_events_pushed, &out);
  WriteU64(10, m.live_events_dropped, &out);
  WriteU64(11, m.live_subscriber_reconnects, &out);
  WriteI64(12, m.last_live_event_unix_ms, &out);
  WriteString(13, m.last_live_event_title, &out);
  WriteU32(14, m.live_queue_depth, &out);
  WriteU32(15, m.live_queue_capacity, &out);

  WriteU64(16, m.ipc_messages_received, &out);
  WriteU64(17, m.ipc_messages_sent, &out);
  WriteU64(18, m.ipc_errors, &out);
  WriteU32(19, m.connected_clients, &out);

  WriteU32(20, m.service_pid, &out);
  WriteBool(21, m.has_cpu_percent, &out);
  WriteDouble(22, m.cpu_percent, &out);
  WriteU64(23, m.working_set_bytes, &out);
  WriteU32(24, m.thread_count, &out);
  WriteU32(25, m.handle_count, &out);

  WriteI32(26, m.stage_event_log, &out);
  WriteI32(27, m.stage_collector, &out);
  WriteI32(28, m.stage_intelligence, &out);
  WriteI32(29, m.stage_ipc, &out);
  WriteString(30, m.stage_detail, &out);

  WriteString(31, m.windows_edition, &out);
  WriteString(32, m.windows_version, &out);
  return out;
}

std::vector<uint8_t> EncodeInjectDiagnosticsTestEvent(const InjectDiagnosticsTestEvent&) {
  return {};
}

bool DecodeString(const uint8_t*& p, const uint8_t* end, std::string* s) {
  uint64_t len = 0;
  if (!ReadVarint(p, end, &len)) return false;
  if (p + len > end) return false;
  s->assign(reinterpret_cast<const char*>(p), static_cast<size_t>(len));
  p += len;
  return true;
}

bool SkipField(uint32_t wire, const uint8_t*& p, const uint8_t* end) {
  uint64_t v = 0;
  switch (wire) {
    case 0:
      return ReadVarint(p, end, &v);
    case 1:
      if (p + 8 > end) return false;
      p += 8;
      return true;
    case 2: {
      if (!ReadVarint(p, end, &v)) return false;
      if (p + v > end) return false;
      p += static_cast<size_t>(v);
      return true;
    }
    case 5:
      if (p + 4 > end) return false;
      p += 4;
      return true;
    default:
      return false;
  }
}

bool DecodeClientHello(const uint8_t* data, size_t len, ClientHello* m) {
  const uint8_t* p = data;
  const uint8_t* end = data + len;
  while (p < end) {
    uint64_t tag = 0;
    if (!ReadVarint(p, end, &tag)) return false;
    const uint32_t field = static_cast<uint32_t>(tag >> 3);
    const uint32_t wire = static_cast<uint32_t>(tag & 7);
    if (field == 1 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->protocol_version = static_cast<uint32_t>(v);
    } else if (field == 2 && wire == 2) {
      if (!DecodeString(p, end, &m->client_name)) return false;
    } else if (field == 3 && wire == 2) {
      if (!DecodeString(p, end, &m->client_version)) return false;
    } else if (!SkipField(wire, p, end)) {
      return false;
    }
  }
  return true;
}

bool DecodeServerHello(const uint8_t* data, size_t len, ServerHello* m) {
  const uint8_t* p = data;
  const uint8_t* end = data + len;
  while (p < end) {
    uint64_t tag = 0;
    if (!ReadVarint(p, end, &tag)) return false;
    const uint32_t field = static_cast<uint32_t>(tag >> 3);
    const uint32_t wire = static_cast<uint32_t>(tag & 7);
    if (field == 1 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->protocol_version = static_cast<uint32_t>(v);
    } else if (field == 2 && wire == 2) {
      if (!DecodeString(p, end, &m->service_version)) return false;
    } else if (!SkipField(wire, p, end)) {
      return false;
    }
  }
  return true;
}

bool DecodePing(const uint8_t* data, size_t len, Ping* m) {
  const uint8_t* p = data;
  const uint8_t* end = data + len;
  while (p < end) {
    uint64_t tag = 0;
    if (!ReadVarint(p, end, &tag)) return false;
    const uint32_t field = static_cast<uint32_t>(tag >> 3);
    const uint32_t wire = static_cast<uint32_t>(tag & 7);
    if (field == 1 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->nonce = v;
    } else if (field == 2 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->unix_ms = static_cast<int64_t>(v);
    } else if (!SkipField(wire, p, end)) {
      return false;
    }
  }
  return true;
}

bool DecodePong(const uint8_t* data, size_t len, Pong* m) {
  const uint8_t* p = data;
  const uint8_t* end = data + len;
  while (p < end) {
    uint64_t tag = 0;
    if (!ReadVarint(p, end, &tag)) return false;
    const uint32_t field = static_cast<uint32_t>(tag >> 3);
    const uint32_t wire = static_cast<uint32_t>(tag & 7);
    if (field == 1 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->nonce = v;
    } else if (field == 2 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->unix_ms = static_cast<int64_t>(v);
    } else if (field == 3 && wire == 2) {
      if (!DecodeString(p, end, &m->service_version)) return false;
    } else if (!SkipField(wire, p, end)) {
      return false;
    }
  }
  return true;
}

bool DecodeHeartbeat(const uint8_t* data, size_t len, Heartbeat* m) {
  const uint8_t* p = data;
  const uint8_t* end = data + len;
  while (p < end) {
    uint64_t tag = 0;
    if (!ReadVarint(p, end, &tag)) return false;
    const uint32_t field = static_cast<uint32_t>(tag >> 3);
    const uint32_t wire = static_cast<uint32_t>(tag & 7);
    if (field == 1 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->unix_ms = static_cast<int64_t>(v);
    } else if (!SkipField(wire, p, end)) {
      return false;
    }
  }
  return true;
}

bool DecodeError(const uint8_t* data, size_t len, ErrorResponse* m) {
  const uint8_t* p = data;
  const uint8_t* end = data + len;
  while (p < end) {
    uint64_t tag = 0;
    if (!ReadVarint(p, end, &tag)) return false;
    const uint32_t field = static_cast<uint32_t>(tag >> 3);
    const uint32_t wire = static_cast<uint32_t>(tag & 7);
    if (field == 1 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->code = static_cast<int32_t>(v);
    } else if (field == 2 && wire == 2) {
      if (!DecodeString(p, end, &m->message)) return false;
    } else if (field == 3 && wire == 2) {
      if (!DecodeString(p, end, &m->technical_detail)) return false;
    } else if (field == 4 && wire == 2) {
      if (!DecodeString(p, end, &m->component)) return false;
    } else if (!SkipField(wire, p, end)) {
      return false;
    }
  }
  return true;
}

bool DecodeTimelineEvent(const uint8_t* data, size_t len, TimelineEvent* m) {
  const uint8_t* p = data;
  const uint8_t* end = data + len;
  while (p < end) {
    uint64_t tag = 0;
    if (!ReadVarint(p, end, &tag)) return false;
    const uint32_t field = static_cast<uint32_t>(tag >> 3);
    const uint32_t wire = static_cast<uint32_t>(tag & 7);
    if (field == 1 && wire == 2) {
      if (!DecodeString(p, end, &m->event_id)) return false;
    } else if (field == 2 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->timestamp_unix_ms = static_cast<int64_t>(v);
    } else if (field == 3 && wire == 2) {
      if (!DecodeString(p, end, &m->timestamp_iso)) return false;
    } else if (field == 4 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->severity = static_cast<Severity>(static_cast<int32_t>(v));
    } else if (field == 5 && wire == 2) {
      if (!DecodeString(p, end, &m->channel)) return false;
    } else if (field == 6 && wire == 2) {
      if (!DecodeString(p, end, &m->provider_name)) return false;
    } else if (field == 7 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->win_event_id = static_cast<uint32_t>(v);
    } else if (field == 8 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->record_id = v;
    } else if (field == 9 && wire == 2) {
      if (!DecodeString(p, end, &m->computer_name)) return false;
    } else if (field == 10 && wire == 2) {
      if (!DecodeString(p, end, &m->summary)) return false;
    } else if (field == 11 && wire == 2) {
      if (!DecodeString(p, end, &m->technical_summary)) return false;
    } else if (field == 12 && wire == 2) {
      if (!DecodeString(p, end, &m->message)) return false;
    } else if (field == 13 && wire == 2) {
      if (!DecodeString(p, end, &m->title)) return false;
    } else if (field == 14 && wire == 2) {
      if (!DecodeString(p, end, &m->recommendation)) return false;
    } else if (field == 15 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->action_required = v != 0;
    } else if (field == 16 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->importance = static_cast<Importance>(static_cast<int32_t>(v));
    } else if (field == 17 && wire == 2) {
      if (!DecodeString(p, end, &m->category)) return false;
    } else if (!SkipField(wire, p, end)) {
      return false;
    }
  }
  return true;
}

bool DecodeGetTimelineSnapshot(const uint8_t* data, size_t len,
                               GetTimelineSnapshot* m) {
  const uint8_t* p = data;
  const uint8_t* end = data + len;
  while (p < end) {
    uint64_t tag = 0;
    if (!ReadVarint(p, end, &tag)) return false;
    const uint32_t field = static_cast<uint32_t>(tag >> 3);
    const uint32_t wire = static_cast<uint32_t>(tag & 7);
    if (field == 1 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->limit = static_cast<uint32_t>(v);
    } else if (field == 2 && wire == 2) {
      if (!DecodeString(p, end, &m->channel)) return false;
    } else if (!SkipField(wire, p, end)) {
      return false;
    }
  }
  return true;
}

bool DecodeTimelineSnapshot(const uint8_t* data, size_t len,
                            TimelineSnapshot* m) {
  const uint8_t* p = data;
  const uint8_t* end = data + len;
  while (p < end) {
    uint64_t tag = 0;
    if (!ReadVarint(p, end, &tag)) return false;
    const uint32_t field = static_cast<uint32_t>(tag >> 3);
    const uint32_t wire = static_cast<uint32_t>(tag & 7);
    if (field == 1 && wire == 2) {
      uint64_t blen = 0;
      if (!ReadVarint(p, end, &blen)) return false;
      if (p + blen > end) return false;
      TimelineEvent event;
      if (!DecodeTimelineEvent(p, static_cast<size_t>(blen), &event)) return false;
      p += static_cast<size_t>(blen);
      m->events.push_back(std::move(event));
    } else if (field == 2 && wire == 2) {
      if (!DecodeString(p, end, &m->channel)) return false;
    } else if (field == 3 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->requested_limit = static_cast<uint32_t>(v);
    } else if (field == 4 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->collected_unix_ms = static_cast<int64_t>(v);
    } else if (!SkipField(wire, p, end)) {
      return false;
    }
  }
  return true;
}

bool DecodeStartLiveMonitoring(const uint8_t* data, size_t len,
                               StartLiveMonitoring* m) {
  const uint8_t* p = data;
  const uint8_t* end = data + len;
  while (p < end) {
    uint64_t tag = 0;
    if (!ReadVarint(p, end, &tag)) return false;
    const uint32_t field = static_cast<uint32_t>(tag >> 3);
    const uint32_t wire = static_cast<uint32_t>(tag & 7);
    if (field == 1 && wire == 2) {
      if (!DecodeString(p, end, &m->channel)) return false;
    } else if (!SkipField(wire, p, end)) {
      return false;
    }
  }
  return true;
}

bool DecodeStopLiveMonitoring(const uint8_t* data, size_t len,
                              StopLiveMonitoring* /*m*/) {
  const uint8_t* p = data;
  const uint8_t* end = data + len;
  while (p < end) {
    uint64_t tag = 0;
    if (!ReadVarint(p, end, &tag)) return false;
    const uint32_t wire = static_cast<uint32_t>(tag & 7);
    if (!SkipField(wire, p, end)) return false;
  }
  return true;
}

bool DecodeHealthProcessEntry(const uint8_t* data, size_t len,
                              HealthProcessEntry* m) {
  const uint8_t* p = data;
  const uint8_t* end = data + len;
  while (p < end) {
    uint64_t tag = 0;
    if (!ReadVarint(p, end, &tag)) return false;
    const uint32_t field = static_cast<uint32_t>(tag >> 3);
    const uint32_t wire = static_cast<uint32_t>(tag & 7);
    if (field == 1 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->pid = static_cast<uint32_t>(v);
    } else if (field == 2 && wire == 2) {
      if (!DecodeString(p, end, &m->name)) return false;
    } else if (field == 3 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->has_cpu_percent = v != 0;
    } else if (field == 4 && wire == 1) {
      if (!ReadDouble(p, end, &m->cpu_percent)) return false;
    } else if (field == 5 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->has_memory_bytes = v != 0;
    } else if (field == 6 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->memory_bytes = v;
    } else if (field == 7 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->has_gpu_percent = v != 0;
    } else if (field == 8 && wire == 1) {
      if (!ReadDouble(p, end, &m->gpu_percent)) return false;
    } else if (field == 9 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->has_disk_bps = v != 0;
    } else if (field == 10 && wire == 1) {
      if (!ReadDouble(p, end, &m->disk_bps)) return false;
    } else if (field == 11 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->has_net_bps = v != 0;
    } else if (field == 12 && wire == 1) {
      if (!ReadDouble(p, end, &m->net_bps)) return false;
    } else if (field == 13 && wire == 2) {
      if (!DecodeString(p, end, &m->path)) return false;
    } else if (!SkipField(wire, p, end)) {
      return false;
    }
  }
  return true;
}

bool DecodeHealthStaticInfo(const uint8_t* data, size_t len, HealthStaticInfo* m) {
  const uint8_t* p = data;
  const uint8_t* end = data + len;
  while (p < end) {
    uint64_t tag = 0;
    if (!ReadVarint(p, end, &tag)) return false;
    const uint32_t field = static_cast<uint32_t>(tag >> 3);
    const uint32_t wire = static_cast<uint32_t>(tag & 7);
    if (field == 1 && wire == 2) {
      if (!DecodeString(p, end, &m->windows_edition)) return false;
    } else if (field == 2 && wire == 2) {
      if (!DecodeString(p, end, &m->windows_version)) return false;
    } else if (field == 3 && wire == 2) {
      if (!DecodeString(p, end, &m->cpu_model)) return false;
    } else if (field == 4 && wire == 2) {
      if (!DecodeString(p, end, &m->gpu_model)) return false;
    } else if (field == 5 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->installed_ram_bytes = v;
    } else if (field == 6 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->primary_storage_bytes = v;
    } else if (field == 7 && wire == 2) {
      if (!DecodeString(p, end, &m->active_network_adapter)) return false;
    } else if (field == 8 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->cpu_base_mhz = static_cast<uint32_t>(v);
    } else if (field == 9 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->cpu_sockets = static_cast<uint32_t>(v);
    } else if (field == 10 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->cpu_cores = static_cast<uint32_t>(v);
    } else if (field == 11 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->cpu_logical_processors = static_cast<uint32_t>(v);
    } else if (field == 12 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->cpu_virtualization_enabled = v != 0;
    } else if (field == 13 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->gpu_dedicated_bytes = v;
    } else if (field == 14 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->gpu_shared_bytes = v;
    } else if (!SkipField(wire, p, end)) {
      return false;
    }
  }
  return true;
}

bool DecodeHealthSample(const uint8_t* data, size_t len, HealthSample* m) {
  const uint8_t* p = data;
  const uint8_t* end = data + len;
  while (p < end) {
    uint64_t tag = 0;
    if (!ReadVarint(p, end, &tag)) return false;
    const uint32_t field = static_cast<uint32_t>(tag >> 3);
    const uint32_t wire = static_cast<uint32_t>(tag & 7);
    if (field == 1 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->unix_ms = static_cast<int64_t>(v);
    } else if (field == 2 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->has_cpu_percent = v != 0;
    } else if (field == 3 && wire == 1) {
      if (!ReadDouble(p, end, &m->cpu_percent)) return false;
    } else if (field == 4 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->memory_used_bytes = v;
    } else if (field == 5 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->memory_total_bytes = v;
    } else if (field == 6 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->has_gpu_percent = v != 0;
    } else if (field == 7 && wire == 1) {
      if (!ReadDouble(p, end, &m->gpu_percent)) return false;
    } else if (field == 8 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->has_net_download_bps = v != 0;
    } else if (field == 9 && wire == 1) {
      if (!ReadDouble(p, end, &m->net_download_bps)) return false;
    } else if (field == 10 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->has_net_upload_bps = v != 0;
    } else if (field == 11 && wire == 1) {
      if (!ReadDouble(p, end, &m->net_upload_bps)) return false;
    } else if (field == 12 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->has_disk_read_bps = v != 0;
    } else if (field == 13 && wire == 1) {
      if (!ReadDouble(p, end, &m->disk_read_bps)) return false;
    } else if (field == 14 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->has_disk_write_bps = v != 0;
    } else if (field == 15 && wire == 1) {
      if (!ReadDouble(p, end, &m->disk_write_bps)) return false;
    } else if (field == 16 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->disk_used_bytes = v;
    } else if (field == 17 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->disk_total_bytes = v;
    } else if (field == 18 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->uptime_ms = v;
    } else if (field == 19 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->has_cpu_temp_c = v != 0;
    } else if (field == 20 && wire == 1) {
      if (!ReadDouble(p, end, &m->cpu_temp_c)) return false;
    } else if (field == 21 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->has_gpu_temp_c = v != 0;
    } else if (field == 22 && wire == 1) {
      if (!ReadDouble(p, end, &m->gpu_temp_c)) return false;
    } else if (field == 23 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->has_ssd_temp_c = v != 0;
    } else if (field == 24 && wire == 1) {
      if (!ReadDouble(p, end, &m->ssd_temp_c)) return false;
    } else if (field == 25 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->has_cpu_current_mhz = v != 0;
    } else if (field == 26 && wire == 1) {
      if (!ReadDouble(p, end, &m->cpu_current_mhz)) return false;
    } else if (field == 27 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->memory_available_bytes = v;
    } else if (field == 28 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->has_memory_committed = v != 0;
    } else if (field == 29 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->memory_committed_bytes = v;
    } else if (field == 30 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->memory_commit_limit_bytes = v;
    } else if (field == 31 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->has_memory_cached = v != 0;
    } else if (field == 32 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->memory_cached_bytes = v;
    } else if (field == 33 && wire == 2) {
      if (!DecodeString(p, end, &m->ipv4)) return false;
    } else if (field == 34 && wire == 2) {
      if (!DecodeString(p, end, &m->ipv6)) return false;
    } else if (field == 35 && wire == 2) {
      if (!DecodeString(p, end, &m->gateway)) return false;
    } else if (field == 36 && wire == 2) {
      if (!DecodeString(p, end, &m->dns)) return false;
    } else if (field == 37 && wire == 2) {
      uint64_t blen = 0;
      if (!ReadVarint(p, end, &blen)) return false;
      if (p + blen > end) return false;
      HealthProcessEntry entry;
      if (!DecodeHealthProcessEntry(p, static_cast<size_t>(blen), &entry)) {
        return false;
      }
      m->top_cpu.push_back(std::move(entry));
      p += blen;
    } else if (field == 38 && wire == 2) {
      uint64_t blen = 0;
      if (!ReadVarint(p, end, &blen)) return false;
      if (p + blen > end) return false;
      HealthProcessEntry entry;
      if (!DecodeHealthProcessEntry(p, static_cast<size_t>(blen), &entry)) {
        return false;
      }
      m->top_memory.push_back(std::move(entry));
      p += blen;
    } else if (field == 39 && wire == 2) {
      uint64_t blen = 0;
      if (!ReadVarint(p, end, &blen)) return false;
      if (p + blen > end) return false;
      HealthProcessEntry entry;
      if (!DecodeHealthProcessEntry(p, static_cast<size_t>(blen), &entry)) {
        return false;
      }
      m->top_gpu.push_back(std::move(entry));
      p += blen;
    } else if (field == 40 && wire == 2) {
      uint64_t blen = 0;
      if (!ReadVarint(p, end, &blen)) return false;
      if (p + blen > end) return false;
      HealthProcessEntry entry;
      if (!DecodeHealthProcessEntry(p, static_cast<size_t>(blen), &entry)) {
        return false;
      }
      m->top_disk.push_back(std::move(entry));
      p += blen;
    } else if (field == 41 && wire == 2) {
      uint64_t blen = 0;
      if (!ReadVarint(p, end, &blen)) return false;
      if (p + blen > end) return false;
      HealthProcessEntry entry;
      if (!DecodeHealthProcessEntry(p, static_cast<size_t>(blen), &entry)) {
        return false;
      }
      m->top_network.push_back(std::move(entry));
      p += blen;
    } else if (field == 42 && wire == 1) {
      double core = 0.0;
      if (!ReadDouble(p, end, &core)) return false;
      m->cpu_core_percent.push_back(core);
    } else if (!SkipField(wire, p, end)) {
      return false;
    }
  }
  return true;
}

bool DecodeGetHealthSnapshot(const uint8_t* data, size_t len,
                             GetHealthSnapshot* /*m*/) {
  const uint8_t* p = data;
  const uint8_t* end = data + len;
  while (p < end) {
    uint64_t tag = 0;
    if (!ReadVarint(p, end, &tag)) return false;
    const uint32_t wire = static_cast<uint32_t>(tag & 7);
    if (!SkipField(wire, p, end)) return false;
  }
  return true;
}

bool DecodeHealthSnapshot(const uint8_t* data, size_t len, HealthSnapshot* m) {
  const uint8_t* p = data;
  const uint8_t* end = data + len;
  while (p < end) {
    uint64_t tag = 0;
    if (!ReadVarint(p, end, &tag)) return false;
    const uint32_t field = static_cast<uint32_t>(tag >> 3);
    const uint32_t wire = static_cast<uint32_t>(tag & 7);
    if (field == 1 && wire == 2) {
      uint64_t blen = 0;
      if (!ReadVarint(p, end, &blen)) return false;
      if (p + blen > end) return false;
      if (!DecodeHealthStaticInfo(p, static_cast<size_t>(blen), &m->info)) return false;
      p += static_cast<size_t>(blen);
    } else if (field == 2 && wire == 2) {
      uint64_t blen = 0;
      if (!ReadVarint(p, end, &blen)) return false;
      if (p + blen > end) return false;
      if (!DecodeHealthSample(p, static_cast<size_t>(blen), &m->sample)) return false;
      p += static_cast<size_t>(blen);
    } else if (!SkipField(wire, p, end)) {
      return false;
    }
  }
  return true;
}

bool DecodeHealthUpdate(const uint8_t* data, size_t len, HealthUpdate* m) {
  const uint8_t* p = data;
  const uint8_t* end = data + len;
  while (p < end) {
    uint64_t tag = 0;
    if (!ReadVarint(p, end, &tag)) return false;
    const uint32_t field = static_cast<uint32_t>(tag >> 3);
    const uint32_t wire = static_cast<uint32_t>(tag & 7);
    if (field == 1 && wire == 2) {
      uint64_t blen = 0;
      if (!ReadVarint(p, end, &blen)) return false;
      if (p + blen > end) return false;
      if (!DecodeHealthSample(p, static_cast<size_t>(blen), &m->sample)) return false;
      p += static_cast<size_t>(blen);
    } else if (!SkipField(wire, p, end)) {
      return false;
    }
  }
  return true;
}

bool DecodeStartHealthMonitoring(const uint8_t* data, size_t len,
                                 StartHealthMonitoring* /*m*/) {
  const uint8_t* p = data;
  const uint8_t* end = data + len;
  while (p < end) {
    uint64_t tag = 0;
    if (!ReadVarint(p, end, &tag)) return false;
    const uint32_t wire = static_cast<uint32_t>(tag & 7);
    if (!SkipField(wire, p, end)) return false;
  }
  return true;
}

bool DecodeStopHealthMonitoring(const uint8_t* data, size_t len,
                                StopHealthMonitoring* /*m*/) {
  const uint8_t* p = data;
  const uint8_t* end = data + len;
  while (p < end) {
    uint64_t tag = 0;
    if (!ReadVarint(p, end, &tag)) return false;
    const uint32_t wire = static_cast<uint32_t>(tag & 7);
    if (!SkipField(wire, p, end)) return false;
  }
  return true;
}

bool DecodeGetDiagnosticsSnapshot(const uint8_t* data, size_t len,
                                  GetDiagnosticsSnapshot* /*m*/) {
  const uint8_t* p = data;
  const uint8_t* end = data + len;
  while (p < end) {
    uint64_t tag = 0;
    if (!ReadVarint(p, end, &tag)) return false;
    const uint32_t wire = static_cast<uint32_t>(tag & 7);
    if (!SkipField(wire, p, end)) return false;
  }
  return true;
}

bool DecodeDiagnosticsSnapshot(const uint8_t* data, size_t len,
                               DiagnosticsSnapshot* m) {
  const uint8_t* p = data;
  const uint8_t* end = data + len;
  while (p < end) {
    uint64_t tag = 0;
    if (!ReadVarint(p, end, &tag)) return false;
    const uint32_t field = static_cast<uint32_t>(tag >> 3);
    const uint32_t wire = static_cast<uint32_t>(tag & 7);
    if (field == 1 && wire == 2) {
      if (!DecodeString(p, end, &m->service_version)) return false;
    } else if (field == 2 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->protocol_version = static_cast<uint32_t>(v);
    } else if (field == 3 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->service_start_unix_ms = static_cast<int64_t>(v);
    } else if (field == 4 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->service_uptime_ms = v;
    } else if (field == 5 && wire == 2) {
      if (!DecodeString(p, end, &m->run_mode)) return false;
    } else if (field == 6 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->ipc_listening = v != 0;
    } else if (field == 7 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->live_subscribed = v != 0;
    } else if (field == 8 && wire == 2) {
      if (!DecodeString(p, end, &m->live_channel)) return false;
    } else if (field == 9 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->live_events_pushed = v;
    } else if (field == 10 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->live_events_dropped = v;
    } else if (field == 11 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->live_subscriber_reconnects = v;
    } else if (field == 12 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->last_live_event_unix_ms = static_cast<int64_t>(v);
    } else if (field == 13 && wire == 2) {
      if (!DecodeString(p, end, &m->last_live_event_title)) return false;
    } else if (field == 14 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->live_queue_depth = static_cast<uint32_t>(v);
    } else if (field == 15 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->live_queue_capacity = static_cast<uint32_t>(v);
    } else if (field == 16 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->ipc_messages_received = v;
    } else if (field == 17 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->ipc_messages_sent = v;
    } else if (field == 18 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->ipc_errors = v;
    } else if (field == 19 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->connected_clients = static_cast<uint32_t>(v);
    } else if (field == 20 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->service_pid = static_cast<uint32_t>(v);
    } else if (field == 21 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->has_cpu_percent = v != 0;
    } else if (field == 22 && wire == 1) {
      if (!ReadDouble(p, end, &m->cpu_percent)) return false;
    } else if (field == 23 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->working_set_bytes = v;
    } else if (field == 24 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->thread_count = static_cast<uint32_t>(v);
    } else if (field == 25 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->handle_count = static_cast<uint32_t>(v);
    } else if (field == 26 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->stage_event_log = static_cast<int32_t>(v);
    } else if (field == 27 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->stage_collector = static_cast<int32_t>(v);
    } else if (field == 28 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->stage_intelligence = static_cast<int32_t>(v);
    } else if (field == 29 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      m->stage_ipc = static_cast<int32_t>(v);
    } else if (field == 30 && wire == 2) {
      if (!DecodeString(p, end, &m->stage_detail)) return false;
    } else if (field == 31 && wire == 2) {
      if (!DecodeString(p, end, &m->windows_edition)) return false;
    } else if (field == 32 && wire == 2) {
      if (!DecodeString(p, end, &m->windows_version)) return false;
    } else if (!SkipField(wire, p, end)) {
      return false;
    }
  }
  return true;
}

bool DecodeInjectDiagnosticsTestEvent(const uint8_t* data, size_t len,
                                      InjectDiagnosticsTestEvent* /*m*/) {
  const uint8_t* p = data;
  const uint8_t* end = data + len;
  while (p < end) {
    uint64_t tag = 0;
    if (!ReadVarint(p, end, &tag)) return false;
    const uint32_t wire = static_cast<uint32_t>(tag & 7);
    if (!SkipField(wire, p, end)) return false;
  }
  return true;
}

}  // namespace

bool EncodeEnvelope(const Envelope& env, std::vector<uint8_t>* out) {
  out->clear();
  WriteU64(1, env.request_id, out);
  if (std::holds_alternative<ClientHello>(env.body)) {
    WriteBytesField(10, EncodeClientHello(std::get<ClientHello>(env.body)), out);
  } else if (std::holds_alternative<ServerHello>(env.body)) {
    WriteBytesField(11, EncodeServerHello(std::get<ServerHello>(env.body)), out);
  } else if (std::holds_alternative<Ping>(env.body)) {
    WriteBytesField(12, EncodePing(std::get<Ping>(env.body)), out);
  } else if (std::holds_alternative<Pong>(env.body)) {
    WriteBytesField(13, EncodePong(std::get<Pong>(env.body)), out);
  } else if (std::holds_alternative<Heartbeat>(env.body)) {
    WriteBytesField(14, EncodeHeartbeat(std::get<Heartbeat>(env.body)), out);
  } else if (std::holds_alternative<GetTimelineSnapshot>(env.body)) {
    WriteBytesField(20, EncodeGetTimelineSnapshot(std::get<GetTimelineSnapshot>(env.body)),
                    out);
  } else if (std::holds_alternative<TimelineSnapshot>(env.body)) {
    WriteBytesField(21, EncodeTimelineSnapshot(std::get<TimelineSnapshot>(env.body)), out);
  } else if (std::holds_alternative<TimelineEvent>(env.body)) {
    WriteBytesField(22, EncodeTimelineEvent(std::get<TimelineEvent>(env.body)), out);
  } else if (std::holds_alternative<StartLiveMonitoring>(env.body)) {
    WriteBytesField(23, EncodeStartLiveMonitoring(std::get<StartLiveMonitoring>(env.body)),
                    out);
  } else if (std::holds_alternative<StopLiveMonitoring>(env.body)) {
    WriteBytesField(24, EncodeStopLiveMonitoring(std::get<StopLiveMonitoring>(env.body)),
                    out);
  } else if (std::holds_alternative<GetHealthSnapshot>(env.body)) {
    WriteBytesField(25, EncodeGetHealthSnapshot(std::get<GetHealthSnapshot>(env.body)), out);
  } else if (std::holds_alternative<HealthSnapshot>(env.body)) {
    WriteBytesField(26, EncodeHealthSnapshot(std::get<HealthSnapshot>(env.body)), out);
  } else if (std::holds_alternative<HealthUpdate>(env.body)) {
    WriteBytesField(27, EncodeHealthUpdate(std::get<HealthUpdate>(env.body)), out);
  } else if (std::holds_alternative<StartHealthMonitoring>(env.body)) {
    WriteBytesField(28, EncodeStartHealthMonitoring(std::get<StartHealthMonitoring>(env.body)),
                    out);
  } else if (std::holds_alternative<StopHealthMonitoring>(env.body)) {
    WriteBytesField(29, EncodeStopHealthMonitoring(std::get<StopHealthMonitoring>(env.body)),
                    out);
  } else if (std::holds_alternative<GetDiagnosticsSnapshot>(env.body)) {
    WriteBytesField(
        30, EncodeGetDiagnosticsSnapshot(std::get<GetDiagnosticsSnapshot>(env.body)), out);
  } else if (std::holds_alternative<DiagnosticsSnapshot>(env.body)) {
    WriteBytesField(31, EncodeDiagnosticsSnapshot(std::get<DiagnosticsSnapshot>(env.body)),
                    out);
  } else if (std::holds_alternative<InjectDiagnosticsTestEvent>(env.body)) {
    WriteBytesField(
        32,
        EncodeInjectDiagnosticsTestEvent(std::get<InjectDiagnosticsTestEvent>(env.body)),
        out);
  } else if (std::holds_alternative<ErrorResponse>(env.body)) {
    WriteBytesField(99, EncodeError(std::get<ErrorResponse>(env.body)), out);
  }
  return true;
}

bool DecodeEnvelope(const uint8_t* data, size_t len, Envelope* out) {
  out->request_id = 0;
  out->body = std::monostate{};
  const uint8_t* p = data;
  const uint8_t* end = data + len;
  while (p < end) {
    uint64_t tag = 0;
    if (!ReadVarint(p, end, &tag)) return false;
    const uint32_t field = static_cast<uint32_t>(tag >> 3);
    const uint32_t wire = static_cast<uint32_t>(tag & 7);
    if (field == 1 && wire == 0) {
      uint64_t v = 0;
      if (!ReadVarint(p, end, &v)) return false;
      out->request_id = v;
    } else if (wire == 2 &&
               (field == 10 || field == 11 || field == 12 || field == 13 ||
                field == 14 || field == 20 || field == 21 || field == 22 ||
                field == 23 || field == 24 || field == 25 || field == 26 ||
                field == 27 || field == 28 || field == 29 || field == 30 ||
                field == 31 || field == 32 || field == 99)) {
      uint64_t blen = 0;
      if (!ReadVarint(p, end, &blen)) return false;
      if (p + blen > end) return false;
      const uint8_t* sub = p;
      p += static_cast<size_t>(blen);
      if (field == 10) {
        ClientHello m;
        if (!DecodeClientHello(sub, static_cast<size_t>(blen), &m)) return false;
        out->body = std::move(m);
      } else if (field == 11) {
        ServerHello m;
        if (!DecodeServerHello(sub, static_cast<size_t>(blen), &m)) return false;
        out->body = std::move(m);
      } else if (field == 12) {
        Ping m;
        if (!DecodePing(sub, static_cast<size_t>(blen), &m)) return false;
        out->body = std::move(m);
      } else if (field == 13) {
        Pong m;
        if (!DecodePong(sub, static_cast<size_t>(blen), &m)) return false;
        out->body = std::move(m);
      } else if (field == 14) {
        Heartbeat m;
        if (!DecodeHeartbeat(sub, static_cast<size_t>(blen), &m)) return false;
        out->body = std::move(m);
      } else if (field == 20) {
        GetTimelineSnapshot m;
        if (!DecodeGetTimelineSnapshot(sub, static_cast<size_t>(blen), &m)) return false;
        out->body = std::move(m);
      } else if (field == 21) {
        TimelineSnapshot m;
        if (!DecodeTimelineSnapshot(sub, static_cast<size_t>(blen), &m)) return false;
        out->body = std::move(m);
      } else if (field == 22) {
        TimelineEvent m;
        if (!DecodeTimelineEvent(sub, static_cast<size_t>(blen), &m)) return false;
        out->body = std::move(m);
      } else if (field == 23) {
        StartLiveMonitoring m;
        if (!DecodeStartLiveMonitoring(sub, static_cast<size_t>(blen), &m)) return false;
        out->body = std::move(m);
      } else if (field == 24) {
        StopLiveMonitoring m;
        if (!DecodeStopLiveMonitoring(sub, static_cast<size_t>(blen), &m)) return false;
        out->body = std::move(m);
      } else if (field == 25) {
        GetHealthSnapshot m;
        if (!DecodeGetHealthSnapshot(sub, static_cast<size_t>(blen), &m)) return false;
        out->body = std::move(m);
      } else if (field == 26) {
        HealthSnapshot m;
        if (!DecodeHealthSnapshot(sub, static_cast<size_t>(blen), &m)) return false;
        out->body = std::move(m);
      } else if (field == 27) {
        HealthUpdate m;
        if (!DecodeHealthUpdate(sub, static_cast<size_t>(blen), &m)) return false;
        out->body = std::move(m);
      } else if (field == 28) {
        StartHealthMonitoring m;
        if (!DecodeStartHealthMonitoring(sub, static_cast<size_t>(blen), &m)) return false;
        out->body = std::move(m);
      } else if (field == 29) {
        StopHealthMonitoring m;
        if (!DecodeStopHealthMonitoring(sub, static_cast<size_t>(blen), &m)) return false;
        out->body = std::move(m);
      } else if (field == 30) {
        GetDiagnosticsSnapshot m;
        if (!DecodeGetDiagnosticsSnapshot(sub, static_cast<size_t>(blen), &m)) return false;
        out->body = std::move(m);
      } else if (field == 31) {
        DiagnosticsSnapshot m;
        if (!DecodeDiagnosticsSnapshot(sub, static_cast<size_t>(blen), &m)) return false;
        out->body = std::move(m);
      } else if (field == 32) {
        InjectDiagnosticsTestEvent m;
        if (!DecodeInjectDiagnosticsTestEvent(sub, static_cast<size_t>(blen), &m)) {
          return false;
        }
        out->body = std::move(m);
      } else if (field == 99) {
        ErrorResponse m;
        if (!DecodeError(sub, static_cast<size_t>(blen), &m)) return false;
        out->body = std::move(m);
      }
    } else if (!SkipField(wire, p, end)) {
      return false;
    }
  }
  return true;
}

bool EncodeFrame(const std::vector<uint8_t>& payload, std::vector<uint8_t>* out) {
  if (payload.size() > pulse::kMaxFramePayloadBytes) return false;
  out->resize(8 + payload.size());
  out->at(0) = 'P';
  out->at(1) = 'U';
  out->at(2) = 'L';
  out->at(3) = 'S';
  const uint32_t len = static_cast<uint32_t>(payload.size());
  out->at(4) = static_cast<uint8_t>(len & 0xFF);
  out->at(5) = static_cast<uint8_t>((len >> 8) & 0xFF);
  out->at(6) = static_cast<uint8_t>((len >> 16) & 0xFF);
  out->at(7) = static_cast<uint8_t>((len >> 24) & 0xFF);
  std::memcpy(out->data() + 8, payload.data(), payload.size());
  return true;
}

bool TryDecodeFrame(const uint8_t* data, size_t len, std::vector<uint8_t>* payload,
                    size_t* consumed_bytes, std::string* error) {
  if (len < 8) {
    *consumed_bytes = 0;
    return false;
  }
  if (!(data[0] == 'P' && data[1] == 'U' && data[2] == 'L' && data[3] == 'S')) {
    if (error) *error = "invalid frame magic";
    *consumed_bytes = 0;
    return false;
  }
  const uint32_t plen = static_cast<uint32_t>(data[4]) |
                        (static_cast<uint32_t>(data[5]) << 8) |
                        (static_cast<uint32_t>(data[6]) << 16) |
                        (static_cast<uint32_t>(data[7]) << 24);
  if (plen > pulse::kMaxFramePayloadBytes) {
    if (error) *error = "frame exceeds 2 MB limit";
    *consumed_bytes = 0;
    return false;
  }
  if (len < 8 + plen) {
    *consumed_bytes = 0;
    return false;
  }
  payload->assign(data + 8, data + 8 + plen);
  *consumed_bytes = 8 + plen;
  return true;
}

}  // namespace pulse::ipc
