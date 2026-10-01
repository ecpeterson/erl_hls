#!/usr/bin/env bash

# Prints the XLS codegen configuration for the phi scheduler shards.
phi_scheduler_ram_configurations() {
    local configurations=()
    local index
    local scheduler_count=${1:-${ERL_HLS_PHI_SCHEDULER_COUNT:-6}}

    for ((index = 0; index < scheduler_count; index++)); do
        configurations+=(
            "scheduler_${index}_state:1R1W:_scheduler_${index}_ram_read_req_out:_scheduler_${index}_ram_read_resp_in:_scheduler_${index}_ram_write_req_out:_scheduler_${index}_ram_write_resp_in"
            "scheduler_${index}_mailbox:1R1W:_scheduler_${index}_mailbox_read_req_out:_scheduler_${index}_mailbox_read_resp_in:_scheduler_${index}_mailbox_write_req_out:_scheduler_${index}_mailbox_write_resp_in"
        )
    done

    local IFS=,
    printf '%s\n' "${configurations[*]}"
}
