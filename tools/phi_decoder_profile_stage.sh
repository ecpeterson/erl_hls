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
initiation_interval=${6:-2}
scheduler_count=$((2 + 2 * shard_count))
stdlib="$xls_root/xls/dslx/stdlib"
. "$stage/phi_scheduler_rams.sh"

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
    phi_decoder_profile.ir \
    phi_decoder_profile.opt.ir \
    phi_decoder_profile.v \
    phi_decoder_profile.vvp \
    phi_decoder_profile.scheduler_profile \
    xls_sim_bridge.o \
    xls_sim_bridge.vpi \
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
    if /usr/bin/time "${time_arguments[@]}" -o "$label.time.new" \
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
    --pipeline_stages="$pipeline_stages" \
    --worst_case_throughput="$initiation_interval" \
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

iverilog-vpi xls_sim_bridge.c

if /usr/bin/time "${time_arguments[@]}" -o phi_decoder_profile-vvp.time.new \
        timeout --signal=TERM --kill-after=5m "$stage_timeout" \
        env ERL_HLS_SIM_PROFILE_ONLY=1 \
        ERL_HLS_SIM_TOP=phi_decoder_profile_tb \
        ERL_HLS_SIM_SCHEDULER_PROFILE=phi_decoder_profile.scheduler_profile \
        vvp -M "$stage" -m xls_sim_bridge phi_decoder_profile.vvp 2>&1 | \
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

awk -F= '
    /_selection_activations=/ {
        name = $1
        sub(/_selection_activations$/, "", name)
        activations[name] = $2
    }
    /_mailbox_occupancy_samples=/ {
        name = $1
        sub(/_mailbox_occupancy_samples$/, "", name)
        occupancy_samples[name] = $2
    }
    /_selection_cycles_selectable=/ {
        name = $1
        sub(/_selection_cycles_selectable$/, "", name)
        accounted[name] += $2
    }
    /_selection_cycles_(same_actor_only|waiting_egress_credit|no_actor_work|internal_other)=/ {
        name = $1
        sub(/_selection_cycles_(same_actor_only|waiting_egress_credit|no_actor_work|internal_other)$/, "", name)
        accounted[name] += $2
    }
    /_selection_cycles_same_actor_only=/ {
        name = $1
        sub(/_selection_cycles_same_actor_only$/, "", name)
        same_actor[name] = $2
    }
    /_same_actor_observed_(mailbox|entry|egress|internal_other)=/ {
        name = $1
        sub(/_same_actor_observed_(mailbox|entry|egress|internal_other)$/, "", name)
        same_actor_observed[name] += $2
    }
    /_same_actor_followups=/ {
        name = $1
        sub(/_same_actor_followups$/, "", name)
        followups[name] = $2
    }
    /_same_actor_followup_(mailbox|entry|egress|waiting_egress_credit|no_work)=/ {
        name = $1
        sub(/_same_actor_followup_(mailbox|entry|egress|waiting_egress_credit|no_work)$/, "", name)
        followup_accounted[name] += $2
    }
    /_same_actor_followup_mailbox=/ {
        name = $1
        sub(/_same_actor_followup_mailbox$/, "", name)
        followup_mailbox[name] = $2
    }
    /_same_actor_followup_direct_mailbox=/ {
        name = $1
        sub(/_same_actor_followup_direct_mailbox$/, "", name)
        direct_mailbox[name] = $2
    }
    END {
        found = 0
        for (name in activations) {
            found = 1
            if (accounted[name] != activations[name])
                exit 1
            if (occupancy_samples[name] != activations[name])
                exit 1
            if (same_actor_observed[name] != same_actor[name])
                exit 1
            if (followup_accounted[name] != followups[name])
                exit 1
            if (followups[name] > same_actor[name] ||
                    same_actor[name] - followups[name] > 1)
                exit 1
            if (direct_mailbox[name] > followup_mailbox[name])
                exit 1
        }
        if (!found)
            exit 1
    }
' phi_decoder_profile.scheduler_profile

{
    printf 'shard_count=%s\n' "$shard_count"
    printf 'scheduler_count=%s\n' "$scheduler_count"
    printf 'pipeline_stages=%s\n' "$pipeline_stages"
    printf 'initiation_interval=%s\n' "$initiation_interval"
    grep -H -E 'PROFILE_RESULT|PROFILE_ACTIVITY|PASS:' \
        phi_decoder_profile.sim.log
    cat phi_decoder_profile.scheduler_profile
    wc -lc \
        phi_decoder_profile_topology.x \
        phi_decoder_profile.ir \
        phi_decoder_profile.opt.ir \
        phi_decoder_profile.v
    sha256_file phi_decoder_profile_topology.x phi_decoder_profile.v
    grep -H -E \
        'Elapsed \(wall clock\)|Maximum resident set size|^real ' \
        phi_decoder_profile-ir.time \
        phi_decoder_profile-opt.time \
        phi_decoder_profile-codegen.time \
        phi_decoder_profile-iverilog.time \
        phi_decoder_profile-vvp.time
} > phi_decoder_profile.metrics.new
mv phi_decoder_profile.metrics.new phi_decoder_profile.metrics
cat phi_decoder_profile.metrics
