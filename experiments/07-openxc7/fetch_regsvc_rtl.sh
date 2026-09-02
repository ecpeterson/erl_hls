#!/usr/bin/env bash
set -euo pipefail

experiment_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
project_root=$(cd "$experiment_root/../.." && pwd)
build_root=${ERL_HLS_OPENXC7_BUILD_ROOT:-"$experiment_root/build"}
remote_host=${ERL_HLS_REMOTE_HOST:-192.168.64.7}
remote_root=${ERL_HLS_REMOTE_ROOT:-/home/ecpeterson/erl_hls-build}
remote_xls=${ERL_HLS_REMOTE_XLS:-/home/ecpeterson/xls-v0.0.0-10601-g9f360fc89-linux-x64}

readonly expected_xls_version=v0.0.0-10601-g9f360fc89
readonly publish_parent="$build_root/regsvc"
readonly publish_path="$publish_parent/generated-rtl"
readonly release_root="$publish_parent/.generated-rtl-releases"

ssh_options=(-o BatchMode=yes -o ConnectTimeout=10)
rsync_shell="ssh -o BatchMode=yes -o ConnectTimeout=10"

rtl_files=(
    regsvc.v
    hls_debug_observer.v
    hls_debug_server.v
    hls_fabric_ingress.v
    hls_fabric_egress.v
)
expected_modules=(
    __regsvc__Top_0_next
    __hls_debug_observer__Observer_0_next
    __hls_debug_server__DebugServer_0_next
    __hls_fabric_router__PairIngress_0_next
    __hls_fabric_router__PairEgress_0_next
)
manifest_inputs=(
    regsvc.x
    axis.x
    hls_debug_types.x
    hls_debug_trace.x
    hls_debug_observer.x
    hls_debug_server.x
    hls_fabric_router.x
    regsvc_core_adapter.v
    regsvc_debug_top.v
    hls_debug_tap.v
    hls_trace_store.v
    regsvc_pair_fixture.sv
    remote_xls_sim.sh
)

local_stage=
remote_stage=
remote_stage_is_safe=false
release_stage=
link_stage=

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

remote_quote() {
    printf '%q' "$1"
}

sha256() {
    local path=$1
    local digest

    if command -v shasum >/dev/null 2>&1; then
        digest=$(shasum -a 256 "$path")
    elif command -v sha256sum >/dev/null 2>&1; then
        digest=$(sha256sum "$path")
    else
        fail "neither shasum nor sha256sum is available"
    fi
    printf '%s' "${digest%% *}"
}

cleanup() {
    local status=$?
    local quoted_stage

    trap - EXIT
    if [[ -n "$link_stage" && -d "$link_stage" ]]; then
        rm -rf -- "$link_stage"
    fi
    if [[ -n "$release_stage" && -d "$release_stage" ]]; then
        rm -rf -- "$release_stage"
    fi
    if [[ -n "$local_stage" && -d "$local_stage" ]]; then
        rm -rf -- "$local_stage"
    fi
    if [[ "$remote_stage_is_safe" == true ]]; then
        quoted_stage=$(remote_quote "$remote_stage")
        ssh "${ssh_options[@]}" "$remote_host" \
            "rm -rf -- $quoted_stage" >/dev/null 2>&1 || true
    fi
    exit "$status"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

case "$remote_host$remote_root$remote_xls" in
    *$'\n'*) fail "remote configuration must not contain newlines" ;;
