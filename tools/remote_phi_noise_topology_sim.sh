#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

stage=${1:?usage: remote_phi_noise_topology_sim.sh STAGE XLS_ROOT [TIMEOUT]}
xls_root=${2:?usage: remote_phi_noise_topology_sim.sh STAGE XLS_ROOT [TIMEOUT]}
stage_timeout=${3:-2h}
stdlib="$xls_root/xls/dslx/stdlib"

cd "$stage"

for artifact in \
    phi_noise_topology.ir \
    phi_noise_topology.opt.ir \
    phi_noise_topology.v \
    phi_noise_topology.vvp \
    phi_noise_topology.metrics \
    phi_noise_topology.sim.log
do
    rm -f -- "$artifact" "$artifact.new" "$artifact.failed"
done
for label in ir opt codegen iverilog vvp; do
    report="phi_noise_topology-$label.time"
    rm -f -- "$report" "$report.new" "$report.failed"
done

timed_output() {
    label=$1
    output=$2
    shift 2
    if /usr/bin/time -v -o "$label.time.new" \
            timeout --signal=TERM --kill-after=5m "$stage_timeout" \
            "$@" > "$output.new"; then
        mv "$label.time.new" "$label.time"
        mv "$output.new" "$output"
    else
        status=$?
        [[ ! -e "$label.time.new" ]] ||
            mv "$label.time.new" "$label.time.failed"
        [[ ! -e "$output.new" ]] || mv "$output.new" "$output.failed"
        return "$status"
    fi
}

timed_command() {
    label=$1
    shift
    if /usr/bin/time -v -o "$label.time.new" \
            timeout --signal=TERM --kill-after=5m "$stage_timeout" \
            "$@"; then
        mv "$label.time.new" "$label.time"
    else
        status=$?
        [[ ! -e "$label.time.new" ]] ||
            mv "$label.time.new" "$label.time.failed"
        return "$status"
    fi
}

timed_output \
    phi_noise_topology-ir \
    phi_noise_topology.ir \
    "$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    --top=Top \
    phi_noise_topology.x

timed_output \
    phi_noise_topology-opt \
    phi_noise_topology.opt.ir \
    "$xls_root/opt_main" \
    phi_noise_topology.ir

timed_output \
    phi_noise_topology-codegen \
    phi_noise_topology.v \
    "$xls_root/codegen_main" \
    --pipeline_stages=1 \
    --delay_model=unit \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    phi_noise_topology.opt.ir

timed_command \
    phi_noise_topology-iverilog \
    iverilog \
    -g2012 \
    -s phi_noise_topology_tb \
    -o phi_noise_topology.vvp.new \
    phi_noise_topology_tb.sv \
    phi_noise_topology.v
mv phi_noise_topology.vvp.new phi_noise_topology.vvp

if /usr/bin/time -v -o phi_noise_topology-vvp.time.new \
        timeout --signal=TERM --kill-after=5m "$stage_timeout" \
        vvp phi_noise_topology.vvp 2>&1 |
        tee phi_noise_topology.sim.log.new; then
    mv phi_noise_topology-vvp.time.new phi_noise_topology-vvp.time
    mv phi_noise_topology.sim.log.new phi_noise_topology.sim.log
else
    status=$?
    [[ ! -e phi_noise_topology-vvp.time.new ]] ||
        mv phi_noise_topology-vvp.time.new \
            phi_noise_topology-vvp.time.failed
    [[ ! -e phi_noise_topology.sim.log.new ]] ||
        mv phi_noise_topology.sim.log.new \
            phi_noise_topology.sim.log.failed
    exit "$status"
fi

{
    wc -lc \
        phi_noise_topology.x \
        phi_noise_topology.ir \
        phi_noise_topology.opt.ir \
        phi_noise_topology.v
    sha256sum phi_noise_topology.x phi_noise_topology.v
    grep -H -E \
        'Elapsed \(wall clock\)|Maximum resident set size' \
        phi_noise_topology-*.time
} > phi_noise_topology.metrics.new
mv phi_noise_topology.metrics.new phi_noise_topology.metrics
cat phi_noise_topology.metrics
