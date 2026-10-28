#!/usr/bin/env bash
set -euo pipefail

experiment_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=openxc7_common.sh
source "$experiment_root/openxc7_common.sh"
prepare_zynq7030
python3 "$experiment_root/test_zynq_ps_probe.py" --yosys "$oss_cad_suite/bin/yosys"
probe_build="$build_root/zynq-ps-probe"
mkdir -p "$probe_build"
netlist="$probe_build/netlist.json"
script="read_verilog \"$experiment_root/zynq_ps_probe.v\" \"$experiment_root/zynq_ps_probe_top.v\";"
script+=" synth_xilinx -flatten -abc9 -arch xc7 -top zynq_ps_probe_top; check -assert;"
script+=" select -assert-count 1 t:PS7; select -assert-count 1 t:BUFG; select -clear;"
script+=" write_json \"$netlist\"; write_verilog -noattr \"$probe_build/mapped.v\";"
"$oss_cad_suite/bin/yosys" -Q -q -l "$probe_build/yosys.log" -p "$script"
build_bitstream zynq-ps-probe "$netlist" xc7z030sbg485-1 \
    "$experiment_root/zynq_ps_probe.xdc"
verify_bitstream xc7z030sbg485-1 "$probe_build/xc7z030sbg485-1"
