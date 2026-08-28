#!/usr/bin/env bash
set -euo pipefail

experiment_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
project_root=$(cd "$experiment_root/../.." && pwd)
# shellcheck source=openxc7_common.sh
source "$experiment_root/openxc7_common.sh"

target=${1:-xc7z020clg484-2}
case "$target" in
    xc7z010clg225-1|xc7z020clg484-2|all) ;;
    *)
        echo "usage: $0 [xc7z010clg225-1|xc7z020clg484-2|all]" >&2
        exit 2
        ;;
esac

prepare_openxc7

regsvc_build="$build_root/regsvc"
generated_rtl="$regsvc_build/generated-rtl"
mkdir -p "$regsvc_build"

sha256_file() {
    local path=$1
    local digest

    if command -v shasum >/dev/null 2>&1; then
        digest=$(shasum -a 256 "$path")
    elif command -v sha256sum >/dev/null 2>&1; then
        digest=$(sha256sum "$path")
    else
        echo "Neither shasum nor sha256sum is available" >&2
        exit 1
    fi
    printf '%s' "${digest%% *}"
}

verify_manifest_entry() {
    local kind=$1
    local name=$2
    local path=$3
    local expected
    local actual

    expected=$(awk -F '\t' -v kind="$kind" -v name="$name" '
        $1 == kind && $3 == name { print $2 }
    ' "$manifest")
    if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
        echo "Manifest has no unique SHA-256 for $kind $name" >&2
        exit 1
    fi
    [[ -s "$path" ]] || {
        echo "Manifest input is missing: $path" >&2
        exit 1
    }
    actual=$(sha256_file "$path")
    if [[ "$actual" != "$expected" ]]; then
        echo "Manifest mismatch for $path" >&2
        echo "Run ./fetch_regsvc_rtl.sh again." >&2
        exit 1
    fi
}

if [[ ! -L "$generated_rtl" ]]; then
    echo "$generated_rtl is not a managed generated-RTL symlink" >&2
    echo "Run ./fetch_regsvc_rtl.sh first." >&2
    exit 1
fi
release_link=$(readlink "$generated_rtl")
case "$release_link" in
    .generated-rtl-releases/*) ;;
    *)
        echo "Unexpected generated-RTL release link: $release_link" >&2
        exit 1
        ;;
esac
generated_release=$(cd -P "$generated_rtl" && pwd -P)
release_parent=$(cd -P "$regsvc_build/.generated-rtl-releases" && pwd -P)
case "$generated_release" in
    "$release_parent"/*) ;;
    *)
        echo "Generated RTL resolves outside its managed release directory" >&2
        exit 1
        ;;
esac
generated_rtl="$generated_release"
manifest="$generated_release/manifest.sha256"
[[ -s "$manifest" ]] || {
    echo "Generated-RTL manifest is missing: $manifest" >&2
    exit 1
}
release_id=${release_link##*/}
if [[ "$(sha256_file "$manifest")" != "$release_id" ]]; then
    echo "Generated-RTL manifest does not match its content-addressed release" >&2
    exit 1
fi
if ! grep -Fxq $'xls-version\tv0.0.0-9235-gb179d691e' "$manifest"; then
    echo "Generated RTL does not use the pinned XLS version" >&2
    exit 1
fi

sources=(
    "$project_root/test/rtl/regsvc_pair_fixture.sv"
    "$project_root/src/examples/regsvc_debug_top.v"
    "$project_root/src/examples/regsvc_core_adapter.v"
    "$project_root/src/xls_debug_tap.v"
    "$project_root/src/xls_trace_store.v"
    "$generated_rtl/regsvc.v"
    "$generated_rtl/xls_debug_observer.v"
    "$generated_rtl/xls_debug_server.v"
    "$generated_rtl/xls_fabric_ingress.v"
    "$generated_rtl/xls_fabric_egress.v"
)

for generated_file in \
    regsvc.v \
    xls_debug_observer.v \
    xls_debug_server.v \
    xls_fabric_ingress.v \
    xls_fabric_egress.v
do
    verify_manifest_entry \
        output \
        "$generated_file" \
        "$generated_rtl/$generated_file"
done

verify_manifest_entry \
    input axis.x "$project_root/experiments/05-xls/axis.x"
verify_manifest_entry \
    input xls_debug_monitor.x "$project_root/src/xls_debug_monitor.x"
verify_manifest_entry \
    input xls_fabric_router.x "$project_root/src/xls_fabric_router.x"
verify_manifest_entry \
    input regsvc_core_adapter.v "$project_root/src/examples/regsvc_core_adapter.v"
verify_manifest_entry \
    input regsvc_debug_top.v "$project_root/src/examples/regsvc_debug_top.v"
verify_manifest_entry \
    input xls_debug_tap.v "$project_root/src/xls_debug_tap.v"
verify_manifest_entry \
    input xls_trace_store.v "$project_root/src/xls_trace_store.v"
verify_manifest_entry \
    input regsvc_pair_fixture.sv "$project_root/test/rtl/regsvc_pair_fixture.sv"
verify_manifest_entry \
    input remote_xls_sim.sh "$project_root/tools/remote_xls_sim.sh"

