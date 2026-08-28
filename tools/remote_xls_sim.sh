#!/usr/bin/env bash
set -euo pipefail

stage=$1
xls_root=$2
stdlib="$xls_root/xls/dslx/stdlib"

cd "$stage"

iverilog \
    -g2012 \
    -s xls_trace_store_tb \
    -o xls_trace_store.vvp \
    xls_trace_store_tb.sv \
    xls_trace_store.v

vvp xls_trace_store.vvp

"$xls_root/interpreter_main" \
    --dslx_stdlib_path="$stdlib" \
    xls_debug_monitor.x

"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_stdlib_path="$stdlib" \
    --top=Top \
    regsvc.x > regsvc.ir

"$xls_root/opt_main" regsvc.ir > regsvc.opt.ir

"$xls_root/codegen_main" \
    --pipeline_stages=1 \
    --delay_model=unit \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    regsvc.opt.ir > regsvc.v

"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_stdlib_path="$stdlib" \
    --top=Observer \
    xls_debug_monitor.x > xls_debug_observer.ir

"$xls_root/opt_main" xls_debug_observer.ir > xls_debug_observer.opt.ir

"$xls_root/codegen_main" \
    --pipeline_stages=2 \
    --delay_model=unit \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    xls_debug_observer.opt.ir > xls_debug_observer.v

"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_stdlib_path="$stdlib" \
    --top=DebugServer \
    xls_debug_monitor.x > xls_debug_server.ir

"$xls_root/opt_main" xls_debug_server.ir > xls_debug_server.opt.ir

"$xls_root/codegen_main" \
    --pipeline_stages=3 \
    --worst_case_throughput=2 \
    --delay_model=unit \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    xls_debug_server.opt.ir > xls_debug_server.v

"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_stdlib_path="$stdlib" \
    --top=PairIngress \
    xls_fabric_router.x > xls_fabric_ingress.ir

"$xls_root/opt_main" xls_fabric_ingress.ir > xls_fabric_ingress.opt.ir

"$xls_root/codegen_main" \
    --pipeline_stages=1 \
    --delay_model=unit \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    xls_fabric_ingress.opt.ir > xls_fabric_ingress.v

"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_stdlib_path="$stdlib" \
    --top=PairEgress \
    xls_fabric_router.x > xls_fabric_egress.ir

"$xls_root/opt_main" xls_fabric_egress.ir > xls_fabric_egress.opt.ir

"$xls_root/codegen_main" \
    --pipeline_stages=1 \
    --delay_model=unit \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    xls_fabric_egress.opt.ir > xls_fabric_egress.v

iverilog \
    -g2012 \
    -s regsvc_pair_tb \
    -o regsvc_pair.vvp \
    regsvc_pair_tb.sv \
    regsvc_pair_fixture.sv \
    regsvc_debug_top.v \
    xls_fabric_ingress.v \
    xls_fabric_egress.v \
    xls_debug_tap.v \
    xls_trace_store.v \
    xls_debug_observer.v \
    xls_debug_server.v \
    regsvc_core_adapter.v \
    regsvc.v

vvp regsvc_pair.vvp

iverilog-vpi xls_sim_bridge.c

iverilog \
    -g2012 \
    -s regsvc_bridge_tb \
    -o regsvc_bridge.vvp \
    regsvc_bridge_tb.sv \
    regsvc_pair_fixture.sv \
    regsvc_debug_top.v \
    xls_fabric_ingress.v \
    xls_fabric_egress.v \
    xls_debug_tap.v \
    xls_trace_store.v \
    xls_debug_observer.v \
    xls_debug_server.v \
    regsvc_core_adapter.v \
    regsvc.v

sim_dir="$stage/sim"
mkdir -p "$sim_dir"
rm -f \
    "$sim_dir/app_tx" \
    "$sim_dir/app_rx" \
    "$sim_dir/debug_tx" \
    "$sim_dir/debug_rx" \
    "$sim_dir/vvp.log"

sim_pid=
cleanup() {
    if [[ -n "$sim_pid" ]]; then
        kill "$sim_pid" 2>/dev/null || true
        wait "$sim_pid" 2>/dev/null || true
    fi
}
trap cleanup EXIT

ERL_XLS_SIM_DIR="$sim_dir" \
    vvp -M "$stage" -m xls_sim_bridge regsvc_bridge.vvp \
    >"$sim_dir/vvp.log" 2>&1 &
sim_pid=$!

# The VPI module creates all four FIFOs during start-of-simulation setup. Do
# not start the Erlang clients until those transport endpoints are ready.
for _attempt in $(seq 1 100); do
    if [[ \
        -p "$sim_dir/app_tx" && \
        -p "$sim_dir/app_rx" && \
        -p "$sim_dir/debug_tx" && \
        -p "$sim_dir/debug_rx" \
    ]]; then
        break
    fi
    if ! kill -0 "$sim_pid" 2>/dev/null; then
        cat "$sim_dir/vvp.log"
        exit 1
    fi
    sleep 0.05
done

if [[ \
    ! -p "$sim_dir/app_tx" || \
    ! -p "$sim_dir/app_rx" || \
    ! -p "$sim_dir/debug_tx" || \
    ! -p "$sim_dir/debug_rx" \
]]; then
    cat "$sim_dir/vvp.log"
    echo "Timed out waiting for simulator transport FIFOs" >&2
    exit 1
fi

beam_dir="$stage/beam"
mkdir -p "$beam_dir"
erlc -o "$beam_dir" "$stage/erl_src/xls_type.erl"
erlc -pa "$beam_dir" -o "$beam_dir" \
    "$stage/erl_src/xls_fabric.erl" \
    "$stage/erl_src/xls_lists.erl" \
    "$stage/erl_src/xls_nums.erl" \
    "$stage/erl_src/xls_gs.erl" \
    "$stage/erl_src/xls_debug.erl"
erlc -pa "$beam_dir" -o "$beam_dir" "$stage/erl_src/regsvc.erl"
erlc -pa "$beam_dir" -o "$beam_dir" \
    "$stage/test_src/regsvc_cpu_tests.erl"

ERL_XLS_SIM_DIR="$sim_dir" erl \
    -noshell \
    -pa "$beam_dir" \
    -eval 'case eunit:test(regsvc_cpu_tests, [verbose]) of ok -> halt(0); error -> halt(1) end.'
