#!/usr/bin/env bash
# Run the shared application_frames regression case with the original positional interface.
set -euo pipefail
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
: "${1:?usage: test_application_frames.sh XLS_ROOT [STAGE]}"
exec python3 "$project_root/tools/run_regression.py" "$@" --cases application_frames
