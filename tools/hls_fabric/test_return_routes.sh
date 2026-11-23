#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
stage="$root/_build/return-routes"
mkdir -p "$stage"
for config in '1 255' '3 255' '16 255' '255 255' '256 -1'; do
    read -r slots cast <<< "$config"
    output="$stage/context-$slots-$cast.vvp"
    iverilog -g2012 -s return_routes_tb -Preturn_routes_tb.SLOTS="$slots" \
        -Preturn_routes_tb.CAST_TXID="$cast" -o "$output" \
        "$root/apps/hls_lowering/priv/rtl/hls_return_routes.v" \
        "$root/apps/hls_fabric/test/rtl/return_routes_tb.sv"
    vvp "$output"
done
