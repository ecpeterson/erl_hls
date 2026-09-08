-module(xls_statem_reduction_lower_tests).

-include_lib("eunit/include/eunit.hrl").

-define(FIXTURE, "test_data/hls_statem_reduction_lower_fixture.erl").

closed_ir_nests_site_owned_work_test() ->
    #{reduction := Reduction, cast_groups := Ordinary} = analyze(?FIXTURE),
    ?assertEqual([accumulator, data, reducers, sites],
        lists:sort(maps:keys(Reduction))),
    [Count, Members] = maps:get(sites, Reduction),
    ?assertMatch(#{
        id := 0,
        phase := counting,
        name := sum,
        population := #{mode := count, size := 2},
        contributions := [#{tag := count_value, build := #{}}],
        completion := #{}
    }, Count),
    ?assertMatch(#{
        id := 1,
        phase := collecting_members,
        population := #{
            mode := members,
            size := 3,
            members := [9, 2, 7]
        },
        contributions := [#{tag := member_value, build := #{}}]
    }, Members),
    ?assertMatch([#{name := sum, body := _, result := _}],
        maps:get(reducers, Reduction)),
    %% The non-contributing count_value catch-all remains in ordinary dispatch.
    ?assertMatch([{{count_value, counting}, [_]}], Ordinary),
    ?assertEqual(false, contains_source_form(Reduction)).

layout_is_minimal_and_derived_test() ->
    Reduction = maps:get(reduction, analyze(?FIXTURE)),
    ?assertEqual(2, xls_statem_reduction_ir:site_count(Reduction)),
    ?assertEqual(3, xls_statem_reduction_ir:max_population(Reduction)),
    ?assertEqual(3, xls_statem_reduction_ir:max_member_count(Reduction)),
    ?assertEqual(1, xls_statem_reduction_ir:site_width(Reduction)),
    ?assertEqual(2, xls_statem_reduction_ir:remaining_width(Reduction)),
    ?assertEqual(3, xls_statem_reduction_ir:member_width(Reduction)),
    ?assertEqual(40, xls_statem_reduction_ir:type_width(
        maps:get(accumulator, Reduction))),
    ?assertEqual(#{
        status_bits => 2,
        site_bits => 1,
        key_bits => 32,
        remaining_bits => 2,
        member_bits => 3,
        accumulator_bits => 40,
        total_bits => 80
    }, xls_statem_reduction_ir:layout(Reduction)),
    ?assertEqual(80, xls_statem_reduction_ir:storage_width(Reduction)).

interface_is_closed_and_omits_derived_facts_test() ->
    Reduction = maps:get(reduction, analyze(?FIXTURE)),
    Interface = xls_statem_reduction_ir:interface(Reduction),
    ?assertEqual([accumulator, reducers, sites],
        lists:sort(maps:keys(Interface))),
    ?assertMatch(#{
        accumulator := #{
            name := sum,
            fields := [#{name := value}, #{name := contributions}]
        },
        sites := [
            #{id := 0, phase := counting, name := sum,
              population := #{mode := count, size := 2},
              contributions := [count_value]},
            #{id := 1, phase := collecting_members, name := sum,
              population := #{mode := members, size := 3,
                  members := [9, 2, 7]},
              contributions := [member_value]}
        ],
        reducers := [sum]
    }, Interface),
    ?assertEqual(80,
        xls_statem_reduction_ir:interface_storage_width(Interface)).

source_locations_do_not_escape_analysis_test() ->
    Expected = maps:get(reduction, analyze(?FIXTURE)),
    with_mutated_fixture(
        <<"counting(enter, _OldPhase, Cell) ->">>,
        <<"\n\ncounting(enter, _OldPhase, Cell) ->">>,
        fun(Path) ->
            ?assertEqual(Expected, maps:get(reduction, analyze(Path)))
        end
    ).

entry_may_install_updated_actor_data_test() ->
    %% The fixture's counting entry increments `entries` while opening. Merely
    %% reaching a closed IR demonstrates that this atomic data update is not
    %% confused with the contribution rule forbidding data mutation.
    ?assertMatch(#{reduction := #{sites := [#{phase := counting} | _]}},
        analyze(?FIXTURE)).

