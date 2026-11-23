#!/usr/bin/env bash
# Check admission ordering and authoritative ordinary/offloaded handoff through generated XLS.
set -euo pipefail
xls_root=${1:?usage: test_admission_collection.sh XLS_ROOT}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 eunit --module=xls_admission_collection_tests
source tools/hls_fabric/backend_env.sh test
for name in admission-collection exclusive-collection direct-collection; do
"$xls_root/interpreter_main" --compare=jit --warnings_as_errors=false \
  --dslx_path="$project_root/apps/hls_lowering/priv/xls/lib:$project_root/apps/hls_lowering/priv/xls:$erl_hls_root/priv/xls/lib:$erl_hls_root/priv/xls/fabric" \
  --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" \
  "$project_root/_build/$name/unit/collection.x"
done
