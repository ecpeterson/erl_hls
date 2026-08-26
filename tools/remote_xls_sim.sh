#!/usr/bin/env bash
set -euo pipefail

stage=$1
xls_root=$2
stdlib="$xls_root/xls/dslx/stdlib"

cd "$stage"

"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_stdlib_path="$stdlib" \
    --top=Top \
    regsvc.x > regsvc.ir

"$xls_root/opt_main" regsvc.ir > regsvc.opt.ir

"$xls_root/codegen_main" \
    --pipeline_stages=1 \
    --delay_model=unit \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    regsvc.opt.ir > regsvc.v

iverilog \
    -g2012 \
    -s regsvc_tb \
    -o regsvc.vvp \
    regsvc_tb.sv \
    regsvc_instrumented_wrapper.v \
    xls_debug_monitor.v \
    regsvc_wrapper.v \
    regsvc.v

vvp regsvc.vvp
