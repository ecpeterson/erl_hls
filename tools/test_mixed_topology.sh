#!/usr/bin/env bash
# Run the shared mixed-topology case, preserving positional placement selection.
set -euo pipefail
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
xls_root=${1:?usage: test_mixed_topology.sh XLS_ROOT [STAGE] [PLACEMENT ...]}
if (( $# > 2 )); then
    exec python3 "$project_root/tools/run_regression.py" "$xls_root" "$2" --cases mixed_topology --placements "${@:3}"
else
    exec python3 "$project_root/tools/run_regression.py" "$@" --cases mixed_topology
fi
