#!/usr/bin/env bash
# Exercise the user-facing preflight command and inspect its newly emitted application bundles.
set -euo pipefail
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${1:-"$project_root/_build/source-protocol"}
cd "$project_root"
bash tools/inspect_phi_protocol.sh "$stage"
rebar3 as test compile
source tools/backend_env.sh test
erl -noshell -eval 'ok = hls_protocol_inventory_validation:run(hd(init:get_plain_arguments())), halt().' -extra "$stage"
