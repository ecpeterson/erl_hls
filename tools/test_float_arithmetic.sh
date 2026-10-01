#!/usr/bin/env bash
set -euo pipefail
xls_root=${1:?usage: test_float_arithmetic.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/typed-float"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
erl -noshell -pa _build/test/lib/erl_hls/ebin _build/test/lib/erl_hls/test \
    -eval 'ok = hls_float_dslx:write(hd(init:get_plain_arguments())), halt().' -extra "$stage"
options=(--warnings_as_errors=false --dslx_path="$project_root/priv/xls/lib"
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib")
for width in 16 32 64; do
    name="float$width"
    "$xls_root/interpreter_main" --compare=jit "${options[@]}" "$stage/$name.x"
    "$xls_root/interpreter_main" --compare=jit "${options[@]}" "$stage/${name}_actor.x"
    # Exercise typed collection lowering through serialized IR as well as JIT:
    # generic helpers instantiated with APFloat used to produce invalid IR names.
    "$xls_root/ir_converter_main" --top=slice "${options[@]}" "$stage/$name.x" > "$stage/${name}_slice.ir"
    "$xls_root/opt_main" "$stage/${name}_slice.ir" > "$stage/${name}_slice.opt.ir"
    "$xls_root/codegen_main" --generator=combinational --use_system_verilog=false \
        "$stage/${name}_slice.opt.ir" > "$stage/${name}_slice.v"
    for target in probe actor; do
        if [[ $target == probe ]]; then source="$name"; top=probe;
        else source="${name}_actor"; top=Top; fi
        prefix="$stage/${name}_$target"
        "$xls_root/ir_converter_main" --top="$top" "${options[@]}" "$stage/$source.x" > "$prefix.ir"
        "$xls_root/opt_main" "$prefix.ir" > "$prefix.opt.ir"
        if [[ $target == probe ]]; then
            "$xls_root/codegen_main" --generator=combinational --module_name=float_probe \
                --use_system_verilog=false "$prefix.opt.ir" > "$prefix.v"
            iverilog -g2012 -I "$stage" -s hls_float_probe_tb -DFLOAT_WIDTH="$width" \
                -DFLOAT_VECTORS="\"$name.svh\"" -o "$prefix.vvp" \
                test/rtl/hls_float_probe_tb.sv "$prefix.v"
            vvp "$prefix.vvp" | tee "$prefix.sim.log"
        else
            "$xls_root/codegen_main" --pipeline_stages=3 --delay_model=unit \
                --flop_inputs=false --flop_outputs=true --use_system_verilog=false \
                --module_name=float_actor --reset=reset --fifo_module= \
                "$prefix.opt.ir" > "$prefix.v"
            case $width in
                16) initial="16'h3e00";;
                32) initial="32'h3fc00000";;
                64) initial="64'h3ff8000000000000";;
            esac
            bash tools/check_rtl_structure.sh float_actor "$prefix-check" "$prefix.v"
            iverilog -g2012 -I "$stage" -s hls_float_actor_tb -DFLOAT_WIDTH="$width" \
                -DFLOAT_INITIAL="$initial" -DFLOAT_ACTOR_VECTORS="\"${name}_actor.svh\"" \
                -o "$prefix.vvp" test/rtl/hls_float_actor_tb.sv "$prefix.v"
            vvp "$prefix.vvp" | tee "$prefix.sim.log"
        fi
    done
done
for invalid in integer_operator wrong_precision integer_operand; do
    if "$xls_root/ir_converter_main" --top=probe "${options[@]}" "$stage/$invalid.x" \
            > "$stage/$invalid.ir" 2> "$stage/$invalid.log"; then
        echo "XLS accepted $invalid" >&2; exit 1
    fi
    if ! grep -Eq 'TypeInferenceError|TypeMismatch|Type mismatch|type mismatch|type error' "$stage/$invalid.log"; then
        cat "$stage/$invalid.log" >&2; exit 1
    fi
    echo "PASS: XLS rejects $invalid"
done
