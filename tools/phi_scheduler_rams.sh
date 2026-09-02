#!/usr/bin/env bash

# Prints the XLS codegen configuration for the three homogeneous phi schedulers.
phi_scheduler_ram_configurations() {
    local configurations=()
    local index

    for index in 0 1 2; do
        configurations+=(
            "scheduler_${index}_state:1RW:_scheduler_${index}_ram_req_out:_scheduler_${index}_ram_resp_in:_scheduler_${index}_ram_wr_comp_in"
            "scheduler_${index}_mailbox:1RW:_scheduler_${index}_mailbox_req_out:_scheduler_${index}_mailbox_resp_in:_scheduler_${index}_mailbox_wr_comp_in"
        )
    done

    local IFS=,
    printf '%s\n' "${configurations[*]}"
}
