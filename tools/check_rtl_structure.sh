#!/usr/bin/env bash
set -euo pipefail

top=${1:?usage: check_rtl_structure.sh TOP OUTPUT_PREFIX RTL...}
output=${2:?usage: check_rtl_structure.sh TOP OUTPUT_PREFIX RTL...}
shift 2
if [[ $# == 0 || ! "$top" =~ ^[a-zA-Z_][a-zA-Z0-9_\$]*$ ]]; then
    echo "expected a Verilog top identifier and at least one RTL file" >&2
    exit 1
fi
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
yosys=${ERL_HLS_YOSYS:-$(command -v yosys || true)}
yosys=${yosys:-"$project_root/experiments/07-openxc7/.apio/packages/oss-cad-suite/bin/yosys"}
mkdir -p "$(dirname "$output")"

{
    printf 'read_verilog -sv'
    for rtl in "$@"; do
        test -s "$rtl"
        quoted=${rtl//\\/\\\\}
        quoted=${quoted//\"/\\\"}
        printf ' "%s"' "$quoted"
    done
    printf '\nhierarchy -check -top %s\n' "$top"
    # Check while Yosys still knows the combinational dependencies of cells.
    # A post-mapping check can overlook feedback through technology primitives.
    printf 'proc\nflatten\nopt\ncheck -assert\nscc -expect 0\n'
} > "$output.ys"

if ! "$yosys" -Q -q -l "$output.log" -s "$output.ys" > "$output.console" 2>&1; then
    tail -80 "$output.console" >&2
    echo "RTL structural check failed; see $output.log" >&2
    exit 1
fi
printf 'PASS: %s has no structural errors or combinational loops\n' "$top"
