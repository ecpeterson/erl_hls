#!/usr/bin/env bash
# Run the shared direct_admission regression case with the original positional interface.
set -euo pipefail
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
: "${1:?usage: test_direct_admission.sh XLS_ROOT [STAGE]}"
exec python3 "$project_root/tools/run_regression.py" "$@" --cases direct_admission
