#!/usr/bin/env bash
set -euo pipefail
xls_root=${1:?usage: test_patterns.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/patterns"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
erl -noshell -pa _build/test/lib/erl_hls/ebin _build/test/lib/erl_hls/test \
    -eval 'ok = xls_patterns_dslx:write(hd(init:get_plain_arguments())), halt().' -extra "$stage"
options=(--warnings_as_errors=false --dslx_path="$project_root/priv/xls/lib"
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib")
"$xls_root/interpreter_main" --compare=jit "${options[@]}" "$project_root/priv/xls/lib/hls_patterns.x"
"$xls_root/interpreter_main" --compare=jit "${options[@]}" "$stage/patterns.x"
"$xls_root/ir_converter_main" --top=probe "${options[@]}" "$stage/patterns.x" > "$stage/patterns.ir"
"$xls_root/opt_main" "$stage/patterns.ir" > "$stage/patterns.opt.ir"
"$xls_root/codegen_main" --generator=combinational --module_name=probe \
    --use_system_verilog=false "$stage/patterns.opt.ir" > "$stage/patterns.v"
iverilog -g2012 -s patterns_tb -o "$stage/patterns.vvp" "$stage/patterns.v" "$stage/patterns_tb.sv"
vvp "$stage/patterns.vvp" | tee "$stage/patterns.sim.log"

for kind in empty_tail overlong_tail; do
    if "$xls_root/ir_converter_main" --top=probe "${options[@]}" "$stage/$kind.x" \
            > "$stage/$kind.ir" 2> "$stage/$kind.log"; then
        echo "XLS accepted $kind" >&2; exit 1
    fi
    if ! grep -q 'const_assert! failure' "$stage/$kind.log"; then
        cat "$stage/$kind.log" >&2; exit 1
    fi
    echo "PASS: XLS rejects $kind"
done

"$xls_root/ir_converter_main" --top=Service "${options[@]}" "$stage/list_reduction.x" \
    > "$stage/list_reduction.ir"
"$xls_root/opt_main" "$stage/list_reduction.ir" > "$stage/list_reduction.opt.ir"
echo "PASS: ordinary reduction with destructured message fields converts and optimizes"
