#!/usr/bin/env bash
# Add the read-only timing queries and packer provenance to a fresh pinned coverage build.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
bash "$here/build.sh" "$@"
stage=$(cd "$1" && pwd)
revision=68aeeb39f92e39bfb239c7e4a44dd93451fc1889
src="$stage/nextpnr-xilinx-$revision"
patch -d "$src" -p1 < "$here/nextpnr-spacetime.patch"
cp "$here/spacetime.h" "$src/xilinx/spacetime.h"
cmake --build "$stage/native-build" --parallel 2 > "$stage/build-spacetime.log" 2>&1
ctest --test-dir "$stage/native-build" --output-on-failure > "$stage/ctest-spacetime.log" 2>&1
cp "$stage/native-build/nextpnr-xilinx" "$stage/bin/nextpnr-spacetime"
python3 "$here/spacetime_build_identity.py" "$stage"
