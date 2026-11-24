#!/usr/bin/env bash
# Finite host-versus-generated-RTL checks; the stage must not already exist.
set -euo pipefail
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
xls_root=${1:?usage: test_protocol_codecs.sh XLS_ROOT FRESH_STAGE [default|layouts|wide]}
stage=${2:?usage: test_protocol_codecs.sh XLS_ROOT FRESH_STAGE [default|layouts|wide]}
cd "$project_root"
rebar3 as test compile
source tools/hls_fabric/backend_env.sh test
mode=${3:-default}
case "$mode" in
    default)
        erl -noshell -eval 'ok = hls_protocol_codec_validation:prepare(hd(init:get_plain_arguments())), halt().' -extra "$stage"
        directories=("$stage")
        names=(unaligned full constant small)
        ;;
    wide)
        erl -noshell -eval 'ok = hls_protocol_codec_validation:prepare_wide(hd(init:get_plain_arguments())), halt().' -extra "$stage"
        directories=("$stage")
        names=(unaligned full constant small)
        ;;
    layouts)
        erl -noshell -eval 'ok = hls_protocol_codec_validation:prepare_layouts(hd(init:get_plain_arguments())), halt().' -extra "$stage"
        directories=("$stage/words1" "$stage/words3")
        names=(narrow constant small)
        ;;
    *) echo "mode must be default, layouts or wide" >&2; exit 2 ;;
esac
for directory in "${directories[@]}"; do
    for name in "${names[@]}"; do
        "$xls_root/ir_converter_main" --top="codec_$name" --dslx_path="$directory:$ERL_HLS_COMPILE_ROOT/priv/xls/lib" --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" "$directory/codec_$name.x" > "$directory/$name.ir" 2> "$directory/$name-convert.log"
        "$xls_root/opt_main" "$directory/$name.ir" > "$directory/$name.opt.ir" 2> "$directory/$name-opt.log"
        "$xls_root/codegen_main" --generator=combinational --use_system_verilog=false --module_name="codec_$name" "$directory/$name.opt.ir" > "$directory/codec_$name.v" 2> "$directory/$name-codegen.log"
        iverilog -g2012 -s tb -o "$directory/$name.vvp" "$directory/codec_$name.v" "$directory/${name}_tb.sv"
        vvp "$directory/$name.vvp"
    done
done
