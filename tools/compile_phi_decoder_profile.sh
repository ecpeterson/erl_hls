#!/usr/bin/env bash
# Lower the decoder profile without installing private-state simulation hooks.
set -euo pipefail
export LC_ALL=C
stage=${1:?usage: compile_phi_decoder_profile.sh STAGE XLS_ROOT [TIMEOUT SHARDS STAGES II]}
xls_root=${2:?usage: compile_phi_decoder_profile.sh STAGE XLS_ROOT [TIMEOUT SHARDS STAGES II]}
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
stage_timeout=${3:-2h}
shard_count=${4:-3}
pipeline_stages=${5:-2}
initiation_interval=${6:-1}
for value in "$shard_count" "$pipeline_stages" "$initiation_interval"; do
    if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
        echo "SHARDS, STAGES, and II must be positive integers" >&2
        exit 1
    fi
done
scheduler_count=$((2 + 2 * shard_count))
stdlib="$xls_root/xls/dslx/stdlib"
source "$stage/phi_scheduler_rams.sh"
if [[ $(uname -s) == Darwin ]]; then time_arguments=(-p); else time_arguments=(-v); fi
cd "$stage"
rm -f phi_decoder_profile.build.json

timed_output() {
    label=$1
    output=$2
    shift 2
    if /usr/bin/time "${time_arguments[@]}" -o "$label.time.new" \
            timeout --signal=TERM --kill-after=5m "$stage_timeout" \
            "$@" > "$output.new"; then
        mv "$label.time.new" "$label.time"
        mv "$output.new" "$output"
    else
        status=$?
        [[ ! -e "$label.time.new" ]] || mv "$label.time.new" "$label.time.failed"
        [[ ! -e "$output.new" ]] || mv "$output.new" "$output.failed"
        return "$status"
    fi
}

timed_output \
    phi_decoder_profile-ir \
    phi_decoder_profile.ir \
    "$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_path=. \
    --dslx_stdlib_path="$stdlib" \
    --top=Top \
    phi_decoder_profile_topology.x

timed_output \
    phi_decoder_profile-opt \
    phi_decoder_profile.opt.ir \
    "$xls_root/opt_main" \
    phi_decoder_profile.ir

timed_output \
    phi_decoder_profile-codegen \
    phi_decoder_profile.v \
    "$xls_root/codegen_main" \
    --pipeline_stages="$pipeline_stages" \
    --worst_case_throughput="$initiation_interval" \
    --delay_model=unit \
    --flop_inputs=false \
    --flop_outputs=true \
    --use_system_verilog=false \
    --reset=reset \
    --fifo_module= \
    --ram_configurations="$(phi_scheduler_ram_configurations "$scheduler_count")" \
    phi_decoder_profile.opt.ir

# Publish provenance only after all three stages succeed. Consumers verify the
# generated RTL and wrapper hashes before labeling a physical result as D3.
python3 - "$xls_root" "$shard_count" "$pipeline_stages" "$initiation_interval" <<'PY'
import hashlib
import json
from pathlib import Path
import re
import sys

def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()

xls = Path(sys.argv[1])
source = Path("phi_decoder_profile_topology.x").read_text()
dimensions = {name.lower(): int(re.search(rf"const {name} = u16:(\d+);", source)[1])
              for name in ("WIDTH", "HEIGHT")}
rtl = ["phi_decoder_profile.v", "phi_decoder_profile_top.v", "hls_1r1w_ram.v"]
result = {
    "schema": 1,
    "profile": {**dimensions, "shards_per_plane": int(sys.argv[2]),
                "pipeline_stages": int(sys.argv[3]), "initiation_interval": int(sys.argv[4]),
                "delay_model": "unit", "flop_inputs": False, "flop_outputs": True},
    "tools": {name: sha(xls / name) for name in ("ir_converter_main", "opt_main", "codegen_main")},
    "sources": {p.name: sha(p) for p in sorted(Path(".").glob("*.x"))},
    "stdlib": {str(p.relative_to(xls)): sha(p) for p in sorted((xls / "xls/dslx/stdlib").rglob("*.x"))},
    "ram_configuration": sha(Path("phi_scheduler_rams.sh")),
    "rtl": {name: sha(Path(name)) for name in rtl},
}
Path("phi_decoder_profile.build.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
PY
