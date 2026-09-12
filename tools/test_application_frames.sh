#!/usr/bin/env bash
set -euo pipefail
xls_root=${1:?usage: test_application_frames.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/application_frames"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
options=(--warnings_as_errors=false
    --dslx_path="$project_root/priv/xls/lib:$project_root/priv/xls/fabric"
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib")
"$xls_root/interpreter_main" --compare=jit "${options[@]}" priv/xls/lib/axis.x
for top in RawTop ReservedTop PairTop EndpointTop DebugTop; do
    "$xls_root/ir_converter_main" --top="$top" "${options[@]}" \
        test_data/application_frames_rtl.x > "$stage/$top.ir"
    "$xls_root/opt_main" "$stage/$top.ir" > "$stage/$top.opt.ir"
    defines=(-g2012)
    case "$top" in
        ReservedTop) defines+=(-DRESERVED);;
        PairTop) defines+=(-DROUTED -DPAIR);;
        EndpointTop) defines+=(-DROUTED);;
    esac
    for schedule in 1:1 2:1 3:2; do
        stages=${schedule%:*}; interval=${schedule#*:}
        prefix="$stage/$top-p$stages-ii$interval"
        "$xls_root/codegen_main" --pipeline_stages="$stages" \
            --worst_case_throughput="$interval" --delay_model=unit \
            --flop_inputs=false --flop_outputs=true --use_system_verilog=false \
            --module_name=application_frames --reset=reset --fifo_module= \
            "$stage/$top.opt.ir" > "$prefix.v"
        bash tools/check_rtl_structure.sh application_frames "$prefix-check" "$prefix.v"
        if [[ "$top" != DebugTop ]]; then
            iverilog "${defines[@]}" -s application_frames_tb \
                -o "$prefix.vvp" test/rtl/application_frames_tb.sv "$prefix.v"
            vvp "$prefix.vvp" | tee "$prefix.sim.log"
        fi
    done
done

rebar3 as test compile
erl -noshell -pa _build/test/lib/erl_hls/ebin _build/test/lib/erl_hls/test \
    -eval 'ok = file:write_file(hd(init:get_plain_arguments()), xls_parse:to_xls("test/xls_init_gs_fixture.erl")), halt().' \
    -extra "$stage/application_service.x"
"$xls_root/ir_converter_main" --top=Top "${options[@]}" \
    "$stage/application_service.x" > "$stage/application_service.ir"
"$xls_root/opt_main" "$stage/application_service.ir" > "$stage/application_service.opt.ir"
for schedule in 1:1 2:1 3:2; do
    stages=${schedule%:*}; interval=${schedule#*:}
    prefix="$stage/service-p$stages-ii$interval"
    "$xls_root/codegen_main" --pipeline_stages="$stages" \
        --worst_case_throughput="$interval" --delay_model=unit \
        --flop_inputs=false --flop_outputs=true --use_system_verilog=false \
        --module_name=application_service --reset=reset --fifo_module= \
        "$stage/application_service.opt.ir" > "$prefix.v"
    bash tools/check_rtl_structure.sh application_service "$prefix-check" "$prefix.v"
    iverilog -g2012 -s application_service_tb -o "$prefix.vvp" \
        test/rtl/application_service_tb.sv "$prefix.v"
    vvp "$prefix.vvp" | tee "$prefix.sim.log"
done
