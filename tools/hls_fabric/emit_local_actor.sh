#!/usr/bin/env bash
# Build the selected checkout and emit complete ordinary source activation functions.
set -euo pipefail
if [[ $# != 3 ]]; then
    echo 'Usage: bash tools/hls_fabric/emit_local_actor.sh SOURCE OPTIONS FRESH_OUTPUT.x' >&2
    exit 2
fi
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$project_root"
rebar3 compile
source "$project_root/tools/hls_fabric/backend_env.sh" default
escript tools/hls_fabric/emit_local_actor.escript "$@"
