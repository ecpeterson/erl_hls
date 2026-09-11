#!/usr/bin/env bash
set -euo pipefail

xls_root=${1:?usage: test_effect_window.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/effect_window"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
stdlib="$xls_root/xls/dslx/stdlib"

"$xls_root/interpreter_main" --compare=jit --warnings_as_errors=false \
    --dslx_path="$project_root/priv/xls/lib" --dslx_stdlib_path="$stdlib" \
    "$project_root/priv/xls/lib/effect_window.x"

for top in ArbiterTop ReturnTop; do
    "$xls_root/ir_converter_main" --top="$top" --warnings_as_errors=false \
        --dslx_path="$project_root/priv/xls/lib" --dslx_stdlib_path="$stdlib" \
        "$project_root/test_data/effect_window_rtl.x" > "$stage/$top.ir"
    "$xls_root/opt_main" "$stage/$top.ir" > "$stage/$top.opt.ir"
    if [[ "$top" == ArbiterTop ]]; then
        testbench=effect_window_tb
    else
        testbench=effect_window_return_tb
    fi
    for schedule in 1:1 2:1 2:2 3:2; do
        stages=${schedule%:*}
        interval=${schedule#*:}
        prefix="$stage/$top-p$stages-ii$interval"
        "$xls_root/codegen_main" --pipeline_stages="$stages" \
            --worst_case_throughput="$interval" --delay_model=unit \
            --flop_inputs=false --flop_outputs=true --use_system_verilog=false \
            --reset=reset --fifo_module= "$stage/$top.opt.ir" > "$prefix.v"
        bash "$project_root/tools/check_rtl_structure.sh" \
            "__effect_window_rtl__${top}_0_next" "$prefix-check" "$prefix.v"
        iverilog -g2012 -s "$testbench" -o "$prefix.vvp" \
            "$project_root/test/rtl/$testbench.sv" "$prefix.v"
        timeout 60s vvp "$prefix.vvp" | tee "$prefix.sim.log"
    done
done
