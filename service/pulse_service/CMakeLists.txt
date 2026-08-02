cmake_minimum_required(VERSION 3.25)
project(PulseService VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(PULSE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../..")

# Embed short git commit at configure time (override with -DPULSE_GIT_COMMIT=...).
if(NOT DEFINED PULSE_GIT_COMMIT OR PULSE_GIT_COMMIT STREQUAL "")
  execute_process(
    COMMAND git rev-parse --short HEAD
    WORKING_DIRECTORY "${PULSE_ROOT}"
    OUTPUT_VARIABLE PULSE_GIT_COMMIT
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
    RESULT_VARIABLE PULSE_GIT_RESULT
  )
  if(NOT PULSE_GIT_RESULT EQUAL 0 OR PULSE_GIT_COMMIT STREQUAL "")
    set(PULSE_GIT_COMMIT "unknown")
  endif()
endif()
configure_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/cmake/pulse_build_info.hpp.in"
  "${CMAKE_CURRENT_BINARY_DIR}/generated/pulse_build_info.hpp"
  @ONLY
)

add_library(pulse_wire STATIC
  "${PULSE_ROOT}/shared/pulse_protocol/cpp/pulse_wire.cpp"
)
target_include_directories(pulse_wire PUBLIC
  "${PULSE_ROOT}/shared/pulse_protocol/cpp"
  "${PULSE_ROOT}/shared/pulse_common/include"
)

add_executable(PulseService WIN32
  src/main.cpp
  src/service_core/service_core.cpp
  src/ipc/ipc_server.cpp
  src/ipc/event_mapper.cpp
  src/intelligence/event_intelligence.cpp
  src/humanization/event_humanizer.cpp
  src/collector/collector.cpp
  src/collectors/event_log_collector.cpp
  src/collectors/event_log_subscriber.cpp
  src/collectors/event_log_channels.cpp
  src/collectors/health_metrics_collector.cpp
  src/collectors/hardware_sensors_collector.cpp
  src/collectors/network_etw_engine.cpp
  src/collectors/gpu_adapter_info.cpp
  src/collectors/system_overview_info.cpp
  src/collectors/process_metrics.cpp
  src/diagnostics/service_identity.cpp
  src/inventory/inventory_engine.cpp
  src/inventory/services_collector.cpp
  src/inventory/drivers_collector.cpp
  src/inventory/software_collector.cpp
  src/windows/wevt_helpers.cpp
  src/logging/logger.cpp
  src/util/config.cpp
)

# Console subsystem so --console works with stdout; also fine for SCM.
set_target_properties(PulseService PROPERTIES
  WIN32_EXECUTABLE FALSE
)

target_include_directories(PulseService PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
  "${CMAKE_CURRENT_BINARY_DIR}/generated"
  "${PULSE_ROOT}/shared/pulse_common/include"
  "${PULSE_ROOT}/shared/pulse_protocol/cpp"
)

target_link_libraries(PulseService PRIVATE
  pulse_wire
  advapi32
  shell32
  ole32
  wevtapi
  pdh
  iphlpapi
  dxgi
  d3d12
  gdi32
  psapi
  version
  wlanapi
  setupapi
  cfgmgr32
  bcrypt
)

enable_testing()
add_executable(pulse_wire_tests
  test/pulse_wire_test.cpp
)
target_include_directories(pulse_wire_tests PRIVATE
  "${PULSE_ROOT}/shared/pulse_protocol/cpp"
  "${PULSE_ROOT}/shared/pulse_common/include"
)
target_link_libraries(pulse_wire_tests PRIVATE pulse_wire)
add_test(NAME pulse_wire_tests COMMAND pulse_wire_tests)

add_executable(event_humanizer_tests
  test/event_humanizer_test.cpp
  src/humanization/event_humanizer.cpp
)
target_include_directories(event_humanizer_tests PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
add_test(NAME event_humanizer_tests COMMAND event_humanizer_tests)

add_executable(event_intelligence_tests
  test/event_intelligence_test.cpp
  src/intelligence/event_intelligence.cpp
)
target_include_directories(event_intelligence_tests PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
  "${PULSE_ROOT}/shared/pulse_protocol/cpp"
  "${PULSE_ROOT}/shared/pulse_common/include"
)
target_link_libraries(event_intelligence_tests PRIVATE pulse_wire)
add_test(NAME event_intelligence_tests COMMAND event_intelligence_tests)

add_executable(services_collector_tests
  test/services_collector_test.cpp
  src/inventory/services_collector.cpp
  src/windows/wevt_helpers.cpp
)
target_include_directories(services_collector_tests PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
  "${PULSE_ROOT}/shared/pulse_protocol/cpp"
  "${PULSE_ROOT}/shared/pulse_common/include"
)
target_link_libraries(services_collector_tests PRIVATE pulse_wire Advapi32 Wevtapi)
add_test(NAME services_collector_tests COMMAND services_collector_tests)

add_executable(drivers_collector_tests
  test/drivers_collector_test.cpp
  src/inventory/drivers_collector.cpp
  src/windows/wevt_helpers.cpp
)
target_include_directories(drivers_collector_tests PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
  "${PULSE_ROOT}/shared/pulse_protocol/cpp"
  "${PULSE_ROOT}/shared/pulse_common/include"
)
target_link_libraries(drivers_collector_tests PRIVATE pulse_wire Advapi32 Wevtapi)
add_test(NAME drivers_collector_tests COMMAND drivers_collector_tests)

add_executable(software_collector_tests
  test/software_collector_test.cpp
  src/inventory/software_collector.cpp
  src/windows/wevt_helpers.cpp
)
target_include_directories(software_collector_tests PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
  "${PULSE_ROOT}/shared/pulse_protocol/cpp"
  "${PULSE_ROOT}/shared/pulse_common/include"
)
target_link_libraries(software_collector_tests PRIVATE pulse_wire Advapi32 Wevtapi)
add_test(NAME software_collector_tests COMMAND software_collector_tests)

add_executable(ipc_client_thread_lifetime_test
  test/ipc_client_thread_lifetime_test.cpp
)
add_test(NAME ipc_client_thread_lifetime_test
         COMMAND ipc_client_thread_lifetime_test)

# Optional IPC ping tool (same tree)
add_executable(pulse_ipc_ping
  "${PULSE_ROOT}/tools/ipc_ping/pulse_ipc_ping.cpp"
)
target_include_directories(pulse_ipc_ping PRIVATE
  "${PULSE_ROOT}/shared/pulse_protocol/cpp"
  "${PULSE_ROOT}/shared/pulse_common/include"
)
target_link_libraries(pulse_ipc_ping PRIVATE pulse_wire)

add_executable(pulse_health_ping
  "${PULSE_ROOT}/tools/ipc_ping/pulse_health_ping.cpp"
)
target_include_directories(pulse_health_ping PRIVATE
  "${PULSE_ROOT}/shared/pulse_protocol/cpp"
  "${PULSE_ROOT}/shared/pulse_common/include"
)
target_link_libraries(pulse_health_ping PRIVATE pulse_wire)

add_executable(pulse_diagnostics_ping
  "${PULSE_ROOT}/tools/ipc_ping/pulse_diagnostics_ping.cpp"
)
target_include_directories(pulse_diagnostics_ping PRIVATE
  "${PULSE_ROOT}/shared/pulse_protocol/cpp"
  "${PULSE_ROOT}/shared/pulse_common/include"
)
target_link_libraries(pulse_diagnostics_ping PRIVATE pulse_wire)
