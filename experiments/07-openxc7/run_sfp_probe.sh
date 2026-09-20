#!/usr/bin/env bash
# Build a standalone carrier-status bitstream using the exact checked package.
set -euo pipefail
experiment_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$experiment_root/openxc7_common.sh"
prepare_zynq7030
python3 "$experiment_root/test_sfp_probe.py" --yosys "$oss_cad_suite/bin/yosys"
sfp_build="$build_root/sfp-probe"
mkdir -p "$sfp_build"
netlist="$sfp_build/netlist.json"
script="read_verilog \"$experiment_root/zynq_ps_probe.v\" \"$experiment_root/zynq_ps_probe_top.v\""
script+=" \"$experiment_root/sfp/rgpio_reader.v\" \"$experiment_root/sfp/te0715_sfp_top.v\";"
script+=" synth_xilinx -flatten -abc9 -arch xc7 -top te0715_sfp_top; check -assert; scc -expect 0;"
script+=" select -assert-count 1 t:PS7; select -assert-count 1 t:BUFG; select -clear;"
script+=" write_json \"$netlist\"; tee -o \"$sfp_build/stat.json\" stat -json;"
"$oss_cad_suite/bin/yosys" -Q -q -l "$sfp_build/yosys.log" -p "$script"
build_bitstream sfp-probe "$netlist" xc7z030sbg485-1 \
    "$experiment_root/sfp/te0715_sfp.xdc" strict 25
verify_bitstream xc7z030sbg485-1 "$sfp_build/xc7z030sbg485-1"
python3 "$experiment_root/sfp/record.py" "$sfp_build" "$apio_home"
