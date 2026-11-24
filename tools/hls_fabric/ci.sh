#!/usr/bin/env bash
# One serial local/CI entry point. External tool execution stays outside rebar.
set -euo pipefail
suite=${1:?usage: ci.sh all|software|components|phi|snowflake XLS_ROOT FRESH_STAGE}
xls_root=${2:?missing XLS_ROOT (use - for software)}
stage=${3:?missing FRESH_STAGE}
case "$suite" in all|software|components|phi|snowflake) ;; *) echo "Unknown suite: $suite" >&2; exit 2;; esac
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
mkdir -p "$(dirname "$stage")"
mkdir "$stage"
stage=$(cd "$stage" && pwd)
cd "$project_root"
printf 'tier\tseconds\n' > "$stage/times.tsv"
tier_started=$(date +%s)
# Wall time includes each tier's orchestration, not just child compiler time.
record_time() {
    local finished
    finished=$(date +%s)
    printf '%s\t%d\n' "$1" "$((finished-tier_started))" | tee -a "$stage/times.tsv"
    tier_started=$finished
}
if [[ "$suite" != software ]]; then xls_root=$(cd "$xls_root" && pwd); fi
# Resolve each profile once. Helpers can request the same no-op rebar check.
rebar3 as test compile
rebar3 release -n hls
record_time prepare
if [[ "$suite" == all || "$suite" == software ]]; then
    bash tools/test_umbrella_eunit.sh default
    bash tools/test_umbrella_eunit.sh boundaries
    rebar3 release -n hls_examples
    bash tools/hls_fabric/test_local_dist.sh
    tests=()
    while IFS= read -r name; do
        case "$name" in ''|\#*) ;; *) tests+=("$name");; esac
    done < tools/hls_fabric/ci_unit_tests.txt
    PYTHONPATH=tools/hls_fabric:apps/hls_phi/tools python3 -m unittest "${tests[@]}"
    # Only mocked board-support contracts; never discover hardware/image witnesses here.
    for test in test_regsvc_context.py test_packaging_support.py; do
        python3 -m unittest discover -s platforms/xc7 -p "$test"
    done
    python3 tools/test_source_contracts.py
    python3 tools/check_source_contracts.py
    rebar3 dialyzer
    rebar3 as spacetime compile
    python3 tools/hls_fabric/check_application_boundaries.py \
        --profile default --profile spacetime
    rebar3 release -n hls_fabric
    bash tools/hls_fabric/test_runtime_release.sh _build/default/rel/hls_fabric
    python3 tools/test_external_consumers.py
    record_time software
fi
if [[ "$suite" == all || "$suite" == components ]]; then
    python3 tools/hls_fabric/test_ci_components.py "$xls_root" "$stage/components"
    record_time components
fi
if [[ "$suite" == all || "$suite" == phi ]]; then
    python3 apps/hls_phi/tools/test_phi_memory.py "$xls_root" --stage "$stage/phi-build" \
        --placement coalesced --reductions ordinary --memory-case board_memory --compiler-timeout 300 --devices-only
    python3 apps/hls_phi/tools/profile_phi_memory.py "$stage/phi-build" --stage "$stage/phi-run" \
        --clock-halves 3 7 --stalls --timeout 300
    record_time phi
fi
if [[ "$suite" == all || "$suite" == snowflake ]]; then
    python3 tools/hls_fabric/test_protocol_snowflake.py "$xls_root" "$stage/snowflake"
    record_time snowflake
fi
