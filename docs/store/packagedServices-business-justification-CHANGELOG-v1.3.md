# Changelog — packagedServices business justification v1.3

Document: `docs/store/packagedServices-business-justification.md`  
Prior version: 1.2 → **1.3**  
Basis: Partner Center simulated reviewer report (approval score 72/100 improvements)

| Modified / added section | Change | Reason |
|--------------------------|--------|--------|
| Document version metadata | Bumped to **1.3** | Track resubmission revision |
| Executive Business Justification — business problem | Removed “customers … expecting”; tied need to ADR/architecture and GitHub LocalService; cited Store validation / UI-only incomplete packaging guidance | Eliminate speculative “customers expect”; evidence-based problem statement |
| Executive — LocalService blurb | Points to capability matrix | Least-privilege rigor |
| **Observation model (precise, code-backed)** | **New** table: persistent host vs health infrastructure vs Event Log live (lazy `StartLiveMonitoring`) | Stop overclaiming continuous Event Log collection; match `ipc_server.cpp` |
| Store vs GitHub feature parity | Replaced “Continuous Event Log / health / inventory host” and vague “Survives UI close” with host/IPC/health/lazy-live rows; reframed as registration path not entitlement | Technical accuracy; avoid “packagedServices unnecessary” pushback from overclaims |
| Alternatives — runFullTrust / StartupTask / Scheduled Task / tray | Removed “customers expect” and “Windows expects”; tied failures to architecture/code; Scheduled Task wording no longer says Event Log is always continuous | Speculative wording removal; code-backed impacts |
| Alternatives — runFullTrust impact | Cites `validate_msix_store.ps1` requiring embedded service | Concrete Store failure mode |
| **Why moving collectors into the UI is not a valid Store replacement** | **New** section | Reviewer priority #8; close “just put collectors in UI” rejection vector |
| Exact responsibilities | Split Event Log snapshot vs live-when-enabled; health tied to `EnsureHealthCollector` at service start; IPC host called out first | Align responsibilities with observation model |
| Why LocalService / LocalSystem | Retained; added matrix cross-link | Least-privilege gap |
| **LocalService capability matrix** | **New** can/cannot table (Event Log channels, PDH, inventory read, pipe, no remote/spawn/inject/plugins/creds) | Reviewer priority #4; grounded in `event_log_channels.cpp` and service code review |
| Customer value | Replaced “customer expectation” table with “product requirement from architecture/code” loss table; audience tied to AGENTS.md/Store listing | Speculative wording removal |
| **IPC security** | **New** main-body section: transport, full SDDL, **BU disclosure**, local-only, diagnostics-only RPC, no remote, no command execution, no attestation | Reviewer priority #2–3; checklist was too thin |
| Security commitments | `internetClient` bullet moved to dedicated section; retained UAC/Store-update clarifications | Clarity |
| **UI internetClient capability** | **New**: code review finding (unused); **recommend removal** from Store MSIX; not required for packagedServices | Reviewer priority #5; no invented justification |
| Capability request summary | Added internetClient packaging note | Align summary with finding |
| Executive Certification Checklist | Added rows for UI collectors, Event Log continuity nuance, expanded IPC, internetClient; updated short answers | Match revised claims |
| Product architecture | Host wording (“Observation host”) | Consistency with observation model |
| Security model | Links to capability matrix | Least privilege |
| Privacy | Added sensitivity + network **rate** (not MITM) notes | Honest attack-surface / privacy disclosure |
| Closing request | Narrowed “continuous diagnostics” to host/IPC/health + live-when-enabled; recommend removing unused internetClient | Accuracy; closing strength without overclaim |
| Appendix A §3 | Clarified lazy live subscribe vs long-running service paths | Consistency |
| Appendix C runtime notes | Explicit health-at-start + lazy live subscribe | Consistency |
| Appendix D | Points to main IPC security; kept supplemental notes | Avoid duplication while preserving evidence |
| Appendix E | Added BU local-pipe risk row with disclosed mitigation | Security honesty |
| Appendix F | Added Event Log channels, SDDL, UI capabilities rows | Traceability |
| Architecture diagrams (all 7 Mermaid blocks) | **Unchanged** | Preserve formatting/diagrams per requirements |

## Explicit non-changes

- No architecture redesign of Pulse UI/service split  
- No invented security mechanisms (PID allowlists, mTLS, etc.)  
- No claim that `internetClient` is required  
- `apps/pulse_app/pubspec.yaml` capability list **not** edited in this doc pass (document recommends removal for a follow-up packaging change)

## Generated artifacts

After this source update, regenerate:

- `docs/store/packagedServices-business-justification.pdf`
- `docs/store/packagedServices-business-justification.docx`
