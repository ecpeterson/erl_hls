-module(hls_spacetime_artifact_tests).
-include_lib("eunit/include/eunit.hrl").

%% A fresh directory exercises the same artifact boundary used by capture producers.
-spec bundle_workflow_test() -> ok.
bundle_workflow_test() ->
    {ok, [Bundle]} = file:consult("test_data/spacetime_example.term"),
    Root = fresh(),
    Output = filename:join(Root, "bundle"),
    Summary = hls_spacetime_artifact:write_bundle(Bundle, Output),
    Path = filename:join(Output, "bundle.etf"),
    ?assertEqual(Bundle, hls_spacetime_artifact:read(Path)),
    ?assertEqual(Summary, hls_spacetime_cli:run(["validate", Path])),
    {ok, Json} = file:read_file(filename:join(Output, "bundle.json")),
    ?assertEqual(iolist_to_binary(hls_spacetime:encode(Bundle)), Json),
    ?assertException(error, {badmatch, {error, eexist}}, hls_spacetime_artifact:write_bundle(Bundle, Output)),
    ok = file:del_dir_r(Root).

%% A new joined artifact passes the full library validator, preserving the graph.
-spec join_workflow_test() -> ok.
join_workflow_test() ->
    {ok, [Bundle]} = file:consult("test_data/spacetime_example.term"),
    Physical = maps:get(physical, Bundle),
    Catalogue = Physical#{bindings := [], generated := []},
    Claims = maps:with([bindings, generated], Physical),
    Root = fresh(),
    BundleDir = filename:join(Root, "bundle"),
    CatalogueDir = filename:join(Root, "catalogue"),
    Output = filename:join(Root, "joined"),
    _ = hls_spacetime_artifact:write_bundle(Bundle#{physical := null}, BundleDir),
    _ = hls_spacetime_artifact:write_catalogue(Catalogue, CatalogueDir),
    ClaimsPath = filename:join(Root, "claims.etf"),
    ok = file:write_file(ClaimsPath, term_to_binary(Claims, [deterministic])),
    Summary = hls_spacetime_cli:run(["join", filename:join(BundleDir, "bundle.etf"),
        filename:join(CatalogueDir, "catalogue.etf"), ClaimsPath, Output]),
    ?assertEqual(hls_spacetime:validate(Bundle), Summary),
    ?assertEqual(Bundle, hls_spacetime_artifact:read(filename:join(Output, "bundle.etf"))),
    ok = file:del_dir_r(Root).

%% Validation occurs before directory creation, so invalid input cannot look complete.
-spec invalid_bundle_test() -> ok.
invalid_bundle_test() ->
    Root = fresh(),
    Output = filename:join(Root, "invalid"),
    ?assertException(error, {spacetime, format}, hls_spacetime_artifact:write_bundle(#{}, Output)),
    ?assertEqual(false, filelib:is_dir(Output)),
    ok = file:del_dir_r(Root).

%% Raw ETF bounds would be ineffective if compressed terms or executable terms passed.
-spec unsafe_interchange_test() -> ok.
unsafe_interchange_test() ->
    Root = fresh(),
    Path = filename:join(Root, "data.etf"),
    ok = file:write_file(Path, term_to_binary(lists:duplicate(1000, hello), [compressed])),
    ?assertException(error, {spacetime_artifact, compressed_term}, hls_spacetime_artifact:read(Path)),
    ok = file:write_file(Path, term_to_binary(self())),
    ?assertException(error, {spacetime_artifact, non_data_term}, hls_spacetime_artifact:read(Path)),
    ok = file:write_file(Path, [term_to_binary(#{}), "trailing"]),
    ?assertException(error, {badmatch, false}, hls_spacetime_artifact:read(Path)),
    ok = file:del_dir_r(Root).

%% A separate VM has not interned native SDF enums by running an importer first.
-spec fresh_process_schema_test() -> ok.
fresh_process_schema_test() ->
    Root = fresh(),
    Path = filename:join(Root, "sdf.etf"),
    Description = #{timescale => #{magnitude => <<"1">>, unit => fs},
        source => #{corner => fast, mode => sta}},
    ok = file:write_file(Path, term_to_binary(Description, [deterministic])),
    Ebin = filename:dirname(code:which(hls_spacetime_artifact)),
    Erl = filename:join([code:root_dir(), "bin", "erl"]),
    Port = open_port({spawn_executable, Erl}, [exit_status, binary, stderr_to_stdout,
        {args, ["+S", "1:1", "-noshell", "-pa", Ebin, "-eval",
            "_ = hls_spacetime_artifact:read(hd(init:get_plain_arguments())), halt().",
            "-extra", Path]}]),
    ok = completed(Port, []),
    ok = file:del_dir_r(Root).

%% The maintained command preserves SDF conditions and returns an exact new-file receipt.
-spec sdf_arcs_workflow_test() -> ok.
sdf_arcs_workflow_test() ->
    Root = fresh(),
    Input = filename:join(Root, "input.sdf"),
    Output = filename:join(Root, "arcs.json"),
    {Bytes, Digest} = sdf_fixture(),
    ok = file:write_file(Input, Bytes),
    try
        Summary = hls_spacetime_cli:run(["sdf-arcs", Input, Digest, "slow", Output]),
        {ok, Json} = file:read_file(Output),
        ?assertEqual(byte_size(Json), maps:get(bytes, Summary)),
        ?assertEqual(binary:encode_hex(crypto:hash(sha256, Json), lowercase), maps:get(sha256, Summary)),
        ?assertEqual(1, maps:get(arcs, Summary)),
        ?assertEqual(1, maps:get(issues, Summary)),
        ?assertMatch(#{corner := slow, mode := sta}, maps:get(source, Summary)),
        #{<<"arcs">> := [Arc], <<"issues">> := [_]} = json:decode(Json),
        ?assertEqual(4, maps:get(<<"max_ps">>, Arc)),
        ?assertEqual(1, length(maps:get(<<"guards">>, Arc))),
        ?assertError({spacetime_cli, {write, Output, eexist}},
            hls_spacetime_cli:run(["sdf-arcs", Input, Digest, "slow", Output])),
        ?assertEqual({ok, Json}, file:read_file(Output))
    after file:del_dir_r(Root) end.

%% Invalid source identity/corner must not leave even an empty output artifact.
-spec sdf_arcs_rejection_test() -> ok.
sdf_arcs_rejection_test() ->
    Root = fresh(),
    Input = filename:join(Root, "input.sdf"),
    Output = filename:join(Root, "arcs.json"),
    {Bytes, Digest} = sdf_fixture(),
    ok = file:write_file(Input, Bytes),
    try
        ?assertError({spacetime_sdf, digest_mismatch},
            hls_spacetime_cli:run(["sdf-arcs", Input, lists:duplicate(64, $0), "fast", Output])),
        ?assertError({spacetime_cli, {sdf_corner, "typical"}},
            hls_spacetime_cli:run(["sdf-arcs", Input, Digest, "typical", Output])),
        ?assertEqual(false, filelib:is_file(Output))
    after file:del_dir_r(Root) end.

%% A clean VM loads the reader/projector through the same dispatcher without prior schema setup.
-spec sdf_arcs_fresh_process_test() -> ok.
sdf_arcs_fresh_process_test() ->
    Root = fresh(),
    Input = filename:join(Root, "input.sdf"),
    Output = filename:join(Root, "arcs.json"),
    {Bytes, Digest} = sdf_fixture(),
    ok = file:write_file(Input, Bytes),
    Ebin = filename:dirname(code:which(hls_spacetime_cli)),
    Erl = filename:join([code:root_dir(), "bin", "erl"]),
    try
        Port = open_port({spawn_executable, Erl}, [exit_status, binary, stderr_to_stdout,
            {args, ["+S", "1:1", "-noshell", "-pa", Ebin, "-eval",
                "_ = hls_spacetime_cli:run(init:get_plain_arguments()), halt().",
                "-extra", "sdf-arcs", Input, Digest, "fast", Output]}]),
        ok = completed(Port, []),
        {ok, Json} = file:read_file(Output),
        ?assertMatch(#{<<"source">> := #{<<"corner">> := <<"fast">>}, <<"arcs">> := [_]}, json:decode(Json))
    after file:del_dir_r(Root) end.

%% Invented delays exercise the CLI contract; they are not native measurements.
-spec sdf_fixture() -> {binary(), string()}.
sdf_fixture() ->
    Bytes = <<"(DELAYFILE (TIMESCALE 1ps) (CELL (CELLTYPE \"LUT1\") (INSTANCE lut) (DELAY (ABSOLUTE (COND EN == 1 (IOPATH I0 O (1:2:3) (2:3:4)))) (UNFAMILIAR x))))">>,
    Digest = binary_to_list(binary:encode_hex(crypto:hash(sha256, Bytes), lowercase)),
    {Bytes, Digest}.

%% Retain child diagnostics in the failing assertion; never wait indefinitely.
-spec completed(port(), [binary()]) -> ok.
completed(Port, Output) ->
    receive
        {Port, {data, Bytes}} -> completed(Port, [Bytes | Output]);
        {Port, {exit_status, 0}} -> ok;
        {Port, {exit_status, Exit}} -> error({child_exit, Exit, lists:reverse(Output)})
    after 10000 -> port_close(Port), error(child_timeout)
    end.

%% VM-local unique integers repeat across test runs. Allocate atomically with
%% a fresh random suffix, preserving earlier witness directories on collision.
-spec fresh() -> file:filename().
fresh() ->
    Suffix = binary_to_list(binary:encode_hex(crypto:strong_rand_bytes(12), lowercase)),
    Path = filename:join("/tmp", "spacetime-artifact-" ++ Suffix),
    case file:make_dir(Path) of
        ok -> Path;
        {error, eexist} -> fresh();
        {error, Reason} -> error({temporary_directory, Path, Reason})
    end.
