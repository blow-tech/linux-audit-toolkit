#!/usr/bin/env bash
#===============================================================================
# lib_common.sh - shared helpers for the linux-audit-toolkit scripts
# Source this from every script:  source "$(dirname "$0")/lib_common.sh"
#===============================================================================

# Don't 'set -e' here — audit scripts must keep running even if one check fails.
set -uo pipefail

TOOLKIT_HOSTNAME="$(hostname -s 2>/dev/null || echo unknown-host)"
TOOLKIT_TS="$(date '+%Y%m%d_%H%M%S')"
LOGDIR="${AUDIT_LOGDIR:-/var/log/sysaudit}"

# Fall back to /tmp if we can't write to /var/log/sysaudit (e.g. not root yet)
if ! mkdir -p "$LOGDIR" 2>/dev/null || [ ! -w "$LOGDIR" ]; then
    LOGDIR="/tmp/sysaudit"
    mkdir -p "$LOGDIR"
fi

SCRIPT_NAME="$(basename "${0%.sh}")"
OUTFILE="${LOGDIR}/${TOOLKIT_HOSTNAME}_${SCRIPT_NAME}_${TOOLKIT_TS}.log"

WARN_COUNT=0
CRIT_COUNT=0

log()   { printf '%s\n' "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$OUTFILE"; }
hdr()   { log ""; log "=== $* ==="; }
warn()  { WARN_COUNT=$((WARN_COUNT+1)); log "[WARN] $*"; }
crit()  { CRIT_COUNT=$((CRIT_COUNT+1)); log "[CRIT] $*"; }

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        warn "Not running as root — some checks (lastb, /var/log/secure, shadow, sudoers) will be skipped or incomplete. Re-run with sudo for a full audit."
        return 1
    fi
    return 0
}

summary_exit() {
    hdr "SUMMARY"
    log "Warnings: ${WARN_COUNT}  Critical: ${CRIT_COUNT}"
    log "Full log: ${OUTFILE}"
    if [ "$CRIT_COUNT" -gt 0 ]; then
        exit 2
    elif [ "$WARN_COUNT" -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}
