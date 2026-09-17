#!/usr/bin/env bash
#===============================================================================
# 02_login_logout_audit.sh
# Purpose : Audit interactive logins, logouts, and failed authentication
#           attempts (brute-force detection) from wtmp/btmp/journald.
# Usage   : ./02_login_logout_audit.sh [days_back] [fail_threshold]
#           Defaults: days_back=1, fail_threshold=5 (per source IP)
# Notes   : Read-only. Full accuracy requires root (btmp + /var/log/secure).
#===============================================================================
source "$(dirname "$0")/lib_common.sh"

DAYS_BACK="${1:-1}"
FAIL_THRESHOLD="${2:-5}"
need_root

hdr "Currently logged in users (who -a)"
who -a 2>/dev/null | tee -a "$OUTFILE"

hdr "Successful logins/logouts — last ${DAYS_BACK} day(s) (last -F)"
last -F -s "-${DAYS_BACK}days" 2>/dev/null | grep -v '^$' | tee -a "$OUTFILE"

hdr "Failed login attempts (lastb) — last ${DAYS_BACK} day(s)"
if [ -r /var/log/btmp ]; then
    lastb -F -s "-${DAYS_BACK}days" 2>/dev/null | grep -v '^$' | tee -a "$OUTFILE"
else
    warn "/var/log/btmp not readable — run as root to audit failed logins."
fi

hdr "Failed SSH attempts by source IP (journald, last ${DAYS_BACK} day(s))"
if command -v journalctl >/dev/null 2>&1; then
    journalctl -u sshd --since "-${DAYS_BACK} days" 2>/dev/null \
        | grep -i "Failed password" \
        | grep -oE 'from [0-9a-fA-F:.]+' | awk '{print $2}' \
        | sort | uniq -c | sort -rn | tee -a "$OUTFILE" > /tmp/_failip.$$
    while read -r count ip; do
        [ -z "$ip" ] && continue
        if [ "$count" -ge "$FAIL_THRESHOLD" ]; then
            crit "Possible brute force: ${ip} — ${count} failed SSH attempts"
        fi
    done < /tmp/_failip.$$
    rm -f /tmp/_failip.$$
else
    warn "journalctl not available — falling back to /var/log/secure grep."
    if [ -r /var/log/secure ]; then
        grep "Failed password" /var/log/secure 2>/dev/null \
            | grep -oE 'from [0-9a-fA-F:.]+' | awk '{print $2}' \
            | sort | uniq -c | sort -rn | tee -a "$OUTFILE"
    fi
fi

hdr "Root logins (direct root SSH — should generally be disabled)"
if command -v journalctl >/dev/null 2>&1; then
    journalctl -u sshd --since "-${DAYS_BACK} days" 2>/dev/null | grep -i "Accepted .* root" | tee -a "$OUTFILE"
fi

summary_exit
