#!/usr/bin/env bash
# Local collectors only. No notifications or remediation.
set -uo pipefail
set +m
shopt -s lastpipe
umask 077
export LC_ALL=C
TOOLKIT_HOSTNAME=$(hostname -s 2>/dev/null || printf unknown)
TOOLKIT_TS=$(date -u +%Y%m%dT%H%M%S)
LOGDIR=${AUDIT_LOGDIR:-/var/log/sysaudit}
# Existing trusted parent required; no shared /tmp fallback or chmod of host paths.
[[ -d $LOGDIR && ! -L $LOGDIR && -O $LOGDIR && -w $LOGDIR ]] || { echo 'Provision an owned, protected AUDIT_LOGDIR first.' >&2; exit 3; }
mode=$(stat -c %a -- "$LOGDIR") || exit 3
(( (8#$mode & 0022) == 0 )) || { echo 'Log parent is group/world writable.' >&2; exit 3; }
RUN_DIR=$(mktemp -d "$LOGDIR/run.XXXXXXXX") || exit 3
OUTFILE=$RUN_DIR/report.log
: > "$OUTFILE" || exit 3
WARN_COUNT=0; CRIT_COUNT=0
AUDIT_TIMEOUT=${AUDIT_TIMEOUT:-60}
[[ $AUDIT_TIMEOUT =~ ^[1-9][0-9]{0,3}$ ]] || { echo 'Invalid AUDIT_TIMEOUT (1..9999 seconds).' >&2; exit 3; }
command -v timeout >/dev/null || { echo 'GNU timeout required.' >&2; exit 3; }
log() { printf '%s\n' "$*" | tee -a "$OUTFILE" || exit 3; }
hdr() { log "=== $* ==="; }
warn() { WARN_COUNT=$((WARN_COUNT+1)); log "[WARN] $*"; }
crit() { CRIT_COUNT=$((CRIT_COUNT+1)); log "[CRIT] $*"; }
unknown() { printf '%s\n' "$*" >> "$RUN_DIR/unknown" || exit 3; log "[UNKNOWN] $*"; }
# Failed collectors mark a persistent per-run file, including inside subshells.
collect() {
    local rc=0
    timeout -k 5 "$AUDIT_TIMEOUT" "$@" || rc=$?
    if ((rc)); then printf '%s (exit %s)\n' "$1" "$rc" >> "$RUN_DIR/unknown"; fi
    return "$rc"
}
need_root() { if ((EUID != 0)); then unknown 'Unprivileged account: restricted checks incomplete.'; return 1; fi; }
summary_exit() {
    log "Warnings: $WARN_COUNT Critical: $CRIT_COUNT; report: $OUTFILE"
    if [[ -s $RUN_DIR/unknown ]]; then log 'Collection incomplete:'; cat "$RUN_DIR/unknown"; exit 3; fi
    ((CRIT_COUNT)) && exit 2
    ((WARN_COUNT)) && exit 1
    exit 0
}
