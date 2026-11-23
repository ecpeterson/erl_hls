#!/usr/bin/env bash
set -euo pipefail

experiment_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=openxc7_common.sh
source "$experiment_root/openxc7_common.sh"
prepare_zynq7030
python3 "$experiment_root/test_zynq7030.py"

for workload in counter resources; do
    smoke_build="$build_root/zynq7030-$workload"
    mkdir -p "$smoke_build"
    if [[ "$workload" == counter ]]; then
        design="$experiment_root/smoke.v"
        top=openxc7_smoke
    else
        design="$experiment_root/zynq7030_smoke.v"
        top=zynq7030_smoke
    fi
    netlist="$smoke_build/netlist.json"
    script="read_verilog \"$design\"; synth_xilinx -flatten -abc9 -arch xc7 -top $top; check -assert;"
    if [[ "$workload" == resources ]]; then
        script+=" select -assert-count 1 t:DSP48E1; select -assert-count 1 t:RAMB18E1 t:RAMB36E1; select -clear;"
    fi
    script+=" write_json \"$netlist\"; write_verilog -noattr \"$smoke_build/mapped.v\";"
    "$oss_cad_suite/bin/yosys" -Q -q -l "$smoke_build/yosys.log" -p "$script"
    build_bitstream "zynq7030-$workload" "$netlist" xc7z030sbg485-1 \
        "$experiment_root/xc7z030sbg485.xdc"
    output="$smoke_build/xc7z030sbg485-1"
    verify_bitstream xc7z030sbg485-1 "$output"
done
