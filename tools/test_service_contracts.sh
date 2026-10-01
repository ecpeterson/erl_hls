#!/usr/bin/env bash
set -euo pipefail
xls_root=${1:?usage: test_service_contracts.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/service_contracts"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
erl -noshell -pa _build/test/lib/erl_hls/ebin _build/test/lib/erl_hls/test \
    -eval 'ok = file:write_file(hd(init:get_plain_arguments()), xls_parse:to_xls("test/hls_reply_fixture.erl")), halt().' \
    -extra "$stage/service.x"
cp priv/xls/lib/*.x "$stage/"
for schedule in 1:1 2:1 3:2; do
    stages=${schedule%:*}; interval=${schedule#*:}
    prefix="$stage/p$stages-ii$interval"
    python3 tools/compile_xls.py "$stage/service.x" "$xls_root" --output "$prefix" \
        --top Top --name reply_service --pipeline-stages "$stages" \
        --initiation-interval "$interval"
    bash tools/check_rtl_structure.sh __service__Top_0_next "$prefix-check" "$prefix/reply_service.v"
    iverilog -g2012 -s service_contracts_tb -o "$prefix.vvp" \
        test/rtl/service_contracts_tb.sv "$prefix/reply_service.v"
    vvp "$prefix.vvp" | tee "$prefix.sim.log"
done
