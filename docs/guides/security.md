# Pulse MCP security

- Default **disabled** until Settings opt-in
- Observation tools only (no process kill / OS mutation in v1)
- Policy hard-refuse when disabled (`POLICY_DISABLED`)
- AI client config edits require explicit Register / Unregister
- Config backups before write; JSON validated before replace
- Uninstall removes only Pulse-owned registration markers
- Cmdline redaction on process details; timeline raw XML opt-in

Pulse never sends telemetry. AI clients may upload tool results — disclose this in Settings.
