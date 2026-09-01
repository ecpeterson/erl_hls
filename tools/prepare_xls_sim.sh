#!/usr/bin/env bash
set -euo pipefail

stage=${1:?usage: prepare_xls_sim.sh STAGE}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

mkdir -p "$stage/erl_src" "$stage/test_src"
cd "$project_root"

rebar3 as test compile

ERL_HLS_REGSVC_X="$stage/regsvc.x" \
ERL_HLS_PHI_HALO_X="$stage/phi_halo_cell.x" \
ERL_HLS_PHENOM_DATA_X="$stage/phenom_data_cell.x" \
ERL_HLS_PHENOM_SYNDROME_X="$stage/phenom_syndrome_cell.x" \
ERL_HLS_PHI_PHENOM_TOPOLOGY_X="$stage/phi_phenom_topology.x" \
ERL_HLS_PHI_TORUS_TOPOLOGY_X="$stage/phi_torus_topology.x" \
ERL_HLS_PHI_NOISE_TOPOLOGY_X="$stage/phi_noise_topology.x" \
ERL_HLS_PHI_NOISE_TOPOLOGY_SMOKE_X="$stage/phi_noise_topology_smoke.x" \
ERL_HLS_ORDERED_EGRESS_ACTOR_X="$stage/ordered_egress_actor.x" \
ERL_HLS_ORDERED_EGRESS_TOPOLOGY_X="$stage/ordered_egress_topology.x" \
ERL_HLS_CASE_FIXTURE_X="$stage/xls_case_fixture.x" \
erl \
    -noshell \
    -pa "$project_root/_build/test/lib/erl_hls/ebin" \
    -pa "$project_root/_build/test/lib/erl_hls/test" \
    -eval '
        Regsvc = xls_parse:to_xls("src/examples/regsvc/regsvc.erl"),
        PhiHalo = xls_parse:to_xls(
            "src/examples/phi_decoder/phi_halo_cell.erl"
        ),
        PhenomData = xls_parse:to_xls(
            "src/examples/phi_decoder/phenom_data_cell.erl"
        ),
        PhenomSyndrome = xls_parse:to_xls(
            "src/examples/phi_decoder/phenom_syndrome_cell.erl"
        ),
        CaseFixture = xls_parse:to_xls(
            "test_data/xls_case_fixture.erl"
        ),
        PhiPhenomTopology = phi_phenom_topology_dslx:to_dslx(),
        PhiTorusTopology = phi_torus_topology_dslx:to_dslx(),
        PhiNoiseTopology = phi_noise_topology_dslx:to_dslx(),
        PhiNoiseTopologySmoke = phi_noise_topology_dslx:to_dslx(1),
        OrderedEgressActor = xls_parse:to_xls(
            "test/ordered_egress_actor.erl"
        ),
        OrderedEgressTopology = ordered_egress_topology:to_dslx(),
        ok = file:write_file(os:getenv("ERL_HLS_REGSVC_X"), Regsvc),
        ok = file:write_file(os:getenv("ERL_HLS_PHI_HALO_X"), PhiHalo),
        ok = file:write_file(
            os:getenv("ERL_HLS_PHENOM_DATA_X"),
            PhenomData
        ),
        ok = file:write_file(
            os:getenv("ERL_HLS_PHENOM_SYNDROME_X"),
            PhenomSyndrome
        ),
        ok = file:write_file(
            os:getenv("ERL_HLS_CASE_FIXTURE_X"),
            CaseFixture
        ),
        ok = file:write_file(
            os:getenv("ERL_HLS_PHI_PHENOM_TOPOLOGY_X"),
            PhiPhenomTopology
        ),
        ok = file:write_file(
            os:getenv("ERL_HLS_PHI_TORUS_TOPOLOGY_X"),
            PhiTorusTopology
        ),
        ok = file:write_file(
            os:getenv("ERL_HLS_PHI_NOISE_TOPOLOGY_X"),
            PhiNoiseTopology
        ),
        ok = file:write_file(
            os:getenv("ERL_HLS_PHI_NOISE_TOPOLOGY_SMOKE_X"),
            PhiNoiseTopologySmoke
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

cp "$project_root/priv/xls/lib/axis.x" "$stage/axis.x"
cp "$project_root/src/examples/regsvc/regsvc_core_adapter.v" \
    "$stage/regsvc_core_adapter.v"
cp "$project_root/src/examples/regsvc/regsvc_debug_top.v" \
    "$stage/regsvc_debug_top.v"
cp "$project_root/priv/xls/fabric/hls_fabric_router.x" \
    "$stage/hls_fabric_router.x"
cp "$project_root/priv/xls/fabric/hls_spatial_router.x" \
    "$stage/hls_spatial_router.x"
cp "$project_root/priv/xls/debug/hls_debug_types.x" \
    "$stage/hls_debug_types.x"
cp "$project_root/priv/xls/debug/hls_debug_trace.x" \
    "$stage/hls_debug_trace.x"
cp "$project_root/priv/xls/debug/hls_debug_observer.x" \
    "$stage/hls_debug_observer.x"
cp "$project_root/priv/xls/debug/hls_debug_server.x" \
    "$stage/hls_debug_server.x"
cp "$project_root/priv/rtl/debug/hls_debug_tap.v" \
    "$stage/hls_debug_tap.v"
cp "$project_root/priv/rtl/debug/hls_trace_store.v" \
    "$stage/hls_trace_store.v"
cp "$project_root/test/rtl/debug/hls_debug_tap_tb.sv" \
    "$stage/hls_debug_tap_tb.sv"
cp "$project_root/test/rtl/regsvc_pair_fixture.sv" \
    "$stage/regsvc_pair_fixture.sv"
cp "$project_root/test/rtl/regsvc_pair_tb.sv" "$stage/regsvc_pair_tb.sv"
cp "$project_root/test/rtl/regsvc_bridge_tb.sv" "$stage/regsvc_bridge_tb.sv"
cp "$project_root/test/rtl/debug/hls_trace_store_tb.sv" \
    "$stage/hls_trace_store_tb.sv"
cp "$project_root/test/rtl/phi_halo_cell_tb.sv" \
    "$stage/phi_halo_cell_tb.sv"
cp "$project_root/test/rtl/phenom_data_cell_tb.sv" \
    "$stage/phenom_data_cell_tb.sv"
cp "$project_root/test/rtl/phi_phenom_topology_tb.sv" \
    "$stage/phi_phenom_topology_tb.sv"
cp "$project_root/test/rtl/phi_torus_topology_tb.sv" \
    "$stage/phi_torus_topology_tb.sv"
cp "$project_root/test/rtl/phi_noise_topology_smoke_tb.sv" \
    "$stage/phi_noise_topology_smoke_tb.sv"
cp "$project_root/test/rtl/phi_noise_topology_tb.sv" \
    "$stage/phi_noise_topology_tb.sv"
cp "$project_root/test/rtl/ordered_egress_topology_tb.sv" \
    "$stage/ordered_egress_topology_tb.sv"
cp "$project_root/test/rtl/xls_sim_bridge.c" "$stage/xls_sim_bridge.c"

# `erlc -P` writes source listings after includes, macros, and parse transforms
# have been expanded. This lets an older remote OTP compile its own compatible
# BEAM files instead of loading BEAM files produced by the development host.
for source in \
    "$project_root/src/runtime/hls_fabric.erl" \
    "$project_root/src/api/hls_gs.erl" \
    "$project_root/src/runtime/hls_debug.erl" \
    "$project_root/src/api/hls_lists.erl" \
    "$project_root/src/api/hls_nums.erl" \
    "$project_root/src/api/hls_type.erl" \
    "$project_root/src/examples/regsvc/regsvc.erl"
do
    erlc -pa "$project_root/_build/test/lib/erl_hls/ebin" \
        -P -o "$stage/erl_src" "$source"
    module=$(basename "$source" .erl)
    cp "$stage/erl_src/$module.P" "$stage/erl_src/$module.erl"
done

erlc -pa "$project_root/_build/test/lib/erl_hls/ebin" \
    -P -o "$stage/test_src" "$project_root/test/regsvc_cpu_tests.erl"
cp "$stage/test_src/regsvc_cpu_tests.P" \
    "$stage/test_src/regsvc_cpu_tests.erl"
