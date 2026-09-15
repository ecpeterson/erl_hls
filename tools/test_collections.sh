#!/usr/bin/env bash
set -euo pipefail
xls_root=${1:?usage: test_collections.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/collections"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
erl -noshell -pa _build/test/lib/erl_hls/ebin _build/test/lib/erl_hls/test \
    -eval 'ok = xls_collection_dslx:write(hd(init:get_plain_arguments())), halt().' -extra "$stage"
options=(--warnings_as_errors=false --dslx_path="$project_root/priv/xls/lib"
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib")
"$xls_root/interpreter_main" --compare=jit "${options[@]}" priv/xls/lib/hls_lists.x
"$xls_root/interpreter_main" --compare=jit "${options[@]}" test_data/hls_collections_semantics.x
"$xls_root/ir_converter_main" --top=constant_probe "${options[@]}" \
    test_data/hls_collections_semantics.x > "$stage/constant.ir"
"$xls_root/opt_main" "$stage/constant.ir" > "$stage/constant.opt.ir"
"$xls_root/codegen_main" --generator=combinational --module_name=constant_probe \
    --use_system_verilog=false "$stage/constant.opt.ir" > "$stage/constant.v"
yosys=${ERL_HLS_YOSYS:-$(command -v yosys || echo "$project_root/experiments/07-openxc7/.apio/packages/oss-cad-suite/bin/yosys")}
"$yosys" -Q -T -p "read_verilog -sv \"$stage/constant.v\"; hierarchy -top constant_probe; proc; opt; check -assert; select -assert-none t:*" > "$stage/constant.log"
echo "PASS: constant collection accesses and checks optimize to wiring"
for width in 8 32 64; do
    for sign in u s; do
        prefix="$stage/$sign$width"
        "$xls_root/interpreter_main" --compare=jit "${options[@]}" "$prefix.x"
        "$xls_root/ir_converter_main" --top=probe "${options[@]}" "$prefix.x" > "$prefix.ir"
        "$xls_root/opt_main" "$prefix.ir" > "$prefix.opt.ir"
        "$xls_root/codegen_main" --generator=combinational --module_name=collection_probe \
            --use_system_verilog=false "$prefix.opt.ir" > "$prefix.v"
        iverilog -g2012 -s xls_collection_tb -DCOLLECTION_WIDTH="$width" \
            -DCOLLECTION_COUNT="$(cat "$prefix.count")" -DCOLLECTION_VECTORS="\"$prefix.mem\"" \
            -o "$prefix.vvp" test/rtl/xls_collection_tb.sv "$prefix.v"
        timeout 60s vvp "$prefix.vvp" | tee "$prefix.sim.log"
    done
done
