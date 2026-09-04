#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

stage=${1:?usage: remote_phi_decoder_profile.sh STAGE XLS_ROOT TIMEOUT SHARDS}
xls_root=${2:?usage: remote_phi_decoder_profile.sh STAGE XLS_ROOT TIMEOUT SHARDS}
stage_timeout=${3:-2h}
shard_count=${4:-3}
scheduler_count=$((2 + 2 * shard_count))
stdlib="$xls_root/xls/dslx/stdlib"
. "$stage/phi_scheduler_rams.sh"

cd "$stage"

for artifact in \
    phi_decoder_profile.ir \
    phi_decoder_profile.opt.ir \
    phi_decoder_profile.v \
    phi_decoder_profile.vvp \
    phi_decoder_profile.metrics \
    phi_decoder_profile.sim.log
do
    rm -f -- "$artifact" "$artifact.new" "$artifact.failed"
done
for label in ir opt codegen iverilog vvp; do
    report="phi_decoder_profile-$label.time"
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
        [[ ! -e "$label.time.new" ]] || mv "$label.time.new" "$label.time.failed"
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
        [[ ! -e "$label.time.new" ]] || mv "$label.time.new" "$label.time.failed"
        return "$status"
    fi
}

timed_output \
    phi_decoder_profile-ir \
    phi_decoder_profile.ir \
    "$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    --top=Top \
    phi_decoder_profile_topology.x

timed_output \
    phi_decoder_profile-opt \
    phi_decoder_profile.opt.ir \
    "$xls_root/opt_main" \
    phi_decoder_profile.ir

timed_output \
    phi_decoder_profile-codegen \
    phi_decoder_profile.v \
    "$xls_root/codegen_main" \
    --pipeline_stages=2 \
    --worst_case_throughput=2 \
    --delay_model=unit \
    --flop_inputs=false \
    --flop_outputs=true \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    --ram_configurations="$(phi_scheduler_ram_configurations "$scheduler_count")" \
    phi_decoder_profile.opt.ir

timed_command \
    phi_decoder_profile-iverilog \
    iverilog \
    -g2012 \
    -s phi_decoder_profile_tb \
    -o phi_decoder_profile.vvp.new \
    phi_decoder_profile_tb.sv \
    phi_decoder_profile_top.v \
    hls_1r1w_ram.v \
    phi_decoder_profile.v
mv phi_decoder_profile.vvp.new phi_decoder_profile.vvp

if /usr/bin/time -v -o phi_decoder_profile-vvp.time.new \
        timeout --signal=TERM --kill-after=5m "$stage_timeout" \
        vvp phi_decoder_profile.vvp 2>&1 | \
        tee phi_decoder_profile.sim.log.new; then
    mv phi_decoder_profile-vvp.time.new phi_decoder_profile-vvp.time
    mv phi_decoder_profile.sim.log.new phi_decoder_profile.sim.log
else
    status=$?
    [[ ! -e phi_decoder_profile-vvp.time.new ]] || \
        mv phi_decoder_profile-vvp.time.new phi_decoder_profile-vvp.time.failed
    [[ ! -e phi_decoder_profile.sim.log.new ]] || \
        mv phi_decoder_profile.sim.log.new phi_decoder_profile.sim.log.failed
    exit "$status"
fi

{
    printf 'shard_count=%s\n' "$shard_count"
    printf 'scheduler_count=%s\n' "$scheduler_count"
    grep -H -E 'PROFILE_RESULT|PROFILE_ACTIVITY|PASS:' \
        phi_decoder_profile.sim.log
    wc -lc \
        phi_decoder_profile_topology.x \
        phi_decoder_profile.ir \
        phi_decoder_profile.opt.ir \
        phi_decoder_profile.v
    sha256sum phi_decoder_profile_topology.x phi_decoder_profile.v
    grep -H -E \
        'Elapsed \(wall clock\)|Maximum resident set size' \
        phi_decoder_profile-ir.time \
        phi_decoder_profile-opt.time \
        phi_decoder_profile-codegen.time \
        phi_decoder_profile-iverilog.time \
        phi_decoder_profile-vvp.time
} > phi_decoder_profile.metrics.new
mv phi_decoder_profile.metrics.new phi_decoder_profile.metrics
cat phi_decoder_profile.metrics
