#!/usr/bin/env bash
set -euo pipefail

stage=${1:?usage: remote_phi_relax_xls.sh STAGE XLS_ROOT}
xls_root=${2:?usage: remote_phi_relax_xls.sh STAGE XLS_ROOT}
stdlib="$xls_root/xls/dslx/stdlib"

cd "$stage"
"$xls_root/interpreter_main" \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    phi_relax_lane.x
"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    --top=RelaxLane \
    phi_relax_lane.x > phi_relax_lane.ir
"$xls_root/opt_main" phi_relax_lane.ir > phi_relax_lane.opt.ir
"$xls_root/codegen_main" \
    --pipeline_stages=1 \
    --delay_model=unit \
    --flop_inputs=false \
    --flop_outputs=true \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    phi_relax_lane.opt.ir > phi_relax_lane.v
