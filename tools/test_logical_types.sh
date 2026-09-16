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
erl -noshell -pa _build/test/lib/erl_hls/ebin _build/test/lib/erl_hls/test \
    -eval 'ok = hls_logical_dslx:write(hd(init:get_plain_arguments())), halt().' -extra "$stage"
options=(--warnings_as_errors=false --dslx_path="$project_root/priv/xls/lib"
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib")
"$xls_root/interpreter_main" --compare=jit "${options[@]}" "$stage/codecs.x"
"$xls_root/ir_converter_main" --top=probe "${options[@]}" "$stage/codecs.x" > "$stage/codecs.ir"
"$xls_root/opt_main" "$stage/codecs.ir" > "$stage/codecs.opt.ir"
"$xls_root/codegen_main" --generator=combinational --module_name=probe \
    --use_system_verilog=false "$stage/codecs.opt.ir" > "$stage/codecs.v"
iverilog -g2012 -s logical_codecs_tb -o "$stage/codecs.vvp" \
    "$stage/codecs.v" test/rtl/logical_codecs_tb.sv
vvp "$stage/codecs.vvp" +vectors="$stage/codecs.mem"
cp priv/xls/lib/*.x "$stage/"
for schedule in 1:1 2:1 3:2; do
    stages=${schedule%:*}; interval=${schedule#*:}
    prefix="$stage/p$stages-ii$interval"
    python3 tools/compile_xls.py "$stage/service.x" "$xls_root" --output "$prefix" \
        --top Top --name logical_service --pipeline-stages "$stages" \
        --initiation-interval "$interval"
    bash tools/check_rtl_structure.sh __service__Top_0_next "$prefix-check" "$prefix/logical_service.v"
    iverilog -g2012 -s logical_service_tb -o "$prefix.vvp" \
        test/rtl/logical_service_tb.sv "$prefix/logical_service.v"
    vvp "$prefix.vvp" +requests="$stage/requests.mem" +replies="$stage/replies.mem"
done
