#!/usr/bin/env bash
#===============================================================================
# 04_service_status_audit.sh
# Purpose : Audit systemd service health for web/app stack + core daemons.
#           Checks active/enabled state, recent restarts, and failed units.
# Usage   : ./04_service_status_audit.sh [extra_service1 extra_service2 ...]
# Notes   : Read-only (systemctl status / show — no start/stop/restart here).
#===============================================================================
source "$(dirname "$0")/lib_common.sh"

DEFAULT_SERVICES=(httpd nginx tomcat sshd crond firewalld chronyd)
SERVICES=("${DEFAULT_SERVICES[@]}" "$@")

hdr "Failed systemd units (systemctl --failed)"
FAILED=$(systemctl --failed --no-legend 2>/dev/null)
if [ -n "$FAILED" ]; then
    echo "$FAILED" | tee -a "$OUTFILE"
    echo "$FAILED" | while read -r line; do crit "Failed unit: $line"; done
else
    log "No failed units."
fi

hdr "Service checks: ${SERVICES[*]}"
for svc in "${SERVICES[@]}"; do
    # Skip services that don't exist on this host at all
    if ! systemctl list-unit-files "${svc}.service" >/dev/null 2>&1 || \
       ! systemctl list-unit-files "${svc}.service" 2>/dev/null | grep -q "${svc}.service"; then
        log "$svc: not installed on this host — skipping"
        continue
    fi

    ACTIVE=$(systemctl is-active "$svc" 2>/dev/null)
    ENABLED=$(systemctl is-enabled "$svc" 2>/dev/null)
    RESTARTS=$(systemctl show "$svc" -p NRestarts --value 2>/dev/null)
    UPTIME=$(systemctl show "$svc" -p ActiveEnterTimestamp --value 2>/dev/null)

    log "$svc: active=${ACTIVE:-unknown} enabled=${ENABLED:-unknown} restarts=${RESTARTS:-0} since=${UPTIME:-n/a}"

    if [ "$ACTIVE" != "active" ]; then
        crit "$svc is NOT active (state: $ACTIVE)"
    fi
    if [ "$ENABLED" != "enabled" ] && [ "$ACTIVE" = "active" ]; then
        warn "$svc is active but not enabled at boot — will not survive a reboot"
    fi
    if [ -n "$RESTARTS" ] && [ "$RESTARTS" -gt 3 ] 2>/dev/null; then
        warn "$svc has restarted ${RESTARTS} times since boot — check for crash-looping"
    fi

    # Last 10 error-level log lines for this unit, last 24h
    ERRS=$(journalctl -u "$svc" -p err --since "-1 day" --no-pager 2>/dev/null | tail -10)
    if [ -n "$ERRS" ]; then
        log "--- recent errors for $svc (last 24h) ---"
        echo "$ERRS" | tee -a "$OUTFILE"
    fi
done

hdr "Listening web ports sanity check (expect 80/443/8080 if webserver active)"
ss -tlnp 2>/dev/null | grep -E ':80 |:443 |:8080 |:8443 ' | tee -a "$OUTFILE"

summary_exit
