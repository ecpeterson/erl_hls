#!/usr/bin/env bash
set -euo pipefail
xls_root=${1:?usage: test_names.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/names"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
erl -noshell -pa _build/test/lib/erl_hls/ebin _build/test/lib/erl_hls/test \
    -eval '[Stage] = init:get_plain_arguments(), ok = xls_names_dslx:write(Stage),
        ok = file:write_file(filename:join(Stage, "unused.x"), xls_short_circuit_dslx:to_dslx()), halt().' -extra "$stage"
# Keep intentionally unused source bindings warning-free after renaming.
"$xls_root/interpreter_main" --warnings_as_errors=true --compare=jit \
    --dslx_path="$project_root/priv/xls/lib" \
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" "$stage/unused.x"
options=(--warnings_as_errors=false --dslx_path="$project_root/priv/xls/lib"
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib")
for kind in names gs; do
    "$xls_root/interpreter_main" --compare=jit "${options[@]}" "$stage/$kind.x"
    "$xls_root/ir_converter_main" --top=probe "${options[@]}" "$stage/$kind.x" > "$stage/$kind.ir"
    "$xls_root/opt_main" "$stage/$kind.ir" > "$stage/$kind.opt.ir"
done
for kind in ordinary gs; do
    "$xls_root/ir_converter_main" --top=Service "${options[@]}" "$stage/$kind.x" > "$stage/$kind.service.ir"
done
"$xls_root/codegen_main" --generator=combinational --module_name=probe \
    --use_system_verilog=false "$stage/names.opt.ir" > "$stage/names.v"
iverilog -g2012 -s names_tb -o "$stage/names.vvp" "$stage/names.v" "$stage/names_tb.sv"
vvp "$stage/names.vvp" | tee "$stage/names.sim.log"
