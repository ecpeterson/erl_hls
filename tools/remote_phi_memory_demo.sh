#!/usr/bin/env bash
set -euo pipefail

stage=${1:?usage: remote_phi_memory_demo.sh STAGE XLS_ROOT}
xls_root=${2:?usage: remote_phi_memory_demo.sh STAGE XLS_ROOT}
stdlib="$xls_root/xls/dslx/stdlib"
. "$stage/phi_scheduler_rams.sh"
reuse_rtl=${ERL_HLS_PHI_DEMO_REUSE_RTL:-0}
compile_only=${ERL_HLS_PHI_DEMO_COMPILE_ONLY:-0}
startup_timeout=${ERL_HLS_SIM_STARTUP_TIMEOUT:-120}
initiation_interval=${ERL_HLS_PHI_SCHEDULER_II:-1}
cpu_witness="$stage/phi_memory_cpu_witness.term"

if [[ $(uname -s) == Darwin ]]; then
    time_arguments=(-p)
else
    time_arguments=(-v)
fi

if [[ ! "$startup_timeout" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERL_HLS_SIM_STARTUP_TIMEOUT must be a positive integer" >&2
    exit 1
fi
if [[ ! "$initiation_interval" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERL_HLS_PHI_SCHEDULER_II must be a positive integer" >&2
    exit 1
fi

if [[ ! -s "$cpu_witness" ]]; then
    echo "Missing CPU witness: $cpu_witness" >&2
    exit 1
fi

cd "$stage"

timed_output() {
    local label=$1
    local output=$2
    shift 2
    /usr/bin/time "${time_arguments[@]}" \
        -o "phi_memory_gateway-${label}.time" \
        "$@" > "$output"
}

if [[ "$reuse_rtl" != 1 ]]; then
    timed_output ir phi_memory_gateway.ir \
        "$xls_root/ir_converter_main" \
        --warnings_as_errors=false \
        --dslx_path=. \
        --dslx_stdlib_path="$stdlib" \
        --top=Top \
        phi_memory_gateway.x

    timed_output opt phi_memory_gateway.opt.ir \
        "$xls_root/opt_main" \
        phi_memory_gateway.ir

    timed_output codegen phi_memory_gateway.v \
        "$xls_root/codegen_main" \
        --pipeline_stages=2 \
        --worst_case_throughput="$initiation_interval" \
        --delay_model=unit \
        --flop_inputs=false \
        --flop_outputs=true \
        --use_system_verilog=false \
        --reset=reset \
        --fifo_module= \
        --ram_configurations="$(phi_scheduler_ram_configurations)" \
        phi_memory_gateway.opt.ir

elif [[ ! -f phi_memory_gateway.v ]]; then
    echo "Cannot reuse missing phi_memory_gateway.v" >&2
    exit 1
fi

# Actor execution is decoupled from the mailbox manager, allowing the
# scheduler core to use II=1 while preserving one-cycle RAM reads. Serialize
# its RoutedFrame output in a separate II=1 compilation unit as before.
timed_output host-tx-ir hls_fabric_host_tx.ir \
    "$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    --top=HostRoutedTx \
    hls_fabric_router.x

timed_output host-tx-opt hls_fabric_host_tx.opt.ir \
    "$xls_root/opt_main" \
    hls_fabric_host_tx.ir

timed_output host-tx-codegen hls_fabric_host_tx.v \
    "$xls_root/codegen_main" \
    --pipeline_stages=1 \
    --delay_model=unit \
    --flop_inputs=false \
    --flop_outputs=true \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    hls_fabric_host_tx.opt.ir

# The monitor and two-endpoint debug router are small enough to regenerate on
# every run. Reusing the expensive topology RTL must not accidentally reuse a
# stale debug wrapper or simulation image.
"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_stdlib_path="$stdlib" \
    --top=Observer \
    hls_debug_observer.x > hls_debug_observer.ir

"$xls_root/opt_main" \
    hls_debug_observer.ir > hls_debug_observer.opt.ir

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

"$xls_root/opt_main" \
    hls_debug_server.ir > hls_debug_server.opt.ir

"$xls_root/codegen_main" \
    --pipeline_stages=3 \
    --worst_case_throughput=2 \
    --delay_model=unit \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    hls_debug_server.opt.ir > hls_debug_server.v

"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    --top=PairIngress \
    hls_fabric_router.x > hls_fabric_ingress.ir

"$xls_root/opt_main" \
    hls_fabric_ingress.ir > hls_fabric_ingress.opt.ir

"$xls_root/codegen_main" \
    --pipeline_stages=1 \
    --delay_model=unit \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    hls_fabric_ingress.opt.ir > hls_fabric_ingress.v

"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    --top=PairEgress \
    hls_fabric_router.x > hls_fabric_egress.ir

"$xls_root/opt_main" \
    hls_fabric_egress.ir > hls_fabric_egress.opt.ir

"$xls_root/codegen_main" \
    --pipeline_stages=1 \
    --delay_model=unit \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    hls_fabric_egress.opt.ir > hls_fabric_egress.v

if [[ "$compile_only" == 1 ]]; then
    exit 0
fi

iverilog-vpi xls_sim_bridge.c
/usr/bin/time "${time_arguments[@]}" -o phi_memory_gateway-iverilog.time \
    iverilog \
    -g2012 \
    -s phi_memory_bridge_tb \
    -o phi_memory_gateway.vvp \
    phi_memory_bridge_tb.sv \
    phi_memory_debug_top.v \
    hls_1r1w_ram.v \
    phi_memory_gateway.v \
    hls_fabric_host_tx.v \
    hls_fabric_ingress.v \
    hls_fabric_egress.v \
    hls_debug_monitor.v \
    hls_debug_tap.v \
    hls_trace_store.v \
    hls_debug_observer.v \
    hls_debug_server.v

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

ERL_HLS_SIM_DIR="$sim_dir" \
ERL_HLS_SIM_TOP=phi_memory_bridge_tb \
    vvp -M "$stage" -m xls_sim_bridge phi_memory_gateway.vvp \
    >"$sim_dir/vvp.log" 2>&1 &
sim_pid=$!

# A distance-three VVP image is tens of megabytes and can spend appreciable
# time loading before start-of-simulation callbacks create the FIFOs.
startup_deadline=$((SECONDS + startup_timeout))
while ((SECONDS < startup_deadline)); do
    if [[ -p "$sim_dir/app_tx" && -p "$sim_dir/app_rx" &&
          -p "$sim_dir/debug_tx" && -p "$sim_dir/debug_rx" ]]; then
        break
    fi
    if ! kill -0 "$sim_pid" 2>/dev/null; then
        cat "$sim_dir/vvp.log"
        exit 1
    fi
    sleep 0.1
done

if [[ ! -p "$sim_dir/app_tx" || ! -p "$sim_dir/app_rx" ||
      ! -p "$sim_dir/debug_tx" || ! -p "$sim_dir/debug_rx" ]]; then
    cat "$sim_dir/vvp.log"
    echo "Timed out waiting for phi simulator transport FIFOs" >&2
    exit 1
fi

beam_dir="$stage/beam"
mkdir -p "$beam_dir"
erlc -o "$beam_dir" "$stage/erl_src/hls_type.erl"
erlc -pa "$beam_dir" -o "$beam_dir" \
    "$stage/erl_src/hls_fabric.erl" \
    "$stage/erl_src/hls_gs.erl" \
    "$stage/erl_src/hls_debug.erl" \
    "$stage/erl_src/hls_lists.erl" \
    "$stage/erl_src/hls_nums.erl" \
    "$stage/erl_src/hls_pauli.erl"
erlc -pa "$beam_dir" -o "$beam_dir" \
    "$stage/erl_src/phenom_data_cell.erl" \
    "$stage/erl_src/phenom_syndrome_cell.erl" \
    "$stage/erl_src/phi_halo_cell.erl" \
    "$stage/erl_src/phi_memory_boundary.erl" \
    "$stage/erl_src/phi_memory_demo.erl" \
    "$stage/erl_src/phi_memory_experiment.erl" \
    "$stage/erl_src/phi_memory_runner.erl" \
    "$stage/erl_src/phi_memory_wire.erl" \
    "$stage/erl_src/phi_noise_topology.erl"
erlc -pa "$beam_dir" -o "$beam_dir" \
    "$stage/test_src/phi_memory_bridge_tests.erl"

/usr/bin/time "${time_arguments[@]}" -o phi_memory_gateway-sim.time \
    env ERL_HLS_PHI_SIM_DIR="$sim_dir" \
    ERL_HLS_PHI_DEMO=d3 \
    ERL_HLS_PHI_CPU_WITNESS="$cpu_witness" \
    erl -noshell -pa "$beam_dir" \
    -eval 'case eunit:test(phi_memory_bridge_tests, [verbose]) of
        ok -> halt(0);
        error -> halt(1)
    end.' | tee phi_memory_demo.log

kill "$sim_pid" 2>/dev/null || true
wait "$sim_pid" 2>/dev/null || true
sim_pid=

{
    wc -c phi_memory_gateway.x phi_memory_gateway.v hls_fabric_host_tx.v
    wc -l phi_memory_gateway.x phi_memory_gateway.v hls_fabric_host_tx.v
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum phi_memory_gateway.x phi_memory_gateway.v \
            hls_fabric_host_tx.v
    else
        shasum -a 256 phi_memory_gateway.x phi_memory_gateway.v \
            hls_fabric_host_tx.v
    fi
    for report in phi_memory_gateway-*.time; do
        echo
        echo "[$report]"
        cat "$report"
    done
} > phi_memory_demo.metrics

cat phi_memory_demo.metrics
