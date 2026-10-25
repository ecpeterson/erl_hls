-module(xls_shared_reduction_lower_tests).

-include_lib("eunit/include/eunit.hrl").

-define(FIXTURE, "test_data/hls_statem_reduction_lower_fixture.erl").

%% Checks closed ir nests site owned work.
-spec closed_ir_nests_site_owned_work_test() -> 'ok'.
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

%% Checks layout is minimal and derived.
-spec layout_is_minimal_and_derived_test() -> 'ok'.
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
        failure_bits => 16,
        expected_bits => 0,
        total_bits => 96
    }, xls_statem_reduction_ir:layout(Reduction)),
    ?assertEqual(96, xls_statem_reduction_ir:storage_width(Reduction)).

%% Checks interface is closed and omits derived facts.
-spec interface_is_closed_and_omits_derived_facts_test() -> 'ok'.
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
    ?assertEqual([true, true], [
        maps:get(source_transportable, Site)
        || Site <- maps:get(sites, Interface)
    ]),
    ?assertEqual([false, true], [
        maps:get(source_capture_total, Site)
        || Site <- maps:get(sites, Interface)
    ]),
    ?assertEqual(96,
        xls_statem_reduction_ir:interface_storage_width(Interface)).

%% Checks structural interface matches closed ir.
-spec structural_interface_matches_closed_ir_test() -> 'ok'.
structural_interface_matches_closed_ir_test() ->
    {Forms, Context} = context(?FIXTURE),
    #{reduction := Closed, cast_groups := ClosedOrdinary} =
        xls_statem_reduction_lower:analyze(Forms, Context),
    #{reduction := Interface, cast_groups := InterfaceOrdinary} =
        xls_statem_reduction_lower:analyze_interface(Forms, Context),
    ?assertEqual(
        xls_statem_reduction_ir:interface(Closed),
        Interface
    ),
    ?assertEqual(ClosedOrdinary, InterfaceOrdinary).

