/// Shared Dart constants matching pulse/constants.hpp

const String kProductName = 'Pulse';
const String kServiceName = 'PulseService';
const String kPipeName = r'\\.\pipe\PulseService';
const String kAppVersion = '0.1.2-beta';
const String kServiceVersionExpected = '0.1.2-beta';
const int kProtocolVersion = 1;
const int kMaxFramePayloadBytes = 2 * 1024 * 1024;
const int kFrameMagic0 = 0x50; // P
const int kFrameMagic1 = 0x55; // U
const int kFrameMagic2 = 0x4C; // L
const int kFrameMagic3 = 0x53; // S
