#!/usr/bin/env bash
set -euo pipefail

experiment_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
apio_home=${ERL_XLS_APIO_HOME:-"$experiment_root/.apio"}
build_root=${ERL_XLS_OPENXC7_BUILD_ROOT:-"$experiment_root/build"}
openxc7="$apio_home/packages/openxc7"
oss_cad_suite="$apio_home/packages/oss-cad-suite"
nextpnr_python="$openxc7/share/nextpnr/python"
prjxray_db="$openxc7/share/nextpnr/external/prjxray-db"

require_executable() {
    if [[ ! -x "$1" ]]; then
        echo "Missing executable: $1" >&2
        echo "Install the experiment-local Apio packages described in README.md." >&2
        exit 1
    fi
}

require_executable "$openxc7/libexec/python3.12"
require_executable "$openxc7/bin/bbasm"
require_executable "$openxc7/bin/nextpnr-xilinx"
require_executable "$openxc7/bin/fasm2frames"
require_executable "$openxc7/bin/xc7frames2bit"
require_executable "$oss_cad_suite/bin/yosys"

verify_package() {
    local build_info=$1
    local expected_name=$2
    local expected_release=$3
    local expected_commit=$4

    "$openxc7/libexec/python3.12" -c '
import json
import sys

path, name, release, commit = sys.argv[1:]
with open(path, encoding="utf-8") as stream:
    info = json.load(stream)
expected = {
    "package-name": name,
    "release-tag": release,
    "commit": commit,
    "target-platform": "darwin-arm64",
}
actual = {key: info.get(key) for key in expected}
if actual != expected:
    raise SystemExit(
        f"Unexpected package metadata in {path}: {actual}; expected {expected}"
    )
' "$build_info" "$expected_name" "$expected_release" "$expected_commit"
}

verify_package \
    "$openxc7/BUILD-INFO.json" \
    openxc7 \
    2026-08-20 \
    4643d2ecfd6569bad2ae7963b17d90687363af6e
verify_package \
    "$oss_cad_suite/BUILD-INFO.json" \
    oss-cad-suite \
    2026-08-19 \
    b246ed025634562f953daccef0c9d2f7995d30c3

mkdir -p "$build_root/chipdb"

toolchain_id=$(shasum -a 256 "$openxc7/BUILD-INFO.json" | cut -d ' ' -f 1)

make_chipdb() {
    local part=$1
    local footprint=${part%-*}
    local bba="$build_root/$footprint.$$.bba"
    local chipdb="$build_root/chipdb/$footprint.bin"
    local chipdb_tmp="$chipdb.$$.tmp"
    local stamp="$chipdb.toolchain"
    local stamp_tmp="$stamp.$$.tmp"
    local expected_stamp="$part $toolchain_id"

    if [[ -s "$chipdb" && -f "$stamp" ]] &&
            [[ $(<"$stamp") == "$expected_stamp" ]]; then
        return
    fi

    echo "Generating chip database for $part"
    rm -f "$bba" "$chipdb_tmp" "$stamp_tmp"
    "$openxc7/libexec/python3.12" "$nextpnr_python/bbaexport.py" \
        --device "$part" \
        --bba "$bba"
    "$openxc7/bin/bbasm" -l "$bba" "$chipdb_tmp"
    test -s "$chipdb_tmp"
    mv "$chipdb_tmp" "$chipdb"
    printf '%s\n' "$expected_stamp" > "$stamp_tmp"
    mv "$stamp_tmp" "$stamp"
    rm "$bba"
}

make_chipdb xc7z010clg225-1
make_chipdb xc7z020clg484-2

design="$experiment_root/smoke.v"
netlist="$build_root/smoke.json"

echo "Synthesizing openXC7 smoke design"
"$oss_cad_suite/bin/yosys" \
    -q \
    -l "$build_root/yosys.log" \
    -p "read_verilog \"$design\"; synth_xilinx -flatten -abc9 -arch xc7 -top openxc7_smoke; write_json \"$netlist\""

build_part() {
    local part=$1
    local footprint=${part%-*}
    local xdc=$2
    local output="$build_root/$part"

    echo "Building $part"
    "$openxc7/bin/nextpnr-xilinx" \
        --quiet \
        --chipdb "$build_root/chipdb/$footprint.bin" \
        --xdc "$xdc" \
        --json "$netlist" \
        --fasm "$output.fasm" \
        --report "$output-report.json" \
        --freq 100 \
        --router router2 \
        --log "$output-nextpnr.log"

    "$openxc7/bin/fasm2frames" \
        --part "$part" \
        --db-root "$prjxray_db/zynq7" \
        "$output.fasm" \
        "$output.frames"

    "$openxc7/bin/xc7frames2bit" \
        --part_file "$prjxray_db/zynq7/$part/part.yaml" \
        --part_name "$part" \
        --frm_file "$output.frames" \
        --output_file "$output.bit"

    test -s "$output.bit"
    printf 'Deterministic frame checksum: '
    shasum -a 256 "$output.frames" | cut -d ' ' -f 1
}

build_part \
    xc7z010clg225-1 \
    "$experiment_root/xc7z010clg225.xdc"
build_part \
    xc7z020clg484-2 \
    "$experiment_root/xc7z020clg484.xdc"
