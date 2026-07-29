# Placeholder: run when protoc is installed.
# protoc --cpp_out=... --dart_out=... shared/pulse_protocol/proto/pulse.proto
#
# Bootstrap uses hand-maintained pulse_wire codecs that match field numbers in pulse.proto.
Write-Host "protoc codegen not required for TASK-001 (wire codec is checked in)."
