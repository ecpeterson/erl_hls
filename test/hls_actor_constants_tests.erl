-module(hls_actor_constants_tests).
-moduledoc "Finite source-analysis regressions; these cases do not prove soundness for all accepted actors.".
-include_lib("eunit/include/eunit.hrl").

%% Changing payloads through a helper must not destroy the unchanged identity fact.
-spec helper_preserves_only_unchanged_fields_test() -> ok.
helper_preserves_only_unchanged_fields_test() ->
    States = analyze("idle(enter, _, C) -> {C, []};\n"
        "idle(cast, {put, X}, C) -> {idle, put(X, C), consume}.\n"
        "put(X, C) -> D = C, D#cell{x = X}.\n", [{put, unknown}]),
    ?assertEqual(unknown, field(States, idle, 2)),
    ?assertEqual({ok, 7}, field(States, idle, 3)).

%% Both alternatives must be represented, including different callback tuple arities.
-spec conditional_write_and_result_arity_test() -> ok.
conditional_write_and_result_arity_test() ->
    States = analyze("idle(enter, _, C) -> {C, []};\n"
        "idle(cast, {put, X}, C) -> case X of\n"
        "  0 -> {idle, C, consume};\n"
        "  _ -> {idle, C#cell{id = 8}, consume, [{next_event, internal, next}]}\n"
        "end.\n", [{put, unknown}]),
    ?assertEqual(unknown, field(States, idle, 3)).

%% An opaque helper may replace the complete record; never infer preservation from syntax alone.
-spec opaque_record_replacement_test() -> ok.
opaque_record_replacement_test() ->
    States = analyze("idle(enter, _, C) -> {C, []};\n"
        "idle(cast, _, C) -> {idle, opaque:replace(C), consume}.\n", [{put, unknown}]),
    ?assertEqual(unknown, field(States, idle, 3)).

%% Configuration can remain fixed in each phase even though its initial value differs.
-spec startup_constant_is_phase_scoped_test() -> ok.
startup_constant_is_phase_scoped_test() ->
    Fs = forms("boot(enter, _, C) -> {C, []};\n"
        "boot(cast, {configure, I}, C) -> {idle, C#cell{id=I}, consume}.\n"
        "idle(enter, _, C) -> {C, []};\n"
        "idle(cast, {put, X}, C) -> {idle, C#cell{x=X}, consume};\n"
        "idle(cast, _, C) -> {idle, C, fail}.\n"),
    Messages = [hls_actor_constants:value({configure, 23}),
        hls_actor_constants:unknown_record(put, 1)],
    States = hls_actor_constants:analyze(Fs, [boot, idle], {boot, {cell, 0, 7}}, Messages),
    ?assertEqual({ok, 7}, field(States, boot, 3)),
    ?assertEqual({ok, 23}, field(States, idle, 3)),
    Open = hls_actor_constants:analyze(Fs, [boot, idle], {boot, {cell, 0, 7}},
        [hls_actor_constants:unknown_record(configure, 1) | Messages]),
    ?assertEqual(unknown, field(Open, idle, 3)).

%% Phase entry writes and internal callbacks are not excluded from the fixed point.
-spec entry_and_internal_writes_test() -> ok.
entry_and_internal_writes_test() ->
    States = analyze("idle(enter, _, C) -> {C#cell{x=9}, []};\n"
        "idle(internal, _, C) -> {idle, C#cell{id=11}, consume}.\n", []),
    ?assertEqual(unknown, field(States, idle, 2)),
    ?assertEqual(unknown, field(States, idle, 3)).

%% No unbounded host arithmetic is mistaken for a finite-width hardware constant.
-spec arithmetic_requires_width_context_test() -> ok.
arithmetic_requires_width_context_test() ->
    States = analyze("idle(enter, _, C) -> {C, []};\n"
        "idle(cast, _, C) -> {idle, C#cell{id=255+1}, consume}.\n", [{put, unknown}]),
    ?assertEqual(unknown, field(States, idle, 3)).

%% Mailbox disposal does not establish that the callback's data is unchanged.
-spec directives_do_not_imply_preservation_test() -> ok.
directives_do_not_imply_preservation_test() ->
    lists:foreach(fun(Directive) ->
        States = analyze("idle(enter, _, C) -> {C, []};\n"
            "idle(cast, _, C) -> {idle, C#cell{id=99}, " ++ Directive ++ "}.\n", [{put, unknown}]),
        ?assertEqual(unknown, field(States, idle, 3))
    end, ["fail", "postpone"]).

%% Initial constants come from the current initializer, including local construction helpers.
-spec source_initializer_test() -> ok.
source_initializer_test() ->
    Fs = forms("init([]) -> {ok, idle, fresh()}.\n"
        "fresh() -> #cell{id=23}.\n"
        "idle(enter, _, C) -> {C, []}.\n"),
    States = hls_actor_constants:from_source(Fs, [idle], []),
    ?assertEqual({ok, 23}, field(States, idle, 3)).

