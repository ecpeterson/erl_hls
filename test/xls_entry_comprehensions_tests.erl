-module(xls_entry_comprehensions_tests).
-moduledoc "Finite BEAM and normalized-source witnesses for statically bounded entry comprehensions.".
-include_lib("eunit/include/eunit.hrl").

%% The direction table determines literal ports and ordered payload constants.
-spec tuple_table_preserves_order_and_values_test() -> ok.
tuple_table_preserves_order_and_values_test() ->
    Body = "{Cell, [{cast, Port, #small{value = stamp(Port, Mask)}} "
        "|| {Port, Mask, _Source} <- [{second, 2, 1}, {first, 1, 2}]]}",
    ?assertEqual([second, first], trace(Body)),
    Plan = analyze(Body),
    ?assertEqual(2, xls_statem_entry:max_effects(Plan)),
    ?assertEqual([
        #{order => 0, port => second, schema => small},
        #{order => 1, port => first, schema => small}
    ], xls_statem_entry:effects(Plan)).

%% A generator binding shadows a same-spelled outer value without replacing it afterward.
-spec generator_shadows_outer_binding_test() -> ok.
generator_shadows_outer_binding_test() ->
    Body = "Port = 99, Actions = [{cast, Port, #small{value = stamp(Port, 3)}} "
        "|| Port <- [first, second]], {Port, Actions}",
    ?assertMatch({{ok, {99, [_First, _Second]}}, [first, second]}, equivalent(Body)).

%% Every iteration has fresh locals, and those names remain available after the list.
-spec iteration_locals_do_not_leak_test() -> ok.
iteration_locals_do_not_leak_test() ->
    Body = "Actions = [{cast, Port, #small{value = begin Local = stamp(Port, N), "
        "Local end}} || {Port, N} <- [{first, 1}, {second, 2}]], "
        "Local = 99, {Local, Actions}",
    ?assertMatch({{ok, {99, [_First, _Second]}}, [first, second]}, equivalent(Body)).

%% Branch locals remain visible inside the comprehension, while its own locals stay inside each iteration.
-spec comprehension_in_branch_keeps_nested_scopes_test() -> ok.
comprehension_in_branch_keeps_nested_scopes_test() ->
    lists:foreach(fun(Choice) ->
        Body = "Actions = case stamp(choice, " ++ atom_to_list(Choice) ++ ") of "
            "true -> Branch = 10, [{cast, Port, #small{value = case N of "
            "1 -> Local = stamp(Port, Branch + N), Local; "
            "_ -> Local = stamp(Port, Branch + N), Local end}} "
            "|| {Port, N} <- [{first, 1}, {second, 2}]]; false -> [] end, "
            "Local = 99, {Local, Actions}",
        Expected = case Choice of
            true -> {{ok, {99, [{cast, first, {small, 11}}, {cast, second, {small, 12}}]}},
                [choice, first, second]};
            false -> {{ok, {99, []}}, [choice]}
        end,
        ?assertEqual(Expected, equivalent(Body))
    end, [true, false]).

%% Source names resembling compiler temporaries remain distinct, even when bound after the comprehension.
-spec generated_name_collision_is_avoided_test() -> ok.
generated_name_collision_is_avoided_test() ->
    Body = "HlsEntryComprehension0 = 17, "
        "Actions = [{cast, Port, #small{value = begin "
        "Local = stamp(Port, HlsEntryComprehension0 + N), Local end}} "
        "|| {Port, N} <- [{first, 1}, {second, 2}]], "
        "HlsEntryComprehension1 = 99, {HlsEntryComprehension1, Actions}",
    ?assertEqual({{ok, {99, [{cast, first, {small, 18}}, {cast, second, {small, 19}}]}},
        [first, second]}, equivalent(Body)).

%% Non-generator references keep the surrounding binding, including its match obligation.
-spec outer_body_binding_keeps_equality_check_test() -> ok.
outer_body_binding_keeps_equality_check_test() ->
    Body = "Local = 7, {Cell, [{cast, Port, #small{value = begin "
        "Local = stamp(Port, N), Local end}} "
        "|| {Port, N} <- [{first, 7}, {second, 8}]]}",
    ?assertEqual({{error, {badmatch, 8}}, [first, second]}, equivalent(Body)).

