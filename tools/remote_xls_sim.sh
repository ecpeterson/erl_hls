#!/usr/bin/env bash
set -euo pipefail

stage=$1
xls_root=$2
stdlib="$xls_root/xls/dslx/stdlib"

cd "$stage"

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
for test_module in hls_debug_trace.x hls_debug_observer.x; do
    "$xls_root/interpreter_main" \
        --dslx_path=. \
        --dslx_stdlib_path="$stdlib" \
        "$test_module"
done

"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_path=. \
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

# Compile-only conformance coverage for tuple and homogeneous-record case
# patterns in an hls_gs callback. The phi simulation below covers integer
# case selection in hls_statem.
"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    --top=Top \
    xls_case_fixture.x > xls_case_fixture.ir

"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    --top=Top \
    phi_halo_cell.x > phi_halo_cell.ir

"$xls_root/opt_main" phi_halo_cell.ir > phi_halo_cell.opt.ir

"$xls_root/codegen_main" \
    --pipeline_stages=1 \
    --delay_model=unit \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    phi_halo_cell.opt.ir > phi_halo_cell.v

# Keep independent actor codegen as a compile check. The combined frame
# topology below imports these DSLX modules and generates one collision-free
# RTL graph rather than composing their separately generated Verilog.
for actor in phenom_data_cell phenom_syndrome_cell; do
    "$xls_root/ir_converter_main" \
        --warnings_as_errors=false \
        --dslx_path=. \
        --dslx_stdlib_path="$stdlib" \
        --top=Top \
        "$actor.x" > "$actor.ir"

    "$xls_root/opt_main" "$actor.ir" > "$actor.opt.ir"

    "$xls_root/codegen_main" \
        --pipeline_stages=1 \
        --delay_model=unit \
        --use_system_verilog=false \
        --reset=reset \
        --fifo_module= \
        "$actor.opt.ir" > "$actor.v"
done

"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    --top=Top \
    phi_phenom_topology.x > phi_phenom_topology.ir

"$xls_root/opt_main" \
    phi_phenom_topology.ir > phi_phenom_topology.opt.ir

# All generated topology codegen below follows this policy. Compact family
# lanes require producer output flops as their bounded holding slots; other
# topologies retain explicit link FIFOs. Avoid duplicate consumer input queues.
"$xls_root/codegen_main" \
    --pipeline_stages=1 \
    --delay_model=unit \
    --flop_inputs=false \
    --flop_outputs=true \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    phi_phenom_topology.opt.ir > phi_phenom_topology.v

# The regular torus source retains one family node and elaboration-time loops;
# this compile/codegen check proves the pinned XLS build accepts its channel
# arrays, statically indexed polling merge, and wrapped node wiring.
"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    --top=Top \
    phi_torus_topology.x > phi_torus_topology.ir

"$xls_root/opt_main" \
    phi_torus_topology.ir > phi_torus_topology.opt.ir

"$xls_root/codegen_main" \
    --pipeline_stages=1 \
    --delay_model=unit \
    --flop_inputs=false \
    --flop_outputs=true \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    phi_torus_topology.opt.ir > phi_torus_topology.v

iverilog \
    -g2012 \
    -s phi_torus_topology_tb \
    -o phi_torus_topology.vvp \
    phi_torus_topology_tb.sv \
    phi_torus_topology.v

vvp phi_torus_topology.vvp

# Elaborate the checked distance-three graph to IR so distinct cross-family
# shifts and wrapping are accepted by the pinned XLS build. The opt-in
# run_phi_noise_topology_sim.sh handles full distance-three RTL simulation;
# this routine regression keeps the cheaper distance-one smoke below.
"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    --top=Top \
    phi_noise_topology.x > phi_noise_topology.ir

# This distance-one graph exercises all six family types, per-instance
# startup, and queued announcement fanout through generated RTL.
"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    --top=Top \
    phi_noise_topology_smoke.x > phi_noise_topology_smoke.ir

"$xls_root/opt_main" \
    phi_noise_topology_smoke.ir > phi_noise_topology_smoke.opt.ir

"$xls_root/codegen_main" \
    --pipeline_stages=1 \
    --delay_model=unit \
    --flop_inputs=false \
    --flop_outputs=true \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    phi_noise_topology_smoke.opt.ir > phi_noise_topology_smoke.v

iverilog \
    -g2012 \
    -s phi_noise_topology_smoke_tb \
    -o phi_noise_topology_smoke.vvp \
    phi_noise_topology_smoke_tb.sv \
    phi_noise_topology_smoke.v

vvp phi_noise_topology_smoke.vvp

iverilog \
    -g2012 \
    -s phi_halo_cell_tb \
    -o phi_halo_cell.vvp \
    phi_halo_cell_tb.sv \
    phi_halo_cell.v

vvp phi_halo_cell.vvp

iverilog \
    -g2012 \
    -s phi_phenom_topology_tb \
    -o phi_phenom_topology.vvp \
    phi_phenom_topology_tb.sv \
    phi_phenom_topology.v

vvp phi_phenom_topology.vvp

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

"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    --top=PairIngress \
    hls_fabric_router.x > hls_fabric_ingress.ir

"$xls_root/opt_main" hls_fabric_ingress.ir > hls_fabric_ingress.opt.ir

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

"$xls_root/opt_main" hls_fabric_egress.ir > hls_fabric_egress.opt.ir

"$xls_root/codegen_main" \
    --pipeline_stages=1 \
    --delay_model=unit \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    hls_fabric_egress.opt.ir > hls_fabric_egress.v

iverilog \
    -g2012 \
    -s regsvc_pair_tb \
    -o regsvc_pair.vvp \
    regsvc_pair_tb.sv \
    regsvc_pair_fixture.sv \
    regsvc_debug_top.v \
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
    regsvc_pair_fixture.sv \
    regsvc_debug_top.v \
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

ERL_HLS_SIM_DIR="$sim_dir" \
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
erlc -o "$beam_dir" "$stage/erl_src/hls_type.erl"
erlc -pa "$beam_dir" -o "$beam_dir" \
    "$stage/erl_src/hls_fabric.erl" \
    "$stage/erl_src/hls_lists.erl" \
    "$stage/erl_src/hls_nums.erl" \
    "$stage/erl_src/hls_gs.erl" \
    "$stage/erl_src/hls_debug.erl"
erlc -pa "$beam_dir" -o "$beam_dir" "$stage/erl_src/regsvc.erl"
erlc -pa "$beam_dir" -o "$beam_dir" \
    "$stage/test_src/regsvc_cpu_tests.erl"

ERL_HLS_SIM_DIR="$sim_dir" erl \
    -noshell \
    -pa "$beam_dir" \
    -eval 'case eunit:test(regsvc_cpu_tests, [verbose]) of ok -> halt(0); error -> halt(1) end.'
