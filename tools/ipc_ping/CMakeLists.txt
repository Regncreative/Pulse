# C++ Ping client for IPC validation (TASK-001)
cmake_minimum_required(VERSION 3.25)
project(PulseIpcPing LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(PULSE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../..")
add_executable(pulse_ipc_ping pulse_ipc_ping.cpp
  "${PULSE_ROOT}/shared/pulse_protocol/cpp/pulse_wire.cpp")
target_include_directories(pulse_ipc_ping PRIVATE
  "${PULSE_ROOT}/shared/pulse_protocol/cpp"
  "${PULSE_ROOT}/shared/pulse_common/include")
target_link_libraries(pulse_ipc_ping PRIVATE)
