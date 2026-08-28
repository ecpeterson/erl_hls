#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
remote_host=${ERL_XLS_REMOTE_HOST:-192.168.64.7}
remote_root=${ERL_XLS_REMOTE_ROOT:-/home/ecpeterson/erl_xls-build}
remote_xls=${ERL_XLS_REMOTE_XLS:-/home/ecpeterson/xls-v0.0.0-9235-gb179d691e-linux-x64}
local_stage="$project_root/_build/xls_sim/regsvc"
remote_stage="$remote_root/regsvc"

"$project_root/tools/prepare_xls_sim.sh" "$local_stage"
cp "$project_root/tools/remote_xls_sim.sh" "$local_stage/remote_xls_sim.sh"

ssh -o BatchMode=yes "$remote_host" mkdir -p "$remote_stage"
rsync -a -e "ssh -o BatchMode=yes" \
    "$local_stage/regsvc.x" \
    "$local_stage/axis.x" \
    "$local_stage/regsvc_core_adapter.v" \
    "$local_stage/regsvc_debug_top.v" \
    "$local_stage/xls_fabric_router.x" \
    "$local_stage/xls_debug_monitor.x" \
    "$local_stage/xls_debug_tap.v" \
    "$local_stage/xls_trace_store.v" \
    "$local_stage/xls_trace_store_tb.sv" \
    "$local_stage/regsvc_pair_fixture.sv" \
    "$local_stage/regsvc_pair_tb.sv" \
    "$local_stage/regsvc_bridge_tb.sv" \
    "$local_stage/xls_sim_bridge.c" \
    "$local_stage/erl_src" \
    "$local_stage/test_src" \
    "$local_stage/remote_xls_sim.sh" \
    "$remote_host:$remote_stage/"

ssh -o BatchMode=yes "$remote_host" \
    bash "$remote_stage/remote_xls_sim.sh" "$remote_stage" "$remote_xls"
