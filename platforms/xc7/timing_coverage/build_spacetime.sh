#!/usr/bin/env bash
# Add the read-only timing queries and packer provenance to a fresh pinned coverage build.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
bash "$here/build.sh" "$@"
stage=$(cd "$1" && pwd)
revision=68aeeb39f92e39bfb239c7e4a44dd93451fc1889
src="$stage/nextpnr-xilinx-$revision"
patch -d "$src" -p1 < "$here/nextpnr-spacetime.patch"
patch -d "$src" -p1 < "$here/nextpnr-spacetime-sta.patch"
patch -d "$src" -p1 < "$here/nextpnr-spacetime-endpoints.patch"
cp "$here/spacetime.h" "$src/xilinx/spacetime.h"
if [[ ${SPACETIME_CARRY_MODEL:-0} == 1 ]]; then
    patch -d "$src" -p1 < "$here/nextpnr-spacetime-carry.patch"
    cp "$here/nextpnr-spacetime-carry.patch" "$stage/"
fi
if [[ ${SPACETIME_BRAM_MODEL:-0} == 1 ]]; then
    python3 "$here/../timing_model/install_native.py" "$src"
fi
# A patched source and the previous variant's object can share a Make timestamp.
cmake --build "$stage/native-build" --clean-first --parallel 2 > "$stage/build-spacetime.log" 2>&1
ctest --test-dir "$stage/native-build" --output-on-failure > "$stage/ctest-spacetime.log" 2>&1
cp "$stage/native-build/nextpnr-xilinx" "$stage/bin/nextpnr-spacetime"
"$stage/bin/nextpnr-spacetime" --help > "$stage/spacetime-options.log" 2>&1
grep -q -- '--spacetime-timing' "$stage/spacetime-options.log"
python3 "$here/spacetime_build_identity.py" "$stage"
