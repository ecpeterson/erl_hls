#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
remote_host=${ERL_XLS_REMOTE_HOST:-192.168.64.7}
remote_root=${ERL_XLS_REMOTE_ROOT:-/home/ecpeterson/erl_xls-build}
remote_xls=${ERL_XLS_REMOTE_XLS:-/home/ecpeterson/xls-v0.0.0-9235-gb179d691e-linux-x64}
local_stage="$project_root/_build/xls_sim/regsvc"
remote_stage="$remote_root/regsvc"

mkdir -p "$local_stage"

rebar3 compile

TMP_X="$local_stage/regsvc.x" erl \
    -noshell \
    -pa "$project_root/_build/default/lib/erl_xls/ebin" \
    -eval '
        Output = xls_parse:to_xls("src/examples/regsvc.erl"),
        ok = file:write_file(os:getenv("TMP_X"), Output),
        halt().
    '

cp "$project_root/experiments/05-xls/axis.x" "$local_stage/axis.x"
cp "$project_root/src/examples/regsvc_wrapper.v" "$local_stage/regsvc_wrapper.v"
cp "$project_root/src/examples/regsvc_instrumented_wrapper.v" \
    "$local_stage/regsvc_instrumented_wrapper.v"
cp "$project_root/src/xls_debug_monitor.v" "$local_stage/xls_debug_monitor.v"
cp "$project_root/test/rtl/regsvc_tb.sv" "$local_stage/regsvc_tb.sv"
cp "$project_root/tools/remote_xls_sim.sh" "$local_stage/remote_xls_sim.sh"

ssh -o BatchMode=yes "$remote_host" mkdir -p "$remote_stage"
rsync -a -e "ssh -o BatchMode=yes" \
    "$local_stage/regsvc.x" \
    "$local_stage/axis.x" \
    "$local_stage/regsvc_wrapper.v" \
    "$local_stage/regsvc_instrumented_wrapper.v" \
    "$local_stage/xls_debug_monitor.v" \
    "$local_stage/regsvc_tb.sv" \
    "$local_stage/remote_xls_sim.sh" \
    "$remote_host:$remote_stage/"

ssh -o BatchMode=yes "$remote_host" \
    bash "$remote_stage/remote_xls_sim.sh" "$remote_stage" "$remote_xls"
