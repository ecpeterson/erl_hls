#!/usr/bin/env bash
set -euo pipefail

stage=${1:?usage: remote_phi_memory_bram_demo.sh STAGE}
startup_timeout=${ERL_HLS_SIM_STARTUP_TIMEOUT:-120}
cpu_witness="$stage/phi_memory_cpu_witness.term"

if [[ ! "$startup_timeout" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERL_HLS_SIM_STARTUP_TIMEOUT must be a positive integer" >&2
    exit 1
fi
test -s "$cpu_witness"
cd "$stage"

iverilog-vpi xls_sim_bridge.c
/usr/bin/time -v -o phi_memory_bram-iverilog.time \
    iverilog -g2012 -DPHI_MEMORY_DUT=phi_memory_bram_top \
    -s phi_memory_raw_bridge_tb \
    -o phi_memory_bram_demo.vvp \
    phi_sequential_bram_core.v \
    phi_memory_scheduler_boundary.sv \
    phi_memory_bram_top.sv \
    phi_memory_raw_bridge_tb.sv

sim_dir="$stage/sim"
mkdir -p "$sim_dir"
rm -f "$sim_dir/app_tx" "$sim_dir/app_rx" "$sim_dir/vvp.log"

sim_pid=
cleanup() {
    if [[ -n "$sim_pid" ]]; then
        kill "$sim_pid" 2>/dev/null || true
        wait "$sim_pid" 2>/dev/null || true
    fi
}
trap cleanup EXIT

ERL_HLS_SIM_DIR="$sim_dir" \
ERL_HLS_SIM_TOP=phi_memory_raw_bridge_tb \
ERL_HLS_SIM_APP_ONLY=1 \
    vvp -M "$stage" -m xls_sim_bridge phi_memory_bram_demo.vvp \
    >"$sim_dir/vvp.log" 2>&1 &
sim_pid=$!

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
    echo "Timed out waiting for BRAM phi simulator transport FIFOs" >&2
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

/usr/bin/time -v -o phi_memory_bram-sim.time \
    env ERL_HLS_PHI_SIM_DIR="$sim_dir" \
    ERL_HLS_PHI_DEMO=d3 \
    ERL_HLS_PHI_CPU_WITNESS="$cpu_witness" \
    ERL_HLS_PHI_DEBUG=0 \
    erl -noshell -pa "$beam_dir" \
    -eval 'case eunit:test(phi_memory_bridge_tests, [verbose]) of
        ok -> halt(0);
        error -> halt(1)
    end.' | tee phi_memory_bram_demo.log

kill "$sim_pid" 2>/dev/null || true
wait "$sim_pid" 2>/dev/null || true
sim_pid=

{
    wc -c phi_sequential_bram_core.v \
        phi_memory_scheduler_boundary.sv phi_memory_bram_top.sv
    wc -l phi_sequential_bram_core.v \
        phi_memory_scheduler_boundary.sv phi_memory_bram_top.sv
    sha256sum phi_sequential_bram_core.v \
        phi_memory_scheduler_boundary.sv phi_memory_bram_top.sv
    for report in phi_memory_bram-*.time; do
        echo
        echo "[$report]"
        cat "$report"
    done
} > phi_memory_bram_demo.metrics
cat phi_memory_bram_demo.metrics
