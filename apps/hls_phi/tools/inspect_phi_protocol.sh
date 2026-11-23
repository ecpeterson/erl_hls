#!/usr/bin/env bash
# Inspect actual Phi/repetition sources with one freshly compiled default backend.
set -euo pipefail
if [[ $# != 1 ]]; then
    echo 'Usage: bash apps/hls_phi/tools/inspect_phi_protocol.sh FRESH_OUTPUT' >&2
    exit 2
fi
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
cd "$project_root"
rebar3 compile
# Do not select a stale test-profile build merely because it exists.
source "$project_root/tools/hls_fabric/backend_env.sh" default
exec escript apps/hls_phi/tools/inspect_phi_protocol.escript "$project_root/apps/hls_phi" "$1"
