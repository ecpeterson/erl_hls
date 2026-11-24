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

run_compiler() (
    local projection_root
    projection_root=$(mktemp -d "${TMPDIR:-/tmp}/erl-hls-eunit.XXXXXX")
    trap 'cleanup_projection "$projection_root"' EXIT
    link_root_inputs "$projection_root"
    link_full_app "$projection_root" erl_hls
    link_full_app "$projection_root" hls_core
    link_full_app "$projection_root" hls_runtime
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
    link_production_app "$projection_root" hls_runtime
    for app in hls_fabric router hls_lowering hls_phi hls_snowflake; do
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
    link_full_app "$projection_root" hls_spacetime
    printf '==> EUnit standalone spacetime projection\n'
    (cd "$projection_root" && rebar3 as spacetime eunit)
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
    *)
        echo "usage: $0 default|spacetime" >&2
        exit 2
        ;;
esac
