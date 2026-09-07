#!/usr/bin/env bash

# Prints the XLS codegen configuration for one phi scheduler plan.
#
# Reduction schedulers are an explicit contiguous range.  The decoder-only
# and full noise topologies have different scheduler counts. In addition,
# partitioned full topologies place their non-reducing syndrome schedulers
# before the phi shards, so the reduction range cannot be inferred from the
# total count.
phi_scheduler_ram_configurations() {
    if (($# != 3)); then
        echo "usage: phi_scheduler_ram_configurations SCHEDULER_COUNT REDUCTION_FIRST REDUCTION_COUNT" >&2
        return 2
    fi

    local configurations=()
    local index
    local scheduler_count=$1
    local reduction_first=$2
    local reduction_count=$3
    local reduction_limit

    if [[ ! "$scheduler_count" =~ ^[1-9][0-9]*$ ]] ||
            [[ ! "$reduction_first" =~ ^[0-9]+$ ]] ||
            [[ ! "$reduction_count" =~ ^[0-9]+$ ]]; then
        echo "scheduler count must be positive and reduction range nonnegative" >&2
        return 2
    fi
    reduction_limit=$((reduction_first + reduction_count))
    if ((reduction_limit > scheduler_count)); then
        echo "reduction scheduler range exceeds scheduler count" >&2
        return 2
    fi

    for ((index = 0; index < scheduler_count; index++)); do
        configurations+=(
            "scheduler_${index}_state:1R1W:_scheduler_${index}_ram_read_req_out:_scheduler_${index}_ram_read_resp_in:_scheduler_${index}_ram_write_req_out:_scheduler_${index}_ram_write_resp_in"
            "scheduler_${index}_mailbox:1R1W:_scheduler_${index}_mailbox_read_req_out:_scheduler_${index}_mailbox_read_resp_in:_scheduler_${index}_mailbox_write_req_out:_scheduler_${index}_mailbox_write_resp_in"
        )
        if ((index >= reduction_first && index < reduction_limit)); then
            configurations+=(
                "scheduler_${index}_reduction:1R1W:_scheduler_${index}_reduction_read_req_out:_scheduler_${index}_reduction_read_resp_in:_scheduler_${index}_reduction_write_req_out:_scheduler_${index}_reduction_write_resp_in"
            )
        fi
    done

    local IFS=,
    printf '%s\n' "${configurations[*]}"
}
