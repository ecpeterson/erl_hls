#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${1:-"$project_root/_build/phi_memory_raw_rtl"}
bundled_tools="$project_root/experiments/07-openxc7/.apio/packages/oss-cad-suite/bin"

if [[ -n "${ERL_HLS_IVERILOG:-}" ]]; then
    iverilog=$ERL_HLS_IVERILOG
elif [[ -x "$bundled_tools/iverilog" ]]; then
    iverilog=$bundled_tools/iverilog
else
    iverilog=iverilog
fi

if [[ -n "${ERL_HLS_VVP:-}" ]]; then
    vvp=$ERL_HLS_VVP
elif [[ -x "$bundled_tools/vvp" ]]; then
    vvp=$bundled_tools/vvp
else
    vvp=vvp
fi

mkdir -p "$stage"

"$iverilog" \
    -g2012 \
    -Wall \
    -s phi_memory_raw_d3_tb \
    -o "$stage/phi_memory_raw_d3_tb.vvp" \
    "$project_root/test/rtl/phi_memory_raw_d3_tb.sv" \
    "$project_root/src/examples/phi_decoder/rtl/phi_memory_raw_d3.sv"

"$vvp" "$stage/phi_memory_raw_d3_tb.vvp"
