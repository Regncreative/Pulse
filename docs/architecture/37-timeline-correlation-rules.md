# Timeline correlation rules (R2)

**Status:** Living — every rule must cite Microsoft-documented Event IDs / providers.  
**Engine:** Client-side `TimelineIncidentEngine` (Flutter).  
**Constitution:** No fabricated incidents. No AI prose. Empty RCA when no rule matches.

---

## Principles

1. Match only on provider name + Win32 Event ID (+ optional time window).
2. Never invent related events that are not present in the loaded Timeline.
3. Confidence is static per rule (`high` / `medium` / `low`).
4. False-positive notes are required for every rule.

---

## Rules

### `app-crash-wer`

| Field | Value |
|-------|--------|
| Title | Application crash reported |
| Members (ordered) | `Application Error` **1000**, then `Windows Error Reporting` **1001** |
| Window | 120 seconds |
| Possible cause | An application faulted; Windows Error Reporting recorded a follow-up report. |
| Confidence | high |
| Next step | Read the Faulting application / module fields in the Application Error message; open the matching WER report if present. |
| Citations | Microsoft Event ID documentation for Application Error 1000 and Windows Error Reporting 1001 |
| FP notes | Unrelated 1000/1001 pairs can coincide on busy machines; window + newest-first pairing reduces FP. Same-process matching is best-effort from message text only when present. |

### `unexpected-shutdown`

| Field | Value |
|-------|--------|
| Title | Unexpected shutdown recorded |
| Members | `Microsoft-Windows-Kernel-Power` **41**, then `EventLog` **6008** |
| Window | 7 days (6008 is often written at next boot) |
| Possible cause | The system restarted without a clean shutdown; Kernel-Power 41 marks an unexpected reset, and EventLog 6008 records the prior unclean shutdown. |
| Confidence | medium |
| Next step | Review Kernel-Power 41 details and recent Bugcheck / WER entries around the same time. |
| Citations | Microsoft Kernel-Power 41; EventLog 6008 previous shutdown unexpected |
| FP notes | Long window can pair unrelated cycles; prefer nearest 6008 after 41. |

### `service-crash-recover`

| Field | Value |
|-------|--------|
| Title | Service crash and recovery |
| Members | `Service Control Manager` **7031**, then `Service Control Manager` **7036** |
| Window | 180 seconds |
| Possible cause | A Windows service terminated unexpectedly and later reported a state change (often a recovery restart). |
| Confidence | medium |
| Next step | Confirm the service name in both events. Investigate repeated 7031 crashes for the same service. |
| Citations | Microsoft SCM Event IDs 7031 / 7036 |
| FP notes | Any 7036 after a 7031 within the window may pair unrelated services; prefer reviewing message text. |

### `display-tdr-4101`

| Field | Value |
|-------|--------|
| Title | Display driver reset (TDR) |
| Members | `Display` **4101** (single-event incident; expand shows the Windows event) |
| Window | n/a (singleton) |
| Possible cause | Timeout Detection and Recovery reset the display driver after it stopped responding. |
| Confidence | high |
| Next step | Note the driver name in the 4101 message; update or clean-install the GPU driver; check thermals / overclock. |
| Citations | [Event ID 4101 — Display Driver TDR (Microsoft TechNet Wiki archive)](https://learn.microsoft.com/en-us/archive/technet-wiki/1462.event-id-4101-display-driver-timeout-detection-and-recovery) |
| FP notes | Frequent 4101s indicate a real GPU/driver problem; singleton incidents do not invent DWM/recovery rows without documented Event IDs in the loaded set. |

---

## Explicitly not correlated yet

Multi-step “driver → DWM → recovery” chains require additional documented Event IDs present in the user’s Timeline. Until those IDs are listed here with citations, Pulse will not invent sibling rows.

---

## Related

- [36 — Timeline Intelligence R2](36-timeline-intelligence-r2.md)
- [07 — Timeline Engine](07-timeline-engine.md)
