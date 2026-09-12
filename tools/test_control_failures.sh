#!/usr/bin/env bash
set -euo pipefail
xls_root=${1:?usage: test_control_failures.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/control_failures"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
erl -noshell -pa _build/test/lib/erl_hls/ebin _build/test/lib/erl_hls/test \
    -eval 'ok = xls_control_failure_dslx:write(hd(init:get_plain_arguments())), halt().' \
    -extra "$stage"
options=(--warnings_as_errors=false --dslx_path="$project_root/priv/xls/lib"
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib")
"$xls_root/interpreter_main" --compare=jit "${options[@]}" "$stage/control.x"
for kind in case if; do
    if "$xls_root/ir_converter_main" --top=bits_from_report "${options[@]}" \
            "$stage/bad_${kind}_init.x" > "$stage/bad_${kind}_init.ir" 2> "$stage/bad_${kind}_init.log"; then
        echo "nonexhaustive $kind initializer was accepted" >&2; exit 1
    fi
    if ! grep -q 'const_assert! failure.*INITIAL_' "$stage/bad_${kind}_init.log"; then
        cat "$stage/bad_${kind}_init.log" >&2; exit 1
    fi
    echo "PASS: $kind failure rejects constant initialization"
done
for top in control_probe Top; do
    "$xls_root/ir_converter_main" --top="$top" "${options[@]}" \
        "$stage/control.x" > "$stage/$top.ir"
    "$xls_root/opt_main" "$stage/$top.ir" > "$stage/$top.opt.ir"
done
"$xls_root/codegen_main" --generator=combinational --module_name=control_probe \
    --use_system_verilog=false "$stage/control_probe.opt.ir" > "$stage/control_probe.v"
for schedule in 1:1 2:1 3:2; do
    stages=${schedule%:*}; interval=${schedule#*:}
    prefix="$stage/service-p$stages-ii$interval"
    "$xls_root/codegen_main" --pipeline_stages="$stages" \
        --worst_case_throughput="$interval" --delay_model=unit \
        --flop_inputs=false --flop_outputs=true --use_system_verilog=false \
        --module_name=control_service --reset=reset --fifo_module= \
        "$stage/Top.opt.ir" > "$prefix.v"
    bash tools/check_rtl_structure.sh control_service "$prefix-check" "$prefix.v"
    iverilog -g2012 -I "$stage" -s xls_control_failure_tb -o "$prefix.vvp" \
        test/rtl/xls_control_failure_tb.sv "$stage/control_probe.v" "$prefix.v"
    vvp "$prefix.vvp" | tee "$prefix.sim.log"
done
