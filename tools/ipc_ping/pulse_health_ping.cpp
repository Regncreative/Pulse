#include "pulse_wire.hpp"
#include "pulse/constants.hpp"

#include <chrono>
#include <iostream>
#include <string>
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
    std::cerr << "CreateFile failed: " << GetLastError() << "\n";
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
  auto read_one = [&](pulse::ipc::Envelope* out) -> bool {
    while (true) {
      DWORD read = 0;
      if (!ReadFile(pipe, temp, sizeof(temp), &read, nullptr)) return false;
      buffer.insert(buffer.end(), temp, temp + read);
      std::vector<uint8_t> pl;
      size_t consumed = 0;
      std::string err;
      if (!pulse::ipc::TryDecodeFrame(buffer.data(), buffer.size(), &pl, &consumed,
                                      &err)) {
        if (!err.empty()) {
          std::cerr << "frame err: " << err << "\n";
          return false;
        }
        continue;
      }
      buffer.erase(buffer.begin(),
                   buffer.begin() + static_cast<std::ptrdiff_t>(consumed));
      if (!pulse::ipc::DecodeEnvelope(pl.data(), pl.size(), out)) {
        std::cerr << "DecodeEnvelope failed payload=" << pl.size() << "\n";
        return false;
      }
      // Skip server pushes (request_id == 0).
      if (out->request_id == 0) continue;
      return true;
    }
  };

  pulse::ipc::Envelope hello;
  hello.request_id = 1;
  hello.body = pulse::ipc::ClientHello{pulse::kProtocolVersion, "health_ping",
                                       pulse::kAppVersion};
  if (!send(hello)) return 2;
  pulse::ipc::Envelope reply;
  if (!read_one(&reply) ||
      !std::holds_alternative<pulse::ipc::ServerHello>(reply.body)) {
    std::cerr << "Expected ServerHello\n";
    return 3;
  }

  // Two snapshots: first primes process baselines; second has tops.
  for (int round = 0; round < 2; ++round) {
    if (round == 1) Sleep(1100);
    pulse::ipc::Envelope req;
    req.request_id = static_cast<uint64_t>(10 + round);
    req.body = pulse::ipc::GetHealthSnapshot{};
    if (!send(req)) return 4;
    if (!read_one(&reply) ||
      !std::holds_alternative<pulse::ipc::HealthSnapshot>(reply.body)) {
      std::cerr << "Expected HealthSnapshot round=" << round
                << " req=" << reply.request_id << "\n";
      if (std::holds_alternative<pulse::ipc::ErrorResponse>(reply.body)) {
        const auto& e = std::get<pulse::ipc::ErrorResponse>(reply.body);
        std::cerr << "Error code=" << e.code << " msg=" << e.message << "\n";
      } else if (std::holds_alternative<pulse::ipc::HealthUpdate>(reply.body)) {
        std::cerr << "Got HealthUpdate instead\n";
      } else if (std::holds_alternative<pulse::ipc::ServerHello>(reply.body)) {
        std::cerr << "Got ServerHello instead\n";
      } else {
        std::cerr << "Got other body variant index-ish\n";
      }
      return 5;
    }
  }

  const auto& snap = std::get<pulse::ipc::HealthSnapshot>(reply.body);
  const auto& i = snap.info;
  const auto& s = snap.sample;
  std::cout << "cpu_model=" << i.cpu_model << "\n";
  std::cout << "base_mhz=" << i.cpu_base_mhz << " cores=" << i.cpu_cores
            << " logical=" << i.cpu_logical_processors
            << " virt=" << (i.cpu_virtualization_enabled ? "1" : "0") << "\n";
  std::cout << "vram_ded=" << i.gpu_dedicated_bytes
            << " vram_shared=" << i.gpu_shared_bytes << "\n";
  std::cout << "cpu%=" << (s.has_cpu_percent ? s.cpu_percent : -1.0)
            << " current_mhz="
            << (s.has_cpu_current_mhz ? s.cpu_current_mhz : -1.0) << "\n";
  std::cout << "mem_used=" << s.memory_used_bytes
            << " avail=" << s.memory_available_bytes
            << " commit=" << (s.has_memory_committed ? 1 : 0)
            << " cached=" << (s.has_memory_cached ? 1 : 0) << "\n";
  std::cout << "ipv4=" << s.ipv4 << " gw=" << s.gateway << " dns=" << s.dns
            << "\n";
  std::cout << "top_cpu=" << s.top_cpu.size()
            << " top_mem=" << s.top_memory.size()
            << " top_gpu=" << s.top_gpu.size()
            << " top_disk=" << s.top_disk.size()
            << " top_net=" << s.top_network.size() << "\n";
  for (size_t i = 0; i < s.top_cpu.size(); ++i) {
    const auto& e = s.top_cpu[i];
    std::cout << "top_cpu[" << i << "] pid=" << e.pid << " name=" << e.name
              << " cpu=" << e.cpu_percent << " has=" << e.has_cpu_percent
              << " path=" << (e.path.empty() ? "-" : e.path) << "\n";
  }
  for (size_t i = 0; i < s.top_memory.size(); ++i) {
    const auto& e = s.top_memory[i];
    std::cout << "top_mem[" << i << "] pid=" << e.pid << " name=" << e.name
              << " ws=" << e.memory_bytes << "\n";
  }
  CloseHandle(pipe);
  return 0;
}
