#!/usr/bin/env bash
# Exercise public actor queries against a production shared indexed collector.
set -euo pipefail
xls_root=${1:?usage: test_indexed_debug.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/indexed-debug"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
python3 tools/build.py as test compile
source tools/backend_env.sh
erl +S 2:2 -noshell -eval 'ok=hls_indexed_debug_dslx:write(hd(init:get_plain_arguments())),halt().' -extra "$stage"
options=(--warnings_as_errors=false --dslx_path="$stage:$project_root/priv/xls/lib:$project_root/priv/xls/fabric:$erl_hls_root/priv/xls/lib:$erl_hls_root/priv/xls/fabric"
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib")
"$xls_root/ir_converter_main" --top=Top "${options[@]}" "$stage/actor_debug.x" > "$stage/actor_debug.ir"
"$xls_root/opt_main" "$stage/actor_debug.ir" > "$stage/actor_debug.opt.ir"
source tools/phi_scheduler_rams.sh
rams="$(phi_scheduler_ram_configurations 1),scheduler_0_gather:1R1W:_scheduler_0_gather_read_req_out:_scheduler_0_gather_read_resp_in:_scheduler_0_gather_write_req_out:_scheduler_0_gather_write_resp_in"
for stages in 2 3; do
    "$xls_root/codegen_main" --pipeline_stages="$stages" --delay_model=unit \
        --flop_inputs=false --flop_outputs=true --use_system_verilog=false --reset=reset \
        --module_name=actor_debug --fifo_module= --ram_configurations="$rams" \
        "$stage/actor_debug.opt.ir" > "$stage/actor_debug_$stages.v"
    python3 tools/test_topology_debug_integration.py --yosys "${YOSYS:-yosys}" \
        --top actor_debug_wrapper --stage "$stage/p$stages" \
        --actor-projection "$stage/small-actors.json" --actor-test indexed_gather \
        "$stage/actor_debug_$stages.v" "$stage/actor_debug_wrapper.v" \
        "$erl_hls_root/priv/rtl/hls_1r1w_ram.v" priv/rtl/hls_indexed_gather_ram.v
done
