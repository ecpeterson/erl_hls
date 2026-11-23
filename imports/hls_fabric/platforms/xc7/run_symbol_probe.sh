#!/usr/bin/env bash
# Route the bounded external raw-symbol/comma diagnostic; assembly stays separate.
set -euo pipefail
experiment_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$experiment_root/openxc7_common.sh"
prepare_gtx
python3 "$experiment_root/test_symbol_probe.py" --yosys "$oss_cad_suite/bin/yosys"
symbol_build="$build_root/symbol-probe"
mkdir -p "$symbol_build"
script="read_verilog \"$experiment_root/zynq_ps_probe.v\" \"$experiment_root/zynq_ps_probe_top.v\""
for source in gtx_probe_control gtx_probe_sample te0715_gtx_channel; do
    script+=" \"$experiment_root/gtx/$source.v\""
done
for source in symbol_probe_sample te0715_symbol_top; do
    script+=" \"$experiment_root/ethernet/$source.v\""
done
script+="; synth_xilinx -flatten -abc9 -arch xc7 -top te0715_symbol_top; check -assert;"
script+=" select -assert-count 1 t:GTXE2_CHANNEL; select -assert-count 1 t:IBUFDS_GTE2;"
script+=" select -assert-count 1 t:PS7; select -clear; write_json \"$symbol_build/netlist.json\";"
"$oss_cad_suite/bin/yosys" -Q -q -l "$symbol_build/yosys.log" -p "$script"
rm -f "$symbol_build/probe.fasm" "$symbol_build/report.json" "$symbol_build/result.json"
backend=${ERL_HLS_NEXTPNR:-$openxc7/bin/nextpnr-xilinx}
"$backend" --chipdb "$gtx_build/chipdb.bin" \
    --xdc "$experiment_root/gtx/te0715_gtx.xdc" --json "$symbol_build/netlist.json" \
    --write "$symbol_build/routed.json" --fasm "$symbol_build/probe.fasm" \
    --report "$symbol_build/report.json" --freq 25 --seed 1 --router router2 \
    --log "$symbol_build/nextpnr.log" > "$symbol_build/nextpnr.stdout" 2>&1
cp "$gtx_build/preparation.json" "$symbol_build/preparation.json"
python3 "$experiment_root/ethernet/symbol_report.py" "$prjxray_db/zynq7" "$symbol_build"
