#!/usr/bin/env bash
set -euo pipefail
xls_root=${1:?usage: test_logical_types.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/logical-types"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
source tools/backend_env.sh test
erl -noshell -eval 'ok = hls_dense_topology_dslx:write(hd(init:get_plain_arguments())), halt().' -extra "$stage"
cp "$erl_hls_root"/priv/xls/lib/*.x apps/hls_lowering/priv/xls/lib/*.x "$stage/"
cp "$erl_hls_root"/priv/xls/fabric/*.x "$stage/"
source tools/scheduler_ram_configurations.sh
for fixture in direct shared; do
    rams=(--pipeline-stages 2)
    [[ "$fixture" != shared ]] || rams+=(--ram-configurations "$(scheduler_ram_configurations 1)")
    prefix="$stage/dense_$fixture"
    python3 "$erl_hls_root/tools/compile_xls.py" "$prefix.x" "$xls_root" --output "$prefix-build" \
        --top Top --name "dense_$fixture" \
        "${rams[@]}"
    bash "$erl_hls_root/tools/check_rtl_structure.sh" "dense_${fixture}_wrapper" "$prefix-check" \
        "$prefix-build/dense_$fixture.v" "${prefix}_wrapper.v" "$erl_hls_root"/priv/rtl/hls_1r1w_ram.v
    iverilog -g2012 -I "$stage" -DDENSE_TOP="dense_${fixture}_wrapper" \
        -s logical_topology_tb -o "$prefix.vvp" "$erl_hls_root/test/rtl/logical_topology_tb.sv" \
        "$prefix-build/dense_$fixture.v" "${prefix}_wrapper.v" "$erl_hls_root"/priv/rtl/hls_1r1w_ram.v
    vvp "$prefix.vvp"
done
