# linux-audit-toolkit

Read-only Bash audit scripts for RHEL/CentOS-family production servers.
Covers disk/inode space, login/logout + brute-force detection, file &
directory permissions, service health (httpd/nginx/tomcat + core daemons),
web server log analysis (incl. rotated `.gz` logs), CPU/RAM/swap, user
accounts & sudoers, cron/systemd timers, and listening ports/firewall.

All scripts are **read-only** — no service restarts, no config changes, no
file modifications outside of `/var/log/sysaudit/` (their own output logs).
Safe to run in production at any time; no maintenance window required.

## Requirements

- RHEL / CentOS / Rocky / Alma (or any systemd + `journalctl` Linux)
- Bash 4+
- Root or sudo recommended for full coverage (`lastb`, `/etc/shadow`,
  `/var/log/secure`, sudoers, all listening-port process names)
- Optional: `sysstat` (`sar`) for historical CPU trending

## Structure

```
linux-audit-toolkit/
├── README.md
├── LICENSE
├── scripts/
│   ├── lib_common.sh              # shared logging/helpers, sourced by all scripts
│   ├── 01_disk_space_audit.sh
│   ├── 02_login_logout_audit.sh
│   ├── 03_file_permission_audit.sh
│   ├── 04_service_status_audit.sh
│   ├── 05_webserver_log_audit.sh
│   ├── 06_cpu_ram_audit.sh
│   ├── 07_user_account_audit.sh
│   ├── 08_cron_audit.sh
│   ├── 09_network_port_audit.sh
│   └── 10_full_system_report.sh   # orchestrator — runs 01-09, builds one report
└── ansible/                       # fleet-wide deployment (see below)
    ├── ansible.cfg
    ├── playbook.yml
    ├── inventory/
    │   ├── hosts.ini
    │   └── group_vars/webservers.yml
    └── roles/linux_audit_toolkit/
        ├── defaults/main.yml      # all tunables (thresholds, schedule, mail/webhook)
        ├── tasks/main.yml
        ├── handlers/main.yml
        └── templates/             # systemd unit, cron.d, logrotate templates
```

## Manual usage (single host)

```bash
git clone https://github.com/<you>/linux-audit-toolkit.git
cd linux-audit-toolkit/scripts
chmod +x *.sh
sudo ./10_full_system_report.sh
```

Run scripts individually if you only need one area, e.g.:

```bash
sudo ./01_disk_space_audit.sh 90          # alert at 90% instead of default 85%
sudo ./02_login_logout_audit.sh 7 3       # last 7 days, flag IPs with >=3 fails
sudo ./05_webserver_log_audit.sh 48       # last 48 hours of web logs
```

Each script prints to stdout **and** writes a timestamped log to
`/var/log/sysaudit/` (falls back to `/tmp/sysaudit/` if not writable/root).

### Exit codes (all scripts, including the orchestrator)

| Code | Meaning              |
|------|----------------------|
| 0    | Clean, no findings   |
| 1    | Warnings found       |
| 2    | Critical findings    |

Use this in monitoring/cron to alert only on non-zero exit.

## Fleet-wide deployment (Ansible — recommended for production)

The `ansible/` directory installs the toolkit to `/opt/linux-audit-toolkit` on
every host in your inventory, sets file ownership/perms, configures
logrotate, and schedules `10_full_system_report.sh` via a systemd timer
(default) or `cron.d`. It's idempotent — safe to re-run any time, e.g. after
editing a script or changing a threshold in `defaults/main.yml`.

```bash
cd ansible
cp inventory/hosts.ini inventory/hosts.ini.local   # edit with your real hostnames
ansible-playbook -i inventory/hosts.ini.local playbook.yml --check --diff   # dry run first
ansible-playbook -i inventory/hosts.ini.local playbook.yml                  # apply
ansible-playbook -i inventory/hosts.ini.local playbook.yml --limit webservers
```

Key variables (override in `inventory/group_vars/<group>.yml` or
`host_vars/<host>.yml` — see `ansible/inventory/group_vars/webservers.yml`
for an example):

| Variable                        | Default                    | Purpose                                  |
|----------------------------------|----------------------------|-------------------------------------------|
| `audit_install_dir`              | `/opt/linux-audit-toolkit` | Install path on target hosts              |
| `audit_log_dir`                  | `/var/log/sysaudit`        | Where reports/logs land                   |
| `audit_use_systemd_timer`        | `true`                     | `false` deploys `cron.d` instead          |
| `audit_schedule_hour/minute`     | `6` / `0`                  | Daily run time                            |
| `audit_mailto`                   | `""`                       | Email on WARN/CRIT (needs mail configured)|
| `audit_webhook_url`              | `""`                       | Slack/Teams webhook for summary posts     |
| `audit_disk_threshold_pct`       | `85`                       | Reference threshold (tune per host group) |
| `audit_logrotate_keep_weeks`     | `8`                        | Retention for rotated reports             |

Requires: `ansible-core` on the control node, SSH + sudo to target hosts,
targets are systemd-based RHEL-family (the role asserts this and fails fast
otherwise).

## Scheduling manually, without Ansible

### Cron (simple)
```cron
# /etc/cron.d/linux-audit-toolkit
0 6 * * * root MAILTO=oncall@example.com /opt/linux-audit-toolkit/scripts/10_full_system_report.sh
```

### systemd timer (preferred on RHEL 8/9)
`/etc/systemd/system/linux-audit.service`
```ini
[Unit]
Description=Daily production audit (linux-audit-toolkit)

[Service]
Type=oneshot
Environment=MAILTO=oncall@example.com
Environment=AUDIT_WEBHOOK_URL=https://hooks.slack.com/services/XXX
ExecStart=/opt/linux-audit-toolkit/scripts/10_full_system_report.sh
```
`/etc/systemd/system/linux-audit.timer`
```ini
[Unit]
Description=Run linux-audit-toolkit daily at 06:00

[Timer]
OnCalendar=*-*-* 06:00:00
Persistent=true

[Install]
WantedBy=timers.target
```
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now linux-audit.timer
```

### Optional integrations
- `MAILTO=admin@example.com` — emails the report via `mail` if warnings/criticals found (requires `mailx`/`postfix` configured)
- `AUDIT_WEBHOOK_URL=https://...` — posts a one-line summary to Slack/Teams incoming webhook
- Point `logrotate` at `/var/log/sysaudit/*.log` so reports don't accumulate indefinitely — see example below.

`/etc/logrotate.d/sysaudit`:
```
/var/log/sysaudit/*.log /var/log/sysaudit/*.txt {
    weekly
    rotate 8
    compress
    missingok
    notifempty
}
```

## Notes / customization before production use

- **Test on a non-prod host first.** Thresholds (disk %, load/core, memory %,
  failed-login count) are sensible defaults, not guarantees for your workload —
  tune the arguments per script or edit the defaults at the top of each file.
- `03_file_permission_audit.sh` walks the filesystem with `find` — on very
  large volumes this can take several minutes; narrow `scan_path` or schedule
  off-peak if needed.
- Web server detection in `04`/`05` assumes standard RHEL package paths
  (`/var/log/httpd`, `/var/log/nginx`, `/opt/tomcat/logs`). Adjust paths if
  your install uses custom locations.
- None of these scripts collect or transmit data outside the host unless you
  explicitly set `MAILTO` or `AUDIT_WEBHOOK_URL`.

## License

MIT — see [LICENSE](LICENSE).
