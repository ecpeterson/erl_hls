#!/usr/bin/env bash
set -euo pipefail
xls_root=${1:?usage: test_reduction_dslx.sh XLS_ROOT [STAGE]}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=${2:-"$project_root/_build/reduction-semantics"}
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
cd "$project_root"
rebar3 as test compile
ERL_HLS_REDUCTION_STAGE="$stage" erl -noshell -pa _build/test/lib/erl_hls/ebin -eval '
    Stage = os:getenv("ERL_HLS_REDUCTION_STAGE"),
    {ok, MaskSource} = file:read_file("test_data/hls_statem_mask_reduction_fixture.erl"),
    SignedSource = filename:join(Stage, "signed_mask.erl"),
    ok = file:write_file(SignedSource, binary:replace(MaskSource,
        <<"mask = hls_type:zero() :: hls_nums:u8()">>,
        <<"mask = hls_type:zero() :: hls_nums:s8()">>, [global])),
    lists:foreach(fun({Name, Source, Snippets}) ->
        X = xls_parse:to_xls(Source, #{direct_actor_debug => Name =:= "mask_debug"}),
        Tests = [begin {ok, B} = file:read_file("test_data/" ++ S ++ ".inc.x"), B end || S <- Snippets],
        ok = file:write_file(filename:join(Stage, Name ++ ".x"), [X, Tests])
    end, [{"reduction", "test_data/hls_statem_reduction_lower_fixture.erl", ["hls_statem_reduction_semantics"]},
          {"mask", "test_data/hls_statem_mask_reduction_fixture.erl", ["hls_statem_mask_reduction_semantics"]},
          {"mask_debug", "test_data/hls_statem_mask_reduction_fixture.erl", ["hls_statem_mask_debug_semantics"]},
          {"signed_mask", SignedSource, ["hls_statem_signed_mask_semantics"]},
          {"failure", "test/hls_reduction_failure_fixture.erl", ["hls_reduction_failure_semantics", "hls_reduction_failure_ordinary_semantics"]}]), halt().'
for name in reduction failure mask mask_debug signed_mask; do
    "$xls_root/interpreter_main" --compare=jit --warnings_as_errors=false \
        --dslx_path="$project_root/priv/xls/lib" \
        --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" "$stage/$name.x"
    "$xls_root/ir_converter_main" --top=Top --warnings_as_errors=false \
        --dslx_path="$project_root/priv/xls/lib" \
        --dslx_stdlib_path="$xls_root/xls/dslx/stdlib" "$stage/$name.x" > "$stage/$name.ir"
done
