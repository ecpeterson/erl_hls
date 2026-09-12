#!/usr/bin/env bash
set -euo pipefail
xls_root=${1:?usage: test_helpers.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/helpers"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
erl -noshell -pa "$project_root/_build/test/lib/erl_hls/ebin" \
    "$project_root/_build/test/lib/erl_hls/test" \
    -eval 'ok = xls_helpers_dslx:write(hd(init:get_plain_arguments())), halt().' \
    -extra "$stage"
options=(--warnings_as_errors=false --dslx_path="$project_root/priv/xls/lib"
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib")
"$xls_root/interpreter_main" --compare=jit "${options[@]}" "$stage/helpers.x"
for top in factored inline; do
    "$xls_root/ir_converter_main" --top="$top" "${options[@]}" \
        "$stage/helpers.x" > "$stage/$top.ir"
    "$xls_root/opt_main" "$stage/$top.ir" > "$stage/$top.opt.ir"
    "$xls_root/codegen_main" --generator=combinational --module_name="$top" \
        --use_system_verilog=false "$stage/$top.opt.ir" > "$stage/$top.v"
done
iverilog -g2012 -s helpers_tb -o "$stage/helpers.vvp" \
    "$stage/helpers_tb.sv" "$stage/factored.v" "$stage/inline.v"
vvp "$stage/helpers.vvp"
cat > "$stage/equivalence.ys" <<EOF
read_verilog "$stage/factored.v" "$stage/inline.v"
miter -equiv -flatten factored inline helper_equivalence
prep -top helper_equivalence
sat -verify -prove trigger 0 -show-inputs -show-outputs
EOF
# Compare observable results; generated temporary names need not denote the
# same intermediate calculation in the two implementations.
"${YOSYS:-yosys}" -Q -T -s "$stage/equivalence.ys" > "$stage/equivalence.log"
echo "PASS: factored/inline RTL equivalence for all input bits"
for kind in wrong_argument wrong_result wrong_join; do
    if "$xls_root/ir_converter_main" --top=root "${options[@]}" \
            "$stage/$kind.x" > "$stage/$kind.ir" 2> "$stage/$kind.log"; then
        echo "XLS accepted $kind helper" >&2; exit 1
    fi
    pattern='[Tt]ype[Mm]ismatch|[Tt]ype mismatch|[Ss]ize mismatch'
    if ! grep -Eq "$pattern" "$stage/$kind.log"; then
        cat "$stage/$kind.log" >&2; exit 1
    fi
    echo "PASS: XLS rejects $kind helper"
done
