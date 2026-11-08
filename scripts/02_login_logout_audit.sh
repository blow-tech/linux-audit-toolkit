#!/usr/bin/env bash
source "$(dirname "$0")/lib_common.sh"
DAYS_BACK=${1:-1}; FAIL_THRESHOLD=${2:-5}
[[ $DAYS_BACK =~ ^[1-9][0-9]{0,3}$ && $FAIL_THRESHOLD =~ ^[1-9][0-9]{0,6}$ ]] || { unknown 'Invalid days or threshold'; summary_exit; }
need_root || :
hdr 'Current and historical interactive logins'
collect who -a | tee -a "$OUTFILE"
collect last -F -s "-$DAYS_BACK days" | tee -a "$OUTFILE"
if [[ -r /var/log/btmp ]]; then collect lastb -F -s "-$DAYS_BACK days" | tee -a "$OUTFILE"; else unknown 'btmp unavailable'; fi
hdr 'SSH journal observations (sshd and ssh units)'
if collect journalctl -u sshd -u ssh --since "-$DAYS_BACK days" --no-pager > "$RUN_DIR/ssh"; then
    awk '/Failed password/ {for(i=1;i<NF;i++) if($i=="from") print $(i+1)}' "$RUN_DIR/ssh" | sort | uniq -c > "$RUN_DIR/failures"
    while read -r count ip; do
        [[ -n $ip ]] || continue
        ((count >= FAIL_THRESHOLD)) && crit "Repeated failed SSH attempts: $ip ($count)"
    done < "$RUN_DIR/failures"
    awk '/Accepted .* root/' "$RUN_DIR/ssh" | tee -a "$OUTFILE"
fi
log 'Coverage depends on retained journal/wtmp/btmp data; absence does not prove no historical logins.'
summary_exit
