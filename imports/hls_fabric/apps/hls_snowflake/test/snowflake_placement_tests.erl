-module(snowflake_placement_tests).
-moduledoc "Checks that execution placement changes storage, not logical vertex identities or neighbor routes.".
-include_lib("eunit/include/eunit.hrl").
-include("snowflake_actor_protocol.hrl").

%% Tree aggregation changes only status destinations and the coordinator's expected population.
-spec tree_routes_test() -> ok.
tree_routes_test() ->
    Flat = snowflake_actor_topology:topology(),
    Tree = snowflake_actor_topology:topology(3, 3, #{barrier => tree6}),
    ?assertEqual(Flat, snowflake_actor_topology:topology(3, 3, #{barrier => flat, vertex_groups => 0})),
    ?assertEqual(37, map_size(maps:get(actors, Flat))),
    ?assertEqual(43, map_size(maps:get(actors, Tree))),
    ?assertEqual(non_status_routes(Flat), non_status_routes(Tree)),
    lists:foreach(fun(Source) ->
        ?assertEqual([{{{vertex, Source}, status}, [{actor, {barrier, Source div 6}}]}],
            [Route || Route = {{{vertex, I}, status}, _} <- maps:get(routes, Tree), I =:= Source])
    end, lists:seq(0, 35)),
    ?assertEqual([#sf_coordinator_config{count = 6, height = 3}],
        proplists:get_value(coordinator, maps:get(startup, Tree))),
    lists:foreach(fun(Branch) ->
        ?assertEqual([#sf_barrier_config{source = Branch, first = 6 * Branch, count = 6}],
            proplists:get_value({barrier, Branch}, maps:get(startup, Tree)))
    end, lists:seq(0, 5)).

%% Every exact actor occupies one slot; direct control actors never enter a shared bank.
-spec groups_test() -> ok.
groups_test() ->
    lists:foreach(fun(GroupCount) ->
        Options = #{barrier => tree6, vertex_groups => GroupCount},
        Plan = hls_topology:normalize(snowflake_actor_topology:topology(3, 3, Options)),
        #{scheduler_groups := Specs} = snowflake_actor_topology:profile(3, 3, Options),
        #{groups := Groups, direct_members := Direct} = hls_scheduler_plan:normalize(Plan, Specs),
        ?assertEqual(GroupCount, length(Groups)),
        ?assertEqual(lists:sort([{actor, coordinator} | [{actor, {barrier, I}} || I <- lists:seq(0, 5)]]), Direct),
        ?assertEqual(lists:seq(0, 35), [Source || #{members := Members} <- Groups,
            #{id := {vertex, Source}} <- Members]),
        lists:foreach(fun(Group) ->
            ?assertEqual(block_ram, maps:get(state_storage, Group)),
            ?assertEqual(block_ram, maps:get(mailbox_storage, Group)),
            ?assertEqual(24, maps:get(mailbox_capacity, Group)),
            ?assertEqual(36 div GroupCount, maps:get(slot_count, Group)),
            ?assertEqual(lists:seq(0, 36 div GroupCount - 1),
                [Slot || #{base_slot := Slot} <- maps:get(members, Group)])
        end, Groups)
    end, [6, 12]).

%% Reassigning execution preserves the actor graph and makes every slot identity explicit.
-spec explicit_order_test() -> ok.
explicit_order_test() ->
    Order = lists:reverse(lists:seq(0, 35)),
    Options = #{barrier => tree6, vertex_groups => 6, vertex_order => Order},
    Topology = snowflake_actor_topology:topology(3, 3, Options),
    ?assertEqual(snowflake_actor_topology:topology(3, 3, maps:remove(vertex_order, Options)), Topology),
    #{scheduler_groups := Specs} = snowflake_actor_topology:profile(3, 3, Options),
    #{groups := Groups} = hls_scheduler_plan:normalize(hls_topology:normalize(Topology), Specs),
    Expected = lists:append([lists:sort(lists:sublist(Order, I * 6 + 1, 6)) || I <- lists:seq(0, 5)]),
    ?assertEqual(Expected, [Source || #{members := Members} <- Groups,
        #{id := {vertex, Source}} <- Members]),
    ?assertError({vertex_order, [0, 0], 36},
        snowflake_actor_topology:profile(3, 3, Options#{vertex_order => [0, 0]})),
    ?assertError(vertex_order_requires_schedulers,
        snowflake_actor_topology:profile(3, 3, Options#{vertex_groups => 0})).

%% Invalid divisions and option names must fail before emitting a misleading placement.
-spec invalid_placement_test() -> ok.
invalid_placement_test() ->
    ?assertError({vertex_group_placement, 12, 150},
        snowflake_actor_topology:profile(5, 5, #{vertex_groups => 12})),
    ?assertError({vertex_group_placement, 5, 36},
        snowflake_actor_topology:profile(3, 3, #{vertex_groups => 5})),
    ?assertError({barrier_placement, binary, 36},
        snowflake_actor_topology:topology(3, 3, #{barrier => binary})),
    ?assertError({placement_options, [groups]},
        snowflake_actor_topology:profile(3, 3, #{groups => 6})).

%% Bindings, codegen options and wrapper wires describe the same normalized RAM banks.
-spec emitted_bindings_test_() -> term().
emitted_bindings_test_() ->
    {timeout, 30, fun() ->
        Directory = filename:join("_build/snowflake-placement-tests", integer_to_list(erlang:unique_integer([positive]))),
        try
            ok = snowflake_actor_topology:write(3, 3, Directory, #{barrier => tree6, vertex_groups => 12}),
            {ok, Json} = file:read_file(filename:join(Directory, "placement.json")),
            Manifest = json:decode(Json),
            ?assertEqual(<<"snowflake_actor_wrapper">>, maps:get(<<"top_module">>, Manifest)),
            ?assertEqual(6, maps:get(<<"coordinator_population">>, Manifest)),
            ?assertEqual(12, length(maps:get(<<"scheduler_groups">>, Manifest))),
            ?assertEqual(lists:seq(0, 35), [Source || #{<<"members">> := Members} <- maps:get(<<"scheduler_groups">>, Manifest),
                #{<<"source">> := Source} <- Members]),
            Configs = binary:split(maps:get(<<"ram_configurations">>, Manifest), <<",">>, [global]),
            ?assertEqual(24, length(Configs)),
            {ok, Wrapper} = file:read_file(filename:join(Directory, "snowflake_actor_wrapper.v")),
            {ok, Actor} = file:read_file(filename:join(Directory, "snowflake_vertex.x")),
            {match, [WidthText]} = re:run(Actor, "pub type MachineBits = bits\\[([0-9]+)\\]", [{capture, [1], binary}]),
            MachineWidth = binary_to_integer(WidthText),
            lists:foreach(fun(#{<<"index">> := I, <<"state_width">> := Width} = Binding) ->
                ?assertEqual(MachineWidth, Width),
                ?assertEqual(2, maps:get(<<"state_address_width">>, Binding)),
                ?assertEqual(7, maps:get(<<"mailbox_address_width">>, Binding)),
                Stem = iolist_to_binary(["scheduler_", integer_to_list(I)]),
                Declaration = iolist_to_binary(["wire [", integer_to_list(Width - 1), ":0] ", Stem, "_state_wr_data"]),
                ?assertNotEqual(nomatch, binary:match(Wrapper, Declaration)),
                ?assertEqual(2, length([C || C <- Configs, binary:match(C, <<Stem/binary, "_">>) =:= {0, byte_size(Stem) + 1}]))
            end, maps:get(<<"ram_bindings">>, Manifest)),
            lists:foreach(fun(Filename) -> ?assert(filelib:is_regular(filename:join(Directory, binary_to_list(Filename)))) end,
                maps:get(<<"rtl_assets">>, Manifest) ++ maps:get(<<"actor_dslx">>, Manifest))
        after
            file:del_dir_r(Directory)
        end
    end}.

%% Exclude leaf and branch status routes while retaining every other logical edge.
-spec non_status_routes(hls_topology:spec()) -> [tuple()].
non_status_routes(#{routes := Routes}) ->
    [Route || Route <- Routes, element(2, element(1, Route)) =/= status].
