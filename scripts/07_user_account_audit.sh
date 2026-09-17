#!/usr/bin/env bash
#===============================================================================
# 07_user_account_audit.sh
# Purpose : Audit local user accounts, password aging, empty/locked passwords,
#           duplicate UIDs, and sudo/wheel group membership.
# Usage   : ./07_user_account_audit.sh
# Notes   : Read-only. Full accuracy (shadow file, chage) requires root.
#===============================================================================
source "$(dirname "$0")/lib_common.sh"
need_root

hdr "Interactive local users (UID >= 1000, valid shell)"
awk -F: '($3>=1000 && $7 !~ /nologin|false/) {print $1" (uid="$3", shell="$7")"}' /etc/passwd | tee -a "$OUTFILE"

hdr "Accounts with UID 0 (should only be root)"
ROOT_UID0=$(awk -F: '($3==0) {print $1}' /etc/passwd)
echo "$ROOT_UID0" | tee -a "$OUTFILE"
COUNT_UID0=$(echo "$ROOT_UID0" | grep -vc '^root$')
[ "$COUNT_UID0" -gt 0 ] && crit "Non-root account(s) with UID 0 found — investigate immediately"

hdr "Duplicate UIDs"
DUPES=$(awk -F: '{print $3}' /etc/passwd | sort | uniq -d)
if [ -n "$DUPES" ]; then
    warn "Duplicate UID(s) found: $DUPES"
    echo "$DUPES" | while read -r u; do awk -F: -v uid="$u" '$3==uid {print}' /etc/passwd; done | tee -a "$OUTFILE"
else
    log "No duplicate UIDs."
fi

if [ -r /etc/shadow ]; then
    hdr "Accounts with empty password field"
    EMPTY_PW=$(awk -F: '($2=="") {print $1}' /etc/shadow)
    if [ -n "$EMPTY_PW" ]; then
        crit "Account(s) with EMPTY password: $EMPTY_PW"
    else
        log "No accounts with empty password."
    fi

    hdr "Password aging (interactive users)"
    for u in $(awk -F: '($3>=1000 && $7 !~ /nologin|false/) {print $1}' /etc/passwd); do
        chage -l "$u" 2>/dev/null | sed "s/^/[$u] /" | tee -a "$OUTFILE"
    done
else
    warn "/etc/shadow not readable — run as root for password aging/empty-password checks."
fi

hdr "Locked accounts (passwd -S, if available)"
if command -v passwd >/dev/null 2>&1; then
    for u in $(awk -F: '($3>=1000 && $7 !~ /nologin|false/) {print $1}' /etc/passwd); do
        passwd -S "$u" 2>/dev/null | tee -a "$OUTFILE"
    done
fi

hdr "Members of wheel/sudo group (admin privileges)"
getent group wheel 2>/dev/null | tee -a "$OUTFILE"
getent group sudo 2>/dev/null | tee -a "$OUTFILE"

hdr "/etc/sudoers.d/ custom entries"
if [ -d /etc/sudoers.d ]; then
    ls -l /etc/sudoers.d/ | tee -a "$OUTFILE"
    for f in /etc/sudoers.d/*; do
        [ -f "$f" ] || continue
        grep -vE '^\s*#|^\s*$' "$f" | sed "s|^|[$f] |" | tee -a "$OUTFILE"
    done
fi

summary_exit
