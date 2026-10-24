#!/usr/bin/env bash
# Exercise ownership, production source predicates and physical member writes.
set -euo pipefail
xls_root=${1:?usage: test_indexed_collection.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
stage=${2:-_build/indexed-collection}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
python3 tools/build.py as test compile
source tools/backend_env.sh test
erl +S 2:2 -noshell -eval 'ok = hls_indexed_adapter_dslx:write(hd(init:get_plain_arguments())), halt().' -extra "$stage"
for source in "$project_root/priv/xls/lib/mailbox.x" \
              "$project_root/priv/xls/templates/indexed_collection_core_tests.x" \
              "$project_root/priv/xls/lib/indexed_gather_ram.x" \
              "$stage/indexed_adapter.x"; do
    "$xls_root/interpreter_main" --compare=jit --warnings_as_errors=false \
        --dslx_path="$stage:$project_root/priv/xls/lib:$project_root/priv/xls/templates:$erl_hls_root/priv/xls/lib" \
        --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" "$source"
done
iverilog -g2012 -Wall -s hls_indexed_gather_ram_tb -o "$stage/ram.vvp" \
    priv/rtl/hls_indexed_gather_ram.v test/rtl/hls_indexed_gather_ram_tb.sv
vvp "$stage/ram.vvp"
