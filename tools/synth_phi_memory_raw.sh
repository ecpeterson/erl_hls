#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${1:-"$project_root/_build/phi_memory_raw_synth"}
bundled_yosys="$project_root/experiments/07-openxc7/.apio/packages/oss-cad-suite/bin/yosys"

if [[ -n "${ERL_HLS_YOSYS:-}" ]]; then
    yosys=$ERL_HLS_YOSYS
elif [[ -x "$bundled_yosys" ]]; then
    yosys=$bundled_yosys
else
    yosys=yosys
fi

mkdir -p "$stage"
rtl_dir="$project_root/src/examples/phi_decoder/rtl"
log_file="$stage/phi_memory_raw_d3-yosys.log"

(
    cd "$rtl_dir"
    "$yosys" -Q -q -l "$log_file" -p \
        "read_verilog -sv phi_memory_raw_d3.sv; \
         hierarchy -check -top phi_memory_raw_d3; \
         synth_xilinx -flatten -abc9 -arch xc7 -noiopad \
             -top phi_memory_raw_d3; \
         check -assert; \
         stat -tech xilinx"
)

awk '
    /=== phi_memory_raw_d3 ===/ {
        block = $0 ORS
        capture = 1
        next
    }
    capture {
        block = block $0 ORS
    }
    capture && /Estimated number of LCs:/ {
        last = block
        capture = 0
    }
    END {
        printf "%s", last
    }
' "$log_file"
