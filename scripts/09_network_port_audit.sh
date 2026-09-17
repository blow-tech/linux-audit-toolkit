#!/usr/bin/env bash
#===============================================================================
# 09_network_port_audit.sh
# Purpose : Audit listening ports, established connections, and firewall
#           rules; flag ports not in an expected whitelist.
# Usage   : ./09_network_port_audit.sh [comma_separated_expected_ports]
#           Default whitelist: 22,80,443,8080,8443
# Notes   : Read-only (ss/firewall-cmd --list-all). No config changes made.
#===============================================================================
source "$(dirname "$0")/lib_common.sh"

EXPECTED_PORTS="${1:-22,80,443,8080,8443}"
IFS=',' read -ra WHITELIST <<< "$EXPECTED_PORTS"

hdr "Listening TCP/UDP ports (ss -tulnp)"
if [ "$(id -u)" -eq 0 ]; then
    ss -tulnp 2>/dev/null | tee -a "$OUTFILE"
else
    warn "Not root — process names on listening ports will be hidden. Run with sudo for full detail."
    ss -tuln 2>/dev/null | tee -a "$OUTFILE"
fi

hdr "Unexpected listening ports (outside whitelist: ${EXPECTED_PORTS})"
LISTENING=$(ss -tuln 2>/dev/null | awk 'NR>1 {print $5}' | grep -oE '[0-9]+$' | sort -un)
for port in $LISTENING; do
    MATCH=0
    for w in "${WHITELIST[@]}"; do
        [ "$port" = "$w" ] && MATCH=1 && break
    done
    if [ "$MATCH" -eq 0 ]; then
        warn "Unexpected listening port: ${port}"
    fi
done

hdr "Established connection count by remote IP (top 15)"
ss -tn state established 2>/dev/null | awk 'NR>1 {print $4}' | sed -E 's/:[0-9]+$//' \
    | sort | uniq -c | sort -rn | head -15 | tee -a "$OUTFILE"

hdr "Firewall status"
if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
    log "firewalld active. Zones and rules:"
    firewall-cmd --list-all 2>/dev/null | tee -a "$OUTFILE"
elif command -v iptables >/dev/null 2>&1; then
    log "firewalld not active — showing iptables rules:"
    iptables -L -n -v 2>/dev/null | tee -a "$OUTFILE"
else
    warn "No firewall tooling detected (firewalld/iptables) — verify host is protected at network layer."
fi

hdr "Default route / basic connectivity"
ip route show default 2>/dev/null | tee -a "$OUTFILE"
GATEWAY=$(ip route show default 2>/dev/null | awk '{print $3; exit}')
if [ -n "$GATEWAY" ]; then
    if ping -c 2 -W 2 "$GATEWAY" >/dev/null 2>&1; then
        log "Default gateway ${GATEWAY} is reachable."
    else
        crit "Default gateway ${GATEWAY} is NOT reachable."
    fi
fi

summary_exit
