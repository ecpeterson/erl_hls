#!/usr/bin/env bash
set -euo pipefail

experiment_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
project_root=$(cd "$experiment_root/../.." && pwd)
local_stage=${1:-"$project_root/_build/phi_memory_bram_demo"}
remote_host=${ERL_HLS_REMOTE_HOST:-192.168.64.7}
remote_root=${ERL_HLS_REMOTE_ROOT:-/home/ecpeterson/erl_hls-build}
remote_stage="$remote_root/phi_memory_bram_demo"
cpu_witness="$local_stage/phi_memory_cpu_witness.term"

cd "$project_root"
mkdir -p "$local_stage/erl_src" "$local_stage/test_src"
rm -f "$cpu_witness"
ERL_HLS_PHI_CPU_WITNESS="$cpu_witness" \
    rebar3 eunit --module=phi_memory_cpu_fabric_tests
test -s "$cpu_witness"

# Produce and locally check the RAM-rewritten worker before staging it with the
# unchanged ERTS runner.
"$experiment_root/run_bram_xls.sh" "$local_stage"

for source in \
    "$project_root/src/runtime/hls_fabric.erl" \
    "$project_root/src/api/hls_gs.erl" \
    "$project_root/src/api/hls_lists.erl" \
    "$project_root/src/api/hls_nums.erl" \
    "$project_root/src/api/hls_type.erl" \
    "$project_root/src/examples/phi_decoder/hls_pauli.erl" \
    "$project_root/src/examples/phi_decoder/phenom_data_cell.erl" \
    "$project_root/src/examples/phi_decoder/phenom_syndrome_cell.erl" \
    "$project_root/src/examples/phi_decoder/phi_halo_cell.erl" \
    "$project_root/src/examples/phi_decoder/phi_memory_boundary.erl" \
    "$project_root/src/examples/phi_decoder/phi_memory_demo.erl" \
    "$project_root/src/examples/phi_decoder/phi_memory_experiment.erl" \
    "$project_root/src/examples/phi_decoder/phi_memory_runner.erl" \
    "$project_root/src/examples/phi_decoder/phi_memory_wire.erl" \
    "$project_root/src/examples/phi_decoder/phi_noise_topology.erl"
do
    erlc -pa "$project_root/_build/test/lib/erl_hls/ebin" \
        -I "$project_root/include" -P -o "$local_stage/erl_src" "$source"
    module=$(basename "$source" .erl)
    cp "$local_stage/erl_src/$module.P" \
        "$local_stage/erl_src/$module.erl"
done

erlc -pa "$project_root/_build/test/lib/erl_hls/ebin" \
    -P -o "$local_stage/test_src" \
    "$project_root/test/phi_memory_bridge_tests.erl"
cp "$local_stage/test_src/phi_memory_bridge_tests.P" \
    "$local_stage/test_src/phi_memory_bridge_tests.erl"
cp "$experiment_root/phi_memory_raw_bridge_tb.sv" \
    "$local_stage/phi_memory_raw_bridge_tb.sv"
cp "$project_root/test/rtl/xls_sim_bridge.c" \
    "$local_stage/xls_sim_bridge.c"
cp "$experiment_root/remote_bram_demo.sh" \
    "$local_stage/remote_bram_demo.sh"

ssh -o BatchMode=yes "$remote_host" mkdir -p "$remote_stage"
rsync -a -e "ssh -o BatchMode=yes" \
    "$local_stage/phi_sequential_bram_core.v" \
    "$local_stage/phi_memory_scheduler_boundary.sv" \
    "$local_stage/phi_memory_bram_top.sv" \
    "$local_stage/phi_memory_raw_bridge_tb.sv" \
    "$local_stage/xls_sim_bridge.c" \
    "$cpu_witness" \
    "$local_stage/erl_src" \
    "$local_stage/test_src" \
    "$local_stage/remote_bram_demo.sh" \
    "$remote_host:$remote_stage/"

ssh -o BatchMode=yes "$remote_host" \
    bash "$remote_stage/remote_bram_demo.sh" "$remote_stage"

rsync -a -e "ssh -o BatchMode=yes" \
    --include=phi_memory_bram_demo.log \
    --include=phi_memory_bram_demo.metrics \
    --include='phi_memory_bram-*.time' \
    --exclude='*' \
    "$remote_host:$remote_stage/" \
    "$local_stage/"
