#!/usr/bin/env bash
set -euo pipefail

stage=${1:?usage: local_phi_memory_demo.sh STAGE}
stage=$(cd "$stage" && pwd)
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
sim_dir="$stage/sim_native"
cpu_witness="$stage/phi_memory_cpu_witness.term"
debug_metrics="$stage/phi_memory_demo.debug.term"
scheduler_profile="$stage/phi_memory_demo.scheduler_profile"
vvp_log="$stage/phi_memory_demo.vvp.log"

for command in iverilog iverilog-vpi vvp rebar3; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "missing native command: $command" >&2
        exit 1
    fi
done
test -s "$cpu_witness"

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$@"
    else
        shasum -a 256 "$@"
    fi
}

mkdir -p "$sim_dir"
rm -f \
    "$sim_dir/app_tx" \
    "$sim_dir/app_rx" \
    "$sim_dir/debug_tx" \
    "$sim_dir/debug_rx" \
    "$debug_metrics" \
    "$scheduler_profile" \
    "$vvp_log"

cd "$stage"
iverilog-vpi xls_sim_bridge.c
iverilog \
    -g2012 \
    -s phi_memory_bridge_tb \
    -o phi_memory_gateway.vvp \
    phi_memory_bridge_tb.sv \
    phi_memory_debug_top.v \
    hls_1rw_ram.v \
    phi_memory_gateway.v \
    hls_fabric_ingress.v \
    hls_fabric_egress.v \
    hls_debug_monitor.v \
    hls_debug_tap.v \
    hls_trace_store.v \
    hls_debug_observer.v \
    hls_debug_server.v

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
ERL_HLS_SIM_SCHEDULER_PROFILE="$scheduler_profile" \
    vvp -M "$stage" -m xls_sim_bridge phi_memory_gateway.vvp \
    >"$vvp_log" 2>&1 &
sim_pid=$!

startup_deadline=$((SECONDS + 120))
while ((SECONDS < startup_deadline)); do
    if [[ -p "$sim_dir/app_tx" && -p "$sim_dir/app_rx" &&
          -p "$sim_dir/debug_tx" && -p "$sim_dir/debug_rx" ]]; then
        break
    fi
    if ! kill -0 "$sim_pid" 2>/dev/null; then
        cat "$vvp_log"
        exit 1
    fi
    sleep 0.1
done

if [[ ! -p "$sim_dir/app_tx" || ! -p "$sim_dir/app_rx" ||
      ! -p "$sim_dir/debug_tx" || ! -p "$sim_dir/debug_rx" ]]; then
    cat "$vvp_log"
    echo "timed out waiting for native phi simulator FIFOs" >&2
    exit 1
fi

cd "$project_root"
sim_start=$SECONDS
ERL_HLS_PHI_SIM_DIR="$sim_dir" \
ERL_HLS_PHI_DEMO=d3 \
ERL_HLS_PHI_CPU_WITNESS="$cpu_witness" \
ERL_HLS_PHI_DEBUG_METRICS="$debug_metrics" \
    rebar3 eunit --module=phi_memory_bridge_tests
sim_elapsed=$((SECONDS - sim_start))
test -s "$debug_metrics"
test -s "$scheduler_profile"
grep -q '^profile_snapshot=last_application_output$' "$scheduler_profile"
for scheduler in data phi syndrome; do
    grep -Eq "^${scheduler}(_[0-9]+)?_state_reads=" "$scheduler_profile"
    grep -Eq "^${scheduler}(_[0-9]+)?_mailbox_visits=" "$scheduler_profile"
    grep -Eq "^${scheduler}(_[0-9]+)?_entry_visits=" "$scheduler_profile"
done

cleanup
sim_pid=
trap - EXIT

cd "$stage"
{
    echo "native_icarus_seconds=$sim_elapsed"
    wc -c phi_memory_gateway.x phi_memory_gateway.v
    wc -l phi_memory_gateway.x phi_memory_gateway.v
    sha256_file phi_memory_gateway.x phi_memory_gateway.v
    cat "$debug_metrics"
    cat "$scheduler_profile"
} > "$stage/phi_memory_demo.metrics"
cat "$stage/phi_memory_demo.metrics"
