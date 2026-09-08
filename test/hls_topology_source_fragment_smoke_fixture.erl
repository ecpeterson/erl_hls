%%%% hls_topology_source_fragment_smoke_fixture
%%%%
%%%% Small generated-DSLX fixtures shared by the native converter smoke test.

-module(hls_topology_source_fragment_smoke_fixture).

-export([write/1]).

-define(ACTOR, hls_topology_source_fragment_fixture).

write(Stage) ->
    Artifacts = [
        {"hls_topology_source_fragment_fixture.x", actor()},
        {"hls_topology_source_fragment_topology.x", topology(single)},
        {"hls_topology_source_fragment_sharded.x", topology(sharded)},
        {"hls_topology_source_fragment_muxed.x", topology(muxed)}
    ],
    lists:foreach(fun({Name, Contents}) ->
        ok = file:write_file(filename:join(Stage, Name), Contents)
    end, Artifacts),
    ok.

actor() ->
    xls_parse:to_xls(
        "test/hls_topology_source_fragment_fixture.erl",
        #{shared_service => aggregate_only}
    ).

topology(single) ->
    emit(
        source_fragment_semantics,
        [reducer],
        #{reducer => group([{family, reducer}])}
    );
topology(sharded) ->
    emit(
        source_fragment_sharded_smoke,
        [reducer],
        #{
            reducer_even => group([
                {family, reducer, {interleaved, 0, 2}}
            ]),
            reducer_odd => group([
                {family, reducer, {interleaved, 1, 2}}
            ])
        }
    );
topology(muxed) ->
    emit(
        source_fragment_muxed_smoke,
        [reducer_a, reducer_b],
        #{combined => group([
            {family, reducer_a},
            {family, reducer_b}
        ])}
    ).

emit(Name, Families, Groups) ->
    Topology = hls_topology:normalize(#{
        version => 1,
        ingresses => [],
        actors => #{},
        families => maps:from_list([
            {Family, #{module => ?ACTOR, shape => [3, 3]}}
            || Family <- Families
        ]),
        externals => [{reports, out, [notice]}],
        routes => [],
        route_relations => lists:append([
            relations(Family) || Family <- Families
        ]),
        startup => []
    }),
    Profile = #{
        name => Name,
        channel_depth => 1,
        actor_egress_depth => burst,
        scheduler_groups => Groups,
        reduction_placements => maps:from_list([
            {Family, source_fragments} || Family <- Families
        ])
    },
    xls_topology_dslx:emit(Topology, Profile).

relations(Family) ->
    [
        {{Family, north}, [
            {family, Family, {translate, [0, -1], wrap}}
        ]},
        {{Family, south}, [
            {family, Family, {translate, [0, 1], wrap}}
        ]},
        {{Family, report}, [{external, reports}]}
    ].

group(Members) ->
    #{
        members => Members,
        state_storage => block_ram,
        mailbox_storage => block_ram
    }.
