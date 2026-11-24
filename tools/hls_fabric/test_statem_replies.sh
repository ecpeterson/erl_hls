#!/usr/bin/env bash
# Exercise retained calls through public singleton/topology ports at two schedules.
set -euo pipefail
xls_root=${1:?usage: test_statem_replies.sh XLS_ROOT [STAGE] [statem|server]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
stage=${2:-"$project_root/_build/statem-replies"}
kind=${3:-statem}
case "$kind" in statem|server) ;; *) echo "expected statem or server" >&2; exit 2;; esac
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
source tools/hls_fabric/backend_env.sh test
if [[ "$kind" == server ]]; then
    erl -noshell -eval 'ok = hls_statem_reply_dslx:write_server(hd(init:get_plain_arguments())), halt().' -extra "$stage"
    definitions=(-DSERVER_CALLBACKS)
else
    erl -noshell -eval 'ok = hls_statem_reply_dslx:write(hd(init:get_plain_arguments())), halt().' -extra "$stage"
    definitions=()
fi
cp "$hls_compile_root"/priv/xls/lib/*.x apps/hls_target/priv/xls/lib/*.x "$hls_fabric_root"/priv/xls/fabric/*.x "$stage/"
if [[ "$kind" == statem ]]; then
    interpreter=${ERL_HLS_INTERPRETER:-"$xls_root/interpreter_main"}
    for unit in "$stage/statem_direct.x" "$stage/statem_events.x" "$stage/statem_reduction_replies.x" "$stage/hls_reply.x"; do
        # The pinned JIT aborts in shared_internal_burst_test (LLVM bitwidth assertion).
        # Interpret these finite transitions directly; public-port RTL is checked below.
        "$interpreter" --evaluator=dslx-interpreter --compare=none --max_ticks=1000 --warnings_as_errors=false \
            --dslx_path="$stage:$hls_compile_root/priv/xls/lib:$hls_fabric_root/priv/xls/fabric" --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" "$unit"
    done
fi
source tools/hls_fabric/scheduler_ram_configurations.sh
for kind in shared; do
    rams=(--ram-configurations "")
    top="__statem_${kind}__Top_0_next"
    if [[ "$kind" == shared ]]; then
        rams=(--ram-configurations "$(scheduler_ram_configurations 1)")
        top=statem_shared_wrapper
    fi
    for stages in 2 3; do
        prefix="$stage/$kind-p$stages"
        sources=("$prefix/statem.v")
        if [[ "$kind" == shared ]]; then sources+=("$stage/statem_shared_wrapper.v" "$hls_target_root"/priv/rtl/hls_1r1w_ram.v); fi
        python3 "$project_root/tools/compile_xls.py" "$stage/statem_$kind.x" "$xls_root" --output "$prefix" \
            --name statem --top Top --pipeline-stages "$stages" "${rams[@]}"
        bash "$project_root/tools/check_rtl_structure.sh" "$top" "$prefix-check" "${sources[@]}"
        iverilog -g2012 "${definitions[@]}" -s "statem_reply_${kind}_tb" -o "$prefix.vvp" \
            "apps/hls_fabric/test/rtl/statem_reply_${kind}_tb.sv" "${sources[@]}"
        vvp "$prefix.vvp" | tee "$prefix.sim.log"
    done
done
