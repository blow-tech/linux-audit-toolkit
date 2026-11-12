#!/usr/bin/env bash
source "$(dirname "$0")/lib_common.sh"
SERVICES=("$@")
if ((${#SERVICES[@]} == 0)); then unknown 'Supply explicit expected service units; installation guesses cannot establish health.'; summary_exit; fi
if failed=$(collect systemctl --failed --no-legend --plain); then
    while IFS= read -r line; do [[ -n $line ]] && crit "Failed unit: $line"; done <<< "$failed"
fi
for svc in "${SERVICES[@]}"; do
    [[ $svc =~ ^[a-zA-Z0-9_.@:-]+$ ]] && [[ $svc != -* ]] || { unknown "Invalid unit $svc"; continue; }
    if data=$(collect systemctl show "$svc" -p LoadState -p ActiveState -p UnitFileState -p NRestarts); then
        log "$svc: $data"
        load=$(awk -F= '$1=="LoadState"{print $2}' <<< "$data")
        active=$(awk -F= '$1=="ActiveState"{print $2}' <<< "$data")
        [[ $load == loaded && -n $active ]] || { unknown "Expected unit unavailable: $svc"; continue; }
        [[ $active == active ]] || crit "$svc is $active"
        # Static/indirect units may start via dependencies; not automatically unhealthy.
    fi
done
summary_exit
