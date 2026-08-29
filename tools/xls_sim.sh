#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
local_stage="$project_root/_build/xls_sim/regsvc"

cd "$project_root"
rebar3 eunit
"$project_root/tools/run_xls_sim.sh" "$local_stage"
"$project_root/tools/xls_goldens.sh" check "$local_stage"
