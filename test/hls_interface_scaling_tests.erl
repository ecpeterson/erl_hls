-module(hls_interface_scaling_tests).

-include_lib("eunit/include/eunit.hrl").

%% Count actual source reads instead of imposing a machine-dependent timeout.
%% Each boundary must still read again: an earlier successful query is not a
%% license to reuse interfaces after a header or loaded module changes.
population_and_fanout_do_not_multiply_source_reads_test() ->
    lists:foreach(fun({Count, Fanout}) ->
        Spec = exact_topology(Count, Fanout),
        {Plan, 1} = source_reads(fun() -> hls_topology:normalize(Spec) end),
        ?assertEqual(Count, length(maps:get(actors, Plan))),
        {_, 1} = source_reads(fun() -> xls_topology_dslx:emit(Plan, profile()) end),
        {_, 1} = source_reads(fun() -> hls_topology:normalize(Spec) end),
        Groups = maps:from_list([{Id, #{members => [{actor, Id}],
            state_storage => registers, mailbox_storage => registers}}
            || #{id := Id} <- maps:get(actors, Plan)]),
        {#{groups := Scheduled}, 1} = source_reads(fun() ->
            hls_scheduler_plan:normalize(Plan, Groups)
        end),
        ?assertEqual(Count, length(Scheduled))
    end, [{1, 1}, {32, 1}, {32, 8}]).

family_count_and_dimensions_do_not_multiply_source_reads_test() ->
    lists:foreach(fun({Count, Dimension}) ->
        Spec = family_topology(Count, Dimension),
        {Plan, 1} = source_reads(fun() -> hls_topology:normalize(Spec) end),
        ?assertEqual(Count, length(maps:get(families, Plan))),
        %% Family emission runs reduction planning and interface annotation;
        %% each pass reads once per distinct module, not once per family.
        {_, 2} = source_reads(fun() -> xls_topology_dslx:emit(Plan, profile()) end)
    end, [{1, 1}, {12, 1}, {12, 8}]).

exact_and_family_sections_share_interface_resolution_test() ->
    Exact = exact_topology(4, 1),
    Family = family_topology(4, 2),
    Mixed = Exact#{families := maps:get(families, Family),
        route_relations := maps:get(route_relations, Family)},
    {_, 1} = source_reads(fun() -> hls_topology:normalize(Mixed) end).

source_reads(Fun) ->
    {module, hls_source} = code:ensure_loaded(hls_source),
    Session = trace:session_create(interface_scaling, self(), []),
    try
        1 = trace:function(Session, {hls_source, read, 2}, true, [call_count]),
        Result = Fun(),
        {call_count, Count} = trace:info(Session, {hls_source, read, 2}, call_count),
        {Result, Count}
    after
        trace:session_destroy(Session)
    end.

profile() -> #{name => interface_scaling, channel_depth => 1,
    actor_egress_depth => burst}.

exact_topology(Count, Fanout) ->
    Externals = lists:sublist([out_a, out_b, out_c, out_d, out_e, out_f, out_g, out_h], Fanout),
    Ids = [{actor, N} || N <- lists:seq(1, Count)],
    (empty_topology())#{
        actors := maps:from_list([{Id, hls_topology_source_fixture} || Id <- Ids]),
        externals := [{Id, out, [message]} || Id <- Externals],
        routes := [{{Id, out}, queued,
            [{actor, Id} | [{external, E} || E <- Externals]]} || Id <- Ids]
    }.

family_topology(Count, Dimension) ->
    Ids = [{family, N} || N <- lists:seq(1, Count)],
    (empty_topology())#{
        families := maps:from_list([{Id, #{module => hls_topology_source_fixture,
            shape => [Dimension, Dimension]}} || Id <- Ids]),
        externals := [{out_a, out, [message]}],
        route_relations := [{{Id, out}, queued,
            [{family, Id, {translate, [0, 0], wrap}}, {external, out_a}]} || Id <- Ids]
    }.

empty_topology() -> #{version => 1, actors => #{}, families => #{},
    externals => [], routes => [], route_relations => [], startup => [], ingresses => []}.
