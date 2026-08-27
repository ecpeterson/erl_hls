#!/usr/bin/env bash
set -euo pipefail

stage=${1:?usage: prepare_xls_sim.sh STAGE}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

mkdir -p "$stage/erl_src" "$stage/test_src"
cd "$project_root"

rebar3 eunit

TMP_X="$stage/regsvc.x" erl \
    -noshell \
    -pa "$project_root/_build/test/lib/erl_xls/ebin" \
    -eval '
        Output = xls_parse:to_xls("src/examples/regsvc.erl"),
        ok = file:write_file(os:getenv("TMP_X"), Output),
        halt().
    '

cp "$project_root/experiments/05-xls/axis.x" "$stage/axis.x"
cp "$project_root/src/examples/regsvc_core_adapter.v" \
    "$stage/regsvc_core_adapter.v"
cp "$project_root/src/examples/regsvc_debug_top.v" \
    "$stage/regsvc_debug_top.v"
cp "$project_root/src/xls_fabric_router.x" "$stage/xls_fabric_router.x"
cp "$project_root/src/xls_debug_monitor.x" "$stage/xls_debug_monitor.x"
cp "$project_root/src/xls_debug_tap.v" "$stage/xls_debug_tap.v"
cp "$project_root/test/rtl/regsvc_pair_fixture.sv" \
    "$stage/regsvc_pair_fixture.sv"
cp "$project_root/test/rtl/regsvc_pair_tb.sv" "$stage/regsvc_pair_tb.sv"
cp "$project_root/test/rtl/regsvc_bridge_tb.sv" "$stage/regsvc_bridge_tb.sv"
cp "$project_root/test/rtl/xls_sim_bridge.c" "$stage/xls_sim_bridge.c"

# `erlc -P` writes source listings after includes, macros, and parse transforms
# have been expanded. This lets an older remote OTP compile its own compatible
# BEAM files instead of loading BEAM files produced by the development host.
for source in \
    "$project_root/src/xls_fabric.erl" \
    "$project_root/src/xls_gs.erl" \
    "$project_root/src/xls_debug.erl" \
    "$project_root/src/xls_lists.erl" \
    "$project_root/src/xls_nums.erl" \
    "$project_root/src/xls_type.erl" \
    "$project_root/src/examples/regsvc.erl"
do
    erlc -pa "$project_root/_build/test/lib/erl_xls/ebin" \
        -P -o "$stage/erl_src" "$source"
    module=$(basename "$source" .erl)
    cp "$stage/erl_src/$module.P" "$stage/erl_src/$module.erl"
done

erlc -pa "$project_root/_build/test/lib/erl_xls/ebin" \
    -P -o "$stage/test_src" "$project_root/test/regsvc_cpu_tests.erl"
cp "$stage/test_src/regsvc_cpu_tests.P" \
    "$stage/test_src/regsvc_cpu_tests.erl"