%% Literal patterns skip mismatches and repeated variables enforce equality.
-spec literal_pattern_skips_mismatches_test() -> ok.
literal_pattern_skips_mismatches_test() ->
    Body = "{Cell, [{cast, Port, #small{value = stamp(Port, N)}} "
        "|| {keep, Port, {N, N}} <- [ignore, {keep, third, {1, 2}}, "
        "{keep, second, {3, 3}}, {drop, first, {4, 4}}]]}",
    ?assertEqual([second], trace(Body)),
    ?assertEqual([#{order => 0, port => second, schema => small}],
        xls_statem_entry:effects(analyze(Body))).

%% The empty domain evaluates no body, including a body that would raise.
-spec empty_generator_suppresses_body_test() -> ok.
empty_generator_suppresses_body_test() ->
    Body = "{stamp(data, Cell), [{cast, Port, #small{value = boom()}} || Port <- []]}",
    ?assertEqual([data], trace(Body)),
    ?assertEqual(0, xls_statem_entry:max_effects(analyze(Body))).

%% Captured lists evaluate before later control, even if that control discards them.
-spec discarded_list_retains_eager_payload_test() -> ok.
discarded_list_retains_eager_payload_test() ->
    Body = "Actions = [{cast, Port, #small{value = stamp(Port, 1)}} "
        "|| Port <- [second, first]], stamp(between, 0), "
        "{Cell, case stamp(choice, false) of true -> Actions; false -> [] end}",
    ?assertEqual([second, first, between, choice], trace(Body)),
    Failure = "Unused = [{cast, Port, #small{value = begin stamp(Port, 1), boom() end}} "
        "|| Port <- [first, second]], {Cell, []}",
    ?assertEqual({{error, body_failed}, [first]}, equivalent(Failure)).

%% Reusing an evaluated segment neither repeats its body nor changes its ordering.
-spec alias_is_evaluated_once_test() -> ok.
alias_is_evaluated_once_test() ->
    Body = "Actions = [{cast, Port, #small{value = stamp(Port, 1)}} "
        "|| Port <- [first, second]], Alias = Actions, {Cell, Alias}",
    ?assertEqual([first, second], trace(Body)),
    ?assertEqual(2, xls_statem_entry:max_effects(analyze(Body))).

%% Existing path-level port uniqueness still applies after expansion.
-spec repeated_ports_are_rejected_test() -> ok.
repeated_ports_are_rejected_test() ->
    ?assertError({duplicate_hls_statem_declaration, entry_output, [first, first]},
        analyze("{Cell, [{cast, Port, #small{}} || Port <- [first, first]]}" )).

%% Unsupported domains and qualifiers reject instead of becoming runtime routing.
-spec unsupported_comprehensions_test_() -> [term()].
unsupported_comprehensions_test_() ->
    [?_assertException(error, {unsupported_static_entry_comprehension, _, _}, expand(Body))
        || Body <- [
            "{Cell, [{cast, Port, #small{}} || Port <- Directions]}",
            "{Cell, [{cast, Port, #small{}} || Port <- directions()]}",
            "{Cell, [{cast, Port, #small{}} || Port <- [first | second]]}",
            "{Cell, [{cast, Port, #small{}} || Port <- [first], true]}",
            "{Cell, [{cast, Port, #small{}} || Port <- [first], N <- [1]]}",
            "{Cell, [{cast, Port, #small{value = [N || N <- [1]]}} || Port <- [first]]}"
        ]].

%% The rewrite rejects excessive expansion before materializing an action program.
-spec expansion_limit_test() -> ok.
expansion_limit_test() ->
    Domain = lists:flatten(lists:join(",", lists:duplicate(257, "first"))),
    ?assertException(error, {static_entry_comprehension_limit, _, 256},
        expand("{Cell, [{cast, Port, #small{}} || Port <- [" ++ Domain ++ "]]}" )).

%% Hardware compilation and interface inference consume the same expansion.
-spec interface_and_codegen_agree_test() -> ok.
interface_and_codegen_agree_test() ->
    Interface = hls_actor_interface:from_module(xls_static_actions_fixture),
    ?assertEqual(2, hls_actor_interface:max_entry_effects(Interface)),
    ?assertEqual([value], hls_actor_interface:output_schemas(Interface, first)),
    ?assertEqual([value], hls_actor_interface:output_schemas(Interface, second)),
    Artifact = xls_parse:actor_artifact("test/xls_static_actions_fixture.erl", []),
    ?assertEqual(2, maps:get(max_entry_effects, Artifact)),
    Generated = iolist_to_binary(xls_parse:to_xls("test/xls_static_actions_fixture.erl")),
    ?assertNotEqual(nomatch, binary:match(Generated, <<"ENTRY_EFFECT_CAPACITY = u32:2;">>)).

%% Compare values, raised reasons and exact eager-call sequence against ordinary BEAM evaluation.
-spec equivalent(string()) -> {{ok, term()} | {error, term()}, [atom()]}.
equivalent(Body) ->
    Original = clause(Body),
    Expanded = xls_entry_comprehensions:clause(Original),
    Expected = {OriginalResult, Trace} = evaluate(Original),
    ?assertEqual(Expected, evaluate(Expanded)),
    #{program := Program} = xls_statem_entry:analyze(
        Expanded, [small], [first, second, third]),
    Normalized = xls_statem_entry:map_leaves(Program, fun(_Id, Value) -> Value end),
    {NormalizedResult, NormalizedTrace} = evaluate(Normalized),
    ?assertEqual(Trace, NormalizedTrace),
    ?assertEqual(outcome(OriginalResult), outcome(NormalizedResult)),
    Expected.

