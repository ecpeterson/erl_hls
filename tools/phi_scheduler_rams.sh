#!/usr/bin/env bash

# Prints the XLS codegen configuration for one phi scheduler plan.
#
# Actor state and mailbox contents use one external 1R1W RAM apiece. Small
# reduction receptacles remain in scheduler registers and have no RAM ports.
phi_scheduler_ram_configurations() {
    if (($# != 1)); then
        echo "usage: phi_scheduler_ram_configurations SCHEDULER_COUNT" >&2
        return 2
    fi

    local configurations=()
    local index
    local scheduler_count=$1

    if [[ ! "$scheduler_count" =~ ^[1-9][0-9]*$ ]]; then
        echo "scheduler count must be positive" >&2
        return 2
    fi

    for ((index = 0; index < scheduler_count; index++)); do
        configurations+=(
            "scheduler_${index}_state:1R1W:_scheduler_${index}_ram_read_req_out:_scheduler_${index}_ram_read_resp_in:_scheduler_${index}_ram_write_req_out:_scheduler_${index}_ram_write_resp_in"
            "scheduler_${index}_mailbox:1R1W:_scheduler_${index}_mailbox_read_req_out:_scheduler_${index}_mailbox_read_resp_in:_scheduler_${index}_mailbox_write_req_out:_scheduler_${index}_mailbox_write_resp_in"
        )
    done

    local IFS=,
    printf '%s\n' "${configurations[*]}"
}
