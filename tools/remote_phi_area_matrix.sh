#!/usr/bin/env bash
set -euo pipefail

stage=${1:?usage: remote_phi_area_matrix.sh STAGE XLS_ROOT}
xls_root=${2:?usage: remote_phi_area_matrix.sh STAGE XLS_ROOT}
stdlib="$xls_root/xls/dslx/stdlib"

cd "$stage"
"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    --top=Top \
    phi_noise_d2.x > phi_noise_d2.ir
"$xls_root/opt_main" phi_noise_d2.ir > phi_noise_d2.opt.ir
"$xls_root/codegen_main" \
    --pipeline_stages=1 \
    --delay_model=unit \
    --flop_inputs=false \
    --flop_outputs=true \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    phi_noise_d2.opt.ir > phi_noise_d2.v
