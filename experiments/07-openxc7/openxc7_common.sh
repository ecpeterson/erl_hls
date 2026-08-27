#!/usr/bin/env bash

# Shared, experiment-local openXC7 setup and bitstream assembly helpers.
# Entry-point scripts source this file after enabling `set -euo pipefail`.

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

prepare_openxc7() {
    require_executable "$openxc7/libexec/python3.12"
    require_executable "$openxc7/bin/bbasm"
    require_executable "$openxc7/bin/nextpnr-xilinx"
    require_executable "$openxc7/bin/fasm2frames"
    require_executable "$openxc7/bin/xc7frames2bit"
    require_executable "$oss_cad_suite/bin/yosys"

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
}

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

summarize_report() {
    local part=$1
    local report_path=$2

    "$openxc7/libexec/python3.12" -c '
import json
import sys

part, report_path = sys.argv[1:]
with open(report_path, encoding="utf-8") as stream:
    report = json.load(stream)
for clock, timing in report.get("fmax", {}).items():
    achieved = timing.get("achieved", 0.0)
    target = timing.get("constraint", 0.0)
    print(f"{part} {clock}: {achieved:.2f} MHz ({target:.2f} MHz target)")
utilization = report.get("utilization", {})
resources = []
for label, key in (
    ("SLICE_LUTX", "SLICE_LUTX"),
    ("SLICE_FFX", "SLICE_FFX"),
    ("RAMB18E1", "RAMB18E1_RAMB18E1"),
    ("RAMB36E1", "RAMB36E1_RAMB36E1"),
    ("DSP48E1", "DSP48E1_DSP48E1"),
):
    if key in utilization:
        resource = utilization[key]
        used = resource.get("used", 0)
        available = resource.get("available", 0)
        resources.append(f"{label} {used}/{available}")
if resources:
    print(f"{part} resources: " + ", ".join(resources))
' "$part" "$report_path"
}

build_bitstream() {
    local design_name=$1
    local netlist=$2
    local part=$3
    local footprint=${part%-*}
    local xdc=$4
    local timing_policy=${5:-strict}
    local output_root="$build_root/$design_name"
    local output="$output_root/$part"
    local nextpnr_options=(
        --quiet
        --chipdb "$build_root/chipdb/$footprint.bin"
        --xdc "$xdc"
        --json "$netlist"
        --fasm "$output.fasm"
        --report "$output-report.json"
        --freq 100
        --router router2
        --log "$output-nextpnr.log"
    )

    case "$timing_policy" in
        strict) ;;
        allow-timing-failure) nextpnr_options+=(--timing-allow-fail) ;;
        *)
            echo "Unknown timing policy: $timing_policy" >&2
            return 1
            ;;
    esac

    mkdir -p "$output_root"
    rm -f \
        "$output.fasm" \
        "$output.frames" \
        "$output.bit" \
        "$output-report.json" \
        "$output-nextpnr.log"
    echo "Placing and routing $design_name for $part"
    "$openxc7/bin/nextpnr-xilinx" "${nextpnr_options[@]}"

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
    printf '%s deterministic frame checksum: ' "$part"
    shasum -a 256 "$output.frames" | cut -d ' ' -f 1
    summarize_report "$part" "$output-report.json"
}
