#!/usr/bin/env bash
set -euo pipefail

experiment_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
project_root=$(cd "$experiment_root/../.." && pwd)
local_stage=${1:-"$project_root/_build/phi_sequential_xls"}
remote_host=${ERL_HLS_REMOTE_HOST:-192.168.64.7}
remote_root=${ERL_HLS_REMOTE_ROOT:-/home/ecpeterson/erl_hls-build}
remote_xls=${ERL_HLS_REMOTE_XLS:-/home/ecpeterson/xls-v0.0.0-10601-g9f360fc89-linux-x64}
remote_stage="$remote_root/phi_sequential_xls"
bundled_yosys="$project_root/experiments/07-openxc7/.apio/packages/oss-cad-suite/bin/yosys"
yosys=${ERL_HLS_YOSYS:-$bundled_yosys}

mkdir -p "$local_stage"
cp "$experiment_root/phi_sequential_core.x" \
    "$local_stage/phi_sequential_core.x"
cp "$experiment_root/remote_sequential_xls.sh" \
    "$local_stage/remote_sequential_xls.sh"

ssh -o BatchMode=yes "$remote_host" mkdir -p "$remote_stage"
rsync -a -e "ssh -o BatchMode=yes" \
    "$local_stage/phi_sequential_core.x" \
    "$local_stage/remote_sequential_xls.sh" \
    "$remote_host:$remote_stage/"
ssh -o BatchMode=yes "$remote_host" \
    bash "$remote_stage/remote_sequential_xls.sh" \
    "$remote_stage" "$remote_xls"
rsync -a -e "ssh -o BatchMode=yes" \
    "$remote_host:$remote_stage/phi_sequential_core.v" \
    "$local_stage/phi_sequential_core.v"

top=$(sed -n 's/^module \([^ (]*\)(.*/\1/p' \
    "$local_stage/phi_sequential_core.v" | tail -1)
if [[ -z "$top" ]]; then
    echo "could not discover generated top module" >&2
    exit 1
fi
log="$local_stage/phi_sequential_core-yosys.log"
"$yosys" -Q -q -l "$log" -p \
    "read_verilog -sv $local_stage/phi_sequential_core.v; \
     hierarchy -check -top $top; \
     synth_xilinx -flatten -abc9 -arch xc7 -noiopad -top $top; \
     check -assert; \
     stat -tech xilinx" 2>/dev/null

awk '
    /=== / { block = $0 ORS; capture = 1; next }
    capture { block = block $0 ORS }
    capture && /Estimated number of LCs:/ { last = block; capture = 0 }
    END { printf "%s", last }
' "$log"
