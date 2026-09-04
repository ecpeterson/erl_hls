#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
local_stage=${1:-"$project_root/_build/xls_sim/phi_decoder_profile"}
remote_host=${ERL_HLS_REMOTE_HOST:-192.168.64.7}
remote_root=${ERL_HLS_REMOTE_ROOT:-/home/ecpeterson/erl_hls-build}
remote_xls=${ERL_HLS_REMOTE_XLS:-/home/ecpeterson/xls-v0.0.0-10601-g9f360fc89-linux-x64}
stage_timeout=${ERL_HLS_D3_TIMEOUT:-2h}
shard_count=${ERL_HLS_PHI_PROFILE_SHARDS:-3}
remote_stage="$remote_root/phi_decoder_profile"

ERL_HLS_PHI_PROFILE_SHARDS="$shard_count" \
    "$project_root/tools/prepare_xls_sim.sh" "$local_stage"
cp "$project_root/tools/remote_phi_decoder_profile.sh" \
    "$local_stage/remote_phi_decoder_profile.sh"

ssh -o BatchMode=yes "$remote_host" mkdir -p "$remote_stage"
rsync -a -e "ssh -o BatchMode=yes" \
    "$local_stage/axis.x" \
    "$local_stage/bram.x" \
    "$local_stage/mailbox.x" \
    "$local_stage/phi_halo_cell.x" \
    "$local_stage/phi_syndrome_replay_cell.x" \
    "$local_stage/phi_decoder_profile_topology.x" \
    "$local_stage/phi_decoder_profile_top.v" \
    "$local_stage/phi_decoder_profile_tb.sv" \
    "$local_stage/hls_1r1w_ram.v" \
    "$local_stage/phi_scheduler_rams.sh" \
    "$local_stage/remote_phi_decoder_profile.sh" \
    "$remote_host:$remote_stage/"

simulation_status=0
ssh -o BatchMode=yes "$remote_host" \
    bash "$remote_stage/remote_phi_decoder_profile.sh" \
    "$remote_stage" "$remote_xls" "$stage_timeout" "$shard_count" || \
    simulation_status=$?

retrieval_status=0
rsync -a -e "ssh -o BatchMode=yes" \
    --include=phi_decoder_profile.metrics \
    --include=phi_decoder_profile.sim.log \
    --include=phi_decoder_profile.sim.log.failed \
    --include='phi_decoder_profile-*.time' \
    --include='phi_decoder_profile-*.time.failed' \
    --exclude='*' \
    "$remote_host:$remote_stage/" \
    "$local_stage/" || retrieval_status=$?

if ((simulation_status != 0)); then
    exit "$simulation_status"
fi
exit "$retrieval_status"
