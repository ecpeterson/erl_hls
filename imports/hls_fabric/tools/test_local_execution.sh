#!/usr/bin/env bash
# Exercise the generated activation functions without a RAM service or topology.
set -euo pipefail
xls_root=${1:?usage: test_local_execution.sh XLS_ROOT [FRESH_STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/local-execution"}
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
source tools/backend_env.sh test
erl -noshell -eval '[Stage, Compiler] = init:get_plain_arguments(), ok = xls_local_execution_validation:prepare(Stage, Compiler), halt().' -extra "$stage" "$erl_hls_root"
options=(--warnings_as_errors=false --dslx_path="$project_root/apps/hls_lowering/priv/xls/lib:$project_root/apps/hls_lowering/priv/xls/fabric:$erl_hls_root/priv/xls/lib:$erl_hls_root/priv/xls/fabric"
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib")
for name in base_test arithmetic_test guard_test phase_test projected; do
    "$xls_root/interpreter_main" --evaluator=dslx-interpreter --compare=none --max_ticks=1000 "${options[@]}" "$stage/$name.x"
done
# Type-check the completion/continuation variants through the new exported boundary.
for name in base projected reduction gather; do
    "$xls_root/ir_converter_main" --top=local_step_at "${options[@]}" "$stage/$name.x" > "$stage/$name.ir"
done
