#!/usr/bin/env bash
#===============================================================================
# 01_disk_space_audit.sh
# Purpose : Audit filesystem usage, inode usage, and largest directories.
# Usage   : ./01_disk_space_audit.sh [threshold_percent] [scan_path]
#           Defaults: threshold=85, scan_path=/
# Notes   : Read-only. Safe to run in production, no maintenance window needed.
#===============================================================================
source "$(dirname "$0")/lib_common.sh"

THRESHOLD="${1:-85}"
SCAN_PATH="${2:-/}"

hdr "Filesystem usage (df -hT)"
df -hT -x tmpfs -x devtmpfs -x overlay 2>/dev/null | tee -a "$OUTFILE"

hdr "Filesystems over ${THRESHOLD}% used"
df -hP -x tmpfs -x devtmpfs 2>/dev/null | awk -v t="$THRESHOLD" 'NR>1 {
    gsub("%","",$5);
    if ($5+0 >= t) print
}' | while read -r line; do
    crit "High disk usage: $line"
done
[ "$CRIT_COUNT" -eq 0 ] && log "No filesystem above ${THRESHOLD}%."

hdr "Inode usage (df -i)"
df -iP -x tmpfs -x devtmpfs 2>/dev/null | tee -a "$OUTFILE"
df -iP -x tmpfs -x devtmpfs 2>/dev/null | awk -v t="$THRESHOLD" 'NR>1 {
    gsub("%","",$5);
    if ($5+0 >= t) print
}' | while read -r line; do
    warn "High inode usage: $line"
done

hdr "Top 15 largest directories under ${SCAN_PATH} (1 level deep, may take a moment)"
du -x -h --max-depth=1 "$SCAN_PATH" 2>/dev/null | sort -rh | head -15 | tee -a "$OUTFILE"

hdr "Top 15 largest files under /var/log (incl. rotated .gz)"
find /var/log -type f \( -name "*.log" -o -name "*.gz" -o -name "*-????????" \) -printf '%s %p\n' 2>/dev/null \
    | sort -rn | head -15 | awk '{printf "%.1f MB\t%s\n", $1/1024/1024, $2}' | tee -a "$OUTFILE"

hdr "Growth check: /var/log total size vs 7 days ago (if find supports -mtime)"
CUR_SIZE=$(du -sh /var/log 2>/dev/null | awk '{print $1}')
log "Current /var/log size: ${CUR_SIZE}"
OLD_LOGS_NOT_ROTATED=$(find /var/log -type f -name "*.log" -mtime +30 -size +100M 2>/dev/null)
if [ -n "$OLD_LOGS_NOT_ROTATED" ]; then
    warn "Large (>100MB) .log files older than 30 days found — check logrotate config:"
    echo "$OLD_LOGS_NOT_ROTATED" | tee -a "$OUTFILE"
fi

summary_exit
