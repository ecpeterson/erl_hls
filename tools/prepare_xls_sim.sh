#!/usr/bin/env bash
set -euo pipefail

stage=${1:?usage: prepare_xls_sim.sh STAGE}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

mkdir -p "$stage/erl_src" "$stage/test_src"
cd "$project_root"

rebar3 as test compile

ERL_HLS_REGSVC_X="$stage/regsvc.x" \
ERL_HLS_ORDERED_EGRESS_ACTOR_X="$stage/ordered_egress_actor.x" \
ERL_HLS_ORDERED_EGRESS_TOPOLOGY_X="$stage/ordered_egress_topology.x" \
ERL_HLS_CASE_FIXTURE_X="$stage/xls_case_fixture.x" \
ERL_HLS_COMPANION_FIXTURE_X="$stage/hls_companion_gs_fixture.x" \
ERL_HLS_NUMERIC_TEST_X="$stage/hls_numeric_test.x" \
ERL_HLS_SHORT_CIRCUIT_TEST_X="$stage/xls_short_circuit_test.x" \
erl \
    -noshell \
    -pa "$project_root/_build/test/lib/erl_hls/ebin" -pa "$project_root/_build/test/lib/hls_runtime/ebin" \
    -pa "$project_root/_build/test/lib/erl_hls/test" \
    -eval '
        Regsvc = xls_parse:to_xls("src/examples/regsvc/regsvc.erl"),
        CaseFixture = xls_parse:to_xls(
            "test_data/xls_case_fixture.erl"
        ),
        ok = file:write_file(os:getenv("ERL_HLS_NUMERIC_TEST_X"),
            hls_numeric_dslx:to_dslx()),
        ok = file:write_file(os:getenv("ERL_HLS_SHORT_CIRCUIT_TEST_X"),
            xls_short_circuit_dslx:to_dslx()),
        CompanionFixture = xls_parse:to_xls(
            "test_data/hls_companion_gs_fixture.erl"
        ),
        OrderedEgressActor = xls_parse:to_xls(
            "test/ordered_egress_actor.erl"
        ),
        OrderedEgressTopology = ordered_egress_topology:to_dslx(),
        ok = file:write_file(os:getenv("ERL_HLS_REGSVC_X"), Regsvc),
        ok = file:write_file(
            os:getenv("ERL_HLS_CASE_FIXTURE_X"),
            CaseFixture
        ),
        ok = file:write_file(
            os:getenv("ERL_HLS_COMPANION_FIXTURE_X"),
            CompanionFixture
        ),
        ok = file:write_file(
            os:getenv("ERL_HLS_ORDERED_EGRESS_ACTOR_X"),
            OrderedEgressActor
        ),
        ok = file:write_file(
            os:getenv("ERL_HLS_ORDERED_EGRESS_TOPOLOGY_X"),
            OrderedEgressTopology
        ),
        halt().
    '

cp "$project_root"/priv/xls/lib/*.x "$stage/"
cp "$project_root/test_data/hls_companion_provider.x" "$stage/hls_companion_provider.x"
cp "$project_root/src/examples/regsvc/regsvc_core_adapter.v" \
    "$stage/regsvc_core_adapter.v"
cp "$project_root/src/examples/regsvc/regsvc_debug_top.v" \
    "$stage/regsvc_debug_top.v"
cp "$project_root/priv/rtl/hls_1r1w_ram.v" "$stage/hls_1r1w_ram.v"
cp "$project_root"/priv/rtl/fabric/*.v "$stage/"
cp "$project_root/priv/xls/fabric/hls_fabric_router.x" \
    "$stage/hls_fabric_router.x"
cp "$project_root/priv/xls/fabric/hls_spatial_router.x" \
    "$stage/hls_spatial_router.x"
cp "$project_root/priv/xls/debug/hls_debug_types.x" \
    "$stage/hls_debug_types.x"
cp "$project_root/priv/xls/debug/hls_debug_trace.x" \
    "$stage/hls_debug_trace.x"
cp "$project_root/priv/xls/debug/hls_debug_framing.x" "$stage/hls_debug_framing.x"
cp "$project_root/priv/xls/debug/hls_debug_observer.x" \
    "$stage/hls_debug_observer.x"
cp "$project_root/priv/xls/debug/hls_debug_server.x" \
    "$stage/hls_debug_server.x"
cp "$project_root/priv/rtl/debug/hls_debug_tap.v" \
    "$stage/hls_debug_tap.v"
cp "$project_root/priv/rtl/debug/hls_debug_monitor.v" \
    "$stage/hls_debug_monitor.v"
cp "$project_root/priv/rtl/debug/hls_trace_store.v" \
    "$stage/hls_trace_store.v"
cp "$project_root/test/rtl/debug/hls_debug_tap_tb.sv" \
    "$stage/hls_debug_tap_tb.sv"
cp "$project_root/test/rtl/regsvc_fabric_fixture.sv" \
    "$stage/regsvc_fabric_fixture.sv"
cp "$project_root/test/rtl/regsvc_pair_tb.sv" "$stage/regsvc_pair_tb.sv"
cp "$project_root/test/rtl/regsvc_bridge_tb.sv" "$stage/regsvc_bridge_tb.sv"
cp "$project_root/test/rtl/debug/hls_trace_store_tb.sv" \
    "$stage/hls_trace_store_tb.sv"
cp "$project_root/test/rtl/hls_fabric_host_tx_tb.sv" \
    "$stage/hls_fabric_host_tx_tb.sv"
cp "$project_root/test/rtl/ordered_egress_topology_tb.sv" \
    "$stage/ordered_egress_topology_tb.sv"
cp "$project_root/test/rtl/xls_sim_bridge.c" "$stage/xls_sim_bridge.c"
cp "$project_root/test/rtl/xls_sim_axis.h" "$stage/xls_sim_axis.h"
cp "$project_root/test/rtl/debug/hls_debug_server_tb.sv" "$stage/hls_debug_server_tb.sv"

# `erlc -P` writes source listings after includes, macros, and parse transforms
# have been expanded. This lets an older remote OTP compile its own compatible
# BEAM files instead of loading BEAM files produced by the development host.
for source in \
    "$project_root"/apps/hls_runtime/src/api/*.erl \
    "$project_root"/apps/hls_runtime/src/runtime/*.erl \
    "$project_root/src/examples/regsvc/regsvc.erl"
do
    erlc -pa "$project_root/_build/test/lib/erl_hls/ebin" -pa "$project_root/_build/test/lib/hls_runtime/ebin" \
        -I "$project_root/include" -P -o "$stage/erl_src" "$source"
    module=$(basename "$source" .erl)
    cp "$stage/erl_src/$module.P" "$stage/erl_src/$module.erl"
done

erlc -pa "$project_root/_build/test/lib/erl_hls/ebin" -pa "$project_root/_build/test/lib/hls_runtime/ebin" \
    -P -o "$stage/test_src" "$project_root/test/regsvc_cpu_tests.erl"
cp "$stage/test_src/regsvc_cpu_tests.P" \
    "$stage/test_src/regsvc_cpu_tests.erl"


for helper in compile_xls.py; do
    cp "$project_root/tools/erl_hls_tools/$helper" "$stage/$helper"
done
