#!/usr/bin/env bash
# One serial local/CI entry point. External tool execution stays outside rebar.
set -euo pipefail
suite=${1:?usage: ci.sh all|software|components|phi|snowflake XLS_ROOT FRESH_STAGE}
xls_root=${2:?missing XLS_ROOT (use - for software)}
stage=${3:?missing FRESH_STAGE}
case "$suite" in all|software|components|phi|snowflake) ;; *) echo "Unknown suite: $suite" >&2; exit 2;; esac
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
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
    rebar3 eunit
    bash tools/test_local_dist.sh
    tests=()
    while IFS= read -r name; do
        case "$name" in ''|\#*) ;; *) tests+=("$name");; esac
    done < tools/ci_unit_tests.txt
    PYTHONPATH=tools python3 -m unittest "${tests[@]}"
    # Only mocked board-support contracts; never discover hardware/image witnesses here.
    for test in test_regsvc_context.py test_packaging_support.py; do
        python3 -m unittest discover -s experiments/07-openxc7 -p "$test"
    done
    python3 tools/check_source_contracts.py
    rebar3 dialyzer
    rebar3 release -n hls_fabric
    python3 tools/check_package_boundaries.py --runtime hls_runtime --runtime hls_fabric \
        --release _build/default/rel/hls_fabric
    record_time software
fi
if [[ "$suite" == all || "$suite" == components ]]; then
    python3 tools/test_ci_components.py "$xls_root" "$stage/components"
    record_time components
fi
if [[ "$suite" == all || "$suite" == phi ]]; then
    python3 tools/test_phi_memory.py "$xls_root" --stage "$stage/phi-build" \
        --placement coalesced --reductions ordinary --memory-case board_memory --compiler-timeout 300 --devices-only
    python3 tools/profile_phi_memory.py "$stage/phi-build" --stage "$stage/phi-run" \
        --clock-halves 3 7 --stalls --timeout 300
    record_time phi
fi
if [[ "$suite" == all || "$suite" == snowflake ]]; then
    python3 tools/test_protocol_snowflake.py "$xls_root" "$stage/snowflake"
    record_time snowflake
fi
