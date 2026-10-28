#!/usr/bin/env bash
set -euo pipefail

script_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
stage=$(cd "$1" && pwd)
xls_root=$(cd "$2" && pwd)
stdlib="$xls_root/xls/dslx/stdlib"

cd "$stage"

# The staged axis module selects its ordinary ABI from this generated dependency.
test -f frame_config.x

iverilog \
    -g2012 \
    -s hls_debug_tap_tb \
    -o hls_debug_tap.vvp \
    hls_debug_tap_tb.sv \
    hls_debug_tap.v

vvp hls_debug_tap.vvp

iverilog \
    -g2012 \
    -s hls_trace_store_tb \
    -o hls_trace_store.vvp \
    hls_trace_store_tb.sv \
    hls_trace_store.v

vvp hls_trace_store.vvp

# The interpreter runs tests from its entry module, not imported modules, so
# keep every test-bearing DSLX module explicit here.
for test_module in \
    axis.x \
    hls_vec.x \
    hls_multiply.x \
    hls_numeric_test.x \
    xls_short_circuit_test.x \
    arbitration.x \
    direct_mailbox_observation.x \
    bram.x \
    frame_transport.x \
    hls_debug_framing.x \
    hls_debug_trace.x \
    hls_debug_observer.x \
    hls_spatial_router.x
do
    "$xls_root/interpreter_main" \
        --dslx_path=. \
        --dslx_stdlib_path="$stdlib" \
        "$test_module"
done

# Check static rounding at narrow and wide widths, including sampled JIT results.
"$xls_root/interpreter_main" --compare=jit --seed=1 \
    --dslx_path=. --dslx_stdlib_path="$stdlib" hls_fixed.x

python3 "$script_root/compile_xls.py" \
    "$stage/regsvc.x" "$xls_root" --output "$stage/regsvc-build"
regsvc_build=$(cd "$stage/regsvc-build" && pwd -P)
# Export the single RTL file consumed by this multi-service simulation/package.
# The compiler's IR, logs, and manifest remain together in the pinned release.
cp "$regsvc_build/regsvc.v" regsvc.v.new
mv regsvc.v.new regsvc.v

# Compile-only conformance coverage for tuple and homogeneous-record case
# patterns in an hls_gs callback. State-machine cases have separate local
# feature regressions in the shared inventory.
"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    --top=Top \
    xls_case_fixture.x > xls_case_fixture.ir

# Companion-provided record types and function calls through the hls_gs path.
"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    --top=Top \
    hls_companion_gs_fixture.x > hls_companion_gs_fixture.ir

# A small observable fixture distinguishes source action order from the actor's
# declared port order and holds the shared external lane under backpressure.
"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    --top=Top \
    ordered_egress_topology.x > ordered_egress_topology.ir

"$xls_root/opt_main" \
    ordered_egress_topology.ir > ordered_egress_topology.opt.ir

"$xls_root/codegen_main" \
    --pipeline_stages=1 \
    --delay_model=unit \
    --flop_inputs=false \
    --flop_outputs=true \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    ordered_egress_topology.opt.ir > ordered_egress_topology.v

iverilog \
    -g2012 \
    -s ordered_egress_topology_tb \
    -o ordered_egress_topology.vvp \
    ordered_egress_topology_tb.sv \
    ordered_egress_topology.v

vvp ordered_egress_topology.vvp

"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_stdlib_path="$stdlib" \
    --top=Observer \
    hls_debug_observer.x > hls_debug_observer.ir

"$xls_root/opt_main" hls_debug_observer.ir > hls_debug_observer.opt.ir

"$xls_root/codegen_main" \
    --pipeline_stages=2 \
    --delay_model=unit \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    hls_debug_observer.opt.ir > hls_debug_observer.v

"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    --top=DebugServer \
    hls_debug_server.x > hls_debug_server.ir

"$xls_root/opt_main" hls_debug_server.ir > hls_debug_server.opt.ir

