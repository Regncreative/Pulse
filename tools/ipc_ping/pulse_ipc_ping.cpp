#include "pulse_wire.hpp"
#include "pulse/constants.hpp"

#include <chrono>
#include <iostream>
#include <string>
#include <vector>

#define WIN32_LEAN_AND_MEAN
#include <Windows.h>

namespace {

int64_t NowMs() {
  using namespace std::chrono;
  return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

bool ReadExact(HANDLE pipe, void* buffer, size_t size) {
  auto* bytes = static_cast<uint8_t*>(buffer);
  size_t got = 0;
  while (got < size) {
    DWORD read = 0;
    if (!ReadFile(pipe, bytes + got, static_cast<DWORD>(size - got), &read, nullptr)) {
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
  HANDLE pipe = CreateFileW(L"\\\\.\\pipe\\PulseService", GENERIC_READ | GENERIC_WRITE, 0,
                            nullptr, OPEN_EXISTING, 0, nullptr);
  if (pipe == INVALID_HANDLE_VALUE) {
    std::wcerr << L"CreateFile failed: " << GetLastError()
               << L" (is PulseService --console running?)\n";
    return 1;
  }

  pulse::ipc::Envelope hello;
  hello.request_id = 1;
  hello.body = pulse::ipc::ClientHello{pulse::kProtocolVersion, "pulse_ipc_ping",
                                       pulse::kAppVersion};
  std::vector<uint8_t> payload;
  pulse::ipc::EncodeEnvelope(hello, &payload);
  std::vector<uint8_t> frame;
  pulse::ipc::EncodeFrame(payload, &frame);
  if (!WriteExact(pipe, frame.data(), frame.size())) return 2;

  std::vector<uint8_t> buffer;
  uint8_t temp[4096];
  auto read_one = [&](pulse::ipc::Envelope* out) -> bool {
    while (true) {
      DWORD read = 0;
      if (!ReadFile(pipe, temp, sizeof(temp), &read, nullptr)) return false;
      buffer.insert(buffer.end(), temp, temp + read);
      std::vector<uint8_t> pl;
      size_t consumed = 0;
      std::string err;
      if (!pulse::ipc::TryDecodeFrame(buffer.data(), buffer.size(), &pl, &consumed, &err)) {
        if (!err.empty()) return false;
        continue;
      }
      buffer.erase(buffer.begin(),
                   buffer.begin() + static_cast<std::ptrdiff_t>(consumed));
      return pulse::ipc::DecodeEnvelope(pl.data(), pl.size(), out);
    }
  };

  pulse::ipc::Envelope reply;
  if (!read_one(&reply) || !std::holds_alternative<pulse::ipc::ServerHello>(reply.body)) {
    std::wcerr << L"Expected ServerHello\n";
    return 3;
  }
  std::wcout << L"ServerHello OK\n";

  pulse::ipc::Envelope ping;
  ping.request_id = 2;
  ping.body = pulse::ipc::Ping{99, NowMs()};
  pulse::ipc::EncodeEnvelope(ping, &payload);
  pulse::ipc::EncodeFrame(payload, &frame);
  if (!WriteExact(pipe, frame.data(), frame.size())) return 4;
  if (!read_one(&reply) || !std::holds_alternative<pulse::ipc::Pong>(reply.body)) {
    std::wcerr << L"Expected Pong\n";
    return 5;
  }
  const auto& pong = std::get<pulse::ipc::Pong>(reply.body);
  std::wcout << L"Pong OK nonce=" << pong.nonce << L" version="
             << pong.service_version.c_str() << L"\n";
  CloseHandle(pipe);
  return pong.nonce == 99 ? 0 : 6;
}
