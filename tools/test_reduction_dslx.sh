#!/usr/bin/env bash
set -euo pipefail

xls_root=${1:?usage: test_reduction_dslx.sh XLS_ROOT}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_stage=$(mktemp -d "${TMPDIR:-/tmp}/erl-hls-reduction.XXXXXX")
trap 'rm -rf -- "$test_stage"' EXIT

cd "$project_root"
rebar3 as test compile >/dev/null

generated="$test_stage/hls_statem_reduction_lower_fixture.x"
ERL_HLS_REDUCTION_TEST_X="$generated" erl \
    -noshell \
    -pa "$project_root/_build/test/lib/erl_hls/ebin" \
    -eval '
        X = xls_parse:to_xls(
            "test_data/hls_statem_reduction_lower_fixture.erl"
        ),
        ok = file:write_file(os:getenv("ERL_HLS_REDUCTION_TEST_X"), X),
        halt().
    '

cat "$project_root/test_data/hls_statem_reduction_semantics.inc.x" \
    >> "$generated"

"$xls_root/interpreter_main" \
    --compare=jit \
    --warnings_as_errors=false \
    --dslx_path="$project_root/priv/xls/lib" \
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" \
    "$generated"

"$xls_root/ir_converter_main" \
    --top=ReductionSharedCompileTop \
    --warnings_as_errors=false \
    --dslx_path="$project_root/priv/xls/lib" \
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" \
    "$generated" \
    >/dev/null
