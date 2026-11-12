#!/usr/bin/env bash
source "$(dirname "$0")/lib_common.sh"
THRESHOLD=${1:-${AUDIT_DISK_THRESHOLD:-85}}; SCAN_PATH=${2:-}
[[ $THRESHOLD =~ ^[0-9]{1,3}$ ]] && ((10#$THRESHOLD >= 1 && 10#$THRESHOLD <= 100)) || { unknown 'Threshold must be 1..100'; summary_exit; }
THRESHOLD=$((10#$THRESHOLD))
for kind in blocks inodes; do
    hdr "$kind usage"
    args=(-P -x tmpfs -x devtmpfs); [[ $kind == inodes ]] && args+=(-i)
    if collect df "${args[@]}" > "$RUN_DIR/df-$kind"; then
        cat "$RUN_DIR/df-$kind" | tee -a "$OUTFILE"
        rows=0
        while read -r fs total used available pct mount; do
            [[ $fs == Filesystem ]] && continue
            [[ -n $fs ]] || continue
            rows=$((rows+1))
            if [[ ! $pct =~ ^[0-9]+%$ ]]; then unknown "Unavailable $kind usage: $fs"; continue; fi
            value=${pct%%%}
            if ((10#$value >= THRESHOLD)); then
                if [[ $kind == blocks ]]; then crit "High disk usage: $pct $mount"; else warn "High inode usage: $pct $mount"; fi
            fi
        done < "$RUN_DIR/df-$kind"
        ((rows)) || unknown "Empty $kind collection"
    fi
done
# Filesystem walks are explicitly scoped and opt-in; timeout is per collector.
if [[ -n $SCAN_PATH ]]; then
    [[ $SCAN_PATH == /* && -d $SCAN_PATH ]] || { unknown 'Scan path must be an existing absolute directory'; summary_exit; }
    hdr "Directory sizes under $SCAN_PATH (single filesystem)"
    if collect du -x -k --max-depth=1 -- "$SCAN_PATH" > "$RUN_DIR/sizes"; then sort -rn "$RUN_DIR/sizes" | sed -n '1,15p' | tee -a "$OUTFILE"; fi
else
    log 'NOT REQUESTED: filesystem size walks; provide scan_path to opt in.'
fi
summary_exit
