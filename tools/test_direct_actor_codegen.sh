#!/usr/bin/env bash
set -euo pipefail
xls_root=${1:?usage: test_direct_actor_codegen.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/direct-actor-codegen"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
xls_root=$(cd "$xls_root" && pwd)
cd "$project_root"
rebar3 as test compile
erl -noshell -pa _build/test/lib/erl_hls/ebin _build/test/lib/erl_hls/test \
    -eval 'ok=xls_actor_observation_tests:write(hd(init:get_plain_arguments())),halt().' -extra "$stage"
for name in hls_dense_statem_fixture debug_scalar debug_rectangle debug_commit; do
    "$xls_root/ir_converter_main" --top=Top --warnings_as_errors=false \
        --dslx_path="$stage:$project_root/priv/xls/lib:$project_root/priv/xls/fabric" \
        --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" "$stage/$name.x" > "$stage/$name.ir"
    "$xls_root/opt_main" "$stage/$name.ir" > "$stage/$name.opt.ir"
    "$xls_root/codegen_main" --pipeline_stages=2 --delay_model=unit \
        --flop_inputs=false --flop_outputs=true --use_system_verilog=false --reset=reset \
        --fifo_module= --module_name="$name" "$stage/$name.opt.ir" > "$stage/$name.v"
done
iverilog -g2012 -I "$stage" -s hls_actor_observation_tb -o "$stage/commit.vvp" \
    test/rtl/debug/hls_actor_observation_tb.sv "$stage/debug_commit.v"
vvp "$stage/commit.vvp"
python3 - "$stage" <<'PY'
import json
import pathlib
import re
import sys

stage = pathlib.Path(sys.argv[1])
for name in ("hls_dense_statem_fixture", "debug_scalar", "debug_rectangle"):
    verilog = (stage / f"{name}.v").read_text()
    text = re.search(r"module " + name + r"\s*\((.*?)\);", verilog, re.S).group(1)
    expected = json.loads((stage / f"{name}.json").read_text())
    ports = dict((port, int(high) + 1) for high, port in re.findall(
        r"output wire \[(\d+):0\] (_(?:actor|family).*?_debug_out(?:__\d+_\d+)?)(?:,|\s*$)", text, re.M))
    assert ports == {entry["port"]: entry["width"] for entry in expected}, (name, ports, expected)
    for entry in expected:
        port = re.escape(entry["port"])
        assert re.search(r"input wire " + port + r"_rdy(?:,|\s*$)", text, re.M), entry
        assert re.search(r"output wire " + port + r"_vld(?:,|\s*$)", text, re.M), entry
    print(f"PASS: {name}: {len(expected)} compiler-bound diagnostic ports")
PY
