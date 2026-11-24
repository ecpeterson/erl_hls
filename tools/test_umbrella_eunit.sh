#!/usr/bin/env bash
# Run retained suites from fresh app projections so private fixtures never share a VM.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

cleanup_projection() {
    local projection_root=$1
    case "$projection_root" in
        */erl-hls-eunit.*) rm -rf -- "$projection_root" ;;
        *)
            printf 'refusing to remove unexpected projection path: %s\n' "$projection_root" >&2
            return 1
            ;;
    esac
}

link_root_inputs() {
    local projection_root=$1
    local source name
    for source in "$repo_root"/* "$repo_root"/.[!.]* "$repo_root"/..?*; do
        [[ -e "$source" ]] || continue
        name=${source##*/}
        case "$name" in
            .git|_build|_checkouts|apps|imports) continue ;;
        esac
        ln -s "$source" "$projection_root/$name"
    done
    mkdir -p "$projection_root/apps"
}

link_full_app() {
    local projection_root=$1 app=$2
    ln -s "$repo_root/apps/$app" "$projection_root/apps/$app"
}

link_production_app() {
    local projection_root=$1 app=$2 entry
    mkdir -p "$projection_root/apps/$app"
    for entry in src include priv rebar.config; do
        [[ -e "$repo_root/apps/$app/$entry" ]] || continue
        ln -s "$repo_root/apps/$app/$entry" "$projection_root/apps/$app/$entry"
    done
}

link_boundary_app() {
    local projection_root=$1 app=$2
    link_production_app "$projection_root" "$app"
    ln -s "$repo_root/apps/$app/test_boundary" "$projection_root/apps/$app/test"
}

run_compiler() (
    local projection_root
    projection_root=$(mktemp -d "${TMPDIR:-/tmp}/erl-hls-eunit.XXXXXX")
    trap 'cleanup_projection "$projection_root"' EXIT
    link_root_inputs "$projection_root"
    link_full_app "$projection_root" erl_hls
    for app in hls_core hls_compile hls_runtime hls_fabric hls_target; do
        link_production_app "$projection_root" "$app"
    done
    printf '==> EUnit compiler projection\n'
    (cd "$projection_root" && rebar3 eunit)
)

run_fabric() (
    local profile=$1 projection_root app
    projection_root=$(mktemp -d "${TMPDIR:-/tmp}/erl-hls-eunit.XXXXXX")
    trap 'cleanup_projection "$projection_root"' EXIT
    link_root_inputs "$projection_root"
    link_production_app "$projection_root" erl_hls
    link_production_app "$projection_root" hls_core
    link_production_app "$projection_root" hls_compile
    link_production_app "$projection_root" hls_runtime
    for app in hls_fabric router hls_target hls_phi hls_snowflake; do
        link_full_app "$projection_root" "$app"
    done
    if [[ "$profile" == spacetime ]]; then
        link_production_app "$projection_root" hls_spacetime
        link_full_app "$projection_root" hls_spacetime_observer
        printf '==> EUnit Fabric spacetime projection\n'
        (cd "$projection_root" && rebar3 as spacetime eunit)
    else
        printf '==> EUnit Fabric default projection\n'
        (cd "$projection_root" && rebar3 eunit)
    fi
)

run_spacetime() (
    local projection_root
    projection_root=$(mktemp -d "${TMPDIR:-/tmp}/erl-hls-eunit.XXXXXX")
    trap 'cleanup_projection "$projection_root"' EXIT
    link_root_inputs "$projection_root"
    link_production_app "$projection_root" hls_core
    link_production_app "$projection_root" hls_compile
    link_production_app "$projection_root" hls_runtime
    link_production_app "$projection_root" hls_fabric
    link_production_app "$projection_root" hls_target
    link_full_app "$projection_root" hls_spacetime
    printf '==> EUnit standalone spacetime projection\n'
    (cd "$projection_root" && rebar3 as spacetime eunit)
)

run_boundaries() {
    run_compile_boundary
    run_fabric_boundary
    run_target_boundary
    run_spacetime
}

run_compile_boundary() (
    local projection_root
    projection_root=$(mktemp -d "${TMPDIR:-/tmp}/erl-hls-eunit.XXXXXX")
    trap 'cleanup_projection "$projection_root"' EXIT
    link_root_inputs "$projection_root"
    link_full_app "$projection_root" hls_compile
    link_production_app "$projection_root" hls_core
    link_production_app "$projection_root" hls_runtime
    printf '==> EUnit computation-synthesis boundary projection\n'
    (cd "$projection_root" && rebar3 eunit)
)

run_fabric_boundary() (
    local projection_root
    projection_root=$(mktemp -d "${TMPDIR:-/tmp}/erl-hls-eunit.XXXXXX")
    trap 'cleanup_projection "$projection_root"' EXIT
    link_root_inputs "$projection_root"
    link_boundary_app "$projection_root" hls_fabric
    for app in hls_core hls_runtime hls_compile; do
        link_production_app "$projection_root" "$app"
    done
    printf '==> EUnit communication-synthesis boundary projection\n'
    (cd "$projection_root" && rebar3 eunit)
)

run_target_boundary() (
    local projection_root
    projection_root=$(mktemp -d "${TMPDIR:-/tmp}/erl-hls-eunit.XXXXXX")
    trap 'cleanup_projection "$projection_root"' EXIT
    link_root_inputs "$projection_root"
    link_boundary_app "$projection_root" hls_target
    for app in hls_core hls_runtime hls_compile hls_fabric; do
        link_production_app "$projection_root" "$app"
    done
    printf '==> EUnit physical-target boundary projection\n'
    (cd "$projection_root" && rebar3 eunit)
)

case "${1:-default}" in
    default)
        run_compiler
        run_fabric default
        ;;
    spacetime)
        run_fabric spacetime
        run_spacetime
        ;;
    boundaries)
        run_boundaries
        ;;
    *)
        echo "usage: $0 default|spacetime|boundaries" >&2
        exit 2
        ;;
esac
