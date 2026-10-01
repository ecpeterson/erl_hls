#!/usr/bin/env bash
set -euo pipefail

mode=${1:?usage: xls_goldens.sh check|update STAGE}
stage=${2:?usage: xls_goldens.sh check|update STAGE}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

case "$mode" in
    check|update) ;;
    *)
        echo "usage: xls_goldens.sh check|update STAGE" >&2
        exit 2
        ;;
esac

# Keep this manifest explicit: these are the compact, reviewable DSLX artifacts
# produced by the Erlang translator and topology generator. RTL behavior is
# checked by simulation; its text and hashes are not golden artifacts.
generated=(
    regsvc.x
    phi_halo_cell.x
    phenom_data_cell.x
    phenom_syndrome_cell.x
    phi_phenom_topology.x
    phi_torus_topology.x
    phi_noise_topology.x
)
goldens=(
    src/examples/regsvc/regsvc.erl.x
    src/examples/phi_decoder/phi_halo_cell.erl.x
    src/examples/phi_decoder/phenom_data_cell.erl.x
    src/examples/phi_decoder/phenom_syndrome_cell.erl.x
    src/examples/phi_decoder/phi_phenom_topology.x
    src/examples/phi_decoder/phi_torus_topology.x
    src/examples/phi_decoder/phi_noise_topology.x
)
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

exit "$status"
