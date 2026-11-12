# Linux audit toolkit

Read-only collectors for reviewed Linux scopes. Reports contain sensitive host/account/log information. They are evidence, not compliance certification. No operational run or production suitability is established by CI.

Read [REMEDIATION-2026-11.md](REMEDIATION-2026-11.md) before changing schedules. Bash 4.2+, GNU coreutils/timeout/find, and systemd/Linux collector commands are required. Use only the privileges required for selected evidence; denied queries return UNKNOWN.

| Script | Reviewed scope |
|---|---|
| `01_disk_space_audit.sh` | Block and inode usage; optional explicit filesystem scan |
| `02_login_logout_audit.sh` | Login/session records; bounded journal period |
| `03_file_permission_audit.sh` | Explicit directory only; single-filesystem permission scan |
| `04_service_status_audit.sh` | Explicit systemd unit arguments |
| `05_webserver_log_audit.sh` | Explicit log-file arguments, including gzip; whole supplied files |
| `06_cpu_ram_audit.sh` | CPU/load/memory/swap observations |
| `07_user_account_audit.sh` | Local user/account configuration evidence |
| `08_cron_audit.sh` | Local cron/timer evidence |
| `09_network_port_audit.sh` | Local listeners/routing/firewall evidence; no probes |
| `10_full_system_report.sh` | All nine checks; missing/failed children are UNKNOWN |
| `lib_common.sh` | Private output, bounded collectors and status aggregation |

Exit codes: 0 = no findings in collected scope; 1 = warnings; 2 = critical findings; 3 = incomplete/UNKNOWN, including timeouts. None proves the host safe. Web logs are not automatically a last-N-hours report.

Manual execution requires an existing owned log directory with no group/world write permissions and trusted ancestors. Set `AUDIT_LOGDIR`, `AUDIT_SCAN_ROOT`, `AUDIT_SERVICE_UNITS` (space-separated units), `AUDIT_WEB_LOGS` (newline-separated absolute paths), `AUDIT_TIMEOUT` and `AUDIT_CHILD_TIMEOUT` explicitly. Review scope and resource cost in a disposable lab before invoking the orchestrator. No mail or webhook delivery is built in.

Ansible deployment changes host files and timers; it is not a read-only operation. Scheduling defaults off (`audit_schedule_enabled: false`). Configure the corresponding `audit_scan_root`, `audit_service_units`, `audit_web_logs` and protected report parent before opting in. Start with `--syntax-check`, then review `--check --diff --limit <Host>` under an approved change plan; check mode does not validate live collector results.

Reports are private files under `AUDIT_LOGDIR/run.*/`. Automatic deletion/rotation is disabled to preserve evidence. Establish a separate retention/archival policy and disk-capacity monitoring. Child reports and UNKNOWN markers must be retained together. Backup/recovery, SELinux and integration behavior require lab validation.

Validation: `python3 -m unittest discover -s tests -v` uses isolated local fixtures and mocks; no production data or messages.
