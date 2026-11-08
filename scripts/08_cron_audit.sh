#!/usr/bin/env bash
#===============================================================================
# 08_cron_audit.sh
# Purpose : Inventory all scheduled work (system cron, per-user cron,
#           /etc/cron.d, systemd timers) and flag insecure job scripts.
# Usage   : ./08_cron_audit.sh
# Notes   : Read-only. Root recommended to see all users' crontabs.
#===============================================================================
source "$(dirname "$0")/lib_common.sh"
need_root || :

hdr "/etc/crontab"
[ -f /etc/crontab ] && grep -vE '^\s*#|^\s*$' /etc/crontab | tee -a "$OUTFILE"

hdr "/etc/cron.d/*"
if [ -d /etc/cron.d ]; then
    for f in /etc/cron.d/*; do
        [ -f "$f" ] || continue
        echo "--- $f ---" | tee -a "$OUTFILE"
        grep -vE '^\s*#|^\s*$' "$f" | tee -a "$OUTFILE"
    done
fi

hdr "/etc/cron.{hourly,daily,weekly,monthly}"
for d in hourly daily weekly monthly; do
    DIR="/etc/cron.${d}"
    [ -d "$DIR" ] || continue
    echo "--- $DIR ---" | tee -a "$OUTFILE"
    collect ls -l "$DIR" | tee -a "$OUTFILE"
done

hdr "Per-user crontabs"
if [ -d /var/spool/cron ]; then
    for f in /var/spool/cron/*; do
        [ -f "$f" ] || continue
        u=$(basename "$f")
        echo "--- user: $u ---" | tee -a "$OUTFILE"
        grep -vE '^\s*#|^\s*$' "$f" | tee -a "$OUTFILE"
    done
elif command -v crontab >/dev/null 2>&1; then
    for u in $(cut -f1 -d: /etc/passwd); do
        CT=$(crontab -l -u "$u" 2>/dev/null); rc=$?
        ((rc == 0)) || unknown "Crontab unavailable/absent for $u (exit $rc); not classified as clean"
        if [ -n "$CT" ]; then
            echo "--- user: $u ---" | tee -a "$OUTFILE"
            echo "$CT" | grep -vE '^\s*#|^\s*$' | tee -a "$OUTFILE"
        fi
    done
fi

hdr "systemd timers (modern cron replacement)"
collect systemctl list-timers --all --no-legend 2>/dev/null | tee -a "$OUTFILE"

hdr "Security check: cron job scripts that are world-writable"
FOUND_INSECURE=0
for src in /etc/crontab /etc/cron.d/* /var/spool/cron/*; do
    [ -f "$src" ] || continue
    grep -oE '(/[^ ]+\.sh|/[^ ]+\.py|/[^ ]+\.pl)' "$src" 2>/dev/null | while read -r script; do
        if [ -f "$script" ] && mode=$(collect stat -c %a -- "$script") && (( (8#$mode & 0002) != 0 )); then
            crit "Cron job script is world-writable: $script (referenced in $src)"
            FOUND_INSECURE=1
        fi
    done
done
[ "$FOUND_INSECURE" -eq 0 ] && log "No world-writable cron job scripts detected."

summary_exit
