#include "pulse_wire.hpp"
#include "pulse/constants.hpp"

#include <chrono>
#include <iostream>
#include <string>
#include <thread>
#include <variant>
#include <vector>

#define WIN32_LEAN_AND_MEAN
#include <Windows.h>

namespace {

bool ReadExact(HANDLE pipe, void* buffer, size_t size) {
  auto* bytes = static_cast<uint8_t*>(buffer);
  size_t got = 0;
  while (got < size) {
    DWORD read = 0;
    if (!ReadFile(pipe, bytes + got, static_cast<DWORD>(size - got), &read,
                  nullptr)) {
      return false;
    }
    if (read == 0) return false;
    got += read;
  }
  return true;
}

bool WriteExact(HANDLE pipe, const void* buffer, size_t size) {
  const auto* bytes = static_cast<const uint8_t*>(buffer);
  size_t sent = 0;
  while (sent < size) {
    DWORD written = 0;
    if (!WriteFile(pipe, bytes + sent, static_cast<DWORD>(size - sent), &written,
                   nullptr)) {
      return false;
    }
    if (written == 0) return false;
    sent += written;
  }
  return true;
}

}  // namespace

int wmain() {
  HANDLE pipe = CreateFileW(L"\\\\.\\pipe\\PulseService", GENERIC_READ | GENERIC_WRITE,
                            0, nullptr, OPEN_EXISTING, 0, nullptr);
  if (pipe == INVALID_HANDLE_VALUE) {
    std::cerr << "OFFLINE: CreateFile failed: " << GetLastError() << "\n";
    return 1;
  }

  auto send = [&](pulse::ipc::Envelope env) {
    std::vector<uint8_t> payload;
    pulse::ipc::EncodeEnvelope(env, &payload);
    std::vector<uint8_t> frame;
    pulse::ipc::EncodeFrame(payload, &frame);
    return WriteExact(pipe, frame.data(), frame.size());
  };

  std::vector<uint8_t> buffer;
  uint8_t temp[65536];
  auto read_one = [&](pulse::ipc::Envelope* out, bool allow_push) -> bool {
    const auto deadline =
        std::chrono::steady_clock::now() + std::chrono::seconds(8);
    while (std::chrono::steady_clock::now() < deadline) {
      // Drain any frames already buffered before waiting on the pipe.
      while (true) {
        std::vector<uint8_t> pl;
        size_t consumed = 0;
        std::string err;
        if (!pulse::ipc::TryDecodeFrame(buffer.data(), buffer.size(), &pl,
                                        &consumed, &err)) {
          if (!err.empty()) {
            std::cerr << "frame err: " << err << "\n";
            return false;
          }
          break;
        }
        buffer.erase(buffer.begin(),
                     buffer.begin() + static_cast<std::ptrdiff_t>(consumed));
        if (!pulse::ipc::DecodeEnvelope(pl.data(), pl.size(), out)) {
          std::cerr << "DecodeEnvelope failed\n";
          return false;
        }
        if (out->request_id == 0 && !allow_push) continue;
        return true;
      }

      DWORD avail = 0;
      if (!PeekNamedPipe(pipe, nullptr, 0, nullptr, &avail, nullptr)) {
        return false;
      }
      if (avail == 0) {
        Sleep(20);
        continue;
      }
      DWORD read = 0;
      if (!ReadFile(pipe, temp, sizeof(temp), &read, nullptr)) return false;
      buffer.insert(buffer.end(), temp, temp + read);
    }
    std::cerr << "Timeout waiting for IPC reply\n";
    return false;
  };

  pulse::ipc::Envelope hello;
  hello.request_id = 1;
  hello.body = pulse::ipc::ClientHello{pulse::kProtocolVersion, "diagnostics_ping",
                                       pulse::kAppVersion};
  if (!send(hello)) return 2;
  pulse::ipc::Envelope reply;
  if (!read_one(&reply, false) ||
      !std::holds_alternative<pulse::ipc::ServerHello>(reply.body)) {
    std::cerr << "Expected ServerHello\n";
    return 3;
  }
  const auto& sh = std::get<pulse::ipc::ServerHello>(reply.body);
  std::cout << "CONNECTED service=" << sh.service_version
            << " protocol=" << sh.protocol_version << "\n";

  pulse::ipc::Envelope ping;
  ping.request_id = 2;
  ping.body = pulse::ipc::Ping{42};
  if (!send(ping)) return 4;
  if (!read_one(&reply, false) ||
      !std::holds_alternative<pulse::ipc::Pong>(reply.body)) {
    std::cerr << "Expected Pong\n";
    return 5;
  }
  std::cout << "PING ok nonce=" << std::get<pulse::ipc::Pong>(reply.body).nonce
            << "\n";

  pulse::ipc::Envelope diag_req;
  diag_req.request_id = 3;
  diag_req.body = pulse::ipc::GetDiagnosticsSnapshot{};
  if (!send(diag_req)) return 6;
  if (!read_one(&reply, false) ||
      !std::holds_alternative<pulse::ipc::DiagnosticsSnapshot>(reply.body)) {
    std::cerr << "Expected DiagnosticsSnapshot\n";
    return 7;
  }
  const auto snap = std::get<pulse::ipc::DiagnosticsSnapshot>(reply.body);
  if (snap.service_version.empty() || snap.protocol_version == 0) {
    std::cerr << "DiagnosticsSnapshot missing version fields\n";
    return 8;
  }
  if (snap.service_pid == 0 || snap.working_set_bytes == 0) {
    std::cerr << "DiagnosticsSnapshot missing service process metrics\n";
    return 9;
  }
  std::cout << "DIAGNOSTICS service=" << snap.service_version
            << " mode=" << snap.run_mode << " pid=" << snap.service_pid
            << " ws=" << snap.working_set_bytes
            << " windows=" << snap.windows_edition << " "
            << snap.windows_version << "\n";

  pulse::ipc::Envelope start_live;
  start_live.request_id = 4;
  start_live.body = pulse::ipc::StartLiveMonitoring{"System"};
  if (!send(start_live)) return 10;
  if (!read_one(&reply, false)) return 11;
  std::cout << "LIVE enabled\n";

  pulse::ipc::Envelope inject;
  inject.request_id = 5;
  inject.body = pulse::ipc::InjectDiagnosticsTestEvent{};
  if (!send(inject)) return 12;
  if (!read_one(&reply, false)) return 13;
  if (std::holds_alternative<pulse::ipc::ErrorResponse>(reply.body)) {
    const auto& e = std::get<pulse::ipc::ErrorResponse>(reply.body);
    if (e.code != 0) {
      std::cerr << "Inject failed: " << e.message << "\n";
      return 14;
    }
  }
  std::cout << "INJECT ack\n";

  bool saw_test = false;
  const auto push_deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(5);
  while (std::chrono::steady_clock::now() < push_deadline) {
    if (!read_one(&reply, true)) break;
    if (reply.request_id != 0) continue;
    if (!std::holds_alternative<pulse::ipc::TimelineEvent>(reply.body)) continue;
    const auto& ev = std::get<pulse::ipc::TimelineEvent>(reply.body);
    if (ev.provider_name == "Pulse.Diagnostics" ||
        ev.channel == "Pulse.Diagnostics" ||
        ev.title.find("test") != std::string::npos ||
        ev.title.find("Test") != std::string::npos ||
        ev.category == "diagnostics") {
      saw_test = true;
      std::cout << "TEST_EVENT title=" << ev.title
                << " provider=" << ev.provider_name << "\n";
      break;
    }
  }
  if (!saw_test) {
    std::cerr << "Did not receive injected TimelineEvent push\n";
    return 15;
  }

  pulse::ipc::Envelope stop_live;
  stop_live.request_id = 6;
  stop_live.body = pulse::ipc::StopLiveMonitoring{};
  if (!send(stop_live)) return 16;
  if (!read_one(&reply, false)) return 17;
  std::cout << "LIVE disabled\n";

  diag_req.request_id = 7;
  if (!send(diag_req)) return 18;
  if (!read_one(&reply, false) ||
      !std::holds_alternative<pulse::ipc::DiagnosticsSnapshot>(reply.body)) {
    std::cerr << "Expected DiagnosticsSnapshot after inject\n";
    return 19;
  }
  const auto snap2 = std::get<pulse::ipc::DiagnosticsSnapshot>(reply.body);
  std::cout << "DIAGNOSTICS_AFTER pushed=" << snap2.live_events_pushed
            << " last=" << snap2.last_live_event_title << "\n";
  // Machine-readable line for soak_overnight.ps1 (do not invent fields).
  std::cout << "SOAK_METRICS"
            << " live_events_dropped=" << snap2.live_events_dropped
            << " live_subscriber_reconnects=" << snap2.live_subscriber_reconnects
            << " live_queue_depth=" << snap2.live_queue_depth
            << " live_queue_capacity=" << snap2.live_queue_capacity
            << " live_events_pushed=" << snap2.live_events_pushed
            << " ipc_errors=" << snap2.ipc_errors
            << " service_uptime_ms=" << snap2.service_uptime_ms
            << "\n";
  std::cout << "SMOKE_OK\n";
  CloseHandle(pipe);
  return 0;
}
