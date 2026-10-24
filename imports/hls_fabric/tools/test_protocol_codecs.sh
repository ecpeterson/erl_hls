#!/usr/bin/env bash
# Finite host-versus-generated-RTL checks; the stage must not already exist.
set -euo pipefail
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
xls_root=${1:?usage: test_protocol_codecs.sh XLS_ROOT FRESH_STAGE}
stage=${2:?usage: test_protocol_codecs.sh XLS_ROOT FRESH_STAGE}
cd "$project_root"
rebar3 as test compile
source tools/backend_env.sh test
erl -noshell -eval 'ok = hls_protocol_codec_validation:prepare(hd(init:get_plain_arguments())), halt().' -extra "$stage"
for name in unaligned full constant small; do
    "$xls_root/ir_converter_main" --top="codec_$name" --dslx_path="$ERL_HLS_ROOT/priv/xls/lib" --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" "$stage/codec_$name.x" > "$stage/$name.ir" 2> "$stage/$name-convert.log"
    "$xls_root/opt_main" "$stage/$name.ir" > "$stage/$name.opt.ir" 2> "$stage/$name-opt.log"
    "$xls_root/codegen_main" --generator=combinational --use_system_verilog=false --module_name="codec_$name" "$stage/$name.opt.ir" > "$stage/codec_$name.v" 2> "$stage/$name-codegen.log"
    iverilog -g2012 -s tb -o "$stage/$name.vvp" "$stage/codec_$name.v" "$stage/${name}_tb.sv"
    vvp "$stage/$name.vvp"
done
