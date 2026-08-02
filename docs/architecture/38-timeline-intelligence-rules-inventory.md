# Intelligence rule inventory (R2)

**Status:** Living catalog — must stay in sync with `service/pulse_service/src/intelligence/event_intelligence.cpp` (`kRules`).  
**Baseline (pre-R2):** **38** rules  
**Current (R2 close candidate):** **68** rules (**+30**)

Matching: exact `win_event_id` + case-insensitive provider substring hint. More specific provider hints for the same Event ID are listed first.

---

## Pre-R2 baseline (38)

| Event ID | Provider hint | Title |
|----------|---------------|-------|
| 10016 | DistributedCOM | COM Permission Warning |
| 7040 | Service Control Manager | Windows Service Configuration Changed |
| 7036 | Service Control Manager | Windows Service State Changed |
| 7023 | Service Control Manager | Windows Service Failed |
| 7031 | Service Control Manager | Windows Service Crashed |
| 7034 | Service Control Manager | Windows Service Stopped Unexpectedly |
| 7045 | Service Control Manager | New Service or Driver Installed |
| 4266 | Tcpip | Temporary UDP Port Allocation Failed |
| 4231 | Tcpip | Temporary TCP Port Allocation Failed |
| 114 | HttpService | HTTP Service Endpoint Removed |
| 32 | HttpService | HTTP Service Endpoint Removed |
| 12 | Kernel-General | Windows Started |
| 13 | Kernel-General | Windows Shutdown |
| 6005 | EventLog | Event Log Service Started |
| 6006 | EventLog | Event Log Service Stopped |
| 1074 | User32 | Shutdown or Restart Initiated |
| 41 | Kernel-Power | Windows Restarted Unexpectedly |
| 6008 | EventLog | Previous Shutdown Was Unexpected |
| 42 | Kernel-Power | Windows Entered Sleep |
| 107 | Kernel-Power | Windows Resumed From Sleep |
| 1 | Power-Troubleshooter | Windows Woke From Sleep |
| 158 | Time-Service | Time Synchronization Stopped |
| 1001 | WER-SystemErrorReporting | Windows Stopped Unexpectedly |
| 1001 | BugCheck | Windows Stopped Unexpectedly |
| 1000 | Application Error | Application Crashed |
| 1002 | Application Hang | Application Stopped Responding |
| 1001 | Windows Error Reporting | Windows Error Reporting Recorded a Problem |
| 19 | WindowsUpdateClient | Windows Update Installed Successfully |
| 20 | WindowsUpdateClient | Windows Update Installation Failed |
| 43 | WindowsUpdateClient | Windows Update Installation Started |
| 44 | WindowsUpdateClient | Windows Update Download Started |
| 400 | Kernel-PnP | Device Configured |
| 410 | Kernel-PnP | Device Started |
| 411 | Kernel-PnP | Device Failed to Start |
| 7 | disk | Storage Reported a Bad Block |
| 51 | disk | Storage Reported a Disk Error |
| 4624 | Security-Auditing | User Signed In |
| 4634 | Security-Auditing | User Signed Out |

---

## R2 expansions (+30)

| Event ID | Provider hint | Title |
|----------|---------------|-------|
| 4101 | Display | Display Driver Reset |
| 7000 | Service Control Manager | Windows Service Failed to Start |
| 7009 | Service Control Manager | Windows Service Start Timed Out |
| 7011 | Service Control Manager | Windows Service Timed Out |
| 7022 | Service Control Manager | Windows Service Hung on Start |
| 7024 | Service Control Manager | Windows Service Reported a Specific Error |
| 7026 | Service Control Manager | Windows Service Boot Driver Issue |
| 55 | Ntfs | NTFS Structure Corruption Detected |
| 50 | Ntfs | Delayed Write Failed |
| 7 | Ntfs | NTFS Reported a Bad Cluster |
| 1014 | DNS-Client | DNS Name Resolution Timed Out |
| 1001 | Dhcp-Client | DHCP Lease Acquisition Issue |
| 8001 | WLAN-AutoConfig | Wireless Network Disconnected |
| 8002 | WLAN-AutoConfig | Wireless Connection Attempt Failed |
| 8003 | WLAN-AutoConfig | Wireless Network Connected |
| 36887 | Schannel | Schannel Received a Fatal Alert |
| 36874 | Schannel | Schannel Could Not Create Credentials |
| 2004 | Resource-Exhaustion-Detector | Windows Is Low on Virtual Memory |
| 100 | Diagnostics-Performance | Boot Performance Degraded |
| 1129 | GroupPolicy | Group Policy Processing Failed |
| 4625 | Security-Auditing | Sign-In Failed |
| 4648 | Security-Auditing | Explicit Credentials Sign-In |
| 4720 | Security-Auditing | User Account Created |
| 4732 | Security-Auditing | Member Added to Security Group |
| 1102 | Security-Auditing | Audit Log Cleared |
| 1116 | Windows Defender | Windows Defender Detected Malware |
| 1117 | Windows Defender | Windows Defender Took Action on Malware |
| 104 | EventLog | Event Log Cleared |
| 6009 | EventLog | Windows Version at Boot |
| 6013 | EventLog | System Uptime Reported |

---

## Correlation rules (client, separate catalog)

See [37-timeline-correlation-rules.md](37-timeline-correlation-rules.md). Count: **4** (`app-crash-wer`, `unexpected-shutdown`, `service-crash-recover`, `display-tdr-4101`).

---

## Notes

- Unmatched events fall back to a softened provider title + first-line summary — never invented Event IDs.
- Security-channel rules only surface when the Security log is readable under the user’s privileges.
- Further expansions require Microsoft-documented IDs + this inventory update in the same change.