width_resolution_is_deferred_test() ->
    TypeModule = hls_statem_reduction_deferred_type_fixture,
    _ = code:purge(TypeModule),
    _ = code:delete(TypeModule),
    try
        with_mutated_fixture(
            <<"value = hls_type:zero() :: hls_nums:u32(),\n"
              "    contributions">>,
            <<"value = hls_type:zero() :: "
              "hls_statem_reduction_deferred_type_fixture:word(),\n"
              "    contributions">>,
            fun(Path) ->
                Reduction = maps:get(reduction, analyze(Path)),
                Interface = xls_statem_reduction_ir:interface(Reduction),
                ?assertEqual(false, code:is_loaded(TypeModule)),
                {ok, TypeModule, Beam} = compile:forms(
                    deferred_type_forms(TypeModule), [binary]),
                {module, TypeModule} = code:load_binary(
                    TypeModule,
                    "hls_statem_reduction_deferred_type_fixture.erl",
                    Beam
                ),
                %% 2 status + 1 site + 32 key + 2 remaining + 3 members
                %% + a 24+8-bit accumulator.
                ?assertEqual(72,
                    xls_statem_reduction_ir:storage_width(Reduction)),
                ?assertEqual(72,
                    xls_statem_reduction_ir:interface_storage_width(
                        Interface))
            end
        )
    after
        _ = code:purge(TypeModule),
        _ = code:delete(TypeModule)
    end.

misplaced_open_is_rejected_test() ->
    ActionList = expression(
        "[{cast, out, #member_value{}}, "
        "{open_reduction, sum, 0, {count, 2}, "
        "{commutative_monoid, #sum{value = 0, contributions = 0}}}]"
    ),
    ?assertException(
        error,
        {hls_statem_open_reduction_must_be_first, 1},
        xls_statem_reduction_lower:split_entry_actions(ActionList, 1)
    ).

duplicate_fixed_members_are_rejected_test() ->
    with_mutated_fixture(
        <<"{members, [9, 2, 7]}">>,
        <<"{members, [9, 2, 9]}">>,
        fun(Path) ->
            ?assertException(
                error,
                {invalid_hls_statem_reduction_members, _, [9, 2, 9]},
                analyze(Path)
            )
        end
    ).

contribution_mode_must_match_owning_site_test() ->
    with_mutated_fixture(
        <<"{contribute, sum, Key, Member,\n            #sum{">>,
        <<"{contribute, sum, Key,\n            #sum{">>,
        fun(Path) ->
            ?assertException(
                error,
                {hls_statem_reduction_contribution_mismatch, _, _},
                analyze(Path)
            )
        end
    ).

contribution_clauses_form_a_dispatch_prefix_test() ->
    with_mutated_fixture(
        <<"counting(cast, #count_value{key = Key, value = Value}, Cell)\n">>,
        <<"counting(cast, #count_value{value = 0}, Cell) ->\n"
          "    {counting, Cell, consume};\n"
          "counting(cast, #count_value{key = Key, value = Value}, Cell)\n">>,
        fun(Path) ->
            ?assertException(
                error,
                {nonprefix_hls_statem_reduction_contribution,
                    count_value, counting, _},
                analyze(Path)
            )
        end
    ).

named_reducer_is_required_test() ->
    with_mutated_fixture(
        <<"reduce(sum,">>,
        <<"combine(sum,">>,
        fun(Path) ->
            ?assertError({missing_hls_statem_reducer, [sum]}, analyze(Path))
        end
    ).

reducer_must_be_exported_test() ->
    with_mutated_fixture(
        <<", reduce/3]">>,
        <<"]">>,
        fun(Path) ->
            ?assertError(
                {missing_hls_statem_callback, reduce, 3},
                analyze(Path)
            )
        end
    ).

%%%
%%% Fixture preparation
%%%

analyze(Path) ->
    {Forms, Context} = context(Path),
    xls_statem_reduction_lower:analyze(Forms, Context).

