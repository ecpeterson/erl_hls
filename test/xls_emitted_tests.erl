-module(xls_emitted_tests).
-moduledoc "Checks actor-owned DSLX imports, shared failure codes and complete generated-file writes.".
-include_lib("eunit/include/eunit.hrl").

%% Separate modules use one actor codebook even when their local numbering would differ.
-spec dependency_failures_share_the_actor_codebook_test() -> ok.
dependency_failures_share_the_actor_codebook_test() ->
    Main = origin("actor.erl", 3, badarg),
    Imported = origin("helper.erl", 8, function_clause),
    Locations = [maps:remove(kind, O) || O <- [Main, Imported]],
    Artifact = xls_emitted:new(Locations, "// main\n", value(Main), #{
        "actor_helpers/helper.x" => #{preamble => "// helper\n", body => value(Imported)}
    }),
    ExpectedSites = xls_failure_sites:number([Main, Imported]),
    ?assertEqual(ExpectedSites, xls_emitted:sites(Artifact, Locations)),
    [MainSite, ImportedSite] = ExpectedSites,
    MainDeclaration = iolist_to_binary(xls_failure_sites:declarations([MainSite])),
    ImportedDeclaration = iolist_to_binary(xls_failure_sites:declarations([ImportedSite])),
    MainBytes = xls_emitted:bytes(Artifact),
    #{"actor_helpers/helper.x" := ImportedBytes} = xls_emitted:dependencies(Artifact),
    ?assertNotEqual(nomatch, binary:match(MainBytes, MainDeclaration)),
    ?assertEqual(nomatch, binary:match(MainBytes, ImportedDeclaration)),
    ?assertNotEqual(nomatch, binary:match(ImportedBytes, ImportedDeclaration)),
    ?assertEqual(nomatch, binary:match(ImportedBytes, MainDeclaration)),
    [LocalSite] = xls_failure_sites:number([Imported]),
    ?assertNotEqual(maps:get(code, LocalSite), maps:get(code, ImportedSite)).

%% A changed imported body breaks the seal read by byte, metadata and file consumers.
-spec dependency_bytes_are_sealed_and_preserved_by_composition_test() -> ok.
dependency_bytes_are_sealed_and_preserved_by_composition_test() ->
    Artifact = xls_emitted:new([], [], "// main\n", #{
        "actor_helpers/helper.x" => #{preamble => [], body => "// helper\n"}
    }),
    Composed = xls_emitted:with_bytes(Artifact, "// enclosing main\n"),
    ?assertEqual(xls_emitted:dependencies(Artifact), xls_emitted:dependencies(Composed)),
    Raw = binary_to_term(term_to_binary(Artifact)),
    Bad = Raw#{dependencies := #{"actor_helpers/helper.x" => <<"// changed\n">>}},
    ?assertError(emitted_module_mismatch, xls_emitted:bytes(Bad)),
    ?assertError(emitted_module_mismatch, xls_emitted:dependencies(Bad)),
    ?assertError(emitted_module_mismatch, xls_emitted:sites(Bad)),
    ?assertError(emitted_module_mismatch, xls_emitted:with_bytes(Bad, "// main\n")).

%% Nested imports are written beside the chosen main filename and can be regenerated.
-spec write_includes_imports_and_replaces_generated_files_test() -> ok.
write_includes_imports_and_replaces_generated_files_test() ->
    Directory = scratch(),
    Main = filename:join(Directory, "actor.x"),
    Dependency = "actor_helpers/helper.x",
    Artifact = xls_emitted:new([], [], "// main\n", #{
        Dependency => #{preamble => [], body => "// helper\n"}
    }),
    try
        ok = xls_emitted:write(Artifact, Main),
        ?assertEqual({ok, xls_emitted:bytes(Artifact)}, file:read_file(Main)),
        ?assertEqual({ok, maps:get(Dependency, xls_emitted:dependencies(Artifact))},
            file:read_file(filename:join(Directory, Dependency))),
        Updated = xls_emitted:with_bytes(Artifact, "// updated main\n"),
        ok = xls_emitted:write(Updated, Main),
        ?assertEqual({ok, <<"// updated main\n">>}, file:read_file(Main))
    after
        ok = file:del_dir_r(Directory)
    end.

