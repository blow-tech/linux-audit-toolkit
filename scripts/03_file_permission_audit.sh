#!/usr/bin/env bash
source "$(dirname "$0")/lib_common.sh"
SCAN_PATH=${1:-${AUDIT_SCAN_ROOT:-}}
if [[ -n $SCAN_PATH ]]; then
    [[ $SCAN_PATH == /* && -d $SCAN_PATH ]] || { unknown 'Invalid absolute scan root'; summary_exit; }
    # One bounded metadata walk, NUL-separated paths; no /proc, /sys, /run or /dev.
    if collect find "$SCAN_PATH" -xdev \( -path /proc -o -path /sys -o -path /run -o -path /dev \) -prune -o \( -type f -o -type d \) -printf '%m\0%y\0%p\0' > "$RUN_DIR/files"; then
        while IFS= read -r -d '' mode && IFS= read -r -d '' type && IFS= read -r -d '' path; do
            if (( (8#$mode & 0002) != 0 )); then
                if [[ $type == d ]] && (( (8#$mode & 01000) == 0 )); then crit "World writable nonsticky directory: $path";
                elif [[ $type == f ]]; then warn "World writable file: $path"; fi
            fi
            (( (8#$mode & 06000) != 0 )) && log "SUID/SGID: $mode $path"
        done < "$RUN_DIR/files"
    fi
else
    unknown 'Permission scan not requested; supply AUDIT_SCAN_ROOT or an explicit absolute path.'
fi
hdr 'Baseline permissions'
for f in /etc/passwd /etc/shadow /etc/gshadow /etc/ssh/sshd_config /etc/sudoers; do
    [[ -e $f ]] || { unknown "Missing baseline file: $f"; continue; }
    if mode=$(collect stat -c %a -- "$f"); then
        case $f in
            /etc/passwd|/etc/ssh/sshd_config) (( (8#$mode & 0022) == 0 )) || crit "Writable baseline file: $f ($mode)";;
            *) (( (8#$mode & 0137) == 0 )) || crit "Exposed baseline file: $f ($mode)";;
        esac
    fi
done
log 'Orphan ownership, ACL and SELinux policy assessment require separate scoped review.'
summary_exit