%% Checks interface inference does not lower reducer expressions.
-spec interface_inference_does_not_lower_reducer_expressions_test() -> 'ok'.
interface_inference_does_not_lower_reducer_expressions_test() ->
    Helper = hls_statem_reduction_unloaded_helper,
    ?assertEqual(false, code:is_loaded(Helper)),
    with_mutated_fixture(
        <<"value = Left + Right,">>,
        <<"value = hls_statem_reduction_unloaded_helper:combine("
          "Left, Right),">>,
        fun(Path) ->
            Interface = xls_parse:actor_interface(Path),
            ?assertMatch(#{reductions := #{reducers := [sum]}}, Interface),
            {ok, Module, Binary} = compile:file(
                Path, [binary, debug_info]
            ),
            {ok, {Module, [{attributes, Attributes}]}} =
                beam_lib:chunks(Binary, [attributes]),
            ?assertMatch([_], proplists:get_value(
                hls_actor_interface, Attributes
            )),
            ?assertEqual(false, code:is_loaded(Helper))
        end
    ).

%% Checks list contribution retains message provenance.
-spec list_contribution_retains_message_provenance_test() -> 'ok'.
list_contribution_retains_message_provenance_test() ->
    Path = "test_data/hls_list_reduction_fixture.erl",
    #{reduction := #{sites := [Site]}} = analyze(Path),
    [Contribution] = maps:get(contributions, Site),
    ?assert(maps:get(source_transportable, Contribution)),
    ?assert(maps:get(source_capture_total, Contribution)),
    ?assert(is_binary(iolist_to_binary(lower(Path, #{shared_service => ordinary})))).

%% Checks list contribution rejects actor data.
-spec list_contribution_rejects_actor_data_test() -> 'ok'.
list_contribution_rejects_actor_data_test() ->
    with_mutated_fixture("test_data/hls_list_reduction_fixture.erl",
        <<"values = [A, B]}, Cell)">>,
        <<"values = [A, _]}, Cell = #cell{values = [B | _]})">>,
        fun(Path) ->
            ?assertError({invalid_hls_statem_reduction_origin, data, [message]}, analyze(Path))
        end).

%% Checks list head can supply a typed reduction key.
-spec list_head_can_supply_a_typed_reduction_key_test() -> 'ok'.
list_head_can_supply_a_typed_reduction_key_test() ->
    with_mutated_fixture("test_data/hls_list_reduction_fixture.erl",
        <<"#value{key = Key, values = [A, B]}">>,
        <<"#value{values = [Key = A, B]}">>,
        fun(Path) ->
            ?assert(is_map(analyze(Path)))
        end).

%% Checks list projection does not invent a u32 type.
-spec list_projection_does_not_invent_a_u32_type_test() -> 'ok'.
list_projection_does_not_invent_a_u32_type_test() ->
    with_mutated_fixture("test_data/hls_list_reduction_fixture.erl",
        <<"#value{key = Key, values = [A, B]}">>,
        <<"#value{values = [A | Key = [B]]}">>,
        fun(Path) ->
            ?assertException(error, {invalid_hls_statem_reduction_u32, 'Key', _}, analyze(Path))
        end).

%% Checks actor data dependent applicability is reported not globally rejected.
-spec actor_data_dependent_applicability_is_reported_not_globally_rejected_test() -> 'ok'.
actor_data_dependent_applicability_is_reported_not_globally_rejected_test() ->
    with_mutated_fixture(
        <<"counting(cast, #count_value{key = Key, value = Value}, Cell)\n">>,
        <<"counting(cast, #count_value{key = Key, value = Value},\n"
          "        Cell = #cell{entries = _Entries})\n">>,
        fun(Path) ->
            #{reduction := #{sites := [Count | _]}} = analyze(Path),
            [Contribution] = maps:get(contributions, Count),
            ?assertEqual(false,
                maps:get(source_transportable, Contribution)),
            ?assertEqual(none, maps:get(transport, Contribution)),
            Interface = xls_parse:actor_interface(Path),
            [PublicCount | _] = maps:get(sites,
                maps:get(reductions, Interface)),
            ?assertEqual(false,
                maps:get(source_transportable, PublicCount)),
            ?assert(is_binary(iolist_to_binary(
                lower(Path, #{shared_service => ordinary})))),
            ?assertError(
                {aggregate_only_nontransportable_contributions,
                    [#{phase := counting, schema := count_value}]},
                lower(Path, #{shared_service => aggregate_only})
            )
        end
    ).

%% Checks actor data dependent guard is not source transportable.
-spec actor_data_dependent_guard_is_not_source_transportable_test() -> 'ok'.
actor_data_dependent_guard_is_not_source_transportable_test() ->
    with_mutated_fixture(
        <<"        when Value > 0 ->">>,
        <<"        when Value > 0, Cell#cell.value >= 0 ->">>,
        fun(Path) ->
            #{reduction := #{sites := [Count | _]}} = analyze(Path),
            [Contribution] = maps:get(contributions, Count),
            ?assertEqual(false,
                maps:get(source_transportable, Contribution)),
            ?assertError(
                {aggregate_only_nontransportable_contributions,
                    [#{phase := counting, schema := count_value}]},
                lower(Path, #{shared_service => aggregate_only})
            )
        end
    ).

%% Checks guarded contribution fallback is not total source capture.
-spec guarded_contribution_fallback_is_not_total_source_capture_test() -> 'ok'.
guarded_contribution_fallback_is_not_total_source_capture_test() ->
    #{reduction := #{sites := [Count | _]}, cast_groups := Ordinary} =
        analyze(?FIXTURE),
    [Contribution] = maps:get(contributions, Count),
    ?assertEqual(true, maps:get(source_transportable, Contribution)),
    ?assertEqual(false, maps:get(source_capture_total, Contribution)),
    %% The distinction is placement-only: the ordinary fallback remains in
    %% dispatch and both ordinary entry points still render identically.
    ?assertMatch([{{count_value, counting}, [_]}], Ordinary),
        ?assertEqual(
        iolist_to_binary(xls_shared_parse:to_xls(?FIXTURE)),
        iolist_to_binary(xls_shared_parse:to_xls(?FIXTURE, #{shared_service => ordinary}))
    ),
    %% The generic aggregate helper may still represent the guard miss as an
    %% invalid contribution.  Only whole-schema source capture is forbidden.
    ?assert(is_binary(iolist_to_binary(
        lower(?FIXTURE, #{shared_service => aggregate_only})
    ))).

%% Checks refutable contribution pattern is not total source capture.
-spec refutable_contribution_pattern_is_not_total_source_capture_test() -> 'ok'.
refutable_contribution_pattern_is_not_total_source_capture_test() ->
    with_mutated_fixture(
        <<"#count_value{key = Key, value = Value}, Cell)\n"
          "        when Value > 0 ->">>,
        <<"#count_value{key = Key, value = Value = 1}, Cell) ->">>,
        fun(Path) ->
            #{reduction := #{sites := [Count | _]},
              cast_groups := Ordinary} = analyze(Path),
            [Contribution] = maps:get(contributions, Count),
            ?assertEqual(true,
                maps:get(source_transportable, Contribution)),
            ?assertEqual(false,
                maps:get(source_capture_total, Contribution)),
            ?assertMatch([{{count_value, counting}, [_]}], Ordinary),
            ?assert(is_binary(iolist_to_binary(
                lower(Path, #{shared_service => ordinary})
            )))
        end
    ).

%% Checks source locations do not escape analysis.
-spec source_locations_do_not_escape_analysis_test() -> 'ok'.
source_locations_do_not_escape_analysis_test() ->
    Expected = maps:get(reduction, analyze(?FIXTURE)),
    with_mutated_fixture(
        <<"counting(enter, _OldPhase, Cell) ->">>,
        <<"\n\ncounting(enter, _OldPhase, Cell) ->">>,
        fun(Path) ->
            ?assertEqual(Expected, maps:get(reduction, analyze(Path)))
        end
    ).

%% Checks entry may install updated actor data.
-spec entry_may_install_updated_actor_data_test() -> 'ok'.
entry_may_install_updated_actor_data_test() ->
    %% The fixture's counting entry increments `entries` while opening. Merely
    %% reaching a closed IR demonstrates that this atomic data update is not
    %% confused with the contribution rule forbidding data mutation.
    ?assertMatch(#{reduction := #{sites := [#{phase := counting} | _]}},
        analyze(?FIXTURE)).

%% Checks width resolution is deferred.
-spec width_resolution_is_deferred_test() -> 'ok'.
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
                %% + a 24+8-bit accumulator and 16-bit pending failure.
                ?assertEqual(88,
                    xls_statem_reduction_ir:storage_width(Reduction)),
                ?assertEqual(88,
                    xls_statem_reduction_ir:interface_storage_width(
                        Interface))
            end
        )
    after
        _ = code:purge(TypeModule),
        _ = code:delete(TypeModule)
    end.

%% Checks misplaced open is rejected.
-spec misplaced_open_is_rejected_test() -> 'ok'.
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

%% Checks duplicate fixed members are rejected.
-spec duplicate_fixed_members_are_rejected_test() -> 'ok'.
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

%% Checks contribution mode must match owning site.
-spec contribution_mode_must_match_owning_site_test() -> 'ok'.
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

%% Checks contribution clauses form a dispatch prefix.
-spec contribution_clauses_form_a_dispatch_prefix_test() -> 'ok'.
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

%% Checks named reducer is required.
-spec named_reducer_is_required_test() -> 'ok'.
named_reducer_is_required_test() ->
    with_mutated_fixture(
        <<"reduce(sum,">>,
        <<"combine(sum,">>,
        fun(Path) ->
            ?assertError({missing_hls_statem_reducer, [sum]}, analyze(Path))
        end
    ).

%% Checks reducer must be exported.
-spec reducer_must_be_exported_test() -> 'ok'.
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

-spec analyze(file:filename()) -> map().
analyze(Path) ->
    {Forms, Context} = context(Path),
    xls_statem_reduction_lower:analyze(Forms, Context).

%% Translates the fixture with the selected shared-service options.
-spec lower(file:filename(), map()) -> iodata().
lower(Path, Options) ->
    xls_shared_parse:to_xls(Path, Options).

%% Constructs the source context needed by a lowering witness.
-spec context(file:filename()) -> {[hls_source:form()], map()}.
context(Path) ->
    {ok, Forms} = hls_source:parse_file(Path),
    Phases = hls_source:find_attribute(Forms, hls_phases),
    Prepared = lists:append([
        [prepare_clause(Clause, Phase)
            || Clause <- hls_source:find_function(Forms, Phase, 3)]
        || Phase <- Phases
    ]),
    EntryClauses = [Clause || {enter, Clause} <- Prepared],
    CastClauses = [Clause || {cast, Clause} <- Prepared],
    InternalClauses = [Clause || {internal, Clause} <- Prepared],
    Entries = [entry(Clause, Forms) || Clause <- EntryClauses],
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
        message_names => hls_actor_source:tags(Forms),
        data_name => hls_source:find_attribute(Forms, hls_data)
    }}.

%% Normalizes a parsed callback clause for the lowerer under test.
-spec prepare_clause({'clause',term(),[any(),...],term(),term()},term()) -> {'cast',{'clause',term(),[any(),...],term(),term()}} | {'enter',{'clause',term(),[any(),...],term(),term()}} | {'internal',{'clause',term(),[any(),...],term(),term()}}.
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

%% Builds the fixture's bounded phase-entry result.
-spec entry({'clause',term(),[any(),...],term(),term()},term()) -> map().
entry(Clause = {clause, _Line,
        [_OldPhase, {atom, _PhaseLine, Phase}, _Data], _Guards, _Body}, Forms) ->
    (xls_statem_entry:analyze(Clause, hls_actor_source:tags(Forms),
        hls_source:find_attribute(Forms, hls_outputs)))#{phase => Phase}.

%% Builds the contribution-key expression used by the lowerer witness.
-spec cast_key({'clause',term(),[any(),...],term(),term()}) -> {term(),term()}.
cast_key({clause, _Line,
        [Message, {atom, _PhaseLine, Phase}, _Data], _Guards, _Body}) ->
    {xls_pattern_lower:record_pattern_name(Message), Phase}.

%% Parses one test expression without executing it.
-spec expression([1..255,...]) -> {'nil',erl_anno:anno()} | {atom(),erl_anno:anno(),term()} | {atom(),erl_anno:anno(),term(),term()} | {'op',erl_anno:anno(),atom(),term(),term()} | {'receive',erl_anno:anno(),[{term(),term(),term(),term(),term()},...],term(),[any(),...]} | {'record',erl_anno:anno(),term(),atom(),[{term(),term(),term(),term()}]} | {'record_field',erl_anno:anno(),term(),atom(),{'atom',erl_anno:anno(),atom()}} | {'try',erl_anno:anno(),[any(),...],[{term(),term(),term(),term(),term()}],[{term(),term(),term(),term(),term()}],[any()]}.
expression(Source) ->
    {ok, Tokens, _} = erl_scan:string(Source ++ "."),
    {ok, [Expression]} = erl_parse:parse_exprs(Tokens),
    Expression.

%% Detects unlowered source syntax remaining in the checked result.
-spec contains_source_form(term()) -> boolean().
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

%% Builds a source form whose logical type is resolved at lowering time.
-spec deferred_type_forms('hls_statem_reduction_deferred_type_fixture') -> [{'attribute',1 | 2,'export' | 'module','hls_statem_reduction_deferred_type_fixture' | [{term(),term()},...]} | {'function',3,'width',2,[{term(),term(),term(),term(),term()},...]},...].
deferred_type_forms(Module) ->
    [
        {attribute, 1, module, Module},
        {attribute, 2, export, [{width, 2}]},
        {function, 3, width, 2, [
            {clause, 3,
                [{atom, 3, word}, {nil, 3}], [], [{integer, 3, 24}]}
        ]}
    ].

%% Runs a targeted source mutation in an isolated file and cleans it afterward.
-spec with_mutated_fixture(binary(), binary(), fun((file:filename()) -> Result)) -> Result.
with_mutated_fixture(Find, Replacement, Test) ->
    with_mutated_fixture(?FIXTURE, Find, Replacement, Test).

%% Runs a targeted source mutation in an isolated file and cleans it afterward.
-spec with_mutated_fixture(file:filename(), binary(), binary(), fun((file:filename()) -> Result)) -> Result.
with_mutated_fixture(Fixture, Find, Replacement, Test) ->
    {ok, Source} = file:read_file(Fixture),
    Mutated = binary:replace(Source, Find, Replacement),
    ?assertNotEqual(Source, Mutated),
    Path = filename:join(
        "_build", "xls_statem_reduction_lower_mutated_fixture.erl"),
    ok = filelib:ensure_dir(Path),
    ok = file:write_file(Path, Mutated),
    try Test(Path)
    after ok = file:delete(Path)
    end.
