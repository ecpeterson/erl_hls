#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
generated=${1:?usage: synth_phi_area_matrix.sh GENERATED_D2_VERILOG [STAGE]}
stage=${2:-"$project_root/_build/phi_area_matrix"}
bundled_yosys="$project_root/experiments/07-openxc7/.apio/packages/oss-cad-suite/bin/yosys"
yosys=${ERL_HLS_YOSYS:-$bundled_yosys}
raw="$project_root/src/examples/phi_decoder/rtl/phi_memory_raw_d3.sv"
results="$stage/results.tsv"

mkdir -p "$stage"

first_module() {
    local pattern=$1
    sed -n "s/^module \($pattern[^ (]*\)(.*/\1/p" "$generated" | head -1
}

# XLS emits a small nested proc module with a numeric suffix before the public
# wrapper. The wrapper is last and is the design top used by prior mappings.
top=$(sed -n 's/^module \(__phi_noise.*__Top_0_next[^ (]*\)(.*/\1/p' \
    "$generated" | tail -1)
data_service=$(first_module '__phenom_data_cell.*__Service_0_next')
syndrome_service=$(first_module '__phenom_syndrome_cell.*__Service_0_next')
phi_service=$(first_module '__phi_halo_cell.*__Service_0_next')

for value in "$top" "$data_service" "$syndrome_service" "$phi_service"; do
    if [[ -z "$value" ]]; then
        echo "could not discover expected modules in $generated" >&2
        exit 1
    fi
done

printf 'case\tgeometry\tinstances\testimated_lcs\tflip_flops\tluts\tram32m\tdsp48e1\n' \
    > "$results"

cell_count() {
    local log=$1
    local cell=$2
    awk -v cell="$cell" '$2 == cell { value = $1 } END { print value + 0 }' \
        "$log"
}

record_result() {
    local name=$1
    local geometry=$2
    local instances=$3
    local log=$4
    local lcs fdre fdse luts ram32m dsp
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
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$name" "$geometry" "$instances" "$lcs" "$((fdre + fdse))" \
        "$luts" "$ram32m" "$dsp" >> "$results"
}

map_generated() {
    local name=$1
    local selected_top=$2
    local prelude=$3
    local geometry=$4
    local instances=$5
    local log="$stage/$name-yosys.log"
    "$yosys" -Q -q -l "$log" -p \
        "read_verilog -sv $generated; \
         $prelude \
         hierarchy -check -top $selected_top; \
         synth_xilinx -flatten -abc9 -arch xc7 -noiopad \
             -top $selected_top; \
         stat -tech xilinx" 2>/dev/null
    record_result "$name" "$geometry" "$instances" "$log"
}

cases=${ERL_HLS_AREA_CASES:-services,transport,raw}
if [[ ",$cases," == *,services,* ]]; then
    map_generated data_service "$data_service" '' d2 8
    map_generated syndrome_service "$syndrome_service" '' d2 8
    map_generated phi_service "$phi_service" '' d2 8
    awk -F '\t' '
        NR > 1 && $1 ~ /_service$/ {
            lcs += $3 * $4
            ffs += $3 * $5
            luts += $3 * $6
            ram += $3 * $7
            dsp += $3 * $8
        }
        END {
            printf "replicated_services\td2\t24\t%d\t%d\t%d\t%d\t%d\n",
                lcs, ffs, luts, ram, dsp
        }
    ' "$results" >> "$results"
fi
if [[ ",$cases," == *,transport,* ]]; then
    # Preserve all actor ports but remove their implementations. Black-box
    # boundaries keep the cyclic queues and route controls live without making
    # assumptions about a stub actor's output behavior.
    map_generated transport_only "$top" \
        'blackbox *Service_0_next; select -clear;' d2 1
fi
if [[ ",$cases," == *,full,* ]]; then
    map_generated generated_full "$top" '' d2 1
fi
if [[ ",$cases," == *,raw,* ]]; then
    log="$stage/raw_d3-yosys.log"
    "$yosys" -Q -q -l "$log" -p \
        "read_verilog -sv $raw; \
         hierarchy -check -top phi_memory_raw_d3; \
         synth_xilinx -flatten -abc9 -arch xc7 -noiopad \
             -top phi_memory_raw_d3; \
         check -assert; \
         stat -tech xilinx" 2>/dev/null
    record_result raw_sequential d3 1 "$log"
fi

if command -v column >/dev/null 2>&1; then
    column -t -s $'\t' "$results"
else
    cat "$results"
fi
