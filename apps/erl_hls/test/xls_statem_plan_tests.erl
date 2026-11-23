-module(xls_statem_plan_tests).
-moduledoc "Checks planning provenance, complete dispatch families and retained evaluation obligations without changing ordinary actor rendering.".
-include_lib("eunit/include/eunit.hrl").

-define(GATHER, "test_data/xls_statem_gather_fixture.erl").
-define(ENTRY, "test/xls_entry_outcome_fixture.erl").

%% Planning must not alter the ordinary emitter's closed input or DSLX output.
-spec ordinary_rendering_is_unchanged_test() -> ok.
ordinary_rendering_is_unchanged_test() ->
    lists:foreach(fun(File) ->
        Ordinary = xls_parse:actor_artifact(File, []),
        {Planned, _} = xls_statem_plan:from_file(File, []),
        ?assertEqual(Ordinary, Planned),
        ?assertEqual(iolist_to_binary(xls_statem_codegen:emit(Ordinary)),
            iolist_to_binary(xls_statem_codegen:emit(Planned))),
        ?assertNot(maps:is_key(planning, Ordinary))
    end, [?GATHER, ?ENTRY]).

%% Fresh payload-origin references are renamed bijectively when checking freshness.
-spec fresh_compilation_and_saved_plan_validate_test() -> ok.
fresh_compilation_and_saved_plan_validate_test() ->
    {_, Plan} = xls_statem_plan:from_file(?ENTRY, []),
    Saved = binary_to_term(term_to_binary(Plan)),
    ?assertEqual(ok, xls_statem_plan:validate(?ENTRY, [], Saved)),
    ?assertEqual(xls_statem_plan:manifest(Plan), xls_statem_plan:manifest(Saved)).

%% Alpha-renaming must preserve repeated origins; it must not erase value sharing.
-spec changed_payload_sharing_is_rejected_test() -> ok.
changed_payload_sharing_is_rejected_test() ->
    {_, Plan} = xls_statem_plan:from_file(?ENTRY, []),
    ?assertError(stale_statem_plan,
        xls_statem_plan:validate(?ENTRY, [], split_origins(Plan))).

