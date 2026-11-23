-module(xls_message_facts_tests).
-moduledoc "Checks conservative message domains, alias joins, freshness and unchanged ordinary rendering.".
-include_lib("eunit/include/eunit.hrl").
-define(FIXTURE, "test_data/xls_message_facts_fixture.erl").

%% Sender literals survive aliases, but data-dependent payloads remain unknown.
-spec literal_and_dynamic_fields_test() -> ok.
literal_and_dynamic_fields_test() ->
    {_, Facts} = xls_message_facts:from_file(?FIXTURE, []),
    West = xls_message_facts:on_ports(Facts, [west]),
    ?assert(maps:get(closed, West)),
    ?assertEqual([2], values(West, piece, direction)),
    ?assertEqual(unknown, values(West, piece, value)),
    East = xls_message_facts:on_ports(Facts, [east]),
    ?assertEqual([1], values(East, piece, direction)),
    Mixed = xls_message_facts:on_ports(Facts, [mixed]),
    ?assertEqual([alternate, piece], [T || #{tag := T} <- maps:get(schemas, Mixed)]),
    ?assertEqual(unknown, values(Mixed, piece, direction)),
    ?assertEqual([9], values(Mixed, piece, value)),
    ?assertEqual([-3], values(Mixed, alternate, signed)),
    ?assertEqual([0], values(Mixed, alternate, omitted)).

%% The real lane normalizer merges ports; no single port may stand for that lane.
-spec aliased_lane_and_unknown_join_test() -> ok.
aliased_lane_and_unknown_join_test() ->
    {_, Facts} = xls_message_facts:from_file(?FIXTURE, []),
    [#{source_ports := Ports}] = xls_topology_graph:lanes([
        #{source => {sender, P}, recipients => [{actor, receiver}]} || P <- [west, east]]),
    Joined = xls_message_facts:on_ports(Facts, Ports),
    ?assertEqual([1, 2], values(Joined, piece, direction)),
    ?assertEqual(Joined, xls_message_facts:on_ports(Facts, lists:reverse(Ports))),
    ?assertEqual(unknown, values(xls_message_facts:on_ports(Facts, [west, mixed]), piece, direction)).

%% Marginals intentionally lose correlation; retained alternatives do not invent pairs.
-spec relational_alternatives_test() -> ok.
relational_alternatives_test() ->
    {_, Facts} = xls_message_facts:from_file(?FIXTURE, []),
    #{alternatives := Alternatives} = Report = xls_message_facts:on_ports(Facts, [relation]),
    ?assertEqual([2, 3], values(Report, piece, direction)),
    ?assertEqual([2, 3], values(Report, piece, value)),
    Pairs = lists:usort([{value(Fs, direction), value(Fs, value)} || #{fields := Fs} <- Alternatives]),
    ?assertEqual([{[2], [3]}, {[3], [2]}], Pairs),
    ?assert(lists:all(fun(A) -> maps:is_key(phase, A) andalso maps:is_key(layout, A)
        andalso maps:is_key(order, A) end, Alternatives)).

%% Empty emission differs from unknown replies and invalid/vacuous selections.
-spec missing_and_uncovered_effects_test() -> ok.
missing_and_uncovered_effects_test() ->
    {_, Facts} = xls_message_facts:from_file(?FIXTURE, []),
    ?assertMatch(#{closed := true, schemas := [], alternatives := []},
        xls_message_facts:on_ports(Facts, [silent])),
    ?assertError(empty_message_ports, xls_message_facts:on_ports(Facts, [])),
    ?assertError({unknown_message_ports, [typo]}, xls_message_facts:on_ports(Facts, [typo])),
    {_, Reply} = xls_message_facts:from_file("test/hls_statem_reply_fixture.erl", []),
    ?assertMatch(#{closed := false, schemas := unknown, unknown_sources := [retained_reply]},
        xls_message_facts:on_ports(Reply, [reply])).

%% The analysis cannot change failure evaluation, source effects or emitted DSLX.
-spec ordinary_emission_is_unchanged_test() -> ok.
ordinary_emission_is_unchanged_test() ->
    lists:foreach(fun(File) ->
        Ordinary = xls_parse:actor_artifact(File, []),
        {Analyzed, _} = xls_message_facts:from_file(File, []),
        ?assertEqual(Ordinary, Analyzed),
        ?assertEqual(iolist_to_binary(xls_statem_codegen:emit(Ordinary)),
            iolist_to_binary(xls_statem_codegen:emit(Analyzed)))
    end, [?FIXTURE, "test/xls_entry_outcome_fixture.erl"]).

%% Finite source-execution witness: both callbacks at every 8-bit cell value.
%% This checks emitted-message containment, not receiver semantics or XLS execution.
-spec emitted_messages_fit_analysis_test() -> ok.
emitted_messages_fit_analysis_test() ->
    {ok, Module, Beam} = compile:file(?FIXTURE, [binary]),
    {module, Module} = code:load_binary(Module, ?FIXTURE, Beam),
    try
        {_, Facts} = xls_message_facts:from_file(?FIXTURE, []),
        #{alternatives := Alternatives} = xls_message_facts:on_ports(Facts,
            [west, east, relation, mixed, silent]),
        lists:foreach(fun({Phase, V}) ->
            {_, Effects} = Module:Phase(enter, idle, {cell, V}),
            lists:foreach(fun({cast, Port, Message}) ->
                ?assert(lists:any(fun(A) -> admits(A, Phase, Port, Message) end, Alternatives))
            end, Effects)
        end, [{P, V} || P <- [idle, dynamic], V <- lists:seq(0, 255)])
    after code:delete(Module), code:purge(Module) end.

%% Check a real source message against one complete relational alternative.
-spec admits(map(), atom(), atom(), tuple()) -> boolean().
admits(#{phase := Phase, port := Port, tag := Tag, fields := Fields}, Phase, Port, Message)
        when element(1, Message) =:= Tag ->
    lists:all(fun
        ({#{domain := unknown}, _}) -> true;
        ({#{type := T, domain := {values, Bits}}, V}) -> lists:member(hls_type:pack(V, T), Bits)
    end, lists:zip(Fields, tl(tuple_to_list(Message))));
admits(_, _, _, _) -> false.

%% Regeneration checks facts as well as hashes; unchanged identity is insufficient.
-spec edited_fact_is_rejected_test() -> ok.
edited_fact_is_rejected_test() ->
    {_, Facts} = xls_message_facts:from_file(?FIXTURE, []),
    Saved = binary_to_term(term_to_binary(Facts)),
    ?assertEqual(ok, xls_message_facts:validate(?FIXTURE, [], Saved)),
    ?assertEqual(message_analysis_only, maps:get(role, xls_message_facts:manifest(Saved))),
    ?assertError(stale_message_facts, xls_message_facts:validate(?FIXTURE, [],
        Saved#{alternatives := []})).

%% Full preprocessed source binding includes values introduced by includes.
-spec changed_include_is_rejected_test() -> ok.
changed_include_is_rejected_test() ->
    Root = filename:join("_build", "message-facts-" ++ integer_to_list(erlang:unique_integer([positive]))),
    File = filename:join(Root, "actor.erl"), Include = filename:join(Root, "direction.hrl"),
    ok = filelib:ensure_dir(File),
    {ok, Original} = file:read_file(?FIXTURE),
    Body = binary:replace(Original, <<"Alias#piece{direction = 2}">>, <<"Alias#piece{direction = ?DIRECTION}">>),
    ok = file:write_file(File, ["-include(\"direction.hrl\").\n", Body]),
    try
        ok = file:write_file(Include, "-define(DIRECTION, 2).\n"),
        {_, Facts} = xls_message_facts:from_file(File, []),
        ok = xls_message_facts:validate(File, [], Facts),
        ok = file:write_file(Include, "-define(DIRECTION, 3).\n"),
        ?assertError(stale_message_facts, xls_message_facts:validate(File, [], Facts))
    after file:delete(File), file:delete(Include), file:del_dir(Root) end.

%% Decode test expectations through the same ABI, including signed/sub-byte fields.
-spec values(map(), atom(), atom()) -> unknown | [term()].
values(#{schemas := Schemas}, Tag, Name) ->
    [#{fields := Fields}] = [S || S = #{tag := T} <- Schemas, T =:= Tag],
    value(Fields, Name).

%% A dynamic field remains explicit rather than being represented by an empty set.
-spec value([map()], atom()) -> unknown | [term()].
value(Fields, Name) ->
    [Field] = [F || F = #{name := N} <- Fields, N =:= Name],
    case Field of
        #{domain := unknown} -> unknown;
        #{type := Type, domain := {values, Bits}} ->
            lists:sort([begin {V, <<>>} = hls_type:unpack(B, Type), V end || B <- Bits])
    end.
