#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage="$project_root/_build/xls_sim/regsvc"

"$project_root/tools/run_xls_sim.sh" "$stage"
"$project_root/tools/xls_goldens.sh" update "$stage"

# The checked-artifact EUnit assertion can run only after its candidate has
# been installed.
cd "$project_root"
rebar3 eunit
"$project_root/tools/xls_goldens.sh" check "$stage"
