-module(xls_phase_values_tests).
-moduledoc "Checks conservative phase inference, source freshness and opt-in specialization.".
-include_lib("eunit/include/eunit.hrl").
-define(FIXTURE, "test/xls_phase_values_fixture.erl").

%% Failed writes never become later live state; successful helper aliases do.
-spec inferred_successful_phases_test() -> ok.
inferred_successful_phases_test() ->
    {Ordinary, F} = xls_phase_values:from_file(?FIXTURE, []),
    ?assertEqual([0], xls_phase_values:field(F, idle, kind)),
    ?assertEqual([2, 4], xls_phase_values:field(F, active, kind)),
    ?assertEqual(Ordinary, xls_parse:actor_artifact(?FIXTURE, [])),
    ?assertEqual([], maps:get(limitations, xls_phase_values:manifest(F))).

%% A consumer gets newly inferred facts, never an unchecked user-edited sidecar.
-spec freshness_and_specialization_test() -> ok.
freshness_and_specialization_test() ->
    {A, B, F, Sites} = xls_phase_specialize:from_file(?FIXTURE, []),
    ?assertEqual(ok, xls_phase_values:validate(?FIXTURE, [], F)),
    ?assertError(stale_phase_values, xls_phase_values:validate(?FIXTURE, [], F#{fields := #{}})),
    ?assertMatch([#{phase := active, field := kind, values := [2, 4]}], Sites),
    ?assertNotEqual(maps:get(entries, A), maps:get(entries, B)),
    ?assertEqual(maps:without([entries, failure_sites], A), maps:without([entries, failure_sites], B)),
    OriginalSites = maps:get(failure_sites, A),
    ?assertEqual(OriginalSites, [S || S = #{line := L} <- maps:get(failure_sites, B), L =/= 0]).

%% Finite source witness: every admitted state value and every 8-bit command.
%% This is an exhaustive one-callback containment check, not compiler soundness.
-spec source_transition_containment_test() -> ok.
source_transition_containment_test() ->
    {_, F} = xls_phase_values:from_file(?FIXTURE, []),
    lists:foreach(fun({P, K, Input}) ->
        C = {cell, K, 23},
        try xls_phase_values_fixture:P(cast, {command, Input}, C) of
            {_, _, fail} -> ok;
            {Next, {cell, New, _}, _} -> ?assert(lists:member(New, xls_phase_values:field(F, Next, kind)))
        catch error:{badmatch, false} -> ok end
    end, [{P, K, Input} || {P, Ks} <- [{idle, [0]}, {active, [2, 4]}], K <- Ks, Input <- lists:seq(0, 255)]).

%% A formerly impossible successful transition must widen the result.
-spec extra_transition_is_not_ignored_test() -> ok.
extra_transition_is_not_ignored_test() ->
    changed(<<"kind = 9}, fail">>, <<"kind = 9}, consume">>, fun(File) ->
        {_, F} = xls_phase_values:from_file(File, []),
        ?assertEqual([2, 4, 9], xls_phase_values:field(F, active, kind))
    end).

%% Unknown provider results are not treated as preserving their argument.
-spec unknown_assignment_erases_bound_test() -> ok.
unknown_assignment_erases_bound_test() ->
    changed(<<"kind = Terminal}">>, <<"kind = hls_nums:wrap(hls_nums:u8(), Terminal)}">>, fun(File) ->
        {A, B, F, Sites} = xls_phase_specialize:from_file(File, []),
        ?assertEqual(unknown, xls_phase_values:field(F, active, kind)),
        ?assertEqual([], Sites), ?assertEqual(A, B)
    end).

%% Assertions cannot be assumed if removed from the actual source.
-spec unchecked_input_erases_bound_test() -> ok.
unchecked_input_erases_bound_test() ->
    changed(<<"true = Kind =:= 0 orelse Kind =:= 3,">>, <<"true = true,">>, fun(File) ->
        {_, F} = xls_phase_values:from_file(File, []),
        ?assertEqual(unknown, xls_phase_values:field(F, active, kind))
    end).

%% Temporary source variants exercise re-analysis instead of mutating a fact.
-spec changed(binary(), binary(), fun((file:filename()) -> T)) -> T.
changed(From, To, Check) ->
    Dir = filename:join("_build", "phase-values-" ++ integer_to_list(erlang:unique_integer([positive]))),
    File = filename:join(Dir, "actor.erl"),
    ok = filelib:ensure_dir(File), {ok, Source} = file:read_file(?FIXTURE),
    ?assertMatch({_, _}, binary:match(Source, From)),
    ok = file:write_file(File, binary:replace(Source, From, To)),
    try Check(File) after file:delete(File), file:del_dir(Dir) end.

%% Entry callbacks participate in the fixed point, including newly stored kinds.
-spec entry_transition_participates_test() -> ok.
entry_transition_participates_test() ->
    changed(<<"{Cell, [{cast, out,">>, <<"{Cell#cell{kind = 7}, [{cast, out,">>, fun(File) ->
        {_, F} = xls_phase_values:from_file(File, []),
        ?assertEqual([2, 4, 7], xls_phase_values:field(F, active, kind))
    end).

%% Initialization contributes facts even before the first successful event.
-spec initialization_participates_test() -> ok.
initialization_participates_test() ->
    changed(<<"\ninit([]) -> {ok, idle, #cell{}}.">>, <<"\ninit([]) -> {ok, idle, #cell{kind = 7}}.">>, fun(File) ->
        {_, F} = xls_phase_values:from_file(File, []),
        ?assertEqual([7], xls_phase_values:field(F, idle, kind))
    end).

%% Until fixed-width arithmetic is modeled, even a small arithmetic update widens.
-spec arithmetic_is_conservative_test() -> ok.
arithmetic_is_conservative_test() ->
    changed(<<"kind = Terminal}">>, <<"kind = Terminal + 1}">>, fun(File) ->
        {_, F} = xls_phase_values:from_file(File, []),
        ?assertEqual(unknown, xls_phase_values:field(F, active, kind))
    end).

%% An opaque record result still has unconstrained fields, never no successors.
-spec opaque_record_access_is_unknown_test() -> ok.
opaque_record_access_is_unknown_test() ->
    C = xls_phase_eval:context([{attribute, 0, record, {cell, [
        {record_field, 0, {atom, 0, value}, {integer, 0, 0}}]}}]),
    Clause = {clause, 0, [{var, 0, 'X'}], [], [
        {record_field, 0, {var, 0, 'X'}, cell, {atom, 0, value}}]},
    [{V, S}] = xls_phase_eval:clause(Clause, [xls_phase_eval:unknown()], C),
    ?assertMatch({unknown, _}, xls_phase_eval:concrete(V, S)).

%% Integer zero facts must not be borrowed for a floating-point provider.
-spec float_zero_is_not_integer_zero_test() -> ok.
float_zero_is_not_integer_zero_test() ->
    Default = {call, 0, {remote, 0, {atom, 0, hls_type}, {atom, 0, zero}}, []},
    C = xls_phase_eval:context([{attribute, 0, record, {cell, [
        {typed_record_field, {record_field, 0, {atom, 0, value}, Default},
            {remote_type, 0, [{atom, 0, hls_nums}, {atom, 0, float32}, []]}}]}}]),
    Clause = {clause, 0, [], [], [{record, 0, cell, []}]},
    [{V, S}] = xls_phase_eval:clause(Clause, [], C),
    ?assertMatch({record, cell, #{value := {unknown, _}}}, xls_phase_eval:concrete(V, S)).
