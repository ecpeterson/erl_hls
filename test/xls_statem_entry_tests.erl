-module(xls_statem_entry_tests).

-include_lib("eunit/include/eunit.hrl").

branch_capacity_is_the_largest_selected_list_test() ->
    Interface = hls_actor_interface:from_module(xls_entry_branch_fixture),
    ?assertEqual(3, hls_actor_interface:max_entry_effects(Interface)),
    ?assertEqual([small, wide], hls_actor_interface:output_schemas(Interface, first)),
    ?assertEqual([small, wide], hls_actor_interface:output_schemas(Interface, third)),
    Generated = iolist_to_binary(xls_parse:to_xls("test/xls_entry_branch_fixture.erl")),
    ?assertNotEqual(nomatch, binary:match(Generated,
        <<"ENTRY_EFFECT_PAYLOAD_BITS = u32:160;">>)),
    ?assertNotEqual(nomatch, binary:match(Generated,
        <<"ENTRY_EFFECT_CAPACITY = u32:3;">>)).

alternative_ports_share_an_order_without_becoming_two_effects_test() ->
    Plan = analyze("{Cell, case Cell#cell.value of "
        "0 -> [{cast, first, #small{}}]; "
        "_ -> [{cast, second, #wide{}}] end}"),
    ?assertEqual(1, xls_statem_entry:max_effects(Plan)),
    ?assertEqual([
        #{order => 0, port => first, schema => small, conditional => true},
        #{order => 0, port => second, schema => wide, conditional => true}
    ], xls_statem_entry:effects(Plan)).

branching_suffix_preserves_an_unconditional_prefix_test() ->
    Plan = analyze("{Cell, [{cast, first, #small{}} | "
        "case Cell#cell.value of 0 -> []; "
        "_ -> [{cast, second, #wide{}}] end]}"),
    ?assertEqual([
        #{order => 0, port => first, schema => small},
        #{order => 1, port => second, schema => wide, conditional => true}
    ], xls_statem_entry:effects(Plan)).

port_may_repeat_across_alternatives_but_not_along_a_path_test() ->
    ?assertMatch(#{variants := [_, _]}, analyze("{Cell, "
        "case Cell#cell.value of 0 -> [{cast, first, #small{}}]; "
        "_ -> [{cast, first, #wide{}}] end}")),
    ?assertError({duplicate_hls_statem_declaration, entry_output, [first, first]},
        analyze("{Cell, [{cast, first, #small{}}] ++ "
            "case Cell#cell.value of 0 -> []; _ -> [{cast, first, #wide{}}] end}")),
    ?assertError({duplicate_hls_statem_declaration, entry_output, [first, first]},
        analyze("{Cell, [{cast_if, false, first, #small{}}, {cast, first, #wide{}}]}" )).

unbounded_lists_are_rejected_test() ->
    ?assertException(error, {nonliteral_hls_statem_actions, _, _},
        analyze("{Cell, arbitrary_list()}")),
    ?assertException(error, {nonliteral_hls_statem_actions, _, _},
        analyze("Actions = [], {Cell, Actions}")).

reduction_must_precede_every_cast_on_its_path_test() ->
    ?assertException(error, {hls_statem_open_reduction_must_be_first, _},
        analyze("{Cell, [{cast, first, #small{}}] ++ [" ++ open("1") ++ "]}")),
    ?assertException(error, {hls_statem_open_reduction_must_be_first, _},
        analyze("{Cell, [" ++ open("1") ++ ", " ++ open("1") ++ "]}")).

conditional_open_is_reported_without_changing_the_site_test() ->
    #{reduction := Open} = analyze("{Cell, case Cell#cell.value of "
        "0 -> []; _ -> [" ++ open("Cell#cell.value") ++ "] end}"),
    ?assert(maps:get(opens_conditionally, Open)),
    #{reduction := Always} = analyze("{Cell, case Cell#cell.value of "
        "0 -> [" ++ open("Cell#cell.value") ++ "]; "
        "_ -> [" ++ open("Cell#cell.value") ++ "] end}"),
    ?assertNot(maps:get(opens_conditionally, Always)),
    ?assertError(inconsistent_hls_statem_entry_reductions,
        analyze("{Cell, case Cell#cell.value of 0 -> [" ++ open("1") ++ "]; "
            "_ -> [" ++ open("2") ++ "] end}" )).

variant_explosion_is_bounded_test() ->
    %% Nine independent empty-list choices would create 512 paths even
    %% without allocating any payload storage.
    Choice = "(case Cell#cell.value =:= 0 of true -> []; false -> [] end)",
    ?assertError({too_many_hls_statem_entry_variants, 256},
        analyze("{Cell, " ++ lists:flatten(lists:join(" ++ ",
            lists:duplicate(9, Choice))) ++ "}" )).

open(Key) ->
    "{open_reduction, sum, " ++ Key ++ ", {count, 1}, "
        "{commutative_monoid, #sum{value = 0}}}".

analyze(Body) ->
    {ok, Tokens, _} = erl_scan:string("entry(enter, _Old, Cell) -> " ++ Body ++ "."),
    {ok, {function, _, entry, 3, [Clause]}} = erl_parse:parse_form(Tokens),
    xls_statem_entry:analyze(Clause, [small, wide], [first, second, third]).
