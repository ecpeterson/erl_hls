#!/usr/bin/env bash
# Build the selected checkout and emit complete ordinary source activation functions.
set -euo pipefail
if [[ $# != 3 ]]; then
    echo 'Usage: bash tools/emit_local_actor.sh SOURCE OPTIONS FRESH_OUTPUT.x' >&2
    exit 2
fi
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_root"
rebar3 compile
export ERL_AFLAGS="-pa \"$project_root/_build/default/lib/hls_fabric/ebin\" -pa \"$project_root/_build/default/checkouts/erl_hls/ebin\""
escript tools/emit_local_actor.escript "$@"
