#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${1:-"$project_root/_build/phi_relax_bank"}
bundled_tools="$project_root/experiments/07-openxc7/.apio/packages/oss-cad-suite/bin"
iverilog=${ERL_HLS_IVERILOG:-"$bundled_tools/iverilog"}
vvp=${ERL_HLS_VVP:-"$bundled_tools/vvp"}

mkdir -p "$stage"
"$iverilog" -g2012 -Wall -s phi_relax_bank_tb \
    -o "$stage/phi_relax_bank_tb.vvp" \
    "$project_root/test/rtl/phi_relax_bank_tb.sv" \
    "$project_root/src/examples/phi_decoder/rtl/phi_relax_bank.sv"
"$vvp" "$stage/phi_relax_bank_tb.vvp"
