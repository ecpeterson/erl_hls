#!/usr/bin/env bash
# Compile the source backend and emit boundary hardware from a trusted build config.
set -euo pipefail
if [[ $# != 3 ]]; then
    echo 'Usage: bash tools/hls_fabric/emit_protocol_boundary.sh XLS_ROOT CONFIG FRESH_OUTPUT' >&2
    exit 2
fi
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$project_root"
rebar3 release -n hls
"$project_root/_build/default/rel/hls/bin/hls-fabric" emit --kind boundary --config "$2" --output "$3"
"$project_root/_build/default/rel/hls/bin/compile-source-build" "$1" "$3"
