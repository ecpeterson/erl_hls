#!/usr/bin/env bash
# Build the GP0/PL330 packet-loopback bitstream for the checked TE0715 module.
set -euo pipefail
experiment_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=openxc7_common.sh
source "$experiment_root/openxc7_common.sh"
prepare_zynq7030
python3 "$experiment_root/test_zynq_dma.py" --yosys "$oss_cad_suite/bin/yosys"
dma_build="$build_root/zynq-dma"
mkdir -p "$dma_build"
netlist="$dma_build/netlist.json"
script="read_verilog \"$experiment_root/zynq_ps_probe.v\" \"$experiment_root/dma/zynq_dma_mailbox.v\" \"$experiment_root/dma/zynq_dma_top.v\";"
script+=" synth_xilinx -flatten -abc9 -arch xc7 -top zynq_dma_top; check -assert;"
script+=" select -assert-count 1 t:PS7; select -assert-count 1 t:BUFG;"
script+=" select -assert-count 2 t:RAMB18E1; select -clear;"
script+=" write_json \"$netlist\"; write_verilog -noattr \"$dma_build/mapped.v\";"
"$oss_cad_suite/bin/yosys" -Q -q -l "$dma_build/yosys.log" -p "$script"
build_bitstream zynq-dma "$netlist" xc7z030sbg485-1 "$experiment_root/zynq_ps_probe.xdc"
verify_bitstream xc7z030sbg485-1 "$dma_build/xc7z030sbg485-1"
