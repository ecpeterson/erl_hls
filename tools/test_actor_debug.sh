#!/usr/bin/env bash
set -euo pipefail
xls_root=${1:?usage: test_actor_debug.sh XLS_ROOT [STAGE] [small|mailbox|reduction|aggregate|phi]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/actor-debug"}
kind=${3:-small}
case "$kind" in small|mailbox|reduction|aggregate|phi) ;; *) echo "unknown actor fixture: $kind" >&2; exit 1;; esac
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
erl -noshell -pa _build/test/lib/erl_hls/ebin _build/test/lib/erl_hls/test \
    -eval '[Stage, KindText] = init:get_plain_arguments(),
        Kind = maps:get(KindText, #{"small" => small, "mailbox" => mailbox, "phi" => phi, "reduction" => reduction, "aggregate" => aggregate}),
        Options = case Kind of small -> #{}; _ -> #{mailbox_debug => true} end,
        ok = hls_actor_debug_dslx:write(Kind, Stage, Options), halt().' -extra "$stage" "$kind"
if [[ "$kind" == phi ]]; then
    cp priv/xls/lib/*.x priv/xls/fabric/*.x src/examples/phi_decoder/phi_field.x "$stage/"
    cp tools/phi_scheduler_rams.sh priv/rtl/hls_1r1w_ram.v "$stage/"
    bash tools/compile_phi_decoder_profile.sh "$stage" "$xls_root" 2h 3 2 1
    compiled=$(cd "$stage/compiled" && pwd -P)
    python3 tools/test_topology_debug_integration.py --yosys "${YOSYS:-yosys}" \
        --top phi_decoder_profile_top --clock aclk --reset aresetn --reset-active-low \
        --stage "$stage/debug" --actor-projection "$stage/phi-actors.json" --actor-test phi \
        "$compiled/phi_decoder_profile.v" "$compiled/phi_decoder_profile_top.v" "$compiled/hls_1r1w_ram.v"
    exit 0
fi
scheduler_count=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["banks"]))' "$stage/small-actors.json")
options=(--warnings_as_errors=false --dslx_path="$stage:$project_root/priv/xls/lib:$project_root/priv/xls/fabric"
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib")
"$xls_root/ir_converter_main" --top=Top "${options[@]}" "$stage/actor_debug.x" > "$stage/actor_debug.ir"
"$xls_root/opt_main" "$stage/actor_debug.ir" > "$stage/actor_debug.opt.ir"
source tools/phi_scheduler_rams.sh
stages_to_test=(2 3)
[[ "$kind" != mailbox ]] || stages_to_test+=(4)
for stages in "${stages_to_test[@]}"; do
    "$xls_root/codegen_main" --pipeline_stages="$stages" --delay_model=unit \
        --flop_inputs=false --flop_outputs=true --use_system_verilog=false --reset=reset \
        --fifo_module= --module_name=actor_debug --ram_configurations="$(phi_scheduler_ram_configurations "$scheduler_count")" \
        "$stage/actor_debug.opt.ir" > "$stage/actor_debug_$stages.v"
    python3 tools/test_topology_debug_integration.py --yosys "${YOSYS:-yosys}" \
        --top actor_debug_wrapper --stage "$stage/p$stages" \
        --actor-projection "$stage/small-actors.json" --actor-test "$kind" \
        "$stage/actor_debug_$stages.v" "$stage/actor_debug_wrapper.v" priv/rtl/hls_1r1w_ram.v
done

# The same withheld-participant workload must retain its direct-actor behavior.
# Direct actors have no snapshot provider; check their public output boundary.
if [[ "$kind" == reduction ]]; then
    direct="$stage/direct"
    mkdir -p "$direct"
    erl -noshell -pa _build/test/lib/erl_hls/ebin _build/test/lib/erl_hls/test \
        -eval 'ok=hls_actor_debug_dslx:write(direct_reduction,hd(init:get_plain_arguments()),#{}),halt().' -extra "$direct"
    "$xls_root/ir_converter_main" --top=Top --warnings_as_errors=false \
        --dslx_path="$direct:$project_root/priv/xls/lib:$project_root/priv/xls/fabric" \
        --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" "$direct/actor_debug.x" > "$direct/actor_debug.ir"
    "$xls_root/opt_main" "$direct/actor_debug.ir" > "$direct/actor_debug.opt.ir"
    "$xls_root/codegen_main" --pipeline_stages=2 --delay_model=unit \
        --flop_inputs=false --flop_outputs=true --use_system_verilog=false --reset=reset \
        --fifo_module= --module_name=actor_debug "$direct/actor_debug.opt.ir" > "$direct/actor_debug.v"
    iverilog -g2012 -s hls_reduction_direct_tb -o "$direct/test.vvp" \
        test/rtl/debug/hls_reduction_direct_tb.sv "$direct/actor_debug.v" "$direct/actor_debug_wrapper.v"
    vvp "$direct/test.vvp"
fi
