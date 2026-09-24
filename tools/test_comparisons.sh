#!/usr/bin/env bash
# Check mixed integer comparisons against BEAM through XLS and optimized RTL.
set -euo pipefail
xls_root=${1:?usage: test_comparisons.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/comparisons"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
erl -noshell -pa _build/test/lib/erl_hls/ebin _build/test/lib/erl_hls/test \
    -eval 'ok = xls_comparison_dslx:write(hd(init:get_plain_arguments())), halt().' -extra "$stage"
options=(--warnings_as_errors=false --dslx_path="$project_root/priv/xls/lib"
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib")
for pair in 1_1 3_8 8_8 8_9 32_8 64_32 65_64 128_65; do
    width=${pair%_*}
    other=${pair#*_}
    prefix="$stage/cmp_$pair"
    "$xls_root/interpreter_main" --compare=jit "${options[@]}" "$prefix.x"
    "$xls_root/ir_converter_main" --top=probe "${options[@]}" "$prefix.x" > "$prefix.ir"
    "$xls_root/opt_main" "$prefix.ir" > "$prefix.opt.ir"
    "$xls_root/codegen_main" --generator=combinational --module_name=comparison_probe \
        --use_system_verilog=false "$prefix.opt.ir" > "$prefix.v"
    iverilog -g2012 -s xls_comparison_tb -DLEFT_WIDTH="$width" -DRIGHT_WIDTH="$other" \
        -DCOMPARISON_COUNT="$(cat "$prefix.count")" -DCOMPARISON_VECTORS="\"$prefix.mem\"" \
        -o "$prefix.vvp" test/rtl/xls_comparison_tb.sv "$prefix.v"
    vvp "$prefix.vvp" | tee "$prefix.sim.log"
done

"$xls_root/ir_converter_main" --top=Top "${options[@]}" "$stage/service.x" > "$stage/service.ir"
"$xls_root/opt_main" "$stage/service.ir" > "$stage/service.opt.ir"
"$xls_root/codegen_main" --pipeline_stages=2 --delay_model=unit --reset=reset \
    --flop_inputs=false --flop_outputs=true --use_system_verilog=false --fifo_module= \
    "$stage/service.opt.ir" > "$stage/service.v"
iverilog -g2012 -s logical_service_tb -o "$stage/service.vvp" \
    test/rtl/logical_service_tb.sv "$stage/service.v"
vvp "$stage/service.vvp" +requests="$stage/requests.mem" +replies="$stage/replies.mem" \
    | tee "$stage/service.sim.log"
