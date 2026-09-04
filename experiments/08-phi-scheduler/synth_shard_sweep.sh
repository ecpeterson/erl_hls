#!/usr/bin/env bash
set -euo pipefail

experiment_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
project_root=$(cd "$experiment_root/../.." && pwd)
stage=${1:-"$project_root/_build/phi_shard_sweep"}
bundled_yosys="$project_root/experiments/07-openxc7/.apio/packages/oss-cad-suite/bin/yosys"
yosys=${ERL_HLS_YOSYS:-$bundled_yosys}
results="$stage/results.tsv"

mkdir -p "$stage"
printf 'phi_shards\tschedulers\testimated_lcs\tflip_flops\tluts\tdsp48e1\n' \
    > "$results"

cell_count() {
    local log=$1
    local cell=$2
    awk -v cell="$cell" '$2 == cell { value = $1 } END { print value + 0 }' \
        "$log"
}

map_variant() {
    local shards=$1
    local generated="$stage/shards_${shards}/phi_memory_gateway.v"
    local log="$stage/shards_${shards}/phi_noise_topology-yosys.log"
    local top lcs ffs luts dsp

    test -s "$generated"
    top=$(sed -n \
        's/^module \(__phi_noise_topology__Top_0_next[^ (]*\)(.*/\1/p' \
        "$generated" | tail -1)
    test -n "$top"
    if [[ ${ERL_HLS_PHI_SHARD_REUSE_MAPS:-0} != 1 ]] ||
       ! grep -q '^End of script' "$log" 2>/dev/null; then
        "$yosys" -Q -q -l "$log" -p \
            "read_verilog -sv $generated; \
             hierarchy -check -top $top; \
             synth_xilinx -flatten -abc9 -arch xc7 -noiopad -top $top; \
             stat -tech xilinx" 2>/dev/null
    fi

    lcs=$(awk '/Estimated number of LCs:/ { value = $5 } END { print value }' \
        "$log")
    ffs=$(($(cell_count "$log" FDRE) + $(cell_count "$log" FDSE)))
    luts=0
    for lut in LUT1 LUT2 LUT3 LUT4 LUT5 LUT6; do
        luts=$((luts + $(cell_count "$log" "$lut")))
    done
    dsp=$(cell_count "$log" DSP48E1)
    printf '%d\t%d\t%s\t%d\t%d\t%d\n' \
        "$shards" "$((4 + 2 * shards))" "$lcs" "$ffs" "$luts" "$dsp" \
        >> "$results"
}

for shards in ${ERL_HLS_PHI_SHARD_SWEEP:-1 2 3}; do
    map_variant "$shards"
done

if command -v column >/dev/null 2>&1; then
    column -t -s $'\t' "$results"
else
    cat "$results"
fi
