#!/usr/bin/env bash
set -euo pipefail
xls_root=${1:?usage: test_direct_admission.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/direct-admission-tests"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
erl -noshell -pa _build/test/lib/erl_hls/ebin _build/test/lib/erl_hls/test -eval '
    [Stage] = init:get_plain_arguments(),
    ok = file:write_file(filename:join(Stage,"ordered_egress_actor.x"),
        xls_parse:to_xls("test/ordered_egress_actor.erl")),
    lists:foreach(fun(Depth) ->
        Path = filename:join([Stage,"d" ++ integer_to_list(Depth),"ordered_egress_topology.x"]),
        ok = filelib:ensure_dir(Path),
        Profile = (ordered_egress_topology:profile())#{channel_depth := Depth},
        ok = file:write_file(Path, xls_topology_dslx:emit(
            hls_topology:from_module(ordered_egress_topology), Profile))
    end, [1,2]), halt().' -extra "$stage"
options=(--warnings_as_errors=false
    --dslx_path="$stage:$project_root/priv/xls/lib:$project_root/priv/xls/fabric"
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib")
for kind in service d1 d2; do
    if [[ "$kind" == service ]]; then
        source="$stage/ordered_egress_actor.x"; top=Service
        module=direct_admission_service; tb=direct_admission_tb
    else
        source="$stage/$kind/ordered_egress_topology.x"; top=Top
        module=__ordered_egress_topology__Top_0_next; tb=ordered_egress_topology_tb
    fi
    "$xls_root/ir_converter_main" --top="$top" "${options[@]}" "$source" > "$stage/$kind.ir"
    "$xls_root/opt_main" "$stage/$kind.ir" > "$stage/$kind.opt.ir"
    for schedule in 1:1 2:1 3:2; do
        stages=${schedule%:*}; interval=${schedule#*:}
        prefix="$stage/$kind-p$stages-ii$interval"
        "$xls_root/codegen_main" --pipeline_stages="$stages" \
            --worst_case_throughput="$interval" --delay_model=unit \
            --flop_inputs=false --flop_outputs=true --use_system_verilog=false \
            --module_name="$module" --reset=reset --fifo_module= \
            "$stage/$kind.opt.ir" > "$prefix.v"
        bash tools/check_rtl_structure.sh "$module" "$prefix-check" "$prefix.v"
        iverilog -g2012 -s "$tb" -o "$prefix.vvp" "test/rtl/$tb.sv" "$prefix.v"
        timeout 60s vvp "$prefix.vvp" | tee "$prefix.sim.log"
    done
done
python3 tools/test_direct_admission_formal.py --stage "$stage/formal" "$stage"/service-p*.v
python3 tools/test_topology_debug_integration.py \
    --yosys "${ERL_HLS_YOSYS:-$(command -v yosys || echo "$project_root/experiments/07-openxc7/.apio/packages/oss-cad-suite/bin/yosys")}" \
    --top __ordered_egress_topology__Top_0_next --stage "$stage/debug" "$stage/d1-p2-ii1.v"
