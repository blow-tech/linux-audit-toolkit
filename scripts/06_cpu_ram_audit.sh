#!/usr/bin/env bash
source "$(dirname "$0")/lib_common.sh"
LOAD_THRESHOLD=${1:-1.0}; MEM_THRESHOLD=${2:-90}
[[ $LOAD_THRESHOLD =~ ^[0-9]+([.][0-9]+)?$ && $MEM_THRESHOLD =~ ^[0-9]{1,3}$ ]] && ((10#$MEM_THRESHOLD >= 1 && 10#$MEM_THRESHOLD <= 100)) || { unknown 'Invalid thresholds'; summary_exit; }
if cores=$(collect nproc) && load=$(collect cat /proc/loadavg); then
    read -r load1 _ <<< "$load"
    if [[ $cores =~ ^[1-9][0-9]*$ && $load1 =~ ^[0-9]+[.][0-9]+$ ]]; then
        log "Load1=$load1 cores=$cores"
        awk -v l="$load1" -v n="$cores" -v t="$LOAD_THRESHOLD" 'BEGIN{exit !(l/n>=t)}' && crit 'Load per core exceeds threshold'
    else unknown 'Malformed CPU load data'; fi
fi
if mem=$(collect free -b); then
    read -r total used available <<< "$(awk '$1=="Mem:"{print $2,$3,$7}' <<< "$mem")"
    if [[ $total =~ ^[1-9][0-9]*$ && $available =~ ^[0-9]+$ ]] && ((available<=total)); then
        pct=$(( (total-available)*100/total )); log "Memory used (excluding available cache): $pct%"
        ((pct>=10#$MEM_THRESHOLD)) && crit 'Memory threshold exceeded'
    else unknown 'Malformed memory data (MemAvailable required)'; fi
    read -r st su <<< "$(awk '$1=="Swap:"{print $2,$3}' <<< "$mem")"
    if [[ $st =~ ^[0-9]+$ && $su =~ ^[0-9]+$ ]] && ((su<=st)); then
        if ((st>0 && su*100/st>=50)); then warn 'Swap at least 50% used'; fi
    else unknown 'Malformed swap data'; fi
fi
collect ps -eo pid,ppid,user,pcpu,pmem,comm --sort=-pcpu | sed -n '1,11p' | tee -a "$OUTFILE"
summary_exit
