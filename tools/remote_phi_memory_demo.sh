#!/usr/bin/env bash
set -euo pipefail

stage=${1:?usage: remote_phi_memory_demo.sh STAGE XLS_ROOT}
xls_root=${2:?usage: remote_phi_memory_demo.sh STAGE XLS_ROOT}
stdlib="$xls_root/dslx/stdlib"
reuse_rtl=${ERL_HLS_PHI_DEMO_REUSE_RTL:-0}
startup_timeout=${ERL_HLS_SIM_STARTUP_TIMEOUT:-120}

if [[ ! "$startup_timeout" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERL_HLS_SIM_STARTUP_TIMEOUT must be a positive integer" >&2
    exit 1
fi

cd "$stage"

timed_output() {
    local label=$1
    local output=$2
    shift 2
    /usr/bin/time -v -o "phi_memory_gateway-${label}.time" \
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
        --pipeline_stages=1 \
        --delay_model=unit \
        --flop_inputs=false \
        --flop_outputs=true \
        --use_system_verilog=false \
        --reset=reset \
        --fifo_module= \
        phi_memory_gateway.opt.ir

    iverilog-vpi xls_sim_bridge.c
    /usr/bin/time -v -o phi_memory_gateway-iverilog.time \
        iverilog \
        -g2012 \
        -s phi_memory_bridge_tb \
        -o phi_memory_gateway.vvp \
        phi_memory_bridge_tb.sv \
        phi_memory_gateway.v
elif [[ ! -f phi_memory_gateway.vvp || ! -f xls_sim_bridge.vpi ]]; then
    echo "Cannot reuse missing Icarus artifacts" >&2
    exit 1
fi

sim_dir="$stage/sim"
mkdir -p "$sim_dir"
rm -f \
    "$sim_dir/app_tx" \
    "$sim_dir/app_rx" \
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
ERL_HLS_SIM_APP_ONLY=1 \
    vvp -M "$stage" -m xls_sim_bridge phi_memory_gateway.vvp \
    >"$sim_dir/vvp.log" 2>&1 &
sim_pid=$!

# A distance-three VVP image is tens of megabytes and can spend appreciable
# time loading before start-of-simulation callbacks create the FIFOs.
startup_deadline=$((SECONDS + startup_timeout))
while ((SECONDS < startup_deadline)); do
    if [[ -p "$sim_dir/app_tx" && -p "$sim_dir/app_rx" ]]; then
        break
    fi
    if ! kill -0 "$sim_pid" 2>/dev/null; then
        cat "$sim_dir/vvp.log"
        exit 1
    fi
    sleep 0.1
done

if [[ ! -p "$sim_dir/app_tx" || ! -p "$sim_dir/app_rx" ]]; then
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

/usr/bin/time -v -o phi_memory_gateway-sim.time \
    env ERL_HLS_PHI_SIM_DIR="$sim_dir" ERL_HLS_PHI_DEMO=d3 \
    erl -noshell -pa "$beam_dir" \
    -eval 'case eunit:test(phi_memory_bridge_tests, [verbose]) of
        ok -> halt(0);
        error -> halt(1)
    end.' | tee phi_memory_demo.log

kill "$sim_pid" 2>/dev/null || true
wait "$sim_pid" 2>/dev/null || true
sim_pid=

{
    wc -c phi_memory_gateway.x phi_memory_gateway.v
    wc -l phi_memory_gateway.x phi_memory_gateway.v
    sha256sum phi_memory_gateway.x phi_memory_gateway.v
    for report in phi_memory_gateway-*.time; do
        echo
        echo "[$report]"
        cat "$report"
    done
} > phi_memory_demo.metrics

cat phi_memory_demo.metrics
