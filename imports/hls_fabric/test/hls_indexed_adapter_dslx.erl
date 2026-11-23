-module(hls_indexed_adapter_dslx).
-moduledoc "Generates narrow interpreter/JIT witnesses from the production indexed-adapter emitter.".
-export([write/1]).

-doc "Writes source-generated actor helpers, physical-adapter helpers and bounded lifecycle tests into Stage.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    Path = "test/hls_indexed_adapter_fixture.erl",
    Spec = (xls_parse:actor_artifact(Path, []))#{gather_collection => true},
    ok = xls_indexed_collection_codegen:validate(Spec, #{}),
    {ok, Shape} = file:read_file("test/hls_indexed_adapter_shape.inc.x"),
    {ok, Tests} = file:read_file("test/hls_indexed_adapter_semantics.inc.x"),
    %% Finalize ordinary functions and physical helpers together so both contribute failure references.
    Artifact = xls_actor_codegen:artifact(Spec,
        [direct_mailbox_observation, indexed_collection_core, indexed_gather_ram, arbitration, mailbox],
        [xls_statem_codegen:body(Spec), xls_indexed_collection_codegen:declarations(Spec), Shape,
            xls_indexed_collection_codegen:helpers(Spec), xls_collection_observation:declarations(Spec), Tests]),
    %% A named fixture-only alternative tests wrong-site rejection without an
    %% undefined integer-to-enum cast. Production declarations remain unchanged.
    Actor0 = xls_emitted:bytes(Artifact),
    SiteEnum = <<"enum GatherSite : u8 {">>,
    [_, _] = binary:split(Actor0, SiteEnum, [global]),
    Actor1 = binary:replace(Actor0, SiteEnum,
        <<"enum GatherSite : u8 {\n  WRONG_TEST_SITE = u8:255,">>),
    %% Wrong-site tests stop in indexed_open. Reaching generated payload folding
    %% with this fixture-only site is an assertion failure, never new behavior.
    ApplyMatch = <<"      let values = match p.site {\n">>,
    [_, _] = binary:split(Actor1, ApplyMatch, [global]),
    Actor = binary:replace(Actor1, ApplyMatch,
        <<"      let values = match p.site {\n"
          "        GatherSite::WRONG_TEST_SITE => fail!(\"wrong_test_site_reached_gather_apply\", state.values),\n">>),
    Output = filename:join(Stage, "indexed_adapter.x"),
    ok = filelib:ensure_dir(Output),
    xls_emitted:write(xls_emitted:with_bytes(Artifact, Actor), Output).
