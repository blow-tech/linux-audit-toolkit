#!/usr/bin/env bash
source "$(dirname "$0")/lib_common.sh"
# Explicit files only. Whole-file summary, not an asserted event-time window.
(($#)) || { unknown 'Supply reviewed access/error log paths; automatic server/path guessing removed.'; summary_exit; }
for f in "$@"; do
    [[ -f $f && ! -L $f && -r $f ]] || { unknown "Unreadable, linked or non-regular log: $f"; continue; }
    hdr "Whole-file summary: $f"
    # One decompression/read per file; aggregate streaming with bounded key cardinality.
    if [[ $f == *.gz ]]; then reader=(gzip -cd -- "$f"); else reader=(cat -- "$f"); fi
    collect "${reader[@]}" | awk '
        {lines++; if ($9 ~ /^[0-9][0-9][0-9]$/) {status[$9]++; if($9 ~ /^5/) errors++}
         if(tolower($0) ~ /\[error\]|\[crit\]|severe|exception/) events++}
        END {printf "Lines: %d; HTTP 5xx: %d; error-like lines: %d\n",lines,errors,events;
             for(s in status) printf "HTTP %s: %d\n",s,status[s];
             if(errors || events) exit 1}' > "$RUN_DIR/summary"
    rc=$?
    cat "$RUN_DIR/summary" | tee -a "$OUTFILE"
    ((rc == 1)) && warn "Error-like observations in $f"
    ((rc > 1)) && unknown "Unable to summarize $f"
done
summary_exit
