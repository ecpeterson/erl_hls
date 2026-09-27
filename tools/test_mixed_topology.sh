#!/usr/bin/env bash
set -euo pipefail
xls_root=${1:?usage: test_mixed_topology.sh XLS_ROOT [STAGE] [PLACEMENT ...]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/mixed-topology"}
shift $(( $# >= 2 ? 2 : 1 ))
placements=("$@")
if [[ ${#placements[@]} == 0 ]]; then placements=(direct ingress_direct); fi
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
for placement in "${placements[@]}"; do
    case "$placement" in direct|ingress_direct) ;; *) echo "unknown placement: $placement" >&2; exit 1;; esac
    build="$stage/$placement"
    mkdir -p "$build"
    erl -noshell -pa _build/test/lib/erl_hls/ebin _build/test/lib/erl_hls/test \
        -eval '[Stage, Text] = init:get_plain_arguments(),
            Placement = case Text of "direct" -> direct; "ingress_direct" -> {ingress, direct} end,
            ok = hls_mixed_topology_dslx:write(Placement, Stage), halt().' -extra "$build" "$placement"
    "$xls_root/ir_converter_main" --top=Top --warnings_as_errors=false \
        --dslx_path="$build:$project_root/priv/xls/lib:$project_root/priv/xls/fabric" \
        --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" "$build/mixed_topology.x" > "$build/topology.ir" 2> "$build/convert.log"
    "$xls_root/opt_main" "$build/topology.ir" > "$build/topology.opt.ir" 2> "$build/opt.log"
    codegen_options=(--fifo_module=)
    case "$placement" in direct) actor_test=mixed_direct;; ingress_direct) actor_test=ingress_direct;; esac
    for stages in 2 3; do
        "$xls_root/codegen_main" --pipeline_stages="$stages" --delay_model=unit \
            --flop_inputs=false --flop_outputs=true --use_system_verilog=false --reset=reset \
            --module_name=mixed_topology "${codegen_options[@]}" \
            "$build/topology.opt.ir" > "$build/topology_$stages.v" 2> "$build/codegen_$stages.log"
        python3 tools/test_topology_debug_integration.py --yosys "${YOSYS:-yosys}" \
            --top mixed_topology_wrapper --stage "$build/p$stages" \
            --actor-projection "$build/actors.json" --actor-test "$actor_test" \
            "$build/topology_$stages.v" "$build/mixed_topology_wrapper.v"
    done
done
