#!/usr/bin/env bash
set -euo pipefail

stage=${1:?usage: remote_sequential_xls.sh STAGE XLS_ROOT}
xls_root=${2:?usage: remote_sequential_xls.sh STAGE XLS_ROOT}
stdlib="$xls_root/xls/dslx/stdlib"

cd "$stage"
"$xls_root/interpreter_main" \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    --max_ticks=100000 \
    phi_sequential_core.x
"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    --top=SequentialCore \
    phi_sequential_core.x > phi_sequential_core.ir
"$xls_root/opt_main" \
    phi_sequential_core.ir > phi_sequential_core.opt.ir
"$xls_root/codegen_main" \
    --pipeline_stages=1 \
    --delay_model=unit \
    --flop_inputs=false \
    --flop_outputs=true \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    phi_sequential_core.opt.ir > phi_sequential_core.v
