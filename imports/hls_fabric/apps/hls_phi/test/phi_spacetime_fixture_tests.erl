-module(phi_spacetime_fixture_tests).
-include_lib("eunit/include/eunit.hrl").

%% A completion joins both coordinates, independent of frame catalogue ordering.
-spec both_completion_anchors_test() -> ok.
both_completion_anchors_test() ->
    {Summary, Capture = #{stream := #{frames := Frames}}} = fixture(),
    #{events := [First, Second], boundaries := [Boundary]} =
        phi_spacetime_fixture:bind_summary(Summary, Capture#{
            stream => #{frames => lists:reverse(Frames)}
        }),
    ?assertEqual([<<"status/0">>], maps:get(graph_events, First)),
    ?assertEqual([<<"status/1">>], maps:get(graph_events, Second)),
    ?assertEqual([<<"status/0">>, <<"status/1">>], maps:get(graph_events, Boundary)),
    ?assertEqual(<<"epoch/a">>, maps:get(graph_incarnation, Boundary)),
    ?assertEqual(7, maps:get(cycle, Boundary)).

%% Equal payloads at different FIFO occurrences retain different event identities.
-spec repeated_payload_occurrences_test() -> ok.
repeated_payload_occurrences_test() ->
    First = row(1, 0, 0, 4),
    Second = First#{ordinal => 1, cycle => 7},
    Summary = #{events => [First, Second], boundaries => []},
    Capture = capture([
        {First, <<"epoch/a">>, <<"first">>},
        {Second, <<"epoch/a">>, <<"second">>}
    ]),
    #{events := [BoundFirst, BoundSecond]} = phi_spacetime_fixture:bind_summary(Summary, Capture),
    ?assertEqual([<<"first">>], maps:get(graph_events, BoundFirst)),
    ?assertEqual([<<"second">>], maps:get(graph_events, BoundSecond)),
    Swapped = Summary#{events => [First#{ordinal => 1}, Second#{ordinal => 0}]},
    ?assertError(_, phi_spacetime_fixture:bind_summary(Swapped, Capture)).

