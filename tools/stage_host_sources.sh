#!/usr/bin/env bash
set -euo pipefail

stage=${1:?usage: stage_host_sources.sh STAGE}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
portable_host_sources="$stage/portable_host_sources"
portable_test_sources="$stage/portable_test_sources"

for source_dir in "$portable_host_sources" "$portable_test_sources"; do
    if [[ -e "$source_dir" ]]; then
        echo "source payload already exists: $source_dir" >&2
        exit 1
    fi
done

build_ebins=(
    "$project_root/_build/test/lib/hls_core/ebin"
    "$project_root/_build/test/lib/hls_runtime/ebin"
    "$project_root/_build/test/lib/hls_compile/ebin"
    "$project_root/_build/test/lib/hls_fabric/ebin"
    "$project_root/_build/test/lib/hls_target/ebin"
    "$project_root/_build/test/lib/erl_hls/ebin"
)
erlc_paths=()
for ebin in "${build_ebins[@]}"; do
    if [[ ! -d "$ebin" ]]; then
        echo "missing test-profile application: $ebin" >&2
        exit 1
    fi
    erlc_paths+=(-pa "$ebin")
done

cd "$project_root"
host_sources=$(python3 tools/portable_host_sources.py)
mkdir -p "$portable_host_sources" "$portable_test_sources"
while IFS= read -r source; do
    erlc "${erlc_paths[@]}" \
        -I apps/hls_compile/include -P -o "$portable_host_sources" "$source"
    module=$(basename "$source" .erl)
    cp "$portable_host_sources/$module.P" "$portable_host_sources/$module.erl"
done <<< "$host_sources"

erlc "${erlc_paths[@]}" -P -o "$portable_test_sources" \
    apps/erl_hls/test/regsvc_cpu_tests.erl
cp "$portable_test_sources/regsvc_cpu_tests.P" \
    "$portable_test_sources/regsvc_cpu_tests.erl"