"$xls_root/codegen_main" \
    --pipeline_stages=3 \
    --worst_case_throughput=2 \
    --delay_model=unit \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    hls_debug_server.opt.ir > hls_debug_server.v

iverilog -g2012 -s hls_debug_server_tb -o hls_debug_server.vvp \
    hls_debug_server_tb.sv hls_debug_server.v
vvp hls_debug_server.vvp

"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    --top=HostRoutedTx \
    hls_fabric_router.x > hls_fabric_host_tx.ir

"$xls_root/opt_main" hls_fabric_host_tx.ir > hls_fabric_host_tx.opt.ir

"$xls_root/codegen_main" \
    --pipeline_stages=1 \
    --delay_model=unit \
    --flop_inputs=false \
    --flop_outputs=true \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    hls_fabric_host_tx.opt.ir > hls_fabric_host_tx.v

iverilog \
    -g2012 \
    -s hls_fabric_host_tx_tb \
    -o hls_fabric_host_tx.vvp \
    hls_fabric_host_tx_tb.sv \
    hls_fabric_host_tx.v

vvp hls_fabric_host_tx.vvp

iverilog \
    -g2012 \
    -s regsvc_pair_tb \
    -o regsvc_pair.vvp \
    regsvc_pair_tb.sv \
    regsvc_fabric_fixture.sv \
    regsvc_debug_top.v \
    hls_debug_monitor.v \
    hls_fabric_ingress.v \
    hls_fabric_egress.v \
    hls_debug_tap.v \
    hls_trace_store.v \
    hls_debug_observer.v \
    hls_debug_server.v \
    regsvc_core_adapter.v \
    regsvc.v

vvp regsvc_pair.vvp

iverilog-vpi xls_sim_bridge.c

iverilog \
    -g2012 \
    -s regsvc_bridge_tb \
    -o regsvc_bridge.vvp \
    regsvc_bridge_tb.sv \
    regsvc_fabric_fixture.sv \
    regsvc_debug_top.v \
    hls_debug_monitor.v \
    hls_fabric_ingress.v \
    hls_fabric_egress.v \
    hls_debug_tap.v \
    hls_trace_store.v \
    hls_debug_observer.v \
    hls_debug_server.v \
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

stop_sim() {
    local log=$1 status=0
    kill "$sim_pid" 2>/dev/null || true
    wait "$sim_pid" 2>/dev/null || status=$?
    sim_pid=
    # SIGTERM is the normal shutdown of these continuously clocked benches.
    # Preserve a prior VPI failure instead of masking it during cleanup.
    if [[ "$status" != 0 && "$status" != 143 ]]; then
        cat "$log"
        return "$status"
    fi
}

ERL_HLS_SIM_DIR="$sim_dir" \
    vvp -M "$stage" -m xls_sim_bridge regsvc_bridge.vvp \
    >"$sim_dir/vvp.log" 2>&1 &
sim_pid=$!

# The VPI module creates all four FIFOs during start-of-simulation setup. Do
# not start the Erlang clients until those transport endpoints are ready.
startup_deadline=$((SECONDS + 120))
while ((SECONDS < startup_deadline)); do
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
    sleep 0.1
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
erlc -o "$beam_dir" "$stage/erl_src/hls_type.erl"
# Listings already contain host-expanded schemas and include the full runtime package.
erlc -pa "$beam_dir" -o "$beam_dir" "$stage"/erl_src/*.erl
erlc -pa "$beam_dir" -o "$beam_dir" \
    "$stage/test_src/regsvc_cpu_tests.erl"

ERL_HLS_SIM_DIR="$sim_dir" erl \
    -noshell \
    -pa "$beam_dir" \
    -eval 'case eunit:test(regsvc_cpu_tests, [verbose]) of ok -> halt(0); error -> halt(1) end.'

stop_sim "$sim_dir/vvp.log"
