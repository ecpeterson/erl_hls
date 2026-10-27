#!/usr/bin/env bash
# Run the shared binary regression case with the original positional interface.
set -euo pipefail
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
: "${1:?usage: test_binary.sh XLS_ROOT [STAGE]}"
exec python3 "$project_root/tools/run_regression.py" "$@" --cases binary
