#!/usr/bin/env bash
#===============================================================================
# 03_file_permission_audit.sh
# Purpose : Audit dangerous file/directory permissions: world-writable files,
#           SUID/SGID binaries, orphaned (no owner) files, and baseline perms
#           on critical config files. Also checks SELinux context if enabled.
# Usage   : ./03_file_permission_audit.sh [scan_path]
#           Default scan_path=/  (excludes /proc /sys /run /dev to avoid noise)
# Notes   : Read-only. The full-filesystem find can take a few minutes on
#           large volumes — schedule off-peak or scope scan_path narrower.
#===============================================================================
source "$(dirname "$0")/lib_common.sh"

SCAN_PATH="${1:-/}"
EXCLUDES=(-path /proc -o -path /sys -o -path /run -o -path /dev)

hdr "World-writable files (excluding known safe /tmp, /var/tmp)"
find "$SCAN_PATH" \( "${EXCLUDES[@]}" \) -prune -o \
    -type f -perm -0002 ! -path "/tmp/*" ! -path "/var/tmp/*" -print 2>/dev/null \
    | tee -a "$OUTFILE" | while read -r f; do warn "World-writable file: $f"; done

hdr "World-writable directories without sticky bit (excluding /tmp, /var/tmp)"
find "$SCAN_PATH" \( "${EXCLUDES[@]}" \) -prune -o \
    -type d -perm -0002 ! -perm -1000 ! -path "/tmp*" ! -path "/var/tmp*" -print 2>/dev/null \
    | tee -a "$OUTFILE" | while read -r d; do crit "World-writable dir without sticky bit: $d"; done

hdr "SUID binaries"
find "$SCAN_PATH" \( "${EXCLUDES[@]}" \) -prune -o -type f -perm -4000 -print 2>/dev/null | tee -a "$OUTFILE"

hdr "SGID binaries"
find "$SCAN_PATH" \( "${EXCLUDES[@]}" \) -prune -o -type f -perm -2000 -print 2>/dev/null | tee -a "$OUTFILE"

hdr "Files/dirs with no valid owner or group (orphaned — often left by removed accounts)"
find "$SCAN_PATH" \( "${EXCLUDES[@]}" \) -prune -o \( -nouser -o -nogroup \) -print 2>/dev/null \
    | tee -a "$OUTFILE" | while read -r f; do warn "Orphaned ownership: $f"; done

hdr "Baseline permission check on critical files"
declare -A BASELINE=(
    ["/etc/passwd"]="644"
    ["/etc/shadow"]="000|400|600"
    ["/etc/gshadow"]="000|400|600"
    ["/etc/ssh/sshd_config"]="600|644"
    ["/etc/sudoers"]="440|400"
)
for f in "${!BASELINE[@]}"; do
    [ -e "$f" ] || continue
    PERM=$(stat -c '%a' "$f" 2>/dev/null)
    EXPECTED="${BASELINE[$f]}"
    if [[ "$PERM" =~ ^($EXPECTED)$ ]]; then
        log "OK: $f is $PERM (expected: $EXPECTED)"
    else
        crit "Permission drift: $f is $PERM, expected one of: $EXPECTED"
    fi
done

hdr "SELinux status and enforcement"
if command -v sestatus >/dev/null 2>&1; then
    sestatus | tee -a "$OUTFILE"
    if sestatus | grep -q "Current mode:.*permissive\|disabled"; then
        warn "SELinux is not enforcing — confirm this is intentional for this host."
    fi
else
    log "SELinux tools not found (sestatus) — assuming non-RHEL family or not installed."
fi

hdr "Web root SELinux context sample (if /var/www or /usr/share/nginx exists)"
for webroot in /var/www /usr/share/nginx/html /opt/tomcat/webapps; do
    if [ -d "$webroot" ]; then
        ls -ldZ "$webroot" 2>/dev/null | tee -a "$OUTFILE"
    fi
done

summary_exit
