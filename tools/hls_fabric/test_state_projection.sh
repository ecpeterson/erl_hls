#!/usr/bin/env bash
# Exercise inferred topology constants and the actual generated XLS field codecs.
set -euo pipefail
xls_root=${1:?usage: test_state_projection.sh XLS_ROOT}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 eunit --module=hls_topology_constants_tests
source tools/hls_fabric/backend_env.sh test
for fixture in fixture empty reduction; do
  "$xls_root/interpreter_main" --compare=jit --warnings_as_errors=false \
    --dslx_path="$project_root/apps/hls_target/priv/xls/lib:$project_root/apps/hls_fabric/priv/xls/fabric:$hls_compile_root/priv/xls/lib:$hls_fabric_root/priv/xls/fabric" \
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" \
    "$project_root/_build/state-projection/$fixture.x"
done
