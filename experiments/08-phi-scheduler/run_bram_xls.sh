#!/usr/bin/env bash
set -euo pipefail

experiment_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
project_root=$(cd "$experiment_root/../.." && pwd)
local_stage=${1:-"$project_root/_build/phi_sequential_bram_xls"}
remote_host=${ERL_HLS_REMOTE_HOST:-192.168.64.7}
remote_root=${ERL_HLS_REMOTE_ROOT:-/home/ecpeterson/erl_hls-build}
remote_xls=${ERL_HLS_REMOTE_XLS:-/home/ecpeterson/xls-v0.0.0-10601-g9f360fc89-linux-x64}
remote_stage="$remote_root/phi_sequential_bram_xls"
oss_cad_suite="$project_root/experiments/07-openxc7/.apio/packages/oss-cad-suite"
iverilog=${ERL_HLS_IVERILOG:-"$oss_cad_suite/bin/iverilog"}
vvp=${ERL_HLS_VVP:-"$oss_cad_suite/bin/vvp"}
yosys=${ERL_HLS_YOSYS:-"$oss_cad_suite/bin/yosys"}

mkdir -p "$local_stage"
cp "$experiment_root/phi_sequential_bram_core.x" \
    "$local_stage/phi_sequential_bram_core.x"
cp "$experiment_root/phi_memory_scheduler_boundary.sv" \
    "$local_stage/phi_memory_scheduler_boundary.sv"
cp "$experiment_root/phi_memory_bram_top.sv" \
    "$local_stage/phi_memory_bram_top.sv"
cp "$experiment_root/phi_memory_raw_d3_tb.sv" \
    "$local_stage/phi_memory_raw_d3_tb.sv"
cp "$experiment_root/remote_bram_xls.sh" \
    "$local_stage/remote_bram_xls.sh"

ssh -o BatchMode=yes "$remote_host" mkdir -p "$remote_stage"
rsync -a -e "ssh -o BatchMode=yes" \
    "$local_stage/phi_sequential_bram_core.x" \
    "$local_stage/remote_bram_xls.sh" \
    "$remote_host:$remote_stage/"
ssh -o BatchMode=yes "$remote_host" \
    bash "$remote_stage/remote_bram_xls.sh" \
    "$remote_stage" "$remote_xls"
rsync -a -e "ssh -o BatchMode=yes" \
    "$remote_host:$remote_stage/phi_sequential_bram_core.v" \
    "$local_stage/phi_sequential_bram_core.v"

"$iverilog" -g2012 -DPHI_MEMORY_DUT=phi_memory_bram_top \
    -s phi_memory_raw_d3_tb \
    -o "$local_stage/phi_memory_bram_tb.vvp" \
    "$local_stage/phi_sequential_bram_core.v" \
    "$local_stage/phi_memory_scheduler_boundary.sv" \
    "$local_stage/phi_memory_bram_top.sv" \
    "$local_stage/phi_memory_raw_d3_tb.sv"
"$vvp" "$local_stage/phi_memory_bram_tb.vvp"

log="$local_stage/phi_sequential_bram-yosys.log"
"$yosys" -Q -q -l "$log" -p \
    "read_verilog $local_stage/phi_sequential_bram_core.v; \
     read_verilog -sv $local_stage/phi_memory_scheduler_boundary.sv \
        $local_stage/phi_memory_bram_top.sv; \
     hierarchy -check -top phi_memory_bram_top; \
     synth_xilinx -flatten -abc9 -arch xc7 -noiopad \
        -top phi_memory_bram_top; \
     check -assert; \
     stat -tech xilinx" 2>/dev/null

awk '
    /=== / { block = $0 ORS; capture = 1; next }
    capture { block = block $0 ORS }
    capture && /Estimated number of LCs:/ { last = block; capture = 0 }
    END { printf "%s", last }
' "$log"
