#!/usr/bin/env bash
# Build a separate native backend with the measured GTX and unused-clock fixes.
# The existing LUT legality builder verifies sources and preserves each baseline.
set -euo pipefail
if [[ $# != 1 ]]; then
    echo "usage: $0 NEW_BUILD_DIRECTORY" >&2
    exit 2
fi
root=$(cd "$(dirname "$0")/.." && pwd)
bash "$root/lut_legality/build.sh" "$1"
stage=$(cd "$1" && pwd)
revision=68aeeb39f92e39bfb239c7e4a44dd93451fc1889
for fix in nextpnr-refclk nextpnr-unused-clkin; do
    patch -d "$stage/nextpnr-xilinx-$revision" -p1 < "$root/gtx/$fix.patch"
done
cmake --build "$stage/native-build" --parallel 4 > "$stage/build-gtx.log" 2>&1
ctest --test-dir "$stage/native-build" --output-on-failure > "$stage/ctest-gtx.log" 2>&1
cp "$stage/native-build/nextpnr-xilinx" "$stage/bin/nextpnr-gtx"
shasum -a 256 "$stage/bin/nextpnr-gtx"
