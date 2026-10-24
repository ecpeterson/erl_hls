#!/usr/bin/env bash
# Finite connected transport witness and actual application elaboration, using selected tools.
set -euo pipefail
xls_root=${1:?usage: test_protocol_transport.sh XLS_ROOT FRESH_STAGE}
stage=${2:?usage: test_protocol_transport.sh XLS_ROOT FRESH_STAGE}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_root"
rebar3 as test compile
source tools/backend_env.sh test
python3 tools/test_protocol_transport.py "$xls_root" "$stage"
