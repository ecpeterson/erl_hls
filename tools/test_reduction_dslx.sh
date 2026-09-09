#!/usr/bin/env bash
set -euo pipefail

xls_root=${1:?usage: test_reduction_dslx.sh XLS_ROOT}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_stage=$(mktemp -d "${TMPDIR:-/tmp}/erl-hls-reduction.XXXXXX")
trap 'rm -rf -- "$test_stage"' EXIT

cd "$project_root"
rebar3 as test compile >/dev/null

generated="$test_stage/hls_statem_reduction_lower_fixture.x"
aggregate_generated="$test_stage/hls_statem_reduction_aggregate_fixture.x"
fragment_topology="$test_stage/hls_topology_source_fragment_topology.x"
fragment_sharded="$test_stage/hls_topology_source_fragment_sharded.x"
fragment_muxed="$test_stage/hls_topology_source_fragment_muxed.x"
fragment_population="$test_stage/hls_topology_source_fragment_population.x"
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

ERL_HLS_REDUCTION_TEST_X="$aggregate_generated" erl \
    -noshell \
    -pa "$project_root/_build/test/lib/erl_hls/ebin" \
    -eval '
        X = xls_parse:to_xls(
            "test_data/hls_statem_reduction_lower_fixture.erl",
            #{shared_service => aggregate_only}
        ),
        ok = file:write_file(os:getenv("ERL_HLS_REDUCTION_TEST_X"), X),
        halt().
    '

ERL_HLS_FRAGMENT_STAGE="$test_stage" erl \
    -noshell \
    -pa "$project_root/_build/test/lib/erl_hls/ebin" \
    -pa "$project_root/_build/test/lib/erl_hls/test" \
    -eval '
        ok = hls_topology_source_fragment_smoke_fixture:write(
            os:getenv("ERL_HLS_FRAGMENT_STAGE")
        ),
        halt().
    '

cat "$project_root/test_data/hls_statem_reduction_semantics.inc.x" \
    >> "$generated"
cat "$project_root/test_data/hls_statem_reduction_aggregate_semantics.inc.x" \
    >> "$aggregate_generated"
cat "$project_root/test_data/hls_topology_source_fragment_semantics.inc.x" \
    >> "$fragment_topology"
cat "$project_root/test_data/hls_topology_source_fragment_population_semantics.inc.x" \
    >> "$fragment_population"

"$xls_root/interpreter_main" \
    --compare=jit \
    --warnings_as_errors=false \
    --dslx_path="$project_root/priv/xls/lib" \
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" \
    "$generated"

"$xls_root/interpreter_main" \
    --compare=jit \
    --warnings_as_errors=false \
    --dslx_path="$project_root/priv/xls/lib" \
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" \
    "$aggregate_generated"

"$xls_root/interpreter_main" \
    --compare=jit \
    --warnings_as_errors=false \
    --dslx_path="$test_stage:$project_root/priv/xls/lib" \
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" \
    "$fragment_topology"

"$xls_root/interpreter_main" \
    --compare=jit \
    --warnings_as_errors=false \
    --dslx_path="$test_stage:$project_root/priv/xls/lib" \
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" \
    "$fragment_population"

"$xls_root/ir_converter_main" \
    --top=ReductionSharedCompileTop \
    --warnings_as_errors=false \
    --dslx_path="$project_root/priv/xls/lib" \
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" \
    "$generated" \
    >/dev/null

"$xls_root/ir_converter_main" \
    --top=ReductionAggregateSharedCompileTop \
    --warnings_as_errors=false \
    --dslx_path="$project_root/priv/xls/lib" \
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" \
    "$aggregate_generated" \
    >/dev/null

"$xls_root/ir_converter_main" \
    --top=SchedulerGrid \
    --warnings_as_errors=false \
    --dslx_path="$test_stage:$project_root/priv/xls/lib" \
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" \
    "$fragment_sharded" \
    >/dev/null

"$xls_root/ir_converter_main" \
    --top=SchedulerGrid \
    --warnings_as_errors=false \
    --dslx_path="$test_stage:$project_root/priv/xls/lib" \
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" \
    "$fragment_muxed" \
    >/dev/null

"$xls_root/ir_converter_main" \
    --top=SchedulerGrid \
    --warnings_as_errors=false \
    --dslx_path="$test_stage:$project_root/priv/xls/lib" \
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" \
    "$fragment_population" \
    >/dev/null
