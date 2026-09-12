#!/usr/bin/env bash
set -euo pipefail
xls_root=${1:?usage: test_actor_debug.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/actor-debug"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
erl -noshell -pa _build/test/lib/erl_hls/ebin _build/test/lib/erl_hls/test \
    -eval 'ok = hls_actor_debug_dslx:write(hd(init:get_plain_arguments())), halt().' -extra "$stage"
options=(--warnings_as_errors=false --dslx_path="$stage:$project_root/priv/xls/lib:$project_root/priv/xls/fabric"
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib")
"$xls_root/ir_converter_main" --top=Top "${options[@]}" "$stage/actor_debug.x" > "$stage/actor_debug.ir"
"$xls_root/opt_main" "$stage/actor_debug.ir" > "$stage/actor_debug.opt.ir"
source tools/phi_scheduler_rams.sh
for stages in 2 3; do
    "$xls_root/codegen_main" --pipeline_stages="$stages" --delay_model=unit \
        --flop_inputs=false --flop_outputs=true --use_system_verilog=false --reset=reset \
        --fifo_module= --module_name=actor_debug --ram_configurations="$(phi_scheduler_ram_configurations 1)" \
        "$stage/actor_debug.opt.ir" > "$stage/actor_debug_$stages.v"
    python3 tools/test_topology_debug_integration.py --yosys "${YOSYS:-yosys}" \
        --top actor_debug_wrapper --stage "$stage/p$stages" \
        --actor-projection "$stage/small-actors.json" --actor-test small \
        "$stage/actor_debug_$stages.v" "$stage/actor_debug_wrapper.v" priv/rtl/hls_1r1w_ram.v
done
