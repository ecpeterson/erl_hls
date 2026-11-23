#!/usr/bin/env bash
# Build one fresh source application with its exact host binding and shared gateway.
set -euo pipefail
if [[ $# != 3 ]]; then
    echo 'Usage: bash tools/emit_protocol_application.sh XLS_ROOT CONFIG FRESH_OUTPUT' >&2
    exit 2
fi
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_root"
rebar3 release -n hls
"$project_root/_build/default/rel/hls/bin/hls-fabric" emit --kind application --config "$2" --output "$3"
"$project_root/_build/default/rel/hls/bin/compile-source-build" "$1" "$3"
