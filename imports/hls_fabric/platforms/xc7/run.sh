#!/usr/bin/env bash
set -euo pipefail

experiment_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=openxc7_common.sh
source "$experiment_root/openxc7_common.sh"

prepare_openxc7
make_chipdb xc7z010clg225-1
make_chipdb xc7z020clg484-2

smoke_build="$build_root/smoke"
design="$experiment_root/smoke.v"
netlist="$smoke_build/smoke.json"
mkdir -p "$smoke_build"
rm -f "$netlist" "$smoke_build/yosys.log"

echo "Synthesizing openXC7 smoke design"
yosys_script="read_verilog \"$design\";"
yosys_script+=" synth_xilinx -flatten -abc9 -arch xc7 -top openxc7_smoke;"
yosys_script+=" check -assert;"
yosys_script+=" write_json \"$netlist\""
"$oss_cad_suite/bin/yosys" \
    -q \
    -l "$smoke_build/yosys.log" \
    -p "$yosys_script"

build_bitstream \
    smoke \
    "$netlist" \
    xc7z010clg225-1 \
    "$experiment_root/xc7z010clg225.xdc"
build_bitstream \
    smoke \
    "$netlist" \
    xc7z020clg484-2 \
    "$experiment_root/xc7z020clg484.xdc"
