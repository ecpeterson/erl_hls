-module(hls_mixed_topology_tests).

-include_lib("eunit/include/eunit.hrl").

crossing_routes_retain_logical_identities_test() ->
    Plan = hls_topology:normalize(topology()),
    ?assertEqual([sink, source], [Id || #{id := Id} <- maps:get(actors, Plan)]),
    ?assertEqual([workers], [Id || #{id := Id} <- maps:get(families, Plan)]),
    ?assertEqual(#{source => {source, out}, delivery => direct,
        recipients => [{actor, {workers, 1, 2}}]},
        route(maps:get(routes, Plan), {source, out})),
    ?assertEqual([#{source => {workers, out}, delivery => direct,
        recipients => [{actor, sink}]}], maps:get(route_relations, Plan)),
    lists:foreach(fun(Coordinates) ->
        Id = list_to_tuple([workers | Coordinates]),
        ?assertEqual([#{source => {Id, out}, delivery => direct,
            recipients => [{actor, sink}]}],
            hls_topology:routes_for_instance(Plan, workers, Coordinates))
    end, [[0, 0], [1, 2]]),
    ?assertEqual(#{source => source, destination => {actor, {workers, 1, 2}},
        source_ports => [out]}, lane(maps:get(lanes, Plan), source, {actor, {workers, 1, 2}})),
    ?assertEqual([#{source => workers, destination => {actor, sink},
        source_ports => [out]}], maps:get(lane_relations, Plan)).

crossing_relations_remain_compact_test() ->
    Spec = topology(),
    Small = hls_topology:normalize(Spec),
    Large = hls_topology:normalize(Spec#{families := #{workers => #{
        module => hls_topology_source_fixture, shape => [500, 300]}}}),
    lists:foreach(fun(Key) ->
        ?assertEqual(maps:get(Key, Small), maps:get(Key, Large))
    end, [actors, routes, route_relations, lanes, lane_relations]).

crossing_input_order_is_canonical_test() ->
    Spec = topology(),
    ?assertEqual(hls_topology:normalize(Spec), hls_topology:normalize(Spec#{
        routes := lists:reverse(maps:get(routes, Spec)),
        route_relations := lists:reverse(maps:get(route_relations, Spec))})).

fixed_actor_and_translated_family_can_share_fanout_test() ->
    Spec = topology(),
    Recipients = [{actor, sink}, {family, workers, {translate, [1, -1], wrap}}],
    Plan = hls_topology:normalize(Spec#{route_relations := [
        {{workers, out}, queued, Recipients}]}),
    [Relation] = maps:get(route_relations, Plan),
    ?assertEqual(queued, maps:get(delivery, Relation)),
    ?assertEqual(Recipients, maps:get(recipients, Relation)),
    [Resolved] = hls_topology:routes_for_instance(Plan, workers, [1, 0]),
    ?assertEqual([{actor, sink}, {actor, {workers, 0, 2}}], maps:get(recipients, Resolved)).

exact_source_can_fan_out_to_distinct_family_members_test() ->
    Spec = topology(),
    Recipients = [{actor, {workers, 0, 0}}, {actor, {workers, 1, 2}}],
    Plan = hls_topology:normalize(replace_route(Spec,
        {{source, out}, queued, lists:reverse(Recipients)})),
    ?assertEqual(#{source => {source, out}, delivery => queued,
        recipients => Recipients}, route(maps:get(routes, Plan), {source, out})).

aliased_crossing_ports_share_one_lane_test() ->
    Plan = hls_topology:normalize(alias_topology()),
    Ports = [message_out, padding_out],
    ?assertEqual(Ports, maps:get(source_ports,
        lane(maps:get(lanes, Plan), source, {actor, {workers, 1, 2}}))),
    ?assertEqual([#{source => workers, destination => {actor, sink},
        source_ports => Ports}], maps:get(lane_relations, Plan)).

family_member_recipients_are_bounded_test() ->
    lists:foreach(fun(Id) ->
        ?assertError({invalid_family_instance, Id, [2, 3]},
            hls_topology:normalize(replace_route(topology(),
                {{source, out}, [{actor, Id}]})))
    end, [{workers, -1, 0}, {workers, 2, 0}, {workers, 0, 3}, {workers, 0, 1.0}]),
    lists:foreach(fun(Id) ->
        ?assertError({unknown_actor, Id, {route_recipient, {source, out}}},
            hls_topology:normalize(replace_route(topology(),
                {{source, out}, [{actor, Id}]})))
    end, [{workers, 0}, {workers, 0, 0, 0}, {missing, 0, 0}]).

