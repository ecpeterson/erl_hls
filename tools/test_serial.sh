#!/usr/bin/env bash
# Compare wrapping counters with BEAM at scalar and framed actor boundaries.
set -euo pipefail
xls_root=${1:?usage: test_serial.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/serial"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
erl -noshell -pa _build/test/lib/erl_hls/ebin _build/test/lib/erl_hls/test \
    -eval 'ok = hls_serial_dslx:write(hd(init:get_plain_arguments())), halt().' -extra "$stage"
options=(--warnings_as_errors=false --dslx_path="$project_root/priv/xls/lib"
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib")
for width in 1 3 8 9 32 64 65; do
    prefix="$stage/serial$width"
    "$xls_root/interpreter_main" --compare=jit "${options[@]}" "$prefix.x"
    "$xls_root/ir_converter_main" --top=probe "${options[@]}" "$prefix.x" > "$prefix.ir"
    "$xls_root/opt_main" "$prefix.ir" > "$prefix.opt.ir"
    "$xls_root/codegen_main" --generator=combinational --module_name=serial_probe \
        --use_system_verilog=false "$prefix.opt.ir" > "$prefix.v"
    iverilog -g2012 -s hls_serial_tb -DSERIAL_WIDTH="$width" \
        -DSERIAL_COUNT="$(cat "$prefix.count")" -DSERIAL_VECTORS="\"$prefix.mem\"" \
        -o "$prefix.vvp" test/rtl/hls_serial_tb.sv "$prefix.v"
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
