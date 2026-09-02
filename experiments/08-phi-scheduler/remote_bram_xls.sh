#!/usr/bin/env bash
set -euo pipefail

stage=${1:?usage: remote_bram_xls.sh STAGE XLS_ROOT}
xls_root=${2:?usage: remote_bram_xls.sh STAGE XLS_ROOT}
stdlib="$xls_root/xls/dslx/stdlib"
ram_request=phi_sequential_bram_core__ram_req_out
ram_response=phi_sequential_bram_core__ram_resp_in
ram_completion=phi_sequential_bram_core__ram_wr_comp_in
ram_configuration="actor_state:1RW:$ram_request:$ram_response:$ram_completion"

cd "$stage"
"$xls_root/interpreter_main" \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    --max_ticks=250000 \
    phi_sequential_bram_core.x
"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    --top=SequentialBramCore \
    phi_sequential_bram_core.x > phi_sequential_bram_core.ir
"$xls_root/opt_main" \
    phi_sequential_bram_core.ir > phi_sequential_bram_core.opt.ir
"$xls_root/codegen_main" \
    --pipeline_stages=2 \
    --worst_case_throughput=2 \
    --delay_model=unit \
    --flop_inputs=false \
    --flop_outputs=true \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    --ram_configurations="$ram_configuration" \
    phi_sequential_bram_core.opt.ir > phi_sequential_bram_core.v