%% The entry analyzer changes its successful result representation, but not whether or why it fails.
-spec outcome({ok, term()} | {error, term()}) -> ok | {error, term()}.
outcome({ok, _}) -> ok;
outcome({error, Reason}) -> {error, Reason}.

%% Return the original trace only after its complete rewritten result also matches.
-spec trace(string()) -> [atom()].
trace(Body) ->
    {{ok, _}, Trace} = equivalent(Body),
    Trace.

%% Normalize one source clause before the existing structural effect analyzer.
-spec analyze(string()) -> map().
analyze(Body) ->
    xls_statem_entry:analyze(expand(Body), [small], [first, second, third]).

%% Parse the same entry shape used by the production source preparation.
-spec expand(string()) -> erl_parse:abstract_clause().
expand(Body) -> xls_entry_comprehensions:clause(clause(Body)).

%% The parser supplies authentic source annotations for rewrite diagnostics.
-spec clause(string()) -> erl_parse:abstract_clause().
clause(Body) ->
    {function, _, entry, 3, [Clause]} = form("entry(enter, _Old, Cell) -> " ++ Body ++ "."),
    Clause.

%% Expand records before interpretation; the test hook observes payload evaluation without hardware.
-spec evaluate(erl_parse:abstract_clause()) -> {{ok, term()} | {error, term()}, [atom()]}.
evaluate(Clause) ->
    Forms = erl_expand_records:module([
        {attribute, 0, module, static_entry_evaluation},
        form("-record(small, {value = 0})."),
        {function, 0, entry, 3, [Clause]}], []),
    [{function, _, entry, 3, [{clause, _, _, _, Expressions}]}] =
        [F || F = {function, _, entry, 3, _} <- Forms],
    put(static_entry_trace, []),
    try
        Bindings = erl_eval:add_binding('Cell', {cell, 7}, erl_eval:new_bindings()),
        Result = try erl_eval:exprs(Expressions, Bindings, {value, fun hook/2}) of
            {value, Value, _} -> {ok, Value}
        catch error:Reason -> {error, Reason}
        end,
        {Result, lists:reverse(get(static_entry_trace))}
    after erase(static_entry_trace)
    end.

%% Only these test-only calls execute; production normalization must never invoke them.
-spec hook(atom(), [term()]) -> term().
hook(stamp, [Name, Value]) ->
    put(static_entry_trace, [Name | get(static_entry_trace)]),
    Value;
hook(boom, []) -> error(body_failed).

%% Parse a complete Erlang form used by the finite test harness.
-spec form(string()) -> erl_parse:abstract_form().
form(Source) ->
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, Form} = erl_parse:parse_form(Tokens),
    Form.
