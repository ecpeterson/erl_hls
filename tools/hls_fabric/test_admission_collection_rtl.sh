#!/usr/bin/env bash
# Exercise real RAM ownership, output stalls and reset through the materialized topology.
set -euo pipefail
xls_root=${1:?usage: test_admission_collection_rtl.sh XLS_ROOT}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$project_root"
policy=${2:-true}
case "$policy" in true|exclusive_epoch) ;; *) echo "invalid collector policy" >&2; exit 1;; esac
stage="$project_root/_build/admission-collection/rtl-$policy"
mkdir -p "$stage"
rebar3 as test compile
source tools/hls_fabric/backend_env.sh test
erl -noshell -eval '
[Stage,Policy]=init:get_plain_arguments(),
ok=hls_admission_collection_dslx:write(Stage,case Policy of "true" -> true; "exclusive_epoch" -> exclusive_epoch end),halt().' -extra "$stage" "$policy"
cp "$erl_hls_root"/priv/xls/lib/*.x apps/hls_lowering/priv/xls/lib/*.x "$erl_hls_root"/priv/xls/fabric/*.x "$stage/"
source tools/hls_fabric/scheduler_ram_configurations.sh
for stages in 2 3; do
  output="$stage/p$stages"
  python3 "$project_root/tools/compile_xls.py" "$stage/collection_top.x" "$xls_root" --output "$output" \
    --name collection --top Top --pipeline-stages "$stages" --delay-model unit \
    --ram-configurations "$(scheduler_ram_configurations 1)"
  iverilog -g2012 -s admission_collection_tb -o "$stage/test-p$stages.vvp" \
    apps/hls_fabric/test/rtl/admission_collection_tb.sv \
    "$output/collection.v" "$stage/collection_wrapper.v" "$erl_hls_root/priv/rtl/hls_1r1w_ram.v"
  vvp "$stage/test-p$stages.vvp"
  if [[ "$policy" == exclusive_epoch ]]; then
    iverilog -g2012 -s exclusive_collection_tb -o "$stage/exclusive-p$stages.vvp" \
      apps/hls_fabric/test/rtl/exclusive_collection_tb.sv \
      "$output/collection.v" "$stage/collection_wrapper.v" "$erl_hls_root/priv/rtl/hls_1r1w_ram.v"
    vvp "$stage/exclusive-p$stages.vvp"
  fi
done
