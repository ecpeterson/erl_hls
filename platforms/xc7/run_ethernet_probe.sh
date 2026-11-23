#!/usr/bin/env bash
# Native board-facing Ethernet compile probe; no bitstream or programming stage.
set -euo pipefail
experiment_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$experiment_root/openxc7_common.sh"
prepare_gtx
python3 "$experiment_root/ethernet/board.py" \
    --yosys "$oss_cad_suite/bin/yosys" \
    --nextpnr "${ERL_HLS_NEXTPNR:-$openxc7/bin/nextpnr-xilinx}" \
    --chipdb "$gtx_build/chipdb.bin" --database "$prjxray_db/zynq7" \
    --output "$build_root/ethernet-board" "$@"
