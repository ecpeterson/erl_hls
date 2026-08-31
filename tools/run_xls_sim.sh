#!/usr/bin/env bash
set -euo pipefail

local_stage=${1:?usage: run_xls_sim.sh STAGE}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
remote_host=${ERL_HLS_REMOTE_HOST:-192.168.64.7}
remote_root=${ERL_HLS_REMOTE_ROOT:-/home/ecpeterson/erl_hls-build}
remote_xls=${ERL_HLS_REMOTE_XLS:-/home/ecpeterson/xls-v0.0.0-9235-gb179d691e-linux-x64}
remote_stage="$remote_root/regsvc"

"$project_root/tools/prepare_xls_sim.sh" "$local_stage"
cp "$project_root/tools/remote_xls_sim.sh" \
    "$local_stage/remote_xls_sim.sh"

ssh -o BatchMode=yes "$remote_host" mkdir -p "$remote_stage"
rsync -a -e "ssh -o BatchMode=yes" \
    "$local_stage/regsvc.x" \
    "$local_stage/phi_halo_cell.x" \
    "$local_stage/phenom_data_cell.x" \
    "$local_stage/phenom_syndrome_cell.x" \
    "$local_stage/phi_phenom_topology.x" \
    "$local_stage/xls_case_fixture.x" \
    "$local_stage/axis.x" \
    "$local_stage/regsvc_core_adapter.v" \
    "$local_stage/regsvc_debug_top.v" \
    "$local_stage/hls_fabric_router.x" \
    "$local_stage/hls_debug_types.x" \
    "$local_stage/hls_debug_trace.x" \
    "$local_stage/hls_debug_observer.x" \
    "$local_stage/hls_debug_server.x" \
    "$local_stage/hls_debug_tap.v" \
    "$local_stage/hls_debug_tap_tb.sv" \
    "$local_stage/hls_trace_store.v" \
    "$local_stage/hls_trace_store_tb.sv" \
    "$local_stage/regsvc_pair_fixture.sv" \
    "$local_stage/regsvc_pair_tb.sv" \
    "$local_stage/regsvc_bridge_tb.sv" \
    "$local_stage/phi_halo_cell_tb.sv" \
    "$local_stage/phi_phenom_topology_tb.sv" \
    "$local_stage/xls_sim_bridge.c" \
    "$local_stage/erl_src" \
    "$local_stage/test_src" \
    "$local_stage/remote_xls_sim.sh" \
    "$remote_host:$remote_stage/"

ssh -o BatchMode=yes "$remote_host" \
    bash "$remote_stage/remote_xls_sim.sh" "$remote_stage" "$remote_xls"

# Retrieve review artifacts only after the remote runner has generated and
# simulated them successfully.
# The topology DSLX is generated locally from its Erlang plan and physical
# profile. Its regenerated RTL is brought back for review and synthesis;
# behavioral regeneration, rather than a 500-KiB Verilog golden, is enforced
# by the remote simulation above.
rsync -a -e "ssh -o BatchMode=yes" \
    --include=regsvc.v \
    --include=phi_halo_cell.v \
    --include=phenom_data_cell.v \
    --include=phenom_syndrome_cell.v \
    --include=phi_phenom_topology.v \
    --exclude='*' \
    "$remote_host:$remote_stage/" \
    "$local_stage/"