%% The successful gather arm must not hide late/wrong-key postponement arms.
-spec selection_keeps_whole_dispatch_families_test() -> ok.
selection_keeps_whole_dispatch_families_test() ->
    {_, Plan} = xls_statem_plan:from_file(?GATHER, []),
    #{callbacks := Casts, protocol := Protocol, roots := Roots} =
        xls_statem_plan:select(Plan, [{collecting, cast}]),
    ?assertEqual([1, 2, 3], [N || #{ordinal := N} <- Casts]),
    ?assertEqual([gather, postpone, postpone], [outcome(C) || C <- Casts]),
    ?assertMatch(#{gathers := #{sites := [_]}, reductions := #{sites := [_]},
        continuations := [fold, finish], capacity := 8}, Protocol),
    ?assertEqual([{init, 1}, {reduce, 3}], [F || #{function := F} <- Roots]),
    #{callbacks := Completion} = xls_statem_plan:select(Plan, [{collecting, internal}]),
    ?assertEqual(2, length(Completion)).

%% Source ordering and guards remain available even when clauses share a schema.
-spec guard_and_fallback_order_is_retained_test() -> ok.
guard_and_fallback_order_is_retained_test() ->
    {_, Plan} = xls_statem_plan:from_file(?GATHER, []),
    #{callbacks := [First, Second | _]} = xls_statem_plan:select(Plan, [{idle, cast}]),
    #{clause := {clause, _, _, Guards, _}} = First,
    #{clause := {clause, _, _, [], _}} = Second,
    ?assertMatch([[_]], Guards),
    ?assertEqual(1, maps:get(ordinal, First)),
    ?assertEqual(2, maps:get(ordinal, Second)).

%% Closure must include an indirect helper and its provider calls in callee order.
-spec transitive_helpers_are_closed_test() -> ok.
transitive_helpers_are_closed_test() ->
    {ok, Forms} = hls_source:parse_file(?GATHER, []),
    Wrapped = [wrap_completion(F) || F <- Forms] ++ [
        form("-spec outer(hls_lists:list(#element{}, 4)) -> hls_nums:u32()."),
        form("outer(Values) -> ordered(Values).")],
    {_, Plan} = planned(Wrapped),
    #{helpers := Helpers, providers := Providers} =
        xls_statem_plan:select(Plan, [{collecting, internal}]),
    ?assertEqual(["hls_local_ordered__1", "hls_local_outer__1"],
        [Name || #{name := Name} <- Helpers]),
    ?assert(lists:member({hls_lists, nth, 2}, Providers)),
    ?assert(lists:member({hls_type, as, 2}, Providers)).

%% A precomputed but omitted effect can fail: do not delete its evaluation or helper.
-spec discarded_evaluation_stays_in_entry_program_test() -> ok.
discarded_evaluation_stays_in_entry_program_test() ->
    {_, Plan} = xls_statem_plan:from_file(?ENTRY, []),
    #{callbacks := [#{clause := Clause}], entries := [#{program := Program}],
        helpers := Helpers} = xls_statem_plan:select(Plan, [{precomputed, enter}]),
    ?assert(contains_helper(Clause, "hls_local_nonzero__1")),
    ?assert(contains_helper(Program, "hls_local_nonzero__1")),
    ?assert(lists:any(fun(#{name := Name}) -> Name =:= "hls_local_nonzero__1" end, Helpers)).

%% No missing family or empty list may act as a vacuous structural witness.
-spec invalid_selections_fail_test() -> ok.
invalid_selections_fail_test() ->
    {_, Plan} = xls_statem_plan:from_file(?GATHER, []),
    ?assertError(empty_statem_plan_selection, xls_statem_plan:select(Plan, [])),
    ?assertError(duplicate_statem_plan_selection,
        xls_statem_plan:select(Plan, [{idle, cast}, {idle, cast}])),
    ?assertError({missing_statem_plan_families, [{done, cast}]},
        xls_statem_plan:select(Plan, [{done, cast}])),
    ?assertError({missing_statem_plan_families, [{unknown, enter}]},
        xls_statem_plan:select(Plan, [{unknown, enter}])).

%% Corrupt cached content cannot pass simply because the saved source hash is intact.
-spec modified_plan_is_rejected_test() -> ok.
modified_plan_is_rejected_test() ->
    {_, Plan} = xls_statem_plan:from_file(?GATHER, []),
    ?assertError(stale_statem_plan,
        xls_statem_plan:validate(?GATHER, [], Plan#{callbacks := []})),
    ?assertError(stale_statem_plan,
        xls_statem_plan:validate(?GATHER, [], Plan#{helpers := []})).

%% A missing transitive helper is an error even when its caller was retained.
-spec incomplete_dependency_graph_is_rejected_test() -> ok.
incomplete_dependency_graph_is_rejected_test() ->
    {_, Plan} = xls_statem_plan:from_file(?GATHER, []),
    ?assertError({missing_statem_plan_helper, "hls_local_ordered__1"},
        xls_statem_plan:select(Plan#{helpers := []}, [{collecting, internal}])).

%% Bind source bodies beyond the actor-interface summary, including unused source.
-spec complete_source_fingerprint_test() -> ok.
complete_source_fingerprint_test() ->
    {ok, Forms} = hls_source:parse_file(?GATHER, []),
    {_, Before} = planned(Forms),
    {_, After} = planned(Forms ++ [form("host_only() -> 42.")]),
    A = xls_statem_plan:manifest(Before), B = xls_statem_plan:manifest(After),
    ?assertNotEqual(maps:get(source_sha256, A), maps:get(source_sha256, B)),
    ?assertEqual(maps:get(callbacks, A), maps:get(callbacks, B)).

%% A saved plan must reread include contents rather than trust the old context.
-spec changed_include_is_rejected_test() -> ok.
changed_include_is_rejected_test() ->
    Root = filename:join("_build", "statem-plan-include-" ++
        integer_to_list(erlang:unique_integer([positive]))),
    Source = filename:join(Root, "actor.erl"), Include = filename:join(Root, "value.hrl"),
    ok = filelib:ensure_dir(Source),
    {ok, Original} = file:read_file(?GATHER),
    Body = binary:replace(Original, <<"* 1000.">>, <<"* ?LAST_WEIGHT.">>),
    ok = file:write_file(Source, ["-include(\"value.hrl\").\n", Body]),
    try
        ok = file:write_file(Include, "-define(LAST_WEIGHT, 1000).\n"),
        {_, Plan} = xls_statem_plan:from_file(Source, []),
        ok = xls_statem_plan:validate(Source, [], Plan),
        ok = file:write_file(Include, "-define(LAST_WEIGHT, 1001).\n"),
        ?assertError(stale_statem_plan, xls_statem_plan:validate(Source, [], Plan))
    after
        file:delete(Source), file:delete(Include), file:del_dir(Root)
    end.

%% Inspect only the fixture's ordinary three/four-element callback outcomes.
-spec outcome(map()) -> atom().
outcome(#{clause := {clause, _, _, _, [{tuple, _, [_, _, Result | _]}]}}) ->
    case Result of
        {atom, _, Directive} -> Directive;
        {tuple, _, [{atom, _, Directive} | _]} -> Directive
    end.

%% Add one indirect helper call without replacing the helper's own definition.
-spec wrap_completion(hls_source:form()) -> hls_source:form().
wrap_completion({function, L, collecting, 3, Clauses}) ->
    {function, L, collecting, 3, rename_call(Clauses)};
wrap_completion(Form) -> Form.

%% This fixture mutation preserves all arguments and changes only the named call.
-spec rename_call(term()) -> term().
rename_call({call, L, {atom, A, ordered}, Args}) -> {call, L, {atom, A, outer}, Args};
rename_call(Tuple) when is_tuple(Tuple) -> list_to_tuple([rename_call(X) || X <- tuple_to_list(Tuple)]);
rename_call(List) when is_list(List) -> [rename_call(X) || X <- List];
rename_call(Value) -> Value.

%% Search the retained program, including evaluation prefixes and selected leaves.
-spec contains_helper(term(), string()) -> boolean().
contains_helper({xls_helper_call, _, Name, _}, Name) -> true;
contains_helper(Tuple, Name) when is_tuple(Tuple) -> contains_helper(tuple_to_list(Tuple), Name);
contains_helper(List, Name) when is_list(List) -> lists:any(fun(X) -> contains_helper(X, Name) end, List);
contains_helper(_, _Name) -> false.

%% Deliberately break repeated payload identities while leaving syntax unchanged.
-spec split_origins(term()) -> term().
split_origins(Ref) when is_reference(Ref) -> make_ref();
split_origins(Map) when is_map(Map) -> maps:map(fun(_, V) -> split_origins(V) end, Map);
split_origins(Tuple) when is_tuple(Tuple) -> list_to_tuple([split_origins(X) || X <- tuple_to_list(Tuple)]);
split_origins(List) when is_list(List) -> [split_origins(X) || X <- List];
split_origins(Value) -> Value.

%% Compile mutated forms through the same checked lowering as file compilation.
-spec planned([hls_source:form()]) -> {xls_actor_codegen:spec(), xls_statem_plan:plan()}.
planned(Forms) ->
    xls_statem_lower:planned_artifact(?GATHER, Forms, hls_source:find_attribute(Forms, hls_phases)).

%% Parse a single fixture declaration without bypassing Erlang syntax validation.
-spec form(string()) -> hls_source:form().
form(Text) ->
    {ok, Tokens, _} = erl_scan:string(Text),
    {ok, Form} = erl_parse:parse_form(Tokens),
    Form.
