#!/usr/bin/env bash
#===============================================================================
# 06_cpu_ram_audit.sh
# Purpose : Audit CPU load, memory, and swap usage; surface top consumers.
# Usage   : ./06_cpu_ram_audit.sh [load_threshold_per_core] [mem_threshold_pct]
#           Defaults: load_threshold_per_core=1.0, mem_threshold_pct=90
# Notes   : Read-only, negligible overhead. Safe for production, any time.
#===============================================================================
source "$(dirname "$0")/lib_common.sh"

LOAD_THRESHOLD="${1:-1.0}"
MEM_THRESHOLD="${2:-90}"
NPROC=$(nproc 2>/dev/null || echo 1)

hdr "Uptime and load average"
uptime | tee -a "$OUTFILE"
LOAD1=$(uptime | awk -F'load average:' '{print $2}' | awk -F', ' '{print $1}' | tr -d ' ')
LOAD_PER_CORE=$(awk -v l="$LOAD1" -v n="$NPROC" 'BEGIN{printf "%.2f", l/n}')
log "Cores: ${NPROC}  Load(1m)/core: ${LOAD_PER_CORE}"
awk -v lpc="$LOAD_PER_CORE" -v t="$LOAD_THRESHOLD" 'BEGIN{exit !(lpc+0 >= t+0)}' \
    && crit "Load per core (${LOAD_PER_CORE}) >= threshold (${LOAD_THRESHOLD})"

hdr "Memory usage (free -h)"
free -h | tee -a "$OUTFILE"
MEM_PCT=$(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')
log "Memory used: ${MEM_PCT}%"
[ "$MEM_PCT" -ge "$MEM_THRESHOLD" ] && crit "Memory usage ${MEM_PCT}% >= threshold ${MEM_THRESHOLD}%"

hdr "Swap usage"
SWAP_TOTAL=$(free | awk '/Swap:/ {print $2}')
if [ "${SWAP_TOTAL:-0}" -gt 0 ]; then
    SWAP_PCT=$(free | awk '/Swap:/ {if ($2>0) printf "%.0f", $3/$2*100; else print 0}')
    log "Swap used: ${SWAP_PCT}%"
    [ "$SWAP_PCT" -ge 50 ] && warn "Swap usage at ${SWAP_PCT}% — investigate memory pressure"
else
    log "No swap configured."
fi

hdr "vmstat snapshot (5 samples, 1s interval)"
vmstat 1 5 | tee -a "$OUTFILE"

hdr "Top 10 processes by CPU"
ps -eo pid,ppid,user,pcpu,pmem,etime,cmd --sort=-pcpu | head -11 | tee -a "$OUTFILE"

hdr "Top 10 processes by memory"
ps -eo pid,ppid,user,pcpu,pmem,rss,cmd --sort=-pmem | head -11 | tee -a "$OUTFILE"

hdr "Zombie / defunct processes"
ZOMBIES=$(ps -eo stat,pid,cmd | awk '$1 ~ /^Z/')
if [ -n "$ZOMBIES" ]; then
    echo "$ZOMBIES" | tee -a "$OUTFILE"
    warn "Zombie processes present — check parent process handling"
else
    log "No zombie processes."
fi

if command -v sar >/dev/null 2>&1; then
    hdr "Historical CPU (sar -u, today)"
    sar -u 2>/dev/null | tail -20 | tee -a "$OUTFILE"
else
    log "sysstat (sar) not installed — historical trending unavailable. Consider: yum install sysstat"
fi

summary_exit
