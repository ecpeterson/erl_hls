#!/usr/bin/env bash
set -euo pipefail
xls_root=${1:?usage: test_binary.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/binary"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
erl -noshell -pa _build/test/lib/erl_hls/ebin _build/test/lib/erl_hls/test \
    -eval 'Stage = hd(init:get_plain_arguments()), ok = xls_binary_dslx:write(Stage),
        ok = file:write_file(filename:join(Stage, "packed_samples.x"),
            xls_parse:to_xls("src/examples/packed_samples/packed_samples.erl")), halt().' -extra "$stage"
options=(--warnings_as_errors=false --dslx_path="$project_root/priv/xls/lib:$project_root/priv/xls/debug"
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib")
"$xls_root/interpreter_main" --compare=jit "${options[@]}" "$project_root/priv/xls/lib/hls_bits.x"
for pair in binary:probe binary_codecs:codec_probe; do
    name=${pair%:*}; top=${pair#*:}
    "$xls_root/interpreter_main" --compare=jit "${options[@]}" "$stage/$name.x"
    "$xls_root/ir_converter_main" --top="$top" "${options[@]}" "$stage/$name.x" > "$stage/$name.ir"
    "$xls_root/opt_main" "$stage/$name.ir" > "$stage/$name.opt.ir"
    "$xls_root/codegen_main" --generator=combinational --module_name="$top" \
        --use_system_verilog=false "$stage/$name.opt.ir" > "$stage/$name.v"
    iverilog -g2012 -s "${name}_tb" -o "$stage/$name.vvp" "$stage/$name.v" "$stage/${name}_tb.sv"
    vvp "$stage/$name.vvp" | tee "$stage/$name.sim.log"
done
"$xls_root/ir_converter_main" --top=wire_probe "${options[@]}" "$stage/binary.x" > "$stage/wires.ir"
"$xls_root/opt_main" "$stage/wires.ir" > "$stage/wires.opt.ir"
"$xls_root/codegen_main" --generator=combinational --module_name=wire_probe \
    --use_system_verilog=false "$stage/wires.opt.ir" > "$stage/wires.v"
yosys=${ERL_HLS_YOSYS:-yosys}
"$yosys" -Q -q -p "read_verilog $stage/wires.v; hierarchy -top wire_probe; proc; opt; check -assert; select -assert-none t:*"
echo "PASS: fixed bit-syntax extraction and rearrangement synthesize to wires only"

# Keep the observer at one observation per cycle, as in production. The
# independently queried server can use the slower two-cycle initiation interval.
for pair in packed_samples:Top hls_debug_observer:Observer hls_debug_server:DebugServer; do
    name=${pair%:*}; top=${pair#*:}
    if [[ "$name" != packed_samples ]]; then cp "$project_root/priv/xls/debug/$name.x" "$stage/$name.x"; fi
    "$xls_root/ir_converter_main" --top="$top" "${options[@]}" "$stage/$name.x" > "$stage/$name.ir"
    "$xls_root/opt_main" "$stage/$name.ir" > "$stage/$name.opt.ir"
    stages=3; interval=2
    if [[ "$name" == hls_debug_observer ]]; then stages=2; interval=1; fi
    "$xls_root/codegen_main" --pipeline_stages="$stages" --worst_case_throughput="$interval" \
        --delay_model=unit --use_system_verilog=false --reset=reset --fifo_module= \
        "$stage/$name.opt.ir" > "$stage/$name.v"
done
bash tools/check_rtl_structure.sh __packed_samples__Top_0_next "$stage/service-check" "$stage/packed_samples.v"
python3 tools/test_packed_samples.py "$stage" --stage "$stage/live"
