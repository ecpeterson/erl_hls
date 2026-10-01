#!/usr/bin/env bash
# Check ordered gathers and scalar completion continuations through the ordinary actor.
set -euo pipefail
xls_root=${1:?usage: test_statem_gathers.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/statem-gathers"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
erl -noshell -pa _build/test/lib/erl_hls/ebin _build/test/lib/erl_hls/test \
    -eval 'ok = xls_statem_gather_dslx:write(hd(init:get_plain_arguments())), halt().' -extra "$stage"
cp priv/xls/lib/*.x priv/xls/fabric/*.x "$stage/"
for unit in "$stage/statem_gather.x" "$stage/statem_gather_sites.x"; do
    "${ERL_HLS_INTERPRETER:-"$xls_root/interpreter_main"}" --compare=jit --warnings_as_errors=false \
        --dslx_path="$stage" --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" "$unit"
done