exact_tuple_actor_takes_precedence_over_family_lookup_test() ->
    Spec = topology(),
    Sink = {workers, 9, 0},
    Plan = hls_topology:normalize(Spec#{
        actors := #{source => hls_topology_source_fixture, Sink => hls_topology_source_fixture},
        routes := [{{source, out}, [{actor, Sink}]}, {{Sink, out}, [{external, values}]}],
        route_relations := [{{workers, out}, [{actor, Sink}]}],
        startup := [{Sink, [{message, 7}]}]}),
    ?assertEqual([{actor, Sink}], maps:get(recipients,
        route(maps:get(routes, Plan), {source, out}))),
    ?assertEqual([#{target => Sink, delivery => cast, messages => [{message, 7}]}],
        maps:get(startup, Plan)).

exact_actor_cannot_shadow_family_or_member_test() ->
    Spec = topology(),
    lists:foreach(fun(Id) ->
        ?assertError({actor_family_id_collisions, [Id]}, hls_topology:normalize(
            Spec#{actors := (maps:get(actors, Spec))#{Id => hls_topology_source_fixture}}))
    end, [workers, {workers, 1, 2}]).

family_relation_fixed_actor_must_be_exact_test() ->
    lists:foreach(fun(Id) ->
        Spec = (topology())#{route_relations := [{{workers, out}, [{actor, Id}]}]},
        ?assertError({unknown_actor, Id, {route_relation_recipient, {workers, out}}},
            hls_topology:normalize(Spec))
    end, [missing, {workers, 0, 0}]).

crossing_sources_remain_total_and_separate_test() ->
    Spec = topology(),
    ?assertError({unrouted_outputs, [{source, out}]},
        hls_topology:normalize(Spec#{routes := [{{sink, out}, [{external, values}]}]})),
    ?assertError({unrouted_family_outputs, [{workers, out}]},
        hls_topology:normalize(Spec#{route_relations := []})),
    ?assertError({unknown_actor, {workers, 0, 0}, route_source},
        hls_topology:normalize(Spec#{routes := maps:get(routes, Spec) ++ [
            {{{workers, 0, 0}, out}, [{actor, sink}]}]})).

duplicate_crossing_recipients_are_rejected_test() ->
    Member = {actor, {workers, 1, 2}},
    ?assertError({duplicate_route_recipients, {source, out}, [Member]},
        hls_topology:normalize(replace_route(topology(),
            {{source, out}, queued, [Member, Member]}))),
    ?assertError({duplicate_route_relation_recipients, {workers, out}, [{actor, sink}]},
        hls_topology:normalize((topology())#{route_relations := [
            {{workers, out}, queued, [{actor, sink}, {actor, sink}]}]})).

exact_to_family_schema_contract_is_checked_test() ->
    Spec = topology(),
    ?assertError({incompatible_route_schemas, {source, padding_out},
        {actor, {workers, 1, 2}}, [padding], [message]},
        hls_topology:normalize(Spec#{
            actors := (maps:get(actors, Spec))#{source := hls_topology_reordered_fixture},
            routes := [{{source, padding_out}, [{actor, {workers, 1, 2}}]},
                {{source, message_out}, [{external, values}]},
                {{sink, out}, [{external, values}]}]})).

family_to_exact_schema_contract_is_checked_test() ->
    Spec = topology(),
    ?assertError({incompatible_route_schemas, {workers, padding_out},
        {actor, sink}, [padding], [message]},
        hls_topology:normalize(Spec#{families := #{workers => #{
            module => hls_topology_reordered_fixture, shape => [2, 3]}},
            route_relations := [{{workers, padding_out}, [{actor, sink}]},
                {{workers, message_out}, [{external, values}]}]})).

exact_to_family_schema_layout_is_checked_test() ->
    Spec = topology(),
    SourceFields = fields(u32),
    DestinationFields = fields(u64),
    ?assertError({incompatible_route_schema_layout, {source, out},
        {actor, {workers, 1, 2}}, message, SourceFields, DestinationFields},
        hls_topology:normalize(Spec#{families := #{workers => #{
            module => hls_topology_layout_fixture, shape => [2, 3]}}})).

family_to_exact_schema_layout_is_checked_test() ->
    Spec = topology(),
    SourceFields = fields(u32),
    DestinationFields = fields(u64),
    ?assertError({incompatible_route_schema_layout, {workers, out},
        {actor, sink}, message, SourceFields, DestinationFields},
        hls_topology:normalize(Spec#{
            actors := (maps:get(actors, Spec))#{sink := hls_topology_layout_fixture}})).

topology() ->
    #{version => 1,
        actors => #{source => hls_topology_source_fixture, sink => hls_topology_source_fixture},
        families => #{workers => #{module => hls_topology_source_fixture, shape => [2, 3]}},
        externals => [{values, out, [message]}], ingresses => [], startup => [],
        routes => [{{source, out}, [{actor, {workers, 1, 2}}]},
            {{sink, out}, [{external, values}]}],
        route_relations => [{{workers, out}, [{actor, sink}]}]}.

alias_topology() ->
    Spec = topology(),
    Spec#{actors := #{source => hls_topology_reordered_fixture, sink => hls_topology_reordered_fixture},
        families := #{workers => #{module => hls_topology_reordered_fixture, shape => [2, 3]}},
        externals := [{values, out, [message, padding]}],
        routes := [{{source, Port}, [{actor, {workers, 1, 2}}]} || Port <- [message_out, padding_out]] ++
            [{{sink, Port}, [{external, values}]} || Port <- [message_out, padding_out]],
        route_relations := [{{workers, Port}, [{actor, sink}]} || Port <- [message_out, padding_out]]}.

replace_route(Spec = #{routes := Routes}, Route) ->
    Source = element(1, Route),
    Spec#{routes := [Route | [R || R <- Routes, element(1, R) =/= Source]]}.

route(Routes, Source) ->
    hd([Route || Route = #{source := Candidate} <- Routes, Candidate =:= Source]).

lane(Lanes, Source, Destination) ->
    hd([Lane || Lane = #{source := S, destination := D} <- Lanes,
        S =:= Source, D =:= Destination]).

fields(Type) -> [#{name => value, type => {hls_type, hls_nums, Type, []}}].
