-module(xls_entry_ir_tests).
-moduledoc "Entry artifacts preserve selected control and payload expressions for backend inspection before code generation.".
-include_lib("eunit/include/eunit.hrl").

%% The artifact contains real branch/constructor nodes, including both distinct effect layouts.
-spec selected_entry_structure_test() -> ok.
selected_entry_structure_test() ->
    #{entries := Entries} = xls_parse:actor_artifact("test/xls_entry_storage_fixture.erl", []),
    [#{evaluation := Evaluation, layouts := Layouts}] =
        [Entry || Entry = #{phase := conditional} <- Entries],
    Nodes = nodes(Evaluation),
    Outcomes = [Fields || {xls_dslx, construct, "EntryOutcome", Fields, none} <- Nodes],
    Effects = [Fields || {xls_dslx, construct, "EntryEffects", Fields, none} <- Nodes],
    ?assertEqual(2, length(Outcomes)),
    ?assertEqual(lists:sort([Layout || #{layout := Layout} <- Layouts]),
        lists:sort([N || Fields <- Effects,
            {"layout", {xls_dslx, literal, "u8", N}} <- Fields])),
    ?assertMatch([_ | _], [N || N = {xls_dslx, choose, _, _, _} <- Nodes]),
    ?assertMatch([_ | _], [N || N = {xls_bits_binary, '+', _, _} <- Nodes]),
    ?assertMatch([_ | _], [N || N = {xls_dslx, call, "bit_slice_update", _} <- Nodes]),
    ?assertEqual([], [F || F <- Nodes, is_function(F)]),
    lists:foreach(fun(Fields) ->
        ?assertMatch({xls_dslx, field, {xls_dslx, field, {xls_dslx, ref, "evaluated"}, 0}, 1},
            proplists:get_value("data", Fields))
    end, Outcomes).

%% Effect serialization retains structural field access and the provider's exact codec call.
-spec provider_codec_structure_test() -> ok.
provider_codec_structure_test() ->
    #{entries := Entries} = xls_parse:actor_artifact("test/xls_entry_storage_fixture.erl", []),
    [#{evaluation := Evaluation}] = [E || E = #{phase := repeated} <- Entries],
    Nodes = nodes(Evaluation),
    ?assertMatch([_ | _], [N || N = {xls_dslx, field, _, "sample"} <- Nodes]),
    Text = iolist_to_binary(xls_clause_lower:print(maps:get(body, Evaluation))),
    ?assertNotEqual(nomatch, binary:match(Text, <<"bits_from_sample">>)),
    ?assertNotEqual(nomatch, binary:match(Text, <<"evaluated.2.0.1.sample">>)).

%% Traverse retained data, not rendered text; function-valued deferred renderers are also visible.
-spec nodes(term()) -> [term()].
nodes(Value) when is_map(Value) -> lists:append([nodes(V) || V <- maps:values(Value)]);
nodes(Value) when is_tuple(Value) -> [Value | nodes(tuple_to_list(Value))];
nodes(Value) when is_list(Value) -> lists:append([nodes(V) || V <- Value]);
nodes(Value) -> [Value].
