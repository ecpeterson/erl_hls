#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
local_stage=${1:-"$project_root/_build/xls_sim/phi_memory_demo"}
remote_host=${ERL_HLS_REMOTE_HOST:-192.168.64.7}
remote_root=${ERL_HLS_REMOTE_ROOT:-/home/ecpeterson/erl_hls-build}
remote_xls=${ERL_HLS_REMOTE_XLS:-/home/ecpeterson/xls-v0.0.0-10601-g9f360fc89-linux-x64}
remote_stage="$remote_root/phi_memory_demo"
reuse_rtl=${ERL_HLS_PHI_DEMO_REUSE_RTL:-0}
native_icarus=${ERL_HLS_PHI_NATIVE_ICARUS:-0}
phi_shards=${ERL_HLS_PHI_SHARDS:-1}
if [[ ! "$phi_shards" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERL_HLS_PHI_SHARDS must be a positive integer" >&2
    exit 1
fi
if ((phi_shards > 9)); then
    echo "ERL_HLS_PHI_SHARDS cannot exceed the nine D3 phi cells" >&2
    exit 1
fi
scheduler_count=$((4 + 2 * phi_shards))
cpu_witness="$local_stage/phi_memory_cpu_witness.term"

cd "$project_root"
mkdir -p "$local_stage"
rm -f "$cpu_witness"
ERL_HLS_PHI_CPU_WITNESS="$cpu_witness" \
    rebar3 eunit --module=phi_memory_cpu_fabric_tests
test -s "$cpu_witness"

ERL_HLS_PHI_BRIDGE_DISTANCE=demo \
    "$project_root/tools/prepare_xls_sim.sh" "$local_stage"
cp "$project_root/tools/remote_phi_memory_demo.sh" \
    "$local_stage/remote_phi_memory_demo.sh"

ssh -o BatchMode=yes "$remote_host" mkdir -p "$remote_stage"
rsync -a -e "ssh -o BatchMode=yes" \
    "$local_stage/phi_halo_cell.x" \
    "$local_stage/phenom_data_cell.x" \
    "$local_stage/phenom_syndrome_cell.x" \
    "$local_stage/phi_noise_topology.x" \
    "$local_stage/phi_memory_gateway.x" \
    "$local_stage/phi_memory_debug_top.v" \
    "$local_stage/hls_1r1w_ram.v" \
    "$local_stage/axis.x" \
    "$local_stage/bram.x" \
    "$local_stage/mailbox.x" \
    "$local_stage/hls_fabric_router.x" \
    "$local_stage/hls_spatial_router.x" \
    "$local_stage/hls_debug_types.x" \
    "$local_stage/hls_debug_trace.x" \
    "$local_stage/hls_debug_observer.x" \
    "$local_stage/hls_debug_server.x" \
    "$local_stage/hls_debug_tap.v" \
    "$local_stage/hls_debug_monitor.v" \
    "$local_stage/hls_trace_store.v" \
    "$local_stage/phi_memory_bridge_tb.sv" \
    "$local_stage/phi_scheduler_rams.sh" \
    "$local_stage/xls_sim_bridge.c" \
    "$cpu_witness" \
    "$local_stage/erl_src" \
    "$local_stage/test_src" \
    "$local_stage/remote_phi_memory_demo.sh" \
    "$remote_host:$remote_stage/"

ssh -o BatchMode=yes "$remote_host" \
    env ERL_HLS_PHI_DEMO_REUSE_RTL="$reuse_rtl" \
    ERL_HLS_PHI_DEMO_COMPILE_ONLY="$native_icarus" \
    ERL_HLS_PHI_SCHEDULER_COUNT="$scheduler_count" \
    bash "$remote_stage/remote_phi_memory_demo.sh" \
    "$remote_stage" "$remote_xls"

if [[ "$native_icarus" == 1 ]]; then
    rsync -a -e "ssh -o BatchMode=yes" \
        "$remote_host:$remote_stage/phi_memory_gateway.v" \
        "$remote_host:$remote_stage/hls_fabric_host_tx.v" \
        "$remote_host:$remote_stage/hls_debug_observer.v" \
        "$remote_host:$remote_stage/hls_debug_server.v" \
        "$remote_host:$remote_stage/hls_fabric_ingress.v" \
        "$remote_host:$remote_stage/hls_fabric_egress.v" \
        "$remote_host:$remote_stage/phi_memory_gateway-ir.time" \
        "$remote_host:$remote_stage/phi_memory_gateway-opt.time" \
        "$remote_host:$remote_stage/phi_memory_gateway-codegen.time" \
        "$remote_host:$remote_stage/phi_memory_gateway-host-tx-ir.time" \
        "$remote_host:$remote_stage/phi_memory_gateway-host-tx-opt.time" \
        "$remote_host:$remote_stage/phi_memory_gateway-host-tx-codegen.time" \
        "$local_stage/"
    "$project_root/tools/local_phi_memory_demo.sh" "$local_stage"
else
    rsync -a -e "ssh -o BatchMode=yes" \
        --include=phi_memory_demo.log \
        --include=phi_memory_demo.metrics \
        --include='phi_memory_gateway-*.time' \
        --exclude='*' \
        "$remote_host:$remote_stage/" \
        "$local_stage/"
fi
