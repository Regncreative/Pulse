#pragma once

#include <cstdint>
#include <string>

namespace pulse {

constexpr const char* kProductName = "Pulse";
constexpr const char* kServiceName = "PulseService";
constexpr const char* kServiceDisplayName = "Pulse";
constexpr const char* kPipeName = "\\\\.\\pipe\\PulseService";
constexpr const char* kServiceVersion = "1.0.0";
constexpr const char* kAppVersion = "1.0.0";

// Framing: magic "PULS" + uint32 LE length + protobuf payload
constexpr uint32_t kFrameMagic = 0x50554C53u; // 'P' 'U' 'L' 'S' little-endian as bytes PULS
constexpr uint32_t kMaxFramePayloadBytes = 2u * 1024u * 1024u; // 2 MB

constexpr uint32_t kProtocolVersion = 1;
// UI + status-daemon + Cursor + Claude + headroom. Exhaustion yields
// CreateFile ERROR_PIPE_BUSY (231) and PulseMCP "IPC timeout connecting".
constexpr uint32_t kMaxPipeInstances = 32;
constexpr size_t kDefaultLiveQueueCapacity = 1000;

// Pipe SDDL from architecture doc 05
constexpr const char* kPipeSddl =
    "D:(A;;GA;;;SY)(A;;GA;;;LS)(A;;GRGW;;;BA)(A;;GRGW;;;BU)";

constexpr const char* kProgramDataRelative = "Pulse";
constexpr const char* kDefaultConfigFileName = "config.json";

}  // namespace pulse
