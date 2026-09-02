#!/usr/bin/env bash
set -euo pipefail

experiment_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
project_root=$(cd "$experiment_root/../.." && pwd)
local_stage=${1:-"$project_root/_build/phi_area_matrix"}
remote_host=${ERL_HLS_REMOTE_HOST:-192.168.64.7}
remote_root=${ERL_HLS_REMOTE_ROOT:-/home/ecpeterson/erl_hls-build}
remote_xls=${ERL_HLS_REMOTE_XLS:-/home/ecpeterson/xls-v0.0.0-9235-gb179d691e-linux-x64}
remote_stage="$remote_root/phi_area_matrix"

ERL_HLS_PHI_DISTANCE=2 \
ERL_HLS_PHI_NOISE_RATE=2147483648 \
    "$project_root/tools/prepare_xls_sim.sh" "$local_stage"
cp "$local_stage/phi_noise_topology.x" "$local_stage/phi_noise_d2.x"
cp "$experiment_root/remote_area_matrix.sh" \
    "$local_stage/remote_area_matrix.sh"

ssh -o BatchMode=yes "$remote_host" mkdir -p "$remote_stage"
rsync -a -e "ssh -o BatchMode=yes" \
    "$local_stage/axis.x" \
    "$local_stage/hls_spatial_router.x" \
    "$local_stage/phi_halo_cell.x" \
    "$local_stage/phenom_data_cell.x" \
    "$local_stage/phenom_syndrome_cell.x" \
    "$local_stage/phi_noise_d2.x" \
    "$local_stage/remote_area_matrix.sh" \
    "$remote_host:$remote_stage/"
ssh -o BatchMode=yes "$remote_host" \
    bash "$remote_stage/remote_area_matrix.sh" \
    "$remote_stage" "$remote_xls"
rsync -a -e "ssh -o BatchMode=yes" \
    "$remote_host:$remote_stage/phi_noise_d2.v" \
    "$local_stage/phi_noise_d2.v"

"$experiment_root/synth_area_matrix.sh" \
    "$local_stage/phi_noise_d2.v" "$local_stage/synthesis"
