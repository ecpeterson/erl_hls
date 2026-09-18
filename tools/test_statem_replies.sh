#!/usr/bin/env bash
# Exercise retained calls through public singleton/topology ports at two schedules.
set -euo pipefail
xls_root=${1:?usage: test_statem_replies.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/statem-replies"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
erl -noshell -pa _build/test/lib/erl_hls/ebin _build/test/lib/erl_hls/test \
    -eval 'ok = hls_statem_reply_dslx:write(hd(init:get_plain_arguments())), halt().' -extra "$stage"
cp priv/xls/lib/*.x priv/xls/fabric/*.x "$stage/"
interpreter=${ERL_HLS_INTERPRETER:-"$xls_root/interpreter_main"}
for unit in "$stage/statem_direct.x" "$stage/statem_events.x" "$stage/statem_reduction_replies.x" "$stage/hls_reply.x"; do
    "$interpreter" --compare=jit --warnings_as_errors=false \
        --dslx_path="$stage" --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" "$unit"
done
source tools/phi_scheduler_rams.sh
for kind in direct shared; do
    rams=(--ram-configurations "")
    top="__statem_${kind}__Top_0_next"
    if [[ "$kind" == shared ]]; then
        rams=(--ram-configurations "$(phi_scheduler_ram_configurations 1)")
        top=statem_shared_wrapper
    fi
    for stages in 2 3; do
        prefix="$stage/$kind-p$stages"
        sources=("$prefix/statem.v")
        if [[ "$kind" == shared ]]; then sources+=("$stage/statem_shared_wrapper.v" priv/rtl/hls_1r1w_ram.v); fi
        python3 tools/compile_xls.py "$stage/statem_$kind.x" "$xls_root" --output "$prefix" \
            --name statem --top Top --pipeline-stages "$stages" "${rams[@]}"
        bash tools/check_rtl_structure.sh "$top" "$prefix-check" "${sources[@]}"
        iverilog -g2012 -s "statem_reply_${kind}_tb" -o "$prefix.vvp" \
            "test/rtl/statem_reply_${kind}_tb.sv" "${sources[@]}"
        vvp "$prefix.vvp" | tee "$prefix.sim.log"
    done
done
