#!/usr/bin/env bash
set -euo pipefail
xls_root=${1:?usage: test_type_shapes.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/type-shapes"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
erl -noshell -pa _build/test/lib/erl_hls/ebin _build/test/lib/erl_hls/test \
    -eval 'ok = xls_type_shape_dslx:write(hd(init:get_plain_arguments())), halt().' -extra "$stage"
options=(--warnings_as_errors=false --dslx_path="$project_root/priv/xls/lib"
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib")
"$xls_root/interpreter_main" --compare=jit "${options[@]}" "$stage/shape.x"
"$xls_root/ir_converter_main" --top=probe "${options[@]}" "$stage/shape.x" > "$stage/shape.ir"
"$xls_root/opt_main" "$stage/shape.ir" > "$stage/shape.opt.ir"
"$xls_root/codegen_main" --generator=combinational --module_name=probe \
    --use_system_verilog=false "$stage/shape.opt.ir" > "$stage/shape.v"
iverilog -g2012 -s shape_tb -o "$stage/shape.vvp" "$stage/shape.v" "$stage/shape_tb.sv"
vvp "$stage/shape.vvp" | tee "$stage/shape.sim.log"
if "$xls_root/ir_converter_main" --top=Service "${options[@]}" "$stage/shape_mismatch.x" \
        > "$stage/shape_mismatch.ir" 2> "$stage/shape_mismatch.log"; then
    echo "XLS accepted a source/DSLX vector shape mismatch" >&2; exit 1
fi
if ! rg -q 'const_assert! failure' "$stage/shape_mismatch.log"; then
    cat "$stage/shape_mismatch.log" >&2; exit 1
fi
echo "PASS: source/DSLX shape mismatch fails the compile-time routing assertion"