%% Unknown numeric widths must not let a guard incorrectly exclude a write.
-spec numeric_guard_loses_facts_test() -> ok.
numeric_guard_loses_facts_test() ->
    States = analyze("idle(enter, _, C) -> {C, []};\n"
        "idle(cast, _, C) when 256 =:= 0 -> {idle, C#cell{id=99}, consume};\n"
        "idle(cast, _, C) -> {idle, C, consume}.\n", [{put, unknown}]),
    ?assertEqual(unknown, field(States, idle, 3)).

%% Reentry carries changed data into the same phase instead of discarding its transition.
-spec repeat_phase_write_test() -> ok.
repeat_phase_write_test() ->
    States = analyze("idle(enter, _, C) -> {C, []};\n"
        "idle(cast, {put, X}, C) -> {repeat_phase, C#cell{x=X, id=9}, consume}.\n", [{put, unknown}]),
    ?assertEqual(unknown, field(States, idle, 2)),
    ?assertEqual(unknown, field(States, idle, 3)).

%% Internal completions and action-bearing returns have the same reentry semantics.
-spec repeat_internal_actions_test() -> ok.
repeat_internal_actions_test() ->
    States = analyze("idle(enter, _, C) -> {C, []};\n"
        "idle(internal, _, C) -> {repeat_phase, C#cell{id=9}, consume, [{next_event, internal, next}]}.\n", []),
    ?assertEqual({ok, 0}, field(States, idle, 2)),
    ?assertEqual(unknown, field(States, idle, 3)).

%% A helper's phase union includes both same-phase writes and transitions to another phase.
-spec repeat_phase_union_test() -> ok.
repeat_phase_union_test() ->
    Fs = forms("idle(enter, _, C) -> {C, []};\n"
        "idle(cast, {put, X}, C) -> {next(X), C#cell{id=9}, consume}.\n"
        "next(0) -> repeat_phase; next(_) -> done.\n"
        "done(enter, _, C) -> {C, []}.\n"),
    States = hls_actor_constants:analyze(Fs, [idle, done], {idle, {cell, 0, 7}},
        [hls_actor_constants:unknown_record(put, 1)]),
    ?assertEqual(unknown, field(States, idle, 3)),
    ?assertEqual({ok, 9}, field(States, done, 3)).

%% An unknown target may include reentry and must retain changed data in every phase.
-spec unknown_phase_target_test() -> ok.
unknown_phase_target_test() ->
    Fs = forms("idle(enter, _, C) -> {C, []};\n"
        "idle(cast, _, C) -> {opaque:next(), C#cell{id=9}, consume}.\n"
        "done(enter, _, C) -> {C, []}.\n"),
    States = hls_actor_constants:analyze(Fs, [idle, done], {idle, {cell, 0, 7}},
        [hls_actor_constants:unknown_record(put, 1)]),
    ?assertEqual(unknown, field(States, idle, 3)),
    ?assertEqual({ok, 9}, field(States, done, 3)).

%% Inputs describe shape and uncertainty explicitly instead of sampling payload values.
-spec analyze(string(), [{atom(), unknown}]) -> map().
analyze(Body, Inputs) ->
    hls_actor_constants:analyze(forms(Body), [idle], {idle, {cell, 0, 7}},
        [hls_actor_constants:unknown_record(Name, 1) || {Name, unknown} <- Inputs]).

%% Extracts one tuple field only if it is established on every abstract path.
-spec field(map(), atom(), pos_integer()) -> {ok, term()} | unknown.
field(States, Phase, Index) ->
    case maps:get(Phase, States) of
        {tuple, Values} -> hls_actor_constants:constant(lists:nth(Index, Values));
        _ -> unknown
    end.

%% Parse small independent witnesses without executing their callback code.
-spec forms(string()) -> [hls_source:form()].
forms(Body) ->
    {ok, Tokens, _} = erl_scan:string("-record(cell, {x=0, id=7}).\n" ++ Body),
    parse_forms(Tokens, [], []).

%% A dot terminates each source form; token contents are never reparsed as text.
-spec parse_forms([term()], [term()], [hls_source:form()]) -> [hls_source:form()].
parse_forms([], [], Acc) -> lists:reverse(Acc);
parse_forms([{dot, _} = Dot | Rest], Current, Acc) ->
    {ok, Form} = erl_parse:parse_form(lists:reverse([Dot | Current])),
    parse_forms(Rest, [], [Form | Acc]);
parse_forms([T | Rest], Current, Acc) -> parse_forms(Rest, [T | Current], Acc).