for source in "${sources[@]}"; do
    if [[ ! -s "$source" ]]; then
        echo "Missing RTL input: $source" >&2
        echo "Run ./fetch_regsvc_rtl.sh first." >&2
        exit 1
    fi
    if [[ "$source" == *\"* ]]; then
        echo "A Yosys input path contains an unsupported quote: $source" >&2
        exit 1
    fi
done

require_executable "$oss_cad_suite/bin/iverilog"
require_executable "$oss_cad_suite/bin/vvp"
harness="$experiment_root/regsvc_pair_harness.v"
harness_test="$experiment_root/regsvc_pair_harness_tb.sv"
harness_sim="$regsvc_build/regsvc_pair_harness_sim"
rm -f "$harness_sim"
echo "Checking the compile harness traffic"
"$oss_cad_suite/bin/iverilog" \
    -g2012 \
    -s regsvc_pair_harness_tb \
    -o "$harness_sim" \
    "${sources[@]}" \
    "$harness" \
    "$harness_test"
"$oss_cad_suite/bin/vvp" "$harness_sim"

yosys_sources=
for source in "${sources[@]}"; do
    yosys_sources+=" \"$source\""
done

core_stats="$regsvc_build/regsvc_pair_core-stats.json"
rm -f "$core_stats" "$regsvc_build/yosys-core.log"
echo "Synthesizing the routed regsvc pair out of context"
core_yosys="read_verilog -sv$yosys_sources;"
core_yosys+=" hierarchy -check -top regsvc_pair_fixture;"
core_yosys+=" synth_xilinx -flatten -abc9 -arch xc7 -noiopad"
core_yosys+=" -top regsvc_pair_fixture;"
core_yosys+=" check -assert;"
core_yosys+=" tee -o \"$core_stats\" stat -json"
"$oss_cad_suite/bin/yosys" \
    -q \
    -l "$regsvc_build/yosys-core.log" \
    -p "$core_yosys"

harness_netlist="$regsvc_build/regsvc_pair_harness.json"
harness_stats="$regsvc_build/regsvc_pair_harness-stats.json"
rm -f \
    "$harness_netlist" \
    "$harness_stats" \
    "$regsvc_build/yosys-harness.log"
echo "Synthesizing the two-pin compile harness"
harness_yosys="read_verilog -sv$yosys_sources \"$harness\";"
harness_yosys+=" hierarchy -check -top regsvc_pair_openxc7_harness;"
harness_yosys+=" synth_xilinx -flatten -abc9 -arch xc7"
harness_yosys+=" -top regsvc_pair_openxc7_harness;"
harness_yosys+=" check -assert;"
harness_yosys+=" tee -o \"$harness_stats\" stat -json;"
harness_yosys+=" write_json \"$harness_netlist\""
"$oss_cad_suite/bin/yosys" \
    -q \
    -l "$regsvc_build/yosys-harness.log" \
    -p "$harness_yosys"

# A legal but overly predictable traffic source can let synthesis specialize
# away dormant endpoint state. Refuse to route a harness which retains fewer
# flip-flops than the raw, out-of-context pair.
"$openxc7/libexec/python3.12" -c '
import json
import sys

def cell_types(path):
    with open(path, encoding="utf-8") as stream:
        report = json.load(stream)
    modules = list(report.get("modules", {}).values())
    if len(modules) != 1:
        raise SystemExit(f"Expected one flattened module in {path}")
    return modules[0].get("num_cells_by_type", {})

def flip_flops(types):
    return sum(count for name, count in types.items() if name.startswith("FD"))

core_path, harness_path = sys.argv[1:]
core_types = cell_types(core_path)
harness_types = cell_types(harness_path)
core_ffs = flip_flops(core_types)
harness_ffs = flip_flops(harness_types)
print(f"Retained flip-flops: raw pair {core_ffs}, harness {harness_ffs}")
if harness_ffs < core_ffs:
    raise SystemExit("Compile harness pruned translated-process state")

core_brams = core_types.get("RAMB36E1", 0)
harness_brams = harness_types.get("RAMB36E1", 0)
print(f"Inferred RAMB36E1: raw pair {core_brams}, harness {harness_brams}")
if core_brams < 4 or harness_brams < 4:
    raise SystemExit("Trace storage did not retain four inferred block RAMs")
' "$core_stats" "$harness_stats"

case "$target" in
    xc7z010clg225-1) make_chipdb xc7z010clg225-1 ;;
    xc7z020clg484-2) make_chipdb xc7z020clg484-2 ;;
    all)
        make_chipdb xc7z010clg225-1
        make_chipdb xc7z020clg484-2
        ;;
esac

# The harness is a compile-only feasibility target, so timing misses are
# recorded in nextpnr's reports without preventing bitstream assembly.
case "$target" in
    xc7z010clg225-1)
        build_bitstream \
            regsvc \
            "$harness_netlist" \
            xc7z010clg225-1 \
            "$experiment_root/xc7z010clg225.xdc" \
            allow-timing-failure
        ;;
    xc7z020clg484-2)
        build_bitstream \
            regsvc \
            "$harness_netlist" \
            xc7z020clg484-2 \
            "$experiment_root/xc7z020clg484.xdc" \
            allow-timing-failure
        ;;
    all)
        build_bitstream \
            regsvc \
            "$harness_netlist" \
            xc7z020clg484-2 \
            "$experiment_root/xc7z020clg484.xdc" \
            allow-timing-failure
        build_bitstream \
            regsvc \
            "$harness_netlist" \
            xc7z010clg225-1 \
            "$experiment_root/xc7z010clg225.xdc" \
            allow-timing-failure
        ;;
esac
