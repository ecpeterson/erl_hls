#!/usr/bin/env bash
set -euo pipefail

local_stage=${1:?usage: run_xls_sim.sh STAGE [XLS_ROOT]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
xls_root=${ERL_HLS_XLS_ROOT:-${2:-}}

if [[ -z "$xls_root" ]]; then
    echo "set ERL_HLS_XLS_ROOT or pass the native XLS root as argument 2" >&2
    exit 1
fi
for binary in interpreter_main ir_converter_main opt_main codegen_main; do
    if [[ ! -x "$xls_root/$binary" ]]; then
        echo "missing native XLS command: $xls_root/$binary" >&2
        exit 1
    fi
done
xls_root=$(cd "$xls_root" && pwd)

"$project_root/tools/prepare_xls_sim.sh" "$local_stage"
local_stage=$(cd "$local_stage" && pwd)
# The portable stage runner is shared with CI; it executes entirely locally.
bash "$project_root/tools/remote_xls_sim.sh" "$local_stage" "$xls_root"
