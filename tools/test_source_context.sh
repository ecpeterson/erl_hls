#!/usr/bin/env bash
set -euo pipefail
xls_root=${1:?usage: test_source_context.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/source_context"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
erl -noshell -pa "$project_root/_build/test/lib/erl_hls/ebin" \
    "$project_root/_build/test/lib/erl_hls/test" \
    -eval 'ok = hls_source_dslx:write(hd(init:get_plain_arguments())), halt().' \
    -extra "$stage"
for configuration in narrow wide; do
    "$xls_root/interpreter_main" --compare=jit --warnings_as_errors=false \
        --dslx_path="$project_root/priv/xls/lib" \
        --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" \
        "$stage/source_$configuration.x"
done
