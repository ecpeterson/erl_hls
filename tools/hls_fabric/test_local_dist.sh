#!/usr/bin/env bash
# Run after rebar3 eunit has compiled the test profile.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/hls_fabric/backend_env.sh test
exec erl +S 4:4 +zdbbl 8 -noshell -kernel net_ticktime 4 -proto_dist hls_local \
    -pa _build/test/lib/hls_fabric/ebin _build/test/lib/hls_fabric/test \
    -eval 'case eunit:test([hls_node_tests, hls_node_actor_tests, hls_protocol_mixed_distribution_tests], [verbose]) of ok -> halt(0); _ -> halt(1) end.'
