#!/usr/bin/env bash
set -euo pipefail

experiment_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
project_root=$(cd "$experiment_root/../.." && pwd)
stage=${1:-"$project_root/_build/phi_shard_sweep"}

for shards in ${ERL_HLS_PHI_SHARD_SWEEP:-1 2 3}; do
    ERL_HLS_PHI_SHARDS="$shards" \
    ERL_HLS_PHI_NATIVE_ICARUS=${ERL_HLS_PHI_NATIVE_ICARUS:-1} \
        "$project_root/tools/run_phi_memory_demo.sh" \
        "$stage/shards_${shards}"
done

"$experiment_root/synth_shard_sweep.sh" "$stage"
