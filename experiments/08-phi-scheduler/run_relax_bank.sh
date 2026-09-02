#!/usr/bin/env bash
set -euo pipefail

experiment_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
project_root=$(cd "$experiment_root/../.." && pwd)
stage=${1:-"$project_root/_build/phi_relax_bank"}
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
"$iverilog" -g2012 -Wall -s phi_relax_bank_tb \
    -o "$stage/phi_relax_bank_tb.vvp" \
    "$experiment_root/phi_relax_bank_tb.sv" \
    "$experiment_root/phi_relax_bank.sv"
"$vvp" "$stage/phi_relax_bank_tb.vvp"
