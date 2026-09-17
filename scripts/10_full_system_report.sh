#!/usr/bin/env bash
#===============================================================================
# 10_full_system_report.sh
# Purpose : Orchestrator — runs all audit scripts (01-09) in sequence and
#           produces one consolidated, timestamped report. Intended to be
#           scheduled via cron/systemd timer for daily production audits.
# Usage   : ./10_full_system_report.sh
#           MAILTO=admin@example.com ./10_full_system_report.sh   (email on WARN/CRIT)
# Exit    : 0 = clean, 1 = warnings found, 2 = critical findings found
# Notes   : Read-only orchestration. Individual scripts are read-only too —
#           safe to run in production at any time, no maintenance window.
#===============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib_common.sh"

REPORT_DIR="${AUDIT_LOGDIR:-/var/log/sysaudit}"
[ -w "$REPORT_DIR" ] || REPORT_DIR="/tmp/sysaudit"
mkdir -p "$REPORT_DIR"
REPORT_FILE="${REPORT_DIR}/${TOOLKIT_HOSTNAME}_full_report_${TOOLKIT_TS}.txt"

SCRIPTS=(
    "01_disk_space_audit.sh"
    "02_login_logout_audit.sh"
    "03_file_permission_audit.sh"
    "04_service_status_audit.sh"
    "05_webserver_log_audit.sh"
    "06_cpu_ram_audit.sh"
    "07_user_account_audit.sh"
    "08_cron_audit.sh"
    "09_network_port_audit.sh"
)

TOTAL_WARN=0
TOTAL_CRIT=0

{
    echo "################################################################"
    echo "# Full System Audit Report"
    echo "# Host: ${TOOLKIT_HOSTNAME}"
    echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "################################################################"
} > "$REPORT_FILE"

for s in "${SCRIPTS[@]}"; do
    TARGET="$SCRIPT_DIR/$s"
    if [ ! -x "$TARGET" ]; then
        echo "[SKIP] $s not found or not executable at $TARGET" | tee -a "$REPORT_FILE"
        continue
    fi
    {
        echo ""
        echo "################################################################"
        echo "# BEGIN: $s"
        echo "################################################################"
    } >> "$REPORT_FILE"

    "$TARGET" >> "$REPORT_FILE" 2>&1
    RC=$?
    # Exit codes from lib_common.sh summary_exit: 0 clean, 1 warn, 2 crit
    [ "$RC" -eq 1 ] && TOTAL_WARN=$((TOTAL_WARN+1))
    [ "$RC" -eq 2 ] && TOTAL_CRIT=$((TOTAL_CRIT+1))

    echo "# END: $s (exit code ${RC})" >> "$REPORT_FILE"
done

{
    echo ""
    echo "################################################################"
    echo "# OVERALL SUMMARY"
    echo "# Scripts with warnings : ${TOTAL_WARN}"
    echo "# Scripts with critical : ${TOTAL_CRIT}"
    echo "# Full report saved to  : ${REPORT_FILE}"
    echo "################################################################"
} | tee -a "$REPORT_FILE"

# Optional: email report if MAILTO is set and mail command exists and anything is flagged
if [ -n "${MAILTO:-}" ] && command -v mail >/dev/null 2>&1 && { [ "$TOTAL_WARN" -gt 0 ] || [ "$TOTAL_CRIT" -gt 0 ]; }; then
    SUBJECT="[AUDIT] ${TOOLKIT_HOSTNAME} - ${TOTAL_CRIT} critical, ${TOTAL_WARN} warning script(s)"
    mail -s "$SUBJECT" "$MAILTO" < "$REPORT_FILE"
fi

# Optional: post a short summary to a Slack/Teams webhook if AUDIT_WEBHOOK_URL is set
if [ -n "${AUDIT_WEBHOOK_URL:-}" ] && command -v curl >/dev/null 2>&1; then
    curl -s -X POST -H 'Content-Type: application/json' \
        -d "{\"text\":\"Audit on ${TOOLKIT_HOSTNAME}: ${TOTAL_CRIT} critical, ${TOTAL_WARN} warning script(s). Report: ${REPORT_FILE}\"}" \
        "$AUDIT_WEBHOOK_URL" >/dev/null 2>&1
fi

if [ "$TOTAL_CRIT" -gt 0 ]; then
    exit 2
elif [ "$TOTAL_WARN" -gt 0 ]; then
    exit 1
else
    exit 0
fi