esac
[[ -n "$remote_host" ]] || fail "ERL_HLS_REMOTE_HOST must not be empty"
[[ "$remote_root" == /* && "$remote_root" != / ]] ||
    fail "ERL_HLS_REMOTE_ROOT must be a non-root absolute path"
[[ "$remote_xls" == /* ]] ||
    fail "ERL_HLS_REMOTE_XLS must be an absolute path"

mkdir -p "$publish_parent" "$release_root"
local_stage=$(mktemp -d "$publish_parent/.fetch-regsvc.XXXXXX")
fetch_stage="$local_stage/fetched-rtl"
mkdir "$fetch_stage"

echo "Preparing a fresh regsvc XLS stage"
"$project_root/tools/prepare_xls_sim.sh" "$local_stage"
cp "$project_root/tools/remote_xls_sim.sh" \
    "$local_stage/remote_xls_sim.sh"

quoted_remote_root=$(remote_quote "$remote_root")
remote_template="${remote_root%/}/openxc7-regsvc.XXXXXX"
quoted_remote_template=$(remote_quote "$remote_template")
ssh "${ssh_options[@]}" "$remote_host" \
    "mkdir -p -- $quoted_remote_root"
remote_stage=$(ssh "${ssh_options[@]}" "$remote_host" \
    "mktemp -d $quoted_remote_template")

case "$remote_stage" in
    *$'\n'*) fail "remote mktemp returned more than one path" ;;
    "${remote_root%/}"/openxc7-regsvc.*) remote_stage_is_safe=true ;;
    *) fail "remote mktemp returned an unexpected path: $remote_stage" ;;
esac

quoted_codegen=$(remote_quote "$remote_xls/codegen_main")
remote_version=$(ssh "${ssh_options[@]}" "$remote_host" \
    "$quoted_codegen --version")
if [[ "$remote_version" != "$expected_xls_version" ]]; then
    fail "remote XLS version is '$remote_version'; expected '$expected_xls_version'"
fi
echo "Using XLS $remote_version"

echo "Uploading the fresh stage to $remote_host"
quoted_remote_stage=$(remote_quote "$remote_stage")
rsync -a -e "$rsync_shell" \
    "$local_stage/" "$remote_host:$quoted_remote_stage/"

echo "Generating RTL and running the complete remote regression"
quoted_remote_script=$(remote_quote "$remote_stage/remote_xls_sim.sh")
quoted_remote_xls=$(remote_quote "$remote_xls")
ssh "${ssh_options[@]}" "$remote_host" \
    "bash $quoted_remote_script $quoted_remote_stage $quoted_remote_xls"

echo "Fetching the five generated RTL outputs"
for rtl_file in "${rtl_files[@]}"; do
    quoted_remote_file=$(remote_quote "$remote_stage/$rtl_file")
    rsync -a -e "$rsync_shell" \
        "$remote_host:$quoted_remote_file" "$fetch_stage/$rtl_file"
    [[ -s "$fetch_stage/$rtl_file" ]] ||
        fail "remote regression produced an empty $rtl_file"
done

fetched_count=$(find "$fetch_stage" -maxdepth 1 -type f | wc -l | tr -d ' ')
[[ "$fetched_count" == "${#rtl_files[@]}" ]] ||
    fail "expected five fetched RTL files; found $fetched_count"

for ((index = 0; index < ${#rtl_files[@]}; index++)); do
    rtl_file=${rtl_files[$index]}
    expected_module=${expected_modules[$index]}
    if ! grep -Eq \
        "^[[:space:]]*module[[:space:]]+$expected_module[[:space:]]*\\(" \
        "$fetch_stage/$rtl_file"; then
        fail "$rtl_file does not declare expected module $expected_module"
    fi
done

release_stage=$(mktemp -d "$release_root/.new.XXXXXX")
for rtl_file in "${rtl_files[@]}"; do
    cp "$fetch_stage/$rtl_file" "$release_stage/$rtl_file"
done

manifest="$release_stage/manifest.sha256"
{
    printf '# erl_hls openXC7 generated-RTL provenance, schema 1\n'
    printf 'xls-version\t%s\n' "$remote_version"
    for input_file in "${manifest_inputs[@]}"; do
        [[ -s "$local_stage/$input_file" ]] ||
            fail "manifest input is missing: $input_file"
        printf 'input\t%s\t%s\n' \
            "$(sha256 "$local_stage/$input_file")" "$input_file"
    done
    for rtl_file in "${rtl_files[@]}"; do
        printf 'output\t%s\t%s\n' \
            "$(sha256 "$release_stage/$rtl_file")" "$rtl_file"
    done
} > "$manifest"

# Releases are content-addressed and generated-rtl is an atomically replaced
# symlink. Readers therefore see either the complete old set or the complete
# new set, never a partially copied directory.
release_id=$(sha256 "$manifest")
release_path="$release_root/$release_id"
if [[ -e "$release_path" ]]; then
    cmp -s "$manifest" "$release_path/manifest.sha256" ||
        fail "content-addressed release collision at $release_path"
    for rtl_file in "${rtl_files[@]}"; do
        cmp -s "$release_stage/$rtl_file" "$release_path/$rtl_file" ||
            fail "content-addressed release collision for $rtl_file"
    done
    rm -rf -- "$release_stage"
else
    mv "$release_stage" "$release_path"
fi
release_stage=

if [[ -e "$publish_path" && ! -L "$publish_path" ]]; then
    fail "$publish_path exists and is not a managed symlink"
fi

link_stage=$(mktemp -d "$publish_parent/.generated-rtl-link.XXXXXX")
ln -s ".generated-rtl-releases/$release_id" "$link_stage/generated-rtl"
if [[ $(uname -s) == Darwin ]]; then
    mv -fh "$link_stage/generated-rtl" "$publish_path"
else
    mv -Tf "$link_stage/generated-rtl" "$publish_path"
fi
rmdir "$link_stage"
link_stage=

echo "Published validated RTL at $publish_path"
echo "Manifest: $publish_path/manifest.sha256"
