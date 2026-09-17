#!/usr/bin/env bash
set -euo pipefail
xls_root=${1:?usage: test_actor_debug.sh XLS_ROOT [STAGE] [small|mailbox|direct_mailbox|mailbox_mixed|reduction|aggregate|direct_reduction|phi]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/actor-debug"}
kind=${3:-small}
case "$kind" in small|mailbox|direct_mailbox|mailbox_mixed|reduction|aggregate|direct_reduction|phi) ;; *) echo "unknown actor fixture: $kind" >&2; exit 1;; esac
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
erl -noshell -pa _build/test/lib/erl_hls/ebin _build/test/lib/erl_hls/test \
    -eval '[Stage, KindText] = init:get_plain_arguments(),
        Kind = maps:get(KindText, #{"small" => small, "mailbox" => mailbox, "direct_mailbox" => direct_mailbox, "mailbox_mixed" => mailbox_mixed, "phi" => phi, "reduction" => reduction, "aggregate" => aggregate, "direct_reduction" => direct_reduction}),
        Options = case Kind of small -> #{}; K when K =:= direct_reduction; K =:= direct_mailbox -> #{direct_actor_debug => true};
            mailbox_mixed -> #{direct_actor_debug => true, mailbox_debug => true}; _ -> #{mailbox_debug => true} end,
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
codegen_options=(--fifo_module=)
[[ "$scheduler_count" == 0 ]] || codegen_options+=(--ram_configurations="$(phi_scheduler_ram_configurations "$scheduler_count")")
if [[ "$kind" == direct_reduction ]]; then
    production="$stage/production"
    mkdir -p "$production"
    erl -noshell -pa _build/test/lib/erl_hls/ebin _build/test/lib/erl_hls/test \
        -eval 'ok=hls_actor_debug_dslx:write(direct_reduction,hd(init:get_plain_arguments()),#{}),halt().' -extra "$production"
    python3 - "$production/actor_debug_wrapper.v" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_text(path.read_text().replace("actor_debug", "actor_debug_production"))
PY
    "$xls_root/ir_converter_main" --top=Top --warnings_as_errors=false \
        --dslx_path="$production:$project_root/priv/xls/lib:$project_root/priv/xls/fabric" \
        --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" "$production/actor_debug.x" > "$production/actor_debug.ir"
    "$xls_root/opt_main" "$production/actor_debug.ir" > "$production/actor_debug.opt.ir"
fi
stages_to_test=(2 3)
[[ "$kind" != mailbox ]] || stages_to_test+=(4)
for stages in "${stages_to_test[@]}"; do
    "$xls_root/codegen_main" --pipeline_stages="$stages" --delay_model=unit \
        --flop_inputs=false --flop_outputs=true --use_system_verilog=false --reset=reset \
        --module_name=actor_debug "${codegen_options[@]}" \
        "$stage/actor_debug.opt.ir" > "$stage/actor_debug_$stages.v"
    reference_options=(--reference-top actor_debug_production_wrapper)
    if [[ "$kind" == direct_reduction ]]; then
        "$xls_root/codegen_main" --pipeline_stages="$stages" --delay_model=unit \
            --flop_inputs=false --flop_outputs=true --use_system_verilog=false --reset=reset \
            --fifo_module= --module_name=actor_debug_production \
            "$production/actor_debug.opt.ir" > "$production/actor_debug_$stages.v"
        reference_options+=(--reference-rtl "$production/actor_debug_$stages.v" --reference-rtl "$production/actor_debug_wrapper.v")
    fi
    python3 tools/test_topology_debug_integration.py --yosys "${YOSYS:-yosys}" \
        --top actor_debug_wrapper --stage "$stage/p$stages" \
        --actor-projection "$stage/small-actors.json" --actor-test "$kind" \
        "${reference_options[@]}" \
        "$stage/actor_debug_$stages.v" "$stage/actor_debug_wrapper.v" priv/rtl/hls_1r1w_ram.v
done
