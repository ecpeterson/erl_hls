#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${1:-"$project_root/_build/phi_relax_sweep"}
bundled_yosys="$project_root/experiments/07-openxc7/.apio/packages/oss-cad-suite/bin/yosys"
yosys=${ERL_HLS_YOSYS:-$bundled_yosys}
rtl="$project_root/src/examples/phi_decoder/rtl/phi_relax_bank.sv"
results="$stage/results.tsv"

mkdir -p "$stage"
printf 'lanes\testimated_lcs\tflip_flops\tluts\tram32m\tdsp48e1\tdiffusion_cycles\n' \
    > "$results"

cell_count() {
    local log=$1
    local cell=$2
    awk -v cell="$cell" '$2 == cell { value = $1 } END { print value + 0 }' \
        "$log"
}

for lanes in 1 2 4 9 18; do
    top="phi_relax_bank_$lanes"
    log="$stage/$top-yosys.log"
    "$yosys" -Q -q -l "$log" -p \
        "read_verilog -sv $rtl; \
         hierarchy -check -top $top; \
         synth_xilinx -flatten -abc9 -arch xc7 -noiopad -top $top; \
         check -assert; \
         stat -tech xilinx" 2>/dev/null
    lcs=$(awk '/Estimated number of LCs:/ { value = $5 } END { print value }' \
        "$log")
    fdre=$(cell_count "$log" FDRE)
    fdse=$(cell_count "$log" FDSE)
    luts=0
    for lut in LUT1 LUT2 LUT3 LUT4 LUT5 LUT6; do
        luts=$((luts + $(cell_count "$log" "$lut")))
    done
    ram32m=$(cell_count "$log" RAM32M)
    dsp=$(cell_count "$log" DSP48E1)
    # Two Jacobi rounds each cover all 18 cells. A bank accepts one batch in
    # one cycle and spends 76 more cycles on its two restoring divisions.
    batches=$(((18 + lanes - 1) / lanes))
    diffusion_cycles=$((2 * batches * 77))
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$lanes" "$lcs" "$((fdre + fdse))" "$luts" "$ram32m" "$dsp" \
        "$diffusion_cycles" >> "$results"
done

if command -v column >/dev/null 2>&1; then
    column -t -s $'\t' "$results"
else
    cat "$results"
fi
