-module(xls_statem_reduction_lower_tests).

-include_lib("eunit/include/eunit.hrl").

-define(FIXTURE, "test_data/hls_statem_reduction_lower_fixture.erl").

bounded_reduction_interface_is_explicit_test() ->
    Interface = xls_parse:actor_interface(?FIXTURE),
    Reductions = maps:get(reductions, Interface),
    ?assertMatch(#{
        accumulator := #{
            name := sum,
            fields := [
                #{name := value},
                #{name := contributions}
            ]
        },
        site_count := 2,
        max_population := 3,
        max_member_count := 3,
        opens := [
            #{
                site := 0,
                phase := counting,
                name := sum,
                population := #{mode := count, size := 2}
            },
            #{
                site := 1,
                phase := collecting_members,
                name := sum,
                population := #{
                    mode := members,
                    size := 3,
                    members := [9, 2, 7]
                }
            }
        ],
        contributions := [
            #{site := 0, phase := counting, tag := count_value,
                name := sum, mode := count},
            #{site := 1, phase := collecting_members, tag := member_value,
                name := sum, mode := members}
        ],
        completions := [
            #{site := 0, phase := counting, name := sum},
            #{site := 1, phase := collecting_members, name := sum}
        ],
        reducers := [sum]
    }, Reductions),
    ?assertEqual(117,
        hls_actor_interface:reduction_storage_width(Interface)),
    %% The private accumulator is not a public wire schema, while contribution
    %% messages remain ordinary dispatches even when their fast clauses are
    %% removed from the generic cast callback.
    ?assertEqual([count_value, member_value], [
        maps:get(name, Schema) || Schema <- maps:get(schemas, Interface)
    ]),
    ?assertEqual(
        [
            #{schema => count_value, phase => counting},
            #{schema => member_value, phase => collecting_members}
        ],
        maps:get(dispatches, Interface)
    ),
    ?assertEqual([], maps:get(entry_effects, Interface)).

reduction_interface_is_source_location_independent_test() ->
    Interface = xls_parse:actor_interface(?FIXTURE),
    with_mutated_fixture(
        <<"counting(enter, _OldPhase, Cell) ->">>,
        <<"\n\ncounting(enter, _OldPhase, Cell) ->">>,
        fun(Path) ->
            ?assertEqual(Interface, xls_parse:actor_interface(Path))
        end
    ).

reduction_accumulator_width_is_deferred_until_interface_query_test() ->
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
                %% Interface extraction runs during the actor's parse
                %% transform, when a custom type may not be compiled yet.
                Interface = xls_parse:actor_interface(Path),
                ?assertEqual(false, code:is_loaded(TypeModule)),
                {ok, TypeModule, Beam} = compile:forms(
                    deferred_type_forms(TypeModule),
                    [binary]
                ),
                {module, TypeModule} = code:load_binary(
                    TypeModule,
                    "hls_statem_reduction_deferred_type_fixture.erl",
                    Beam
                ),
                %% 50 fixed bits + three member bits + a 24+32-bit accumulator.
                ?assertEqual(109,
                    hls_actor_interface:reduction_storage_width(Interface))
            end
        )
    after
        _ = code:purge(TypeModule),
        _ = code:delete(TypeModule)
    end.

generated_reduction_dslx_uses_typed_private_storage_test() ->
    Interface = xls_parse:actor_interface(?FIXTURE),
    StateWidth = maps:get(width, hls_actor_interface:state(Interface)),
    ReductionWidth = hls_actor_interface:reduction_storage_width(Interface),
    MachineWidth = xls_statem_codegen:shared_machine_width(
        StateWidth,
        ReductionWidth
    ),
    Xls = iolist_to_binary(xls_parse:to_xls(?FIXTURE)),
    ?assertNotEqual(nomatch, binary:match(
        Xls,
        <<"struct ReductionState {">>
    )),
    ?assertNotEqual(nomatch, binary:match(
        Xls,
        iolist_to_binary([
            "pub type MachineBits = bits[",
            integer_to_list(MachineWidth),
            "];"
        ])
    )),
    ?assertNotEqual(nomatch, binary:match(
        Xls,
        <<"fn reduction_contribution(">>
    )),
    %% Count-mode contributions have no semantic member label.  Their private
    %% placeholder must nevertheless be a u32 so all builder arms unify.
    ?assertNotEqual(nomatch, binary:match(
        Xls,
        <<"(0 as u32)">>
    )),
    ?assertNotEqual(nomatch, binary:match(
        Xls,
        <<"fn reduction_dispatch_completion(">>
    )),
    ?assertEqual(nomatch, binary:match(
        Xls,
        <<"struct ReductionCompletion {">>
    )),
    ?assertEqual(nomatch, binary:match(
        Xls,
        <<"fn reduction_completion(">>
    )).

reduction_codegen_rejects_an_inconsistent_storage_width_test() ->
    ?assertError(
        {inconsistent_reduction_storage_width, 116, 117},
        xls_statem_reduction_codegen:private_width(#{
            accumulator => #{width => 64},
            storage_width => 116,
            opens => [
                #{population => #{mode => count, size => 2}},
                #{population => #{
                    mode => members,
                    size => 3,
                    members => [9, 2, 7]
                }}
            ]
        })
    ).

