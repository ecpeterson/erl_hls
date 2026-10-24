#!/usr/bin/env bash
# Compile the selected backend and emit network hardware from a trusted build config.
set -euo pipefail
if [[ $# != 3 ]]; then
    echo 'Usage: bash tools/emit_protocol_network.sh XLS_ROOT CONFIG FRESH_OUTPUT' >&2
    exit 2
fi
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_root"
rebar3 compile
source "$project_root/tools/backend_env.sh" default
escript tools/emit_protocol_network.escript "$2" "$3"
python3 tools/compile_protocol_network.py "$1" "$3"
