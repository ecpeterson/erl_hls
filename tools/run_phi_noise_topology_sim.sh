#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
local_stage=${1:-"$project_root/_build/xls_sim/phi_noise_topology"}
remote_host=${ERL_HLS_REMOTE_HOST:-192.168.64.7}
remote_root=${ERL_HLS_REMOTE_ROOT:-/home/ecpeterson/erl_hls-build}
remote_xls=${ERL_HLS_REMOTE_XLS:-/home/ecpeterson/xls-v0.0.0-10601-g9f360fc89-linux-x64}
stage_timeout=${ERL_HLS_D3_TIMEOUT:-2h}
remote_stage="$remote_root/phi_noise_topology"

"$project_root/tools/prepare_xls_sim.sh" "$local_stage"
cp "$project_root/tools/remote_phi_noise_topology_sim.sh" \
    "$local_stage/remote_phi_noise_topology_sim.sh"
for report in \
    phi_noise_topology.metrics \
    phi_noise_topology.sim.log \
    phi_noise_topology-ir.time \
    phi_noise_topology-opt.time \
    phi_noise_topology-codegen.time \
    phi_noise_topology-iverilog.time \
    phi_noise_topology-vvp.time
do
    rm -f -- "$local_stage/$report" "$local_stage/$report.failed"
done

ssh -o BatchMode=yes "$remote_host" mkdir -p "$remote_stage"
rsync -a -e "ssh -o BatchMode=yes" \
    "$local_stage/axis.x" \
    "$local_stage/bram.x" \
    "$local_stage/mailbox.x" \
    "$local_stage/hls_spatial_router.x" \
    "$local_stage/phi_halo_cell.x" \
    "$local_stage/phenom_data_cell.x" \
    "$local_stage/phenom_syndrome_cell.x" \
    "$local_stage/phi_noise_topology.x" \
    "$local_stage/phi_noise_topology_tb.sv" \
    "$local_stage/hls_1r1w_ram.v" \
    "$local_stage/phi_scheduler_rams.sh" \
    "$local_stage/remote_phi_noise_topology_sim.sh" \
    "$remote_host:$remote_stage/"

simulation_status=0
ssh -o BatchMode=yes "$remote_host" \
    bash "$remote_stage/remote_phi_noise_topology_sim.sh" \
    "$remote_stage" "$remote_xls" "$stage_timeout" || simulation_status=$?

retrieval_status=0
rsync -a -e "ssh -o BatchMode=yes" \
    --include=phi_noise_topology.metrics \
    --include=phi_noise_topology.sim.log \
    --include=phi_noise_topology.sim.log.failed \
    --include='phi_noise_topology-*.time' \
    --include='phi_noise_topology-*.time.failed' \
    --exclude='*' \
    "$remote_host:$remote_stage/" \
    "$local_stage/" || retrieval_status=$?

if ((simulation_status != 0)); then
    exit "$simulation_status"
fi
exit "$retrieval_status"
