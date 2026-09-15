#!/usr/bin/env bash
set -euo pipefail
xls_root=${1:?usage: test_integer_arithmetic.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/integer-arithmetic"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
erl -noshell -pa _build/test/lib/erl_hls/ebin _build/test/lib/erl_hls/test \
    -eval 'ok = xls_integer_dslx:write(hd(init:get_plain_arguments())), halt().' -extra "$stage"
options=(--warnings_as_errors=false --dslx_path="$project_root/priv/xls/lib"
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib")
for width in 8 16 32 64; do
    for sign in u s; do
        prefix="$stage/$sign$width"
        "$xls_root/interpreter_main" --compare=jit "${options[@]}" "$prefix.x"
        "$xls_root/ir_converter_main" --top=probe "${options[@]}" "$prefix.x" > "$prefix.ir"
        "$xls_root/opt_main" "$prefix.ir" > "$prefix.opt.ir"
        "$xls_root/codegen_main" --generator=combinational --module_name=integer_probe \
            --use_system_verilog=false "$prefix.opt.ir" > "$prefix.v"
        iverilog -g2012 -s xls_integer_tb -DINTEGER_WIDTH="$width" \
            -DINTEGER_COUNT="$(cat "$prefix.count")" -DINTEGER_VECTORS="\"$prefix.mem\"" \
            -o "$prefix.vvp" test/rtl/xls_integer_tb.sv "$prefix.v"
        vvp "$prefix.vvp" | tee "$prefix.sim.log"
    done
done