%% Reject invalid import identities before rendering and main collisions before any write.
-spec invalid_paths_and_main_collision_are_rejected_test() -> ok.
invalid_paths_and_main_collision_are_rejected_test() ->
    Doc = #{preamble => [], body => "// helper\n"},
    lists:foreach(fun(Path) ->
        ?assertError({invalid_dependency_path, Path}, xls_emitted:new([], [], [], #{Path => Doc}))
    end, ["", "../helper.x", "/helper.x", "./helper.x", "nested/../helper.x", "helper.txt"]),
    Directory = scratch(),
    Main = filename:join(Directory, "actor.x"),
    Artifact = xls_emitted:new([], [], "// main\n", #{"actor.x" => Doc}),
    ?assertError({dependency_overwrites_main, Main}, xls_emitted:write(Artifact, Main)),
    ?assertNot(filelib:is_dir(Directory)).

%% Explicit origins keep these checks independent of compiler-generated fixture names.
-spec origin(string(), pos_integer(), xls_failure_sites:kind()) -> xls_failure_sites:origin().
origin(File, Line, Kind) -> #{file => list_to_binary(File), line => Line, kind => Kind}.

%% A structured use is necessary for allocation; merely printing its name does not count.
-spec value(xls_failure_sites:origin()) -> xls_dslx:value().
value(Origin) -> ["pub fn value() -> u16 { ", xls_dslx:failure_ref(Origin), " }\n"].

%% Each test owns a fresh directory and removes only its own generated files.
-spec scratch() -> file:filename().
scratch() -> filename:join("_build", "emitted-tests-" ++ integer_to_list(erlang:unique_integer([positive]))).

%% Origins travel in the generated main and imports without a companion map file.
-spec origins_are_embedded_in_main_and_imports_test() -> ok.
origins_are_embedded_in_main_and_imports_test() ->
    Origin = origin("include/actions.hrl", 8, badarg),
    Source = maps:remove(kind, Origin),
    ImportedSource = #{file => <<"helper.erl">>, line => 17},
    Artifact = xls_emitted:new([Source], "// preamble\n", xls_dslx:source(Source, value(Origin)), #{
        "imports/helper.x" => #{preamble => "// import\n",
            body => xls_dslx:source(ImportedSource, "pub fn helper() -> u1 { u1:0 }\n")}
    }),
    Bytes = xls_emitted:bytes(Artifact),
    Imported = maps:get("imports/helper.x", xls_emitted:dependencies(Artifact)),
    ?assertNotEqual(nomatch, binary:match(Bytes, <<"@erl \"include/actions.hrl\":8">>)),
    ?assertNotEqual(nomatch, binary:match(Imported, <<"@erl \"helper.erl\":17">>)),
    ?assertEqual(xls_failure_sites:number([Origin]), xls_emitted:sites(Artifact)),
    Directory = scratch(),
    try
        Main = filename:join(Directory, "renamed.x"),
        ok = xls_emitted:write(Artifact, Main),
        ?assertEqual({ok, Bytes}, file:read_file(Main)),
        ?assertEqual({ok, Imported}, file:read_file(filename:join(Directory, "imports/helper.x"))),
        ?assertEqual([], filelib:wildcard(filename:join(Directory, "**/*.json")))
    after
        ok = file:del_dir_r(Directory)
    end.

%% Source comments share the byte seal and remain attached through whole-line composition.
-spec origin_comments_are_sealed_and_move_with_code_test() -> ok.
origin_comments_are_sealed_and_move_with_code_test() ->
    Source = #{file => <<"actor.erl">>, line => 2},
    Body = xls_dslx:source(Source, "pub fn value() -> u1 { u1:0 }\n"),
    Artifact = xls_emitted:new([], [], Body, #{"helper.x" => #{preamble => [], body => Body}}),
    Bytes = xls_emitted:bytes(Artifact),
    Wrapped = <<"// enclosing module\n", Bytes/binary>>,
    Changed = xls_emitted:with_bytes(Artifact, Wrapped),
    ?assertEqual(Wrapped, xls_emitted:bytes(Changed)),
    ?assertEqual(xls_emitted:dependencies(Artifact), xls_emitted:dependencies(Changed)),
    Raw = binary_to_term(term_to_binary(Artifact)),
    Bad = Raw#{dslx := binary:replace(Bytes, <<"actor.erl">>, <<"other.erl">>)},
    ?assertError(emitted_module_mismatch, xls_emitted:bytes(Bad)).
