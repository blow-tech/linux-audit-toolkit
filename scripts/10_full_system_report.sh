#!/usr/bin/env bash
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/lib_common.sh"
SCRIPTS=(01_disk_space_audit.sh 02_login_logout_audit.sh 03_file_permission_audit.sh 04_service_status_audit.sh 05_webserver_log_audit.sh 06_cpu_ram_audit.sh 07_user_account_audit.sh 08_cron_audit.sh 09_network_port_audit.sh)
[[ ${AUDIT_CHILD_TIMEOUT:-300} =~ ^[1-9][0-9]{0,3}$ ]] || { unknown 'Invalid child timeout'; summary_exit; }
completed=0
for s in "${SCRIPTS[@]}"; do
    hdr "$s"
    if [[ ! -f $SCRIPT_DIR/$s || -L $SCRIPT_DIR/$s ]]; then unknown "Missing or linked child: $s"; continue; fi
    rc=0
    child_args=()
    if [[ $s == 04_* ]]; then read -r -a child_args <<< "${AUDIT_SERVICE_UNITS:-}"; fi
    if [[ $s == 05_* && -n ${AUDIT_WEB_LOGS:-} ]]; then mapfile -t child_args <<< "$AUDIT_WEB_LOGS"; fi
    timeout -k 5 "${AUDIT_CHILD_TIMEOUT:-300}" bash "$SCRIPT_DIR/$s" "${child_args[@]}" >> "$OUTFILE" 2>&1 || rc=$?
    case $rc in
        0) completed=$((completed+1));;
        1) completed=$((completed+1)); warn "$s reported warnings";;
        2) completed=$((completed+1)); crit "$s reported critical findings";;
        *) unknown "$s incomplete (exit $rc)";;
    esac
done
log "Expected: ${#SCRIPTS[@]}; completed: $completed"
((completed == ${#SCRIPTS[@]})) || unknown 'Not all child checks completed.'
# Report delivery belongs to a separately configured monitoring integration.
summary_exit
