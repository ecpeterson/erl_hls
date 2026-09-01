#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
local_stage=${1:-"$project_root/_build/xls_sim/phi_memory_demo"}
remote_host=${ERL_HLS_REMOTE_HOST:-192.168.64.7}
remote_root=${ERL_HLS_REMOTE_ROOT:-/home/ecpeterson/erl_hls-build}
remote_xls=${ERL_HLS_REMOTE_XLS:-/home/ecpeterson/xls-v0.0.0-9235-gb179d691e-linux-x64}
remote_stage="$remote_root/phi_memory_demo"
reuse_rtl=${ERL_HLS_PHI_DEMO_REUSE_RTL:-0}
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
    "$local_stage/axis.x" \
    "$local_stage/hls_fabric_router.x" \
    "$local_stage/hls_spatial_router.x" \
    "$local_stage/phi_memory_bridge_tb.sv" \
    "$local_stage/xls_sim_bridge.c" \
    "$cpu_witness" \
    "$local_stage/erl_src" \
    "$local_stage/test_src" \
    "$local_stage/remote_phi_memory_demo.sh" \
    "$remote_host:$remote_stage/"

ssh -o BatchMode=yes "$remote_host" \
    env ERL_HLS_PHI_DEMO_REUSE_RTL="$reuse_rtl" \
    bash "$remote_stage/remote_phi_memory_demo.sh" \
    "$remote_stage" "$remote_xls"

rsync -a -e "ssh -o BatchMode=yes" \
    --include=phi_memory_demo.log \
    --include=phi_memory_demo.metrics \
    --include='phi_memory_gateway-*.time' \
    --exclude='*' \
    "$remote_host:$remote_stage/" \
    "$local_stage/"
