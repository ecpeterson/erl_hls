#!/usr/bin/env bash
# Compile the selected backend and emit network hardware from a trusted build config.
set -euo pipefail
if [[ $# != 3 ]]; then
    echo 'Usage: bash tools/emit_protocol_network.sh XLS_ROOT CONFIG FRESH_OUTPUT' >&2
    exit 2
fi
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_root"
rebar3 release
"$project_root/_build/default/rel/hls/bin/hls-fabric" emit --kind network --config "$2" --output "$3"
"$project_root/_build/default/rel/hls/bin/compile-source-build" "$1" "$3"
