-module(hls_topology_ingress_tests).
-include_lib("eunit/include/eunit.hrl").

point_recipients_are_checked_at_the_declaration_boundary_test() ->
    lists:foreach(fun(Point) ->
        ?assertError({ingress_point, extra, Point, [7, 6]},
            hls_topology:normalize(spec([{actor, extra, {at, Point}}])))
    end, [[-1, 2], [7, 2], [5, 6], [5, 2.0], [5]]),
    lists:foreach(fun(Id) ->
        ?assertError({unknown_actor, Id, ingress},
            hls_topology:normalize(spec([{actor, Id, {at, [5, 2]}}])))
    end, [missing, {workers, 0, 0}]).

point_address_is_consistent_across_targets_test() ->
    Spec = spec([{actor, extra, {at, [5, 2]}}]),
    ?assertError({ingress_embeddings, commands, {actor, extra}, [[4, 2], [5, 2]]},
        hls_topology:normalize(Spec#{ingresses := [{commands, {rectangle, [7, 6]}, [
            {one, [work], [{actor, extra, {at, [5, 2]}}]},
            {two, [work], [{actor, extra, {at, [4, 2]}}]}]}]})).

exact_only_ingress_uses_the_same_contract_test() ->
    Spec = spec([{actor, extra, {at, [5, 2]}}]),
    Plan = hls_topology:normalize(Spec#{families := #{}, route_relations := []}),
    lists:foreach(fun(Groups) ->
        Text = iolist_to_binary(xls_topology_dslx:emit(Plan, profile(Groups))),
        ?assertNotEqual(nomatch, binary:match(Text, <<"spawn IngressRouter0">>)),
        ?assertNotEqual(nomatch, binary:match(Text,
            <<"contains(packet.rectangle, u16:5, u16:2)">>))
    end, [#{}, #{singleton => #{members => [{actor, extra}],
        state_storage => block_ram, mailbox_storage => block_ram}}]).

mixed_targets_require_dispatched_schemas_test() ->
    Spec = spec([{actor, extra, {at, [5, 2]}}]),
    ?assertError({ingress_schemas, all, {actor, extra}, [kick]},
        hls_topology:normalize(Spec#{ingresses := [{commands, {rectangle, [7, 6]}, [
            {all, [kick], [{actor, extra, {at, [5, 2]}}]}]}]})).

mixed_target_layout_mismatch_is_rejected_test() ->
    Spec = #{version => 1, actors => #{sink => hls_topology_source_fixture},
        families => #{cells => #{module => hls_topology_layout_fixture, shape => [1, 1]}},
        externals => [{values, out, [message]}, {others, out, [message]}],
        routes => [{{sink, out}, [{external, values}]}],
        route_relations => [{{cells, out}, [{external, others}]}], startup => [],
        ingresses => [{commands, {rectangle, [2, 1]}, [{all, [message], [
            {actor, sink, {at, [1, 0]}}, {family, cells, {embed, [1, 1], [0, 0]}}]}]}]},
    ?assertException(error, {ingress_layouts, all, message, _}, hls_topology:normalize(Spec)).

mixed_target_selector_mismatch_is_rejected_test() ->
    %% Both modules dispatch message:u32, but allocate different numeric tags.
    Spec = #{version => 1, actors => #{sink => hls_topology_source_fixture},
        families => #{cells => #{module => hls_topology_reordered_fixture, shape => [1, 1]}},
        externals => [{values, out, [message]}, {others, out, [message]}, {padding, out, [padding]}],
        routes => [{{sink, out}, [{external, values}]}],
        route_relations => [{{cells, message_out}, [{external, others}]},
            {{cells, padding_out}, [{external, padding}]}], startup => [],
        ingresses => [{commands, {rectangle, [2, 1]}, [{all, [message], [
            {actor, sink, {at, [1, 0]}}, {family, cells, {embed, [1, 1], [0, 0]}}]}]}]},
    Plan = hls_topology:normalize(Spec),
    ?assertException(error, {ingress_encoding, all, message, _},
        xls_topology_dslx:emit(Plan, profile(#{}))).

aliased_targets_have_one_lane_per_recipient_test() ->
    lists:foreach(fun(Placement) ->
        {Plan, Groups} = hls_mixed_topology_dslx:fixture({ingress, Placement}),
        Text = iolist_to_binary(xls_topology_dslx:emit(Plan, profile(Groups))),
        ?assertEqual(5, length(binary:matches(Text, <<"send_if(tok, lane_">>))),
        %% The boundary schema is shared by every target and placement.
        ?assertNotEqual(nomatch, binary:match(Text, <<"frame.header.payload_words == u8:1">>))
    end, [direct, one, two, coalesced]).

cpu_external_commands_match_closed_graph_test() ->
    ?assertEqual(hls_mixed_topology_dslx:cpu(), hls_mixed_topology_dslx:cpu({ingress, direct})).

profile(Groups) -> #{name => ingress_fixture, channel_depth => 1, actor_egress_depth => 0, scheduler_groups => Groups}.

spec(Recipients) ->
    #{version => 1, actors => #{extra => hls_mixed_worker},
        families => #{workers => #{module => hls_mixed_worker, shape => [2, 2]}},
        externals => [{results, out, [result]}], startup => [],
        routes => [{{extra, Port}, [{external, results}]} || Port <- [result_a, result_b]],
        route_relations => [{{workers, Port}, [{external, results}]} || Port <- [result_a, result_b]],
        ingresses => [{commands, {rectangle, [7, 6]}, [{all, [work], Recipients}]}]}.
