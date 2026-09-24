#!/usr/bin/env bash
# Build an isolated matched pair from verified source archives. The optional
# cache contains nextpnr.tar.gz and eigen.tar.gz from lut_legality/build.sh.
set -euo pipefail
if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: $0 NEW_BUILD_DIRECTORY [ARCHIVE_CACHE]" >&2
    exit 2
fi
here=$(cd "$(dirname "$0")" && pwd)
cache=${2:-}
if [[ -n "$cache" ]]; then cache=$(cd "$cache" && pwd); fi
if [[ -e "$1" ]]; then
    echo "Refusing to overwrite existing build directory: $1" >&2
    exit 2
fi
mkdir -p "$1"
cd "$1"
stage=$PWD
revision=68aeeb39f92e39bfb239c7e4a44dd93451fc1889
if [[ -n "$cache" ]]; then
    cp "$cache/nextpnr.tar.gz" "$cache/eigen.tar.gz" .
else
    curl -fL --retry 3 "https://codeload.github.com/openXC7/nextpnr-xilinx/tar.gz/$revision" -o nextpnr.tar.gz
    curl -fL --retry 3 https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz -o eigen.tar.gz
fi
cat > sources.sha256 <<'HASHES'
5652a7356b1c8ae67355c9bdcd96d88e5592d9eface9ea4b60584a9460824439  nextpnr.tar.gz
8586084f71f9bde545ee7fa6d00288b264a2b7ac3607b974e54d13e7162c1c72  eigen.tar.gz
HASHES
shasum -a 256 -c sources.sha256
tar -xf nextpnr.tar.gz
tar -xf eigen.tar.gz
source_dir="nextpnr-xilinx-$revision"
# Both binaries retain the already-tested LUT correctness repairs.
patch -d "$source_dir" -p1 < "$here/../lut_legality/nextpnr-output-pin.patch"
patch -d "$source_dir" -p1 < "$here/../lut_legality/nextpnr-pin-origins.patch"
mkdir pkgconfig bin
cat > pkgconfig/eigen3.pc <<PKG
prefix=$stage/eigen-3.4.0
Name: Eigen3
Description: Eigen headers
Version: 3.4.0
Cflags: -I\${prefix}
PKG
export PKG_CONFIG_PATH="$stage/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
cmake -S "$source_dir" -B native-build \
    -DARCH=xilinx -DBUILD_GUI=OFF -DBUILD_PYTHON=OFF -DBUILD_TESTS=ON \
    -DUSE_OPENMP=OFF -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_POLICY_DEFAULT_CMP0167=OLD \
    -DBOOST_ROOT="$(brew --prefix boost)" -DCURRENT_GIT_VERSION=68aeeb39-coverage \
    > configure.log 2>&1
for variant in baseline coverage; do
    if [[ "$variant" == coverage ]]; then
        patch -d "$source_dir" -p1 < "$here/nextpnr-coverage.patch"
    fi
    cmake --build native-build --parallel 3 > "build-$variant.log" 2>&1
    cp native-build/nextpnr-xilinx "bin/nextpnr-$variant"
    ctest --test-dir native-build --output-on-failure > "ctest-$variant.log" 2>&1
    shasum -a 256 "bin/nextpnr-$variant"
done
