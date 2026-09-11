#!/usr/bin/env bash
set -euo pipefail

xls_root=${1:?usage: test_entry_outcomes.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/entry_outcomes"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)

cd "$project_root"
rebar3 as test compile
ERL_HLS_ENTRY_STAGE="$stage" erl -noshell \
    -pa "$project_root/_build/test/lib/erl_hls/ebin" \
    -pa "$project_root/_build/test/lib/erl_hls/test" \
    -eval 'ok = xls_entry_outcome_dslx:write(os:getenv("ERL_HLS_ENTRY_STAGE")), halt().'

for fixture in xls_entry_outcome xls_entry_reduction xls_entry_reduction_aggregate; do
    "$xls_root/interpreter_main" --compare=jit --warnings_as_errors=false \
        --dslx_path="$project_root/priv/xls/lib" \
        --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" \
        "$stage/$fixture.x"
done

"$xls_root/ir_converter_main" --top=entry_probe --warnings_as_errors=false \
    --dslx_path="$project_root/priv/xls/lib" \
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" \
    "$stage/xls_entry_outcome.x" > "$stage/entry_probe.ir"
"$xls_root/opt_main" "$stage/entry_probe.ir" > "$stage/entry_probe.opt.ir"
"$xls_root/codegen_main" --generator=combinational --module_name=entry_probe \
    --use_system_verilog=false "$stage/entry_probe.opt.ir" > "$stage/entry_probe.v"
iverilog -g2012 -s xls_entry_outcome_tb -o "$stage/entry_probe.vvp" \
    "$stage/xls_entry_outcome_tb.sv" "$stage/entry_probe.v"
vvp "$stage/entry_probe.vvp"
