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

# Keep this manifest explicit: these are the source-adjacent artifacts produced
# by the Erlang translator and the pinned XLS code generator.
generated=(
    regsvc.x
    regsvc.v
    phi_halo_cell.x
    phi_halo_cell.v
)
goldens=(
    src/examples/regsvc.erl.x
    src/examples/regsvc.v
    src/examples/phi_halo_cell.erl.x
    src/examples/phi_halo_cell.v
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
