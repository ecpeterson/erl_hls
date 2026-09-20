#!/usr/bin/env bash
# Native compile probe only: this command intentionally has no bitstream stage.
set -euo pipefail
experiment_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$experiment_root/openxc7_common.sh"
prepare_zynq7030
gtx_build="$build_root/gtx-probe"
mkdir -p "$gtx_build"
metadata=$(python3 "$experiment_root/gtx/prepare.py" "$prjxray_db/zynq7" \
    "$openxc7/share/nextpnr/external/nextpnr-xilinx-meta/zynq7" "$gtx_build")
identity="$toolchain_id $database_id $(basename "$metadata")"
if [[ ! -s "$gtx_build/chipdb.bin" || ! -f "$gtx_build/chipdb.identity" ]] ||
        [[ $(<"$gtx_build/chipdb.identity") != "$identity" ]]; then
    "$openxc7/libexec/python3.12" "$nextpnr_python/bbaexport.py" \
        --device xc7z030sbg485-1 --xray "$prjxray_db/zynq7" --metadata "$metadata" \
        --bba "$gtx_build/chipdb.bba" > "$gtx_build/bbaexport.log" 2>&1
    "$openxc7/bin/bbasm" -l "$gtx_build/chipdb.bba" "$gtx_build/chipdb.bin.tmp"
    mv "$gtx_build/chipdb.bin.tmp" "$gtx_build/chipdb.bin"
    printf '%s\n' "$identity" > "$gtx_build/chipdb.identity"
    rm "$gtx_build/chipdb.bba"
fi
python3 "$experiment_root/test_gtx_probe.py" --yosys "$oss_cad_suite/bin/yosys"
script="read_verilog \"$experiment_root/zynq_ps_probe.v\" \"$experiment_root/zynq_ps_probe_top.v\""
for source in gtx_probe_control gtx_probe_sample te0715_gtx_lane te0715_gtx_top; do
    script+=" \"$experiment_root/gtx/$source.v\""
done
script+="; synth_xilinx -flatten -abc9 -arch xc7 -top te0715_gtx_top; check -assert;"
script+=" select -assert-count 1 t:GTXE2_CHANNEL; select -assert-count 1 t:IBUFDS_GTE2;"
script+=" select -assert-count 1 t:PS7; select -clear; write_json \"$gtx_build/netlist.json\";"
"$oss_cad_suite/bin/yosys" -Q -q -l "$gtx_build/yosys.log" -p "$script"
rm -f "$gtx_build/probe.fasm" "$gtx_build/report.json" "$gtx_build/result.json"
"$openxc7/bin/nextpnr-xilinx" --chipdb "$gtx_build/chipdb.bin" \
    --xdc "$experiment_root/gtx/te0715_gtx.xdc" --json "$gtx_build/netlist.json" \
    --fasm "$gtx_build/probe.fasm" --report "$gtx_build/report.json" \
    --freq 25 --seed 1 --router router2 --log "$gtx_build/nextpnr.log" \
    > "$gtx_build/nextpnr.stdout" 2>&1
python3 "$experiment_root/gtx/report.py" "$prjxray_db/zynq7" "$gtx_build"
