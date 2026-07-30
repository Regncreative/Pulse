## Goal

Plan the **v1.2** milestone: deeper Windows observability beyond classic Event Log channels.

Still **observation-only** — official APIs, no injection, no hooks, no OS mutation.

---

## Candidate themes

### ETW support
- [ ] ETW engine milestone (providers, session lifecycle, buffering)
- [ ] Map selected ETW events into Timeline Level-1 / Level-2 language
- [ ] ADR for ETW privilege, CPU cost, and drop policy

### WMI integration
- [ ] Read-only WMI queries for system / service / process context
- [ ] Optional enrichment of Timeline events with WMI-backed facts
- [ ] Clear offline / access-denied UX

### Process Monitor
- [ ] Process lifecycle timeline (create / exit / child processes) via supported APIs
- [ ] Correlate process events with Event Log / future ETW rows

### Service Monitor
- [ ] Service start / stop / failure visibility beyond SCM Event Log alone
- [ ] Service detail panel (state, start type, dependencies — read-only)

### Performance history
- [ ] Retain short local health history (CPU / mem / disk / net) for sparklines / review
- [ ] Explicit retention limits (local-only, no cloud)
- [ ] Export optional performance slice with diagnostics

### Incident analysis
- [ ] Crash / WER-oriented timeline view
- [ ] “What happened around time T?” workspace
- [ ] Suggested related events (heuristic, transparent, non-destructive)

---

## Out of scope for v1.2

- Kernel drivers, hooks, or injected agents
- Remote fleet management / SaaS backend
- Anything that changes Windows configuration silently

## References

- Future modules list: `AGENTS.md`
- Architecture package: `docs/architecture/README.md`
- Prior milestone: Roadmap v1.1