%% A matching payload and cycle on another route cannot rescue a missing identity.
-spec route_is_part_of_identity_test() -> ok.
route_is_part_of_identity_test() ->
    {Summary = #{events := [First, Second]}, Capture} = fixture(),
    WrongRoute = First#{route => maps:get(route, First) + 1},
    ?assertError(
        _, phi_spacetime_fixture:bind_summary(Summary#{events => [WrongRoute, Second]}, Capture)
    ).

%% Selected occurrences must independently agree with their final-word cycle and bytes.
-spec occurrence_content_is_checked_test() -> ok.
occurrence_content_is_checked_test() ->
    {Summary = #{events := [First, Second]}, Capture} = fixture(),
    ?assertError(
        _,
        phi_spacetime_fixture:bind_summary(
            Summary#{events => [First#{cycle => 5}, Second]}, Capture
        )
    ),
    ?assertError(
        _,
        phi_spacetime_fixture:bind_summary(
            Summary#{events => [First#{words => [0]}, Second]}, Capture
        )
    ).

%% Existing graph endpoints cannot be exchanged between different frame occurrences.
-spec reordered_event_ids_rejected_test() -> ok.
reordered_event_ids_rejected_test() ->
    {Summary, Capture = #{stream := #{frames := [First, Second]}}} = fixture(),
    Swapped = [First#{event => maps:get(event, Second)}, Second#{event => maps:get(event, First)}],
    ?assertError(
        _, phi_spacetime_fixture:bind_summary(Summary, Capture#{stream => #{frames => Swapped}})
    ).

%% Neither absent transport occurrences nor absent graph endpoints may become anchors.
-spec missing_identities_rejected_test() -> ok.
missing_identities_rejected_test() ->
    {Summary,
        Capture = #{stream := #{frames := [First, _]}, bundle := Graph = #{events := [Event, _]}}} = fixture(),
    ?assertError(
        _, phi_spacetime_fixture:bind_summary(Summary, Capture#{stream => #{frames => [First]}})
    ),
    ?assertError(
        _,
        phi_spacetime_fixture:bind_summary(Summary, Capture#{bundle := Graph#{events := [Event]}})
    ).

%% Duplicate keys are ambiguous even when their values happen to be identical.
-spec duplicate_identities_rejected_test() -> ok.
duplicate_identities_rejected_test() ->
    {
        Summary = #{events := [Row | Rows]},
        Capture = #{
            stream := #{frames := [Frame | Frames]}, bundle := Graph = #{events := [Event | Events]}
        }
    } = fixture(),
    ?assertError(
        _,
        phi_spacetime_fixture:bind_summary(
            Summary, Capture#{stream => #{frames => [Frame, Frame | Frames]}}
        )
    ),
    ?assertError(
        _,
        phi_spacetime_fixture:bind_summary(Summary, Capture#{
            bundle := Graph#{events := [Event, Event | Events]}
        })
    ),
    ?assertError(
        _,
        phi_spacetime_fixture:bind_summary(
            Summary#{events => [Row, Row | Rows], boundaries => []}, Capture
        )
    ).

%% Reset partitions permit the same route and ordinal to identify a later occurrence.
-spec reset_reuses_ordinal_with_new_identity_test() -> ok.
reset_reuses_ordinal_with_new_identity_test() ->
    First = row(1, 0, 0, 4),
    Second = First#{incarnation => 2, cycle => 14},
    Summary = #{events => [First, Second], boundaries => []},
    Capture = capture([
        {First, <<"epoch/a">>, <<"before-reset">>},
        {Second, <<"epoch/b">>, <<"after-reset">>}
    ]),
    #{events := [BoundFirst, BoundSecond]} = phi_spacetime_fixture:bind_summary(Summary, Capture),
    ?assertEqual(<<"epoch/a">>, maps:get(graph_incarnation, BoundFirst)),
    ?assertEqual(<<"epoch/b">>, maps:get(graph_incarnation, BoundSecond)),
    ?assertEqual([<<"after-reset">>], maps:get(graph_events, BoundSecond)),
    StaleEpoch = Summary#{events => [First, Second#{incarnation => 1}]},
    ?assertError(_, phi_spacetime_fixture:bind_summary(StaleEpoch, Capture)).

%% A graph endpoint from a different incarnation cannot validate a public occurrence.
-spec cross_reset_endpoint_rejected_test() -> ok.
cross_reset_endpoint_rejected_test() ->
    {Summary, Capture = #{bundle := Graph = #{events := [First, Second]}}} = fixture(),
    ?assertError(
        _,
        phi_spacetime_fixture:bind_summary(
            Summary, Capture#{
                bundle := Graph#{events := [First#{incarnation => <<"epoch/b">>}, Second]}
            }
        )
    ).

%% Coordinates from different reset executions cannot complete one application step.
-spec cross_reset_completion_rejected_test() -> ok.
cross_reset_completion_rejected_test() ->
    First = row(1, 0, 0, 4),
    Second = row(2, 1, 0, 14),
    Summary = #{events => [First, Second], boundaries => [boundary(1, 14)]},
    Capture = capture([
        {First, <<"epoch/a">>, <<"before-reset">>},
        {Second, <<"epoch/b">>, <<"after-reset">>}
    ]),
    ?assertError(_, phi_spacetime_fixture:bind_summary(Summary, Capture)).

%% The half-open capture partition cannot lend its final clock to the retired epoch.
-spec capture_boundary_membership_test() -> ok.
capture_boundary_membership_test() ->
    Row = row(1, 0, 0, 10),
    Summary = #{events => [Row], boundaries => []},
    Capture = capture([{Row, <<"epoch/a">>, <<"at-reset">>}]),
    ?assertError(_, phi_spacetime_fixture:bind_summary(Summary, Capture)).

%% Exactly coordinates zero and one are required, with no duplicated status per step.
-spec incomplete_or_duplicate_coordinates_rejected_test() -> ok.
incomplete_or_duplicate_coordinates_rejected_test() ->
    {Summary = #{events := [First, Second]}, Capture} = fixture(),
    ?assertError(_, phi_spacetime_fixture:bind_summary(Summary#{events => [First]}, Capture)),
    WrongCoordinate = Second#{event => [phi_status, 1, 2, 0, 7]},
    ?assertError(
        _, phi_spacetime_fixture:bind_summary(Summary#{events => [First, WrongCoordinate]}, Capture)
    ),
    Duplicate = First#{ordinal => 2, cycle => 8},
    Three = capture([
        {First, <<"epoch/a">>, <<"status/0">>},
        {Second, <<"epoch/a">>, <<"status/1">>},
        {Duplicate, <<"epoch/a">>, <<"duplicate-status/0">>}
    ]),
    ?assertError(
        _,
        phi_spacetime_fixture:bind_summary(
            Summary#{events => [First, Second, Duplicate], boundaries => [boundary(1, 8)]}, Three
        )
    ).

%% A declared completion timestamp is checked against both accepted status frames.
-spec completion_timestamp_checked_test() -> ok.
completion_timestamp_checked_test() ->
    {Summary, Capture} = fixture(),
    ?assertError(
        _, phi_spacetime_fixture:bind_summary(Summary#{boundaries => [boundary(1, 6)]}, Capture)
    ),
    ?assertError(
        _, phi_spacetime_fixture:bind_summary(Summary#{boundaries => [boundary(1, 8)]}, Capture)
    ).

%% Minimal independently decoded application rows and transport identities for one step.
-spec fixture() -> {map(), map()}.
fixture() ->
    First = row(1, 0, 0, 4),
    Second = row(1, 1, 1, 7),
    {
        #{events => [First, Second], boundaries => [boundary(1, 7)]},
        capture([
            {First, <<"epoch/a">>, <<"status/0">>},
            {Second, <<"epoch/a">>, <<"status/1">>}
        ])
    }.

%% Values need not invoke a codec: bind_summary validates occurrence identity, not decoding.
-spec row(pos_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) -> map().
row(Epoch, Coordinate, Ordinal, Cycle) ->
    Route = 16#00070002,
    #{
        incarnation => Epoch,
        route => Route,
        ordinal => Ordinal,
        cycle => Cycle,
        stream => status,
        event => [phi_status, 1, Coordinate, 0, 7],
        words => [Route, 16#41000002, Coordinate, 7]
    }.

%% Application completion records are independent of their later graph annotations.
-spec boundary(pos_integer(), non_neg_integer()) -> map().
boundary(Epoch, Cycle) -> #{incarnation => Epoch, step => 1, cycle => Cycle}.

%% Supply only the checked subset consumed by the binder; generic bundle validation is separate.
-spec capture([{map(), binary(), binary()}]) -> map().
capture(Occurrences) ->
    Frames = [
        #{
            incarnation => Epoch,
            route => maps:get(route, Row),
            ordinal => maps:get(ordinal, Row),
            cycle => maps:get(cycle, Row),
            words => maps:get(words, Row),
            event => Id
        }
     || {Row, Epoch, Id} <- Occurrences
    ],
    Events = [
        #{id => Id, cycle => maps:get(cycle, Row), incarnation => Epoch}
     || {Row, Epoch, Id} <- Occurrences
    ],
    #{
        bundle => #{
            capture => #{
                incarnations => [
                    #{id => <<"epoch/a">>, first_cycle => 0, end_cycle => 10},
                    #{id => <<"epoch/b">>, first_cycle => 10, end_cycle => 20}
                ]
            },
            events => Events
        },
        stream => #{frames => Frames}
    }.
