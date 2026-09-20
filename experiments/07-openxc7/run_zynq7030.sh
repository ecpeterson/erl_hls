#!/usr/bin/env bash
set -euo pipefail

experiment_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=openxc7_common.sh
source "$experiment_root/openxc7_common.sh"
prepare_openxc7
require_executable "$openxc7/bin/bitread"
python3 "$experiment_root/test_zynq7030.py"

# Download only the small package pinout archive; the overlay builder checks its hash.
archive=${ERL_HLS_ZYNQ_PINOUTS:-"$build_root/z7all.zip"}
if [[ ! -f "$archive" ]]; then
    pinout_url=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from prepare_zynq7030 import PINOUT_URL; print(PINOUT_URL)' "$experiment_root")
    curl --fail --location --show-error --max-time 90 "$pinout_url" -o "$archive.tmp"
    mv "$archive.tmp" "$archive"
fi
prjxray_db=$(python3 "$experiment_root/prepare_zynq7030.py" \
    "$prjxray_db" "$archive" "$build_root/databases")
database_id=$(shasum -a 256 "$prjxray_db/manifest.json" | cut -d ' ' -f 1)
make_chipdb xc7z030sbg485-1

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
    "$openxc7/bin/bitread" --part_file "$prjxray_db/zynq7/xc7z030sbg485-1/part.yaml" \
        -y -z -o "$output.bits" "$output.bit" > "$output-bitread.log"
    python3 "$experiment_root/check_zynq7030_bitstream.py" "$output.frames" "$output.bits"
done
