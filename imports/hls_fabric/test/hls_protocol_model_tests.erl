-module(hls_protocol_model_tests).
-moduledoc "Application-independent provider and build-boundary tests, not source refinement or progress witnesses.".
-behaviour(hls_protocol_model).
-include_lib("eunit/include/eunit.hrl").
-export([derive/2, summary/1]).

%% A source application without Phi schemas uses the same prepare/plan/emit path.
-spec provider_build_test_() -> term().
provider_build_test_() -> {timeout, 60, fun provider_build/0}.

%% Preparation invokes both callbacks exactly once; placements and emission reuse their checked output.
-spec provider_build() -> ok.
provider_build() ->
    Config = #{sources => [{"test/hls_protocol_network_fixture.erl", []}],
        topology => {hls_protocol_network_fixture, isolated, []}, actor_limit => 1},
    Root = filename:join("_build", "model-provider-" ++ integer_to_list(erlang:system_time(nanosecond))),
    ok = file:make_dir(Root),
    put(model_calls, []),
    Program = hls_protocol_transport:prepare(Config#{protocol_model => {?MODULE, independent}}),
    #{inventory := Inventory} = hls_protocol_transport:bundle(Program),
    Build = hls_protocol_transport:plan(Program, #{}),
    Report = #{provider := ?MODULE, model := #{nodes := [left]}, analysis := #{ranks := #{left := 0}}} =
        maps:get(protocol_model, hls_protocol_transport:descriptor(Build)),
    ?assertEqual(binary:encode_hex(crypto:hash(sha256, term_to_binary(Inventory, [deterministic])), lowercase),
        maps:get(inventory_sha256, Report)),
    Annotated = filename:join(Root, "annotated"),
    _ = hls_protocol_transport:write(Build, Annotated),
    _ = hls_protocol_transport:write(Build, filename:join(Root, "again")),
    ?assertEqual([summary, derive], erase(model_calls)),
    {ok, Bytes} = file:read_file(filename:join(Annotated, "protocol-model.etf")),
    ?assertEqual(Report, binary_to_term(Bytes)),
    {ok, Json} = file:read_file(filename:join(Annotated, "protocol-model.json")),
    #{<<"application">> := #{<<"example">> := <<"independent">>},
      <<"analysis">> := #{<<"evidence">> := <<"finite_graph_check">>,
          <<"source_refinement">> := <<"unestablished">>, <<"whole_protocol_eligible">> := false}} = json:decode(Json),
    Plain = filename:join(Root, "plain"),
    Bare = hls_protocol_transport:write(Config, Plain),
    ?assertNot(maps:is_key(protocol_model, Bare)),
    ?assertNot(filelib:is_file(filename:join(Plain, "protocol-model.etf"))),
    lists:foreach(fun(File) ->
        Relative = lists:nthtail(length(Annotated) + 1, File),
        ?assertEqual(file:read_file(File), file:read_file(filename:join(Plain, Relative)))
    end, filelib:fold_files(Annotated, "\\.(x|sv)$", true, fun(F, Acc) -> [F | Acc] end, [])),
    Rejected = filename:join(Root, "rejected"),
    ?assertError({hls_diagnostic, #{stage := model, code := invalid_wait_graph,
        context := #{provider := ?MODULE, reason := {same_generation_wait_cycle, [[left]]}}}},
        hls_protocol_transport:write(Config#{protocol_model => {?MODULE, cycle}}, Rejected)),
    ?assertNot(filelib:is_dir(Rejected)),
    ?assertEqual([derive], erase(model_calls)),
    ?assertError(example_summary_rejected,
        hls_protocol_transport:write(Config#{protocol_model => {?MODULE, reject_summary}}, Rejected)),
    ?assertNot(filelib:is_dir(Rejected)),
    ?assertEqual([summary, derive], erase(model_calls)),
    ok.

%% Every provider uses the common checker; malformed selections cannot silently disable analysis.
-spec invalid_graph_test() -> ok.
invalid_graph_test() ->
    Inventory = #{actors => [#{id => left}]},
    ?assertError({hls_diagnostic, #{stage := model, code := invalid_wait_graph,
        context := #{provider := ?MODULE, reason := {unknown_prerequisite, absent}}}},
        hls_protocol_model:check({?MODULE, missing}, Inventory)),
    ?assertEqual([derive], erase(model_calls)),
    ?assertError({hls_diagnostic, #{stage := model, code := unsupported_protocol_model,
        context := #{value := #{kind := periodic_neighbor_barrier}}}},
        hls_protocol_model:check(#{kind => periodic_neighbor_barrier}, Inventory)),
    ?assertEqual(none, hls_protocol_model:check(none, Inventory)),
    ?assertError({badmatch, []}, hls_protocol_model:check({?MODULE, independent}, #{actors => []})),
    ?assertEqual([derive], erase(model_calls)),
    ok.

-doc "Proposes actor-local nodes for a non-Phi fixture; negative modes introduce a self wait or missing endpoint. No source-behavior claim is made.".
-spec derive(hls_protocol_inventory:report(), independent | cycle | missing | reject_summary) -> hls_protocol_model:graph().
derive(#{actors := Actors}, Mode) ->
    called(derive),
    Nodes = [Id || #{id := Id} <- Actors],
    [First | _] = Nodes,
    Edges = case Mode of
        Mode when Mode =:= independent; Mode =:= reject_summary -> [];
        cycle -> [#{waiter => First, prerequisite => First, lag => 0, kind => dependency}];
        missing -> [#{waiter => First, prerequisite => absent, lag => 0, kind => dependency}]
    end,
    #{nodes => Nodes, edges => Edges, example => Mode}.

-doc "Returns application-only metadata; records calls to detect accidental invocation during emission.".
-spec summary(hls_protocol_model:graph()) -> map().
summary(#{example := reject_summary}) -> called(summary), error(example_summary_rejected);
summary(Model) -> called(summary), maps:with([example], Model).

%% Process-local observation avoids a global mock or background process in build tests.
-spec called(atom()) -> ok.
called(Name) ->
    Calls = case get(model_calls) of undefined -> []; Values -> Values end,
    put(model_calls, [Name | Calls]),
    ok.
