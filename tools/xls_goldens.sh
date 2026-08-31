#!/usr/bin/env bash
set -euo pipefail

mode=${1:?usage: xls_goldens.sh check|update STAGE}
stage=${2:?usage: xls_goldens.sh check|update STAGE}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
verilog_manifest="$project_root/test/golden/xls_verilog.sha256"

case "$mode" in
    check|update) ;;
    *)
        echo "usage: xls_goldens.sh check|update STAGE" >&2
        exit 2
        ;;
esac

# Keep this manifest explicit: these are the compact, reviewable DSLX artifacts
# produced by the Erlang translator and topology generator. Generated Verilog
# is compiled and simulated in the staging directory, but is not checked in.
generated=(
    regsvc.x
    phi_halo_cell.x
    phenom_data_cell.x
    phenom_syndrome_cell.x
    phi_phenom_topology.x
    phi_torus_topology.x
)
goldens=(
    src/examples/regsvc/regsvc.erl.x
    src/examples/phi_decoder/phi_halo_cell.erl.x
    src/examples/phi_decoder/phenom_data_cell.erl.x
    src/examples/phi_decoder/phenom_syndrome_cell.erl.x
    src/examples/phi_decoder/phi_phenom_topology.x
    src/examples/phi_decoder/phi_torus_topology.x
)
verilog=(
    regsvc.v
    phi_halo_cell.v
    phenom_data_cell.v
    phenom_syndrome_cell.v
)

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

write_verilog_manifest() {
    local artifact

    for artifact in "${verilog[@]}"; do
        printf '%s  %s\n' "$(sha256_file "$stage/$artifact")" "$artifact"
    done
}

missing=false
for index in "${!generated[@]}"; do
    generated_path="$stage/${generated[$index]}"
    golden_path="$project_root/${goldens[$index]}"
    if [[ ! -f "$generated_path" ]]; then
        echo "missing generated artifact: $generated_path" >&2
        missing=true
    fi
    if [[ "$mode" == check && ! -f "$golden_path" ]]; then
        echo "missing checked-in artifact: $golden_path" >&2
        missing=true
    fi
done
for artifact in "${verilog[@]}"; do
    if [[ ! -f "$stage/$artifact" ]]; then
        echo "missing generated artifact: $stage/$artifact" >&2
        missing=true
    fi
done
if [[ "$mode" == check && ! -f "$verilog_manifest" ]]; then
    echo "missing checked-in artifact: $verilog_manifest" >&2
    missing=true
fi
if [[ "$missing" == true ]]; then
    exit 1
fi

status=0
for index in "${!generated[@]}"; do
    generated_path="$stage/${generated[$index]}"
    golden_path="$project_root/${goldens[$index]}"
    case "$mode" in
        check)
            if ! cmp -s "$generated_path" "$golden_path"; then
                echo "generated artifact differs: ${goldens[$index]}" >&2
                status=1
            fi
            ;;
        update)
            cp "$generated_path" "$golden_path"
            echo "updated ${goldens[$index]}"
            ;;
    esac
done

candidate=$(mktemp "${TMPDIR:-/tmp}/xls-verilog-sha256.XXXXXX")
trap 'rm -f "$candidate"' EXIT
write_verilog_manifest > "$candidate"
case "$mode" in
    check)
        if ! cmp -s "$candidate" "$verilog_manifest"; then
            echo "generated Verilog digests differ: test/golden/xls_verilog.sha256" >&2
            status=1
        fi
        ;;
    update)
        cp "$candidate" "$verilog_manifest"
        echo "updated test/golden/xls_verilog.sha256"
        ;;
esac
exit "$status"
