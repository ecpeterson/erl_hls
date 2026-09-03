#!/usr/bin/env bash

# Prints the XLS codegen configuration for the phi scheduler shards.
phi_scheduler_ram_configurations() {
    local configurations=()
    local index
    local scheduler_count=${1:-6}

    for ((index = 0; index < scheduler_count; index++)); do
        configurations+=(
            "scheduler_${index}_state:1RW:_scheduler_${index}_ram_req_out:_scheduler_${index}_ram_resp_in:_scheduler_${index}_ram_wr_comp_in"
            "scheduler_${index}_mailbox:1RW:_scheduler_${index}_mailbox_req_out:_scheduler_${index}_mailbox_resp_in:_scheduler_${index}_mailbox_wr_comp_in"
        )
    done

    local IFS=,
    printf '%s\n' "${configurations[*]}"
}
