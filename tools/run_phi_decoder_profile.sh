#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
local_stage=${1:-"$project_root/_build/xls_sim/phi_decoder_profile"}
xls_root=${ERL_HLS_XLS_ROOT:-${2:-}}
stage_timeout=${ERL_HLS_D3_TIMEOUT:-2h}
shard_count=${ERL_HLS_PHI_PROFILE_SHARDS:-3}
pipeline_stages=${ERL_HLS_PHI_PROFILE_PIPELINE_STAGES:-2}
initiation_interval=${ERL_HLS_PHI_PROFILE_II:-1}

if [[ -z "$xls_root" ]]; then
    echo "set ERL_HLS_XLS_ROOT or pass the native XLS root as argument 2" >&2
    exit 1
fi
for binary in ir_converter_main opt_main codegen_main; do
    if [[ ! -x "$xls_root/$binary" ]]; then
        echo "missing native XLS command: $xls_root/$binary" >&2
        exit 1
    fi
done

ERL_HLS_PHI_PROFILE_SHARDS="$shard_count" \
    "$project_root/tools/prepare_xls_sim.sh" "$local_stage"
cp "$project_root/tools/phi_decoder_profile_stage.sh" \
    "$local_stage/phi_decoder_profile_stage.sh"

bash "$local_stage/phi_decoder_profile_stage.sh" \
    "$local_stage" "$xls_root" "$stage_timeout" "$shard_count"
