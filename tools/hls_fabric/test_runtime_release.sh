#!/usr/bin/env bash
# Audit and execute one already assembled runtime-only release.
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
release=${1:-_build/default/rel/hls_runtime}
case "$release" in
    /*) ;;
    *) release="$project_root/$release" ;;
esac
if [[ ! -x "$release/bin/hls_runtime" ]]; then
    printf 'missing runtime release launcher: %s\n' "$release/bin/hls_runtime" >&2
    exit 2
fi

cd "$project_root"
python3 tools/hls_fabric/check_package_boundaries.py \
    --runtime hls_core --runtime hls_runtime --release "$release"
HLS_RUNTIME_RELEASE="$release" rebar3 eunit -m hls_fabric_runtime_package_tests
