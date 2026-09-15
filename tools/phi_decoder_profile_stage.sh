#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

stage=${1:?usage: phi_decoder_profile_stage.sh STAGE XLS_ROOT TIMEOUT SHARDS PIPELINE_STAGES II}
xls_root=${2:?usage: phi_decoder_profile_stage.sh STAGE XLS_ROOT TIMEOUT SHARDS PIPELINE_STAGES II}
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
stage_timeout=${3:-2h}
shard_count=${4:-3}
pipeline_stages=${5:-2}
initiation_interval=${6:-1}
trace_enabled=${ERL_HLS_PHI_PROFILE_TRACE:-0}

if [[ "$trace_enabled" != 0 && "$trace_enabled" != 1 ]]; then
    echo "ERL_HLS_PHI_PROFILE_TRACE must be 0 or 1" >&2
    exit 1
fi

if [[ $(uname -s) == Darwin ]]; then
    time_arguments=(-p)
else
    time_arguments=(-v)
fi

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$@"
    else
        shasum -a 256 "$@"
    fi
}

cd "$stage"

for artifact in \
    phi_decoder_profile.vvp \
    phi_decoder_profile.scheduler_profile \
    phi_decoder_profile.trace.csv \
    phi_decoder_profile.events \
    xls_sim_bridge.o \
    xls_sim_bridge.vpi \
    phi_profile_trace.o \
    phi_profile_trace.vpi \
    phi_decoder_profile.metrics \
    phi_decoder_profile.sim.log
do
    rm -f -- "$artifact" "$artifact.new" "$artifact.failed"
done
for label in iverilog vvp; do
    report="phi_decoder_profile-$label.time"
    rm -f -- "$report" "$report.new" "$report.failed"
done

timed_command() {
    label=$1
    shift
    if /usr/bin/time "${time_arguments[@]}" -o "$label.time.new" \
            timeout --signal=TERM --kill-after=5m "$stage_timeout" \
            "$@"; then
        mv "$label.time.new" "$label.time"
    else
        status=$?
        [[ ! -e "$label.time.new" ]] || mv "$label.time.new" "$label.time.failed"
        return "$status"
    fi
}

bash "$stage/compile_phi_decoder_profile.sh" "$stage" "$xls_root" \
    "$stage_timeout" "$shard_count" "$pipeline_stages" "$initiation_interval"
compiled=$(cd "$stage/compiled" && pwd -P)

# Read the immutable artifact configuration, not the caller's environment.
read -r width height x_enabled z_enabled scheduler_count plane_count < <(
    python3 - "$compiled/phi_decoder_profile.json" <<'PYCONFIG'
import json, sys
c = json.load(open(sys.argv[1]))
print(c["width"], c["height"], int("x" in c["planes"]), int("z" in c["planes"]),
      c["scheduler_count"], len(c["planes"]))
PYCONFIG
)

timed_command \
    phi_decoder_profile-iverilog \
    iverilog \
    -g2012 \
    -s phi_decoder_profile_tb \
    -Pphi_decoder_profile_tb.WIDTH="$width" \
    -Pphi_decoder_profile_tb.HEIGHT="$height" \
    -Pphi_decoder_profile_tb.X_ENABLED="$x_enabled" \
    -Pphi_decoder_profile_tb.Z_ENABLED="$z_enabled" \
    -o phi_decoder_profile.vvp.new \
    phi_decoder_profile_tb.sv \
    "$compiled/phi_decoder_profile_top.v" \
    "$compiled/hls_1r1w_ram.v" \
    "$compiled/phi_decoder_profile.v"
mv phi_decoder_profile.vvp.new phi_decoder_profile.vvp

# Optional interface trace; no census of optimized XLS implementation locals.
trace_environment=()
trace_module=()
if [[ "$trace_enabled" == 1 ]]; then
    iverilog-vpi phi_profile_trace.c
    trace_environment=(
        ERL_HLS_PHI_PROFILE_SHARDS="$shard_count"
        ERL_HLS_PHI_PROFILE_PLANE_COUNT="$plane_count"
        ERL_HLS_SIM_PHI_TRACE=phi_decoder_profile.trace.csv
        ERL_HLS_SIM_TOP=phi_decoder_profile_tb
    )
    trace_module=(-M "$stage" -m phi_profile_trace)
fi

if /usr/bin/time "${time_arguments[@]}" -o phi_decoder_profile-vvp.time.new \
        timeout --signal=TERM --kill-after=5m "$stage_timeout" \
        env ${trace_environment[@]+"${trace_environment[@]}"} \
        vvp ${trace_module[@]+"${trace_module[@]}"} phi_decoder_profile.vvp 2>&1 | \
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
# vpiFinish can stop a simulator without a failing process exit status.
grep -q '^PASS: decoder-only request-paced profile completed' phi_decoder_profile.sim.log

{
    printf 'width=%s height=%s planes=%s\n' "$width" "$height" "$plane_count"
    printf 'shard_count=%s\n' "$shard_count"
    printf 'scheduler_count=%s\n' "$scheduler_count"
    printf 'pipeline_stages=%s\n' "$pipeline_stages"
    printf 'initiation_interval=%s\n' "$initiation_interval"
    grep -H -E 'PROFILE_RESULT|PROFILE_ACTIVITY|PASS:' \
        phi_decoder_profile.sim.log
    wc -lc \
        "$compiled/sources/phi_decoder_profile_topology.x" \
        "$compiled/phi_decoder_profile.ir" \
        "$compiled/phi_decoder_profile.opt.ir" \
        "$compiled/phi_decoder_profile.v"
    sha256_file "$compiled/sources/phi_decoder_profile_topology.x" "$compiled/phi_decoder_profile.v"
    cat "$stage/compiled.run.json"
    grep -H -E \
        'Elapsed \(wall clock\)|Maximum resident set size|^real ' \
        phi_decoder_profile-iverilog.time \
        phi_decoder_profile-vvp.time
} > phi_decoder_profile.metrics.new
mv phi_decoder_profile.metrics.new phi_decoder_profile.metrics
cat phi_decoder_profile.metrics
