#!/usr/bin/env bash
# Compile the selected backend and emit a framed source partition from a trusted build config.
set -euo pipefail
if [[ $# != 3 ]]; then
    echo 'Usage: bash tools/emit_protocol_bridge.sh XLS_ROOT CONFIG FRESH_OUTPUT' >&2
    exit 2
fi
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_root"
rebar3 compile
export ERL_AFLAGS="-pa \"$project_root/_build/default/lib/hls_fabric/ebin\" -pa \"$project_root/_build/default/checkouts/erl_hls/ebin\""
escript tools/emit_protocol_bridge.escript "$2" "$3"
python3 tools/compile_protocol_bridge.py "$1" "$3"
