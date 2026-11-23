#!/usr/bin/env bash
# Route the external 1000BASE-X PCS-boundary diagnostic; assembly stays separate.
set -euo pipefail
experiment_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$experiment_root/openxc7_common.sh"
prepare_gtx
probe_build="$build_root/pcs-probe"
"$openxc7/libexec/python3.12" "$experiment_root/ethernet/prepare_pcs_probe.py" "$probe_build"
python3 "$experiment_root/test_pcs_probe.py" --iverilog "$oss_cad_suite/bin/iverilog" \
    --generated-pcs "$probe_build/generated/liteeth_pcs_probe.v"
generated="$probe_build/generated"
script="read_verilog"
for source in zynq_ps_probe.v zynq_ps_probe_top.v \
        gtx/gtx_probe_control.v gtx/te0715_gtx_channel.v \
        ethernet/clock_pair.v ethernet/gtx_clocks.v ethernet/snapshot.v \
        ethernet/pcs_probe_sample.v ethernet/te0715_pcs_probe_top.v; do
    script+=" \"$experiment_root/$source\""
done
script+=" liteeth_pcs_probe.v liteeth_pcs_gearbox.v;"
script+=" synth_xilinx -flatten -abc9 -arch xc7 -top te0715_pcs_probe_top; check -assert;"
script+=" select -assert-count 1 t:GTXE2_CHANNEL; select -assert-count 1 t:IBUFDS_GTE2;"
script+=" select -assert-count 1 t:PS7; select -assert-count 2 t:MMCME2_BASE; select -clear;"
script+=" write_json \"$probe_build/netlist.json\";"
pushd "$generated" >/dev/null
"$oss_cad_suite/bin/yosys" -Q -q -l "$probe_build/yosys.log" -p "$script"
popd >/dev/null
rm -f "$probe_build/probe.fasm" "$probe_build/report.json" "$probe_build/result.json"
backend=${ERL_HLS_NEXTPNR:-$openxc7/bin/nextpnr-xilinx}
"$backend" --chipdb "$gtx_build/chipdb.bin" \
    --xdc "$experiment_root/ethernet/te0715_ethernet.xdc" --json "$probe_build/netlist.json" \
    --write "$probe_build/routed.json" --fasm "$probe_build/probe.fasm" \
    --report "$probe_build/report.json" --freq 25 --seed 2 --router router2 \
    --log "$probe_build/nextpnr.log" > "$probe_build/nextpnr.stdout" 2>&1
cp "$gtx_build/preparation.json" "$probe_build/preparation.json"
python3 "$experiment_root/ethernet/pcs_probe_report.py" "$prjxray_db/zynq7" "$probe_build" --seed 2
