#!/usr/bin/env bash
# Check the retained dedicated D3 source graph through XLS IR elaboration only.
set -euo pipefail
xls_root=$(cd "${1:?usage: check_dedicated_noise.sh XLS_ROOT NEW_STAGE}" && pwd -P)
stage=${2:?usage: check_dedicated_noise.sh XLS_ROOT NEW_STAGE}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)

[[ -x "$xls_root/ir_converter_main" ]] || {
    echo "missing XLS converter: $xls_root/ir_converter_main" >&2
    exit 2
}
[[ -d "$xls_root/xls/dslx/stdlib" ]] || {
    echo "missing XLS standard library: $xls_root/xls/dslx/stdlib" >&2
    exit 2
}
# A new directory prevents stale source or IR from satisfying the check.
mkdir "$stage"
stage=$(cd "$stage" && pwd -P)
cd "$project_root"
source tools/hls_fabric/backend_env.sh test

PHI_DEDICATED_STAGE="$stage" erl +S 2:2 -noshell -eval '
    Stage = os:getenv("PHI_DEDICATED_STAGE"),
    lists:foreach(fun(Name) ->
        Source = filename:join("apps/hls_phi/src", Name ++ ".erl"),
        Generated = iolist_to_binary(xls_parse:to_xls(Source)),
        ok = file:write_file(filename:join(Stage, Name ++ ".x"), Generated),
        {ok, Expected} = file:read_file(Source ++ ".x"),
        case Generated =:= Expected of
            true -> ok;
            false -> error({actor_golden_mismatch, Source})
        end
    end, ["phi_halo_cell", "phenom_data_cell", "phenom_syndrome_cell"]),
    Topology = iolist_to_binary(phi_noise_topology_dslx:to_dslx()),
    ok = file:write_file(filename:join(Stage, "phi_noise_topology.x"), Topology),
    {ok, TopologyGolden} = file:read_file("apps/hls_phi/src/phi_noise_topology.x"),
    case Topology =:= TopologyGolden of
        true -> ok;
        false -> error(dedicated_noise_golden_mismatch)
    end,
    halt().
' > "$stage/generation.log" 2>&1

# Use support sources from the same compiler selected for the Erlang lowering.
cp "$erl_hls_root"/priv/xls/lib/*.x "$stage/"
cp "$erl_hls_root/priv/xls/fabric/hls_spatial_router.x" "$stage/"
cp apps/hls_phi/src/phi_field.x "$stage/"
"$xls_root/ir_converter_main" \
    --warnings_as_errors=false \
    --dslx_path="$stage" \
    --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" \
    --top=Top \
    "$stage/phi_noise_topology.x" \
    > "$stage/phi_noise_topology.ir" 2> "$stage/elaboration.log"
test -s "$stage/phi_noise_topology.ir"
echo "PASS: dedicated D3 noise golden and XLS elaboration; $stage"
