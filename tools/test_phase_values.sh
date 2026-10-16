#!/usr/bin/env bash
# Generate and execute phase-specialization witnesses with the selected XLS build.
set -euo pipefail
xls_root=${1:?usage: test_phase_values.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/phase_values"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
ERL_HLS_PHASE_STAGE="$stage" erl -noshell \
    -pa "$project_root/_build/test/lib/erl_hls/ebin" \
    -pa "$project_root/_build/test/lib/erl_hls/test" \
    -eval 'ok = xls_phase_values_dslx:write(os:getenv("ERL_HLS_PHASE_STAGE")), halt().'
for fixture in phase_baseline phase_candidate; do
    "$xls_root/interpreter_main" --compare=jit --warnings_as_errors=false \
        --dslx_path="$project_root/priv/xls/lib" \
        --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" "$stage/$fixture.x"
done
