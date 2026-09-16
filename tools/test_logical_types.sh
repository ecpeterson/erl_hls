#!/usr/bin/env bash
set -euo pipefail
xls_root=${1:?usage: test_logical_types.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/logical-types"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
erl -noshell -pa _build/test/lib/erl_hls/ebin _build/test/lib/erl_hls/test \
    -eval 'Stage = hd(init:get_plain_arguments()), ok = hls_logical_dslx:write(Stage),
        ok = hls_dense_topology_dslx:write(Stage), halt().' -extra "$stage"
options=(--warnings_as_errors=false --dslx_path="$project_root/priv/xls/lib"
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib")
"$xls_root/interpreter_main" --compare=jit "${options[@]}" "$stage/codecs.x"
"$xls_root/ir_converter_main" --top=probe "${options[@]}" "$stage/codecs.x" > "$stage/codecs.ir"
"$xls_root/opt_main" "$stage/codecs.ir" > "$stage/codecs.opt.ir"
"$xls_root/codegen_main" --generator=combinational --module_name=probe \
    --use_system_verilog=false "$stage/codecs.opt.ir" > "$stage/codecs.v"
iverilog -g2012 -s logical_codecs_tb -o "$stage/codecs.vvp" \
    "$stage/codecs.v" test/rtl/logical_codecs_tb.sv
vvp "$stage/codecs.vvp" +vectors="$stage/codecs.mem"
# A fixed endian permutation and physical padding must become wires only.
"$xls_root/ir_converter_main" --top=wire_probe "${options[@]}" "$stage/codecs.x" > "$stage/wires.ir"
"$xls_root/opt_main" "$stage/wires.ir" > "$stage/wires.opt.ir"
"$xls_root/codegen_main" --generator=combinational --module_name=wire_probe \
    --use_system_verilog=false "$stage/wires.opt.ir" > "$stage/wires.v"
yosys=${ERL_HLS_YOSYS:-yosys}
"$yosys" -Q -q -p "read_verilog $stage/wires.v; hierarchy -top wire_probe; proc; opt; check -assert; select -assert-none t:*"
echo "PASS: dense bit permutation and padding synthesize to wires only"
cp priv/xls/lib/*.x "$stage/"
for schedule in 1:1 2:1 3:2; do
    stages=${schedule%:*}; interval=${schedule#*:}
    prefix="$stage/p$stages-ii$interval"
    python3 tools/compile_xls.py "$stage/service.x" "$xls_root" --output "$prefix" \
        --top Top --name logical_service --pipeline-stages "$stages" \
        --initiation-interval "$interval"
    bash tools/check_rtl_structure.sh __service__Top_0_next "$prefix-check" "$prefix/logical_service.v"
    iverilog -g2012 -s logical_service_tb -o "$prefix.vvp" \
        test/rtl/logical_service_tb.sv "$prefix/logical_service.v"
    vvp "$prefix.vvp" +requests="$stage/requests.mem" +replies="$stage/replies.mem"
done

cp priv/xls/fabric/*.x "$stage/"
source tools/phi_scheduler_rams.sh
for fixture in direct shared; do
    rams=(--pipeline-stages 2)
    [[ "$fixture" != shared ]] || rams+=(--ram-configurations "$(phi_scheduler_ram_configurations 1)")
    prefix="$stage/dense_$fixture"
    python3 tools/compile_xls.py "$prefix.x" "$xls_root" --output "$prefix-build" \
        --top Top --name "dense_$fixture" \
        "${rams[@]}"
    bash tools/check_rtl_structure.sh "dense_${fixture}_wrapper" "$prefix-check" \
        "$prefix-build/dense_$fixture.v" "${prefix}_wrapper.v" priv/rtl/hls_1r1w_ram.v
    iverilog -g2012 -I "$stage" -DDENSE_TOP="dense_${fixture}_wrapper" \
        -s logical_topology_tb -o "$prefix.vvp" test/rtl/logical_topology_tb.sv \
        "$prefix-build/dense_$fixture.v" "${prefix}_wrapper.v" priv/rtl/hls_1r1w_ram.v
    vvp "$prefix.vvp"
done
