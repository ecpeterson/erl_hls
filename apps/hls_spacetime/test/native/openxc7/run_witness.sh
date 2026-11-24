#!/usr/bin/env bash
# Run three serial compile-only designs from the umbrella root under an outer process guard.
set -euo pipefail
if [[ $# != 5 ]]; then
    echo "usage: bash run_witness.sh APIO_HOME CHIPDB TILEGRID TIMING_TOOLS FRESH_OUTPUT" >&2
    exit 2
fi
apio=$(cd "$1" && pwd)
chipdb=$(realpath "$2")
grid=$(realpath "$3")
backend=$(cd "$4" && pwd)
mkdir "$5"
stage=$(cd "$5" && pwd)
fixture=apps/hls_spacetime/test/native/openxc7
tool=apps/hls_target/priv/tools/export_openxc7.py
common=(--apio-home "$apio" --chipdb "$chipdb" --max-cells 32)
if [[ -n ${OPENXC7_CHIPDB_MANIFEST:-} ]]; then common+=(--chipdb-manifest "$OPENXC7_CHIPDB_MANIFEST"); fi
# The two chip-wide constant nodes each expand to 42,636 constituent wire records.
for design in placement branches cone; do
    args=("${common[@]}")
    constraints=platforms/xc7/xc7z030sbg485.xdc
    case "$design" in
      placement) args+=(--route-all --max-route-objects 90000 --max-bytes 10485760);;
      branches) args+=(--route-net d_alias --max-route-objects 512 --max-bytes 2097152);;
      cone) args+=(--timing-tools "$backend" --max-timing-objects 4096 --storage-word q=q
                  --route-all --max-route-objects 90000 --max-bytes 10485760)
            constraints="$fixture/cone.xdc";;
    esac
    python3 "$tool" "${args[@]}" --rtl "$fixture/$design.v" --xdc "$constraints" \
        --source-id "g4-$design" --observation-id fixture-v1 "$stage/$design"
done
rebar3 as spacetime escriptize
cli=_build/spacetime/bin/spacetime
for design in placement branches cone; do
    "$cli" import-openxc7 "$stage/$design" "$stage/$design/identity.term" "$stage/$design-catalogue"
done
export OPENXC7_PLACEMENT_FIXTURE="$stage/placement" OPENXC7_TILEGRID="$grid"
mkdir "$stage/eunit"
erlc -o "$stage/eunit" apps/hls_spacetime/test/hls_spacetime_openxc7_tests.erl
export ERL_LIBS="$PWD/_build/spacetime/lib"
erl -noshell -pa "$stage/eunit" -eval 'case eunit:test(hls_spacetime_openxc7_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
OPENXC7_ROUTING_FIXTURE="$stage/branches" node --test apps/hls_spacetime/test-js/openxc7-routes.test.js

# The reference run uses nextpnr's own SDF writer solely as an independent timing report.
mkdir "$stage/reference"
cp "$stage/cone/"{synth.json,design.xdc,route-request.json} "$stage/reference/"
python3 - "$stage" "$backend" "$chipdb" <<'PY'
import json, pathlib, subprocess, sys
stage, backend, chipdb = map(pathlib.Path, sys.argv[1:])
args = json.loads((stage/"cone/manifest.json").read_bytes())["nextpnr_args"]
with (stage/"reference/nextpnr.log").open("x") as log:
    subprocess.run([backend/"bin/nextpnr-spacetime", "--chipdb", chipdb, *args, "--sdf", "oracle.sdf"],
                   cwd=stage/"reference", stdout=log, stderr=subprocess.STDOUT, check=True, timeout=300)
PY
python3 "$fixture/check_timing.py" "$stage/cone" "$stage/reference"

# Simulate the actual retained input and bind the finite trace to this capture.
suite="$apio/packages/oss-cad-suite"
"$suite/bin/iverilog" -g2012 -s bench -o "$stage/cone.vvp" "$suite/share/yosys/xilinx/cells_sim.v" \
    "$stage/cone/design.v" "$fixture/cone_tb.v"
"$suite/bin/vvp" "$stage/cone.vvp" > "$stage/samples.term"
escript "$fixture/cone_witness.escript" "$stage/cone" "$stage/samples.term" "$stage/trace"
checkpoint=$(shasum -a 256 "$stage/cone/routed.json" | cut -d ' ' -f 1)
"$cli" join-openxc7 "$stage/trace/bundle.etf" "$stage/cone" "$checkpoint" "$stage/joined"
node apps/hls_spacetime/scripts/prepare-view.mjs --bundle "$stage/joined/bundle.json" --openxc7 "$stage/cone" --output "$stage/view"
OPENXC7_EXPECT_PERMUTATIONS=1 OPENXC7_CONE_FIXTURE="$stage" node --test apps/hls_spacetime/test-js/openxc7-cone.test.js