context(Path) ->
    {ok, Forms} = xls_parse:parse_file(Path),
    Phases = xls_parse:find_attribute(Forms, hls_phases),
    Prepared = lists:append([
        [prepare_clause(Clause, Phase)
            || Clause <- xls_parse:find_function(Forms, Phase, 3)]
        || Phase <- Phases
    ]),
    EntryClauses = [Clause || {enter, Clause} <- Prepared],
    CastClauses = [Clause || {cast, Clause} <- Prepared],
    InternalClauses = [Clause || {internal, Clause} <- Prepared],
    Entries = [entry(Clause) || Clause <- EntryClauses],
    CastGroups = xls_callback_lower:group_by(
        CastClauses,
        fun cast_key/1
    ),
    InternalGroups = xls_statem_reduction_lower:internal_groups(
        InternalClauses, Phases),
    {Forms, #{
        phases => Phases,
        entries => Entries,
        cast_groups => CastGroups,
        internal_groups => InternalGroups,
        message_names => xls_parse:find_tags(Forms),
        data_name => xls_parse:find_attribute(Forms, hls_data)
    }}.

prepare_clause({clause, Line,
        [{atom, _EventLine, enter}, OldPhase, Data], Guards, Body}, Phase) ->
    {enter, {clause, Line,
        [OldPhase, {atom, Line, Phase}, Data], Guards, Body}};
prepare_clause({clause, Line,
        [{atom, _EventLine, cast}, Message, Data], Guards, Body}, Phase) ->
    {cast, {clause, Line,
        [Message, {atom, Line, Phase}, Data], Guards, Body}};
prepare_clause({clause, Line,
        [{atom, _EventLine, internal}, Event, Data], Guards, Body}, Phase) ->
    {internal, {clause, Line,
        [Event, {atom, Line, Phase}, Data], Guards, Body}}.

entry(Clause = {clause, _Line,
        [_OldPhase, {atom, _PhaseLine, Phase}, _Data], _Guards, Body}) ->
    {Prefix, {tuple, TupleLine, [DataExpression, Actions]}} = split_last(Body),
    {Reduction, _Casts} =
        xls_statem_reduction_lower:split_entry_actions(Actions, TupleLine),
    #{
        phase => Phase,
        clause => Clause,
        prefix => Prefix,
        data_expression => DataExpression,
        reduction => Reduction
    }.

cast_key({clause, _Line,
        [Message, {atom, _PhaseLine, Phase}, _Data], _Guards, _Body}) ->
    {xls_pattern_lower:record_pattern_name(Message), Phase}.

split_last(List) ->
    {lists:droplast(List), lists:last(List)}.

expression(Source) ->
    {ok, Tokens, _} = erl_scan:string(Source ++ "."),
    {ok, [Expression]} = erl_parse:parse_exprs(Tokens),
    Expression.

contains_source_form({clause, _, _, _, _}) -> true;
contains_source_form({attribute, _, _, _}) -> true;
contains_source_form(Tuple) when is_tuple(Tuple) ->
    lists:any(fun contains_source_form/1, tuple_to_list(Tuple));
contains_source_form(Map) when is_map(Map) ->
    lists:any(fun({Key, Value}) ->
        contains_source_form(Key) orelse contains_source_form(Value)
    end, maps:to_list(Map));
contains_source_form(List) when is_list(List) ->
    lists:any(fun contains_source_form/1, List);
contains_source_form(_Term) -> false.

deferred_type_forms(Module) ->
    [
        {attribute, 1, module, Module},
        {attribute, 2, export, [{width, 2}]},
        {function, 3, width, 2, [
            {clause, 3,
                [{atom, 3, word}, {nil, 3}], [], [{integer, 3, 24}]}
        ]}
    ].

with_mutated_fixture(Find, Replacement, Test) ->
    {ok, Source} = file:read_file(?FIXTURE),
    Mutated = binary:replace(Source, Find, Replacement),
    ?assertNotEqual(Source, Mutated),
    Path = filename:join(
        "_build", "xls_statem_reduction_lower_mutated_fixture.erl"),
    ok = filelib:ensure_dir(Path),
    ok = file:write_file(Path, Mutated),
    try Test(Path)
    after ok = file:delete(Path)
    end.
