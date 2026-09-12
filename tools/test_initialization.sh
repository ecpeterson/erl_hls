#!/usr/bin/env bash
set -euo pipefail
xls_root=${1:?usage: test_initialization.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/initialization"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
erl -noshell -pa "$project_root/_build/test/lib/erl_hls/ebin" \
    "$project_root/_build/test/lib/erl_hls/test" \
    -eval 'ok = xls_init_dslx:write(hd(init:get_plain_arguments())), halt().' \
    -extra "$stage"
options=(--warnings_as_errors=false --dslx_path="$stage:$project_root/priv/xls/lib:$project_root/priv/xls/fabric"
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib")
for kind in gs statem; do
    "$xls_root/interpreter_main" --compare=jit "${options[@]}" "$stage/init_$kind.x"
    # Rejection must happen even when the selected function/proc never calls
    # the initializer (as for a shared scheduler's proc init() state).
    if "$xls_root/ir_converter_main" --top=bits_from_report "${options[@]}" \
            "$stage/bad_$kind.x" > "$stage/bad_$kind.ir" 2> "$stage/bad_$kind.log"; then
        echo "failing $kind initializer was accepted" >&2; exit 1
    fi
    if ! grep -q 'const_assert! failure.*INITIAL_' "$stage/bad_$kind.log"; then
        cat "$stage/bad_$kind.log" >&2; exit 1
    fi
done
for fixture in gs direct shared; do
    top=Top
    [[ "$fixture" != gs ]] || top=FrameTop
    "$xls_root/ir_converter_main" --top="$top" "${options[@]}" \
        "$stage/init_$fixture.x" > "$stage/init_$fixture.ir"
    "$xls_root/opt_main" "$stage/init_$fixture.ir" > "$stage/init_$fixture.opt.ir"
    rams=
    schedules=(1 2)
    if [[ "$fixture" == shared ]]; then
        source tools/phi_scheduler_rams.sh
        rams=$(phi_scheduler_ram_configurations 1)
        # The fixed-latency RAM channel constraints require at least two stages.
        schedules=(2 3)
    fi
    for stages in "${schedules[@]}"; do
        rtl="$stage/init_${fixture}_${stages}.v"
        "$xls_root/codegen_main" --pipeline_stages="$stages" \
            --delay_model=unit --flop_inputs=false --flop_outputs=true \
            --use_system_verilog=false --reset=reset --fifo_module= \
            --module_name="init_$fixture" --ram_configurations="$rams" \
            "$stage/init_$fixture.opt.ir" > "$rtl"
        sources=("$rtl")
        if [[ "$fixture" == gs ]]; then
            bench=xls_init_gs_tb
        else
            bench=xls_init_topology_tb
            top="init_${fixture}_wrapper"
            sources+=("$stage/${top}.v" priv/rtl/hls_1r1w_ram.v)
        fi
        iverilog -g2012 -I "$stage" -DINIT_TOP="$top" -s "$bench" \
            -o "$stage/init_${fixture}_${stages}.vvp" \
            "test/rtl/$bench.sv" "${sources[@]}"
        vvp "$stage/init_${fixture}_${stages}.vvp"
    done
done
