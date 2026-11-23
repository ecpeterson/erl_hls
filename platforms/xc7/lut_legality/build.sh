#!/usr/bin/env bash
# Build matched native nextpnr binaries in a new isolated directory. Existing
# package tools and caches are untouched; rerun probes directly to reuse them.
set -euo pipefail
if [[ $# != 1 ]]; then
    echo "usage: $0 NEW_BUILD_DIRECTORY" >&2
    exit 2
fi
patches=$(cd "$(dirname "$0")" && pwd)
stage=$1
if [[ -e "$stage" ]]; then
    echo "Refusing to overwrite existing build directory: $stage" >&2
    exit 2
fi
mkdir -p "$stage"
cd "$stage"
stage=$PWD
revision=68aeeb39f92e39bfb239c7e4a44dd93451fc1889
curl -fL --retry 3 "https://codeload.github.com/openXC7/nextpnr-xilinx/tar.gz/$revision" -o nextpnr.tar.gz
curl -fL --retry 3 https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz -o eigen.tar.gz
cat > sources.sha256 <<'HASHES'
5652a7356b1c8ae67355c9bdcd96d88e5592d9eface9ea4b60584a9460824439  nextpnr.tar.gz
8586084f71f9bde545ee7fa6d00288b264a2b7ac3607b974e54d13e7162c1c72  eigen.tar.gz
HASHES
shasum -a 256 -c sources.sha256
tar -xf nextpnr.tar.gz
tar -xf eigen.tar.gz
mkdir pkgconfig bin
cat > pkgconfig/eigen3.pc <<EOF
prefix=$stage/eigen-3.4.0
Name: Eigen3
Description: Eigen headers
Version: 3.4.0
Cflags: -I\${prefix}
EOF
export PKG_CONFIG_PATH="$stage/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
cmake -S "nextpnr-xilinx-$revision" -B native-build \
    -DARCH=xilinx -DBUILD_GUI=OFF -DBUILD_PYTHON=OFF -DBUILD_TESTS=ON \
    -DUSE_OPENMP=OFF -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_POLICY_DEFAULT_CMP0167=OLD \
    -DBOOST_ROOT="$(brew --prefix boost)" -DCURRENT_GIT_VERSION=68aeeb39-baseline \
    > configure.log 2>&1
for variant in baseline placement-only candidate; do
    case $variant in
        placement-only) patch -d "nextpnr-xilinx-$revision" -p1 < "$patches/nextpnr-output-pin.patch" ;;
        candidate) patch -d "nextpnr-xilinx-$revision" -p1 < "$patches/nextpnr-pin-origins.patch" ;;
    esac
    cmake --build native-build --parallel 4 > "build-$variant.log" 2>&1
    cp native-build/nextpnr-xilinx "bin/nextpnr-$variant"
    ctest --test-dir native-build --output-on-failure > "ctest-$variant.log" 2>&1
    shasum -a 256 "bin/nextpnr-$variant"
done
