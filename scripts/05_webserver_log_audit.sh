#!/usr/bin/env bash
#===============================================================================
# 05_webserver_log_audit.sh
# Purpose : Parse httpd/nginx/tomcat access+error logs (incl. rotated .gz) for
#           status-code distribution, top offending IPs, top URLs, and recent
#           errors/exceptions.
# Usage   : ./05_webserver_log_audit.sh [hours_back]
#           Default hours_back=24
# Notes   : Read-only. Uses zgrep/zcat so rotated .gz logs are included.
#===============================================================================
source "$(dirname "$0")/lib_common.sh"

HOURS_BACK="${1:-24}"

find_recent() {
    # $1 = glob pattern (quoted), prints files modified within HOURS_BACK
    find $1 -type f -mmin -"$((HOURS_BACK*60))" 2>/dev/null
}

zgrep_all() {
    # Runs grep/zgrep transparently over a mix of plain and .gz files
    local pattern="$1"; shift
    for f in "$@"; do
        case "$f" in
            *.gz) zgrep -h -- "$pattern" "$f" 2>/dev/null ;;
            *)    grep  -h -- "$pattern" "$f" 2>/dev/null ;;
        esac
    done
}

cat_all() {
    for f in "$@"; do
        case "$f" in
            *.gz) zcat "$f" 2>/dev/null ;;
            *)    cat  "$f" 2>/dev/null ;;
        esac
    done
}

# ---- Apache/httpd ----
if systemctl is-active httpd >/dev/null 2>&1 || [ -d /var/log/httpd ]; then
    hdr "Apache/httpd — access log (last ${HOURS_BACK}h)"
    ACCESS_FILES=$(find_recent "/var/log/httpd/access_log*")
    if [ -n "$ACCESS_FILES" ]; then
        log "HTTP status code distribution:"
        cat_all $ACCESS_FILES | awk '{print $9}' | grep -E '^[0-9]{3}$' | sort | uniq -c | sort -rn | tee -a "$OUTFILE"

        log "Top 10 source IPs:"
        cat_all $ACCESS_FILES | awk '{print $1}' | sort | uniq -c | sort -rn | head -10 | tee -a "$OUTFILE"

        log "Top 10 requested URLs:"
        cat_all $ACCESS_FILES | awk -F'"' '{print $2}' | awk '{print $2}' | sort | uniq -c | sort -rn | head -10 | tee -a "$OUTFILE"

        FIVEXX=$(cat_all $ACCESS_FILES | awk '{print $9}' | grep -c '^5[0-9][0-9]$')
        [ "${FIVEXX:-0}" -gt 0 ] && warn "httpd: ${FIVEXX} x 5xx responses in last ${HOURS_BACK}h"
    else
        log "No httpd access logs modified in last ${HOURS_BACK}h."
    fi

    hdr "Apache/httpd — error log (last ${HOURS_BACK}h)"
    ERROR_FILES=$(find_recent "/var/log/httpd/error_log*")
    if [ -n "$ERROR_FILES" ]; then
        cat_all $ERROR_FILES | tail -50 | tee -a "$OUTFILE"
        ERRCOUNT=$(cat_all $ERROR_FILES | grep -ci '\[error\]\|\[crit\]')
        [ "${ERRCOUNT:-0}" -gt 0 ] && warn "httpd: ${ERRCOUNT} error/crit entries in last ${HOURS_BACK}h"
    fi
fi

# ---- nginx ----
if systemctl is-active nginx >/dev/null 2>&1 || [ -d /var/log/nginx ]; then
    hdr "nginx — access log (last ${HOURS_BACK}h)"
    ACCESS_FILES=$(find_recent "/var/log/nginx/access.log*")
    if [ -n "$ACCESS_FILES" ]; then
        log "HTTP status code distribution:"
        cat_all $ACCESS_FILES | awk '{print $9}' | grep -E '^[0-9]{3}$' | sort | uniq -c | sort -rn | tee -a "$OUTFILE"

        log "Top 10 source IPs:"
        cat_all $ACCESS_FILES | awk '{print $1}' | sort | uniq -c | sort -rn | head -10 | tee -a "$OUTFILE"

        log "Top 10 requested URLs:"
        cat_all $ACCESS_FILES | awk -F'"' '{print $2}' | awk '{print $2}' | sort | uniq -c | sort -rn | head -10 | tee -a "$OUTFILE"

        FIVEXX=$(cat_all $ACCESS_FILES | awk '{print $9}' | grep -c '^5[0-9][0-9]$')
        [ "${FIVEXX:-0}" -gt 0 ] && warn "nginx: ${FIVEXX} x 5xx responses in last ${HOURS_BACK}h"
    else
        log "No nginx access logs modified in last ${HOURS_BACK}h."
    fi

    hdr "nginx — error log (last ${HOURS_BACK}h)"
    ERROR_FILES=$(find_recent "/var/log/nginx/error.log*")
    if [ -n "$ERROR_FILES" ]; then
        cat_all $ERROR_FILES | tail -50 | tee -a "$OUTFILE"
        ERRCOUNT=$(cat_all $ERROR_FILES | grep -ci '\[error\]\|\[crit\]')
        [ "${ERRCOUNT:-0}" -gt 0 ] && warn "nginx: ${ERRCOUNT} error/crit entries in last ${HOURS_BACK}h"
    fi
fi

# ---- Tomcat ----
TOMCAT_LOG_DIRS=(/opt/tomcat/logs /usr/share/tomcat/logs /var/log/tomcat)
for TDIR in "${TOMCAT_LOG_DIRS[@]}"; do
    [ -d "$TDIR" ] || continue
    hdr "Tomcat — catalina.out (last ${HOURS_BACK}h) [$TDIR]"
    CATALINA_FILES=$(find_recent "$TDIR/catalina.out*")
    if [ -n "$CATALINA_FILES" ]; then
        SEVERE=$(cat_all $CATALINA_FILES | grep -c 'SEVERE\|Exception')
        cat_all $CATALINA_FILES | grep -i 'SEVERE\|Exception' | tail -50 | tee -a "$OUTFILE"
        [ "${SEVERE:-0}" -gt 0 ] && warn "Tomcat: ${SEVERE} SEVERE/Exception entries in last ${HOURS_BACK}h [$TDIR]"
    else
        log "No catalina.out modified in last ${HOURS_BACK}h in $TDIR."
    fi
done

if ! systemctl is-active httpd >/dev/null 2>&1 && ! systemctl is-active nginx >/dev/null 2>&1 \
   && [ ! -d /opt/tomcat/logs ] && [ ! -d /usr/share/tomcat/logs ] && [ ! -d /var/log/tomcat ]; then
    log "No httpd, nginx, or tomcat detected as active/installed on this host."
fi

summary_exit