literal_reduction_coordinates_are_explicitly_u32_test() ->
    with_mutated_fixture(
        <<"sum, Cell#cell.key, {count, 2}">>,
        <<"sum, 17, {count, 2}">>,
        fun(Path) ->
            Xls = iolist_to_binary(xls_parse:to_xls(Path)),
            ?assertNotEqual(nomatch, binary:match(
                Xls,
                <<"(17 as u32)">>
            ))
        end
    ),
    with_mutated_fixture(
        <<"{contribute, sum, Key, Member,">>,
        <<"{contribute, sum, Key, 5,">>,
        fun(Path) ->
            Xls = iolist_to_binary(xls_parse:to_xls(Path)),
            ?assertNotEqual(nomatch, binary:match(
                Xls,
                <<"(5 as u32)">>
            ))
        end
    ).

fixed_member_universe_rejects_duplicate_labels_test() ->
    with_mutated_fixture(
        <<"{members, [9, 2, 7]}">>,
        <<"{members, [9, 2, 9]}">>,
        fun(Path) ->
            ?assertException(
                error,
                {invalid_hls_statem_reduction_members, _, [9, 2, 9]},
                xls_parse:actor_interface(Path)
            )
        end
    ).

fixed_member_universe_must_be_literal_test() ->
    with_mutated_fixture(
        <<"{members, [9, 2, 7]}">>,
        <<"{members, Cell}">>,
        fun(Path) ->
            ?assertException(
                error,
                {nonliteral_hls_statem_actions, _, _},
                xls_parse:actor_interface(Path)
            )
        end
    ).

reduction_identity_must_be_a_complete_private_record_test() ->
    with_mutated_fixture(
        <<"{commutative_monoid,\n                #sum{value = 0, contributions = 0}}">>,
        <<"{commutative_monoid, #sum{value = 0}}">>,
        fun(Path) ->
            ?assertException(
                error,
                {incomplete_hls_statem_reduction_record,
                    reduction_identity, _, sum, _, _},
                xls_parse:actor_interface(Path)
            )
        end
    ).

private_accumulator_cannot_collide_with_reserved_wire_tags_test() ->
    with_mutated_fixture(
        <<"-record(sum, {">>,
        <<"-record(error, {">>,
        fun(Path) ->
            ?assertException(
                error,
                {nonprivate_hls_statem_reduction_accumulator, error},
                xls_parse:actor_interface(Path)
            )
        end,
        [{<<"#sum{">>, <<"#error{">>}]
    ).

open_reduction_may_atomically_install_different_actor_data_test() ->
    with_mutated_fixture(
        <<"counting(enter, _OldPhase, Cell) ->\n    {Cell, [">>,
        <<"counting(enter, _OldPhase, Cell) ->\n"
          "    {Cell#cell{value = 1}, [">>,
        fun(Path) ->
            _ = xls_parse:actor_interface(Path),
            OriginalXls = iolist_to_binary(xls_parse:to_xls(?FIXTURE)),
            Xls = iolist_to_binary(xls_parse:to_xls(Path)),
            ?assertNotEqual(OriginalXls, Xls)
        end
    ).

contribution_cannot_mutate_actor_data_test() ->
    with_mutated_fixture(
        <<"    {counting, Cell,\n        {contribute, sum, Key,">>,
        <<"    {counting, Cell#cell{value = Value},\n"
          "        {contribute, sum, Key,">>,
        fun(Path) ->
            ?assertException(
                error,
                {mutating_hls_statem_contribution, _, counting, _, _},
                xls_parse:actor_interface(Path)
            )
        end
    ).

contribution_clauses_must_precede_generic_clauses_test() ->
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
                xls_parse:actor_interface(Path)
            )
        end
    ).

completion_name_must_match_the_open_site_test() ->
    with_mutated_fixture(
        <<"{reduction_complete, sum, Key,\n            #sum{value = Value, contributions = 2}}">>,
        <<"{reduction_complete, other, Key,\n"
          "            #sum{value = Value, contributions = 2}}">>,
        fun(Path) ->
            ?assertException(
                error,
                {incomplete_hls_statem_reduction_completions, _, _},
                xls_parse:actor_interface(Path)
            )
        end
    ).

named_reducer_is_required_test() ->
    with_mutated_fixture(
        <<"reduce(sum,">>,
        <<"combine(sum,">>,
        fun(Path) ->
            ?assertError(
                {missing_hls_statem_reducer, [sum]},
                xls_parse:actor_interface(Path)
            )
        end
    ).

deferred_type_forms(Module) ->
    [
        {attribute, 1, module, Module},
        {attribute, 2, export, [{width, 2}]},
        {function, 3, width, 2, [
            {clause, 3, [{atom, 3, word}, {nil, 3}], [], [{integer, 3, 24}]}
        ]}
    ].

with_mutated_fixture(Find, Replacement, Test) ->
    with_mutated_fixture(Find, Replacement, Test, []).

with_mutated_fixture(Find, Replacement, Test, AdditionalReplacements) ->
    {ok, Source} = file:read_file(?FIXTURE),
    Mutated0 = binary:replace(Source, Find, Replacement),
    Mutated = lists:foldl(
        fun({Needle, Value}, Acc) ->
            binary:replace(Acc, Needle, Value, [global])
        end,
        Mutated0,
        AdditionalReplacements
    ),
    ?assertNotEqual(Source, Mutated),
    Path = filename:join(
        "_build",
        "xls_statem_reduction_lower_mutated_fixture.erl"
    ),
    ok = filelib:ensure_dir(Path),
    ok = file:write_file(Path, Mutated),
    try
        Test(Path)
    after
        ok = file:delete(Path)
    end.
