-module(hls_protocol_routing_tests).
-moduledoc "Pure deployment graph checks, independent of compilation, sessions and transport processes.".
-include_lib("eunit/include/eunit.hrl").

%% Arbitrary role keys and both wire-index extremes survive planning without changing link metadata.
-spec routes_test() -> ok.
routes_test() ->
    Input = #{devices := Devices} = deployment(),
    Plan = hls_protocol_routing:plan(Input),
    ?assertEqual(lists:sort([north, 42, {tile, south}]), hls_protocol_routing:roles(Plan)),
    #{links := [First, Last]} = maps:get(north, Devices),
    ?assertEqual(#{0 => #{from => north, to => 42, link => First},
                  65535 => #{from => north, to => {tile, south}, link => Last}},
                 hls_protocol_routing:routes(Plan)),
    ok.

%% Complete ownership rejects missing, repeated, unknown and malformed actor indices.
-spec ownership_test() -> ok.
ownership_test() ->
    P = #{devices := Devices} = deployment(),
    Middle = maps:get(42, Devices),
    reject([P#{actors := 4}] ++
        [P#{devices := Devices#{42 := Middle#{native_indices := Indices}}}
        || Indices <- [[0], [1, 1], [3], [-1], [1.5], [actor]]]),
    ok.

%% Every descriptor must be present and well formed; nothing is filtered away by its shape.
-spec descriptor_test() -> ok.
descriptor_test() ->
    P = deployment(),
    reject([change(north, Fun, P) || Fun <- [
        fun(L) -> maps:remove(direction, L) end,
        fun(L) -> L#{direction := internal} end,
        fun(L) -> maps:remove(classes, L) end,
        fun(_) -> not_a_link end,
        fun(L) -> L#{index := -1} end,
        fun(L) -> L#{index := 65536} end,
        fun(L) -> L#{index := 0.0} end,
        fun(L) -> L#{source_index := 9} end,
        fun(L) -> L#{destination_index := 9} end,
        fun(L) -> L#{source_index := 1} end,
        fun(L) -> L#{source_index := 2} end,
        fun(L) -> L#{destination_index := 0} end]]),
    ?assertError({wrong_route_owner, 0, incoming, {tile, south}, 42},
        hls_protocol_routing:plan(change(42, fun(L) -> L#{destination_index := 2} end, P))),
    ok.

%% Incoming and outgoing indices pair exactly once and carry the same actor/class contract.
-spec peers_test() -> ok.
peers_test() ->
    P = #{devices := Devices} = deployment(),
    #{links := Outgoing} = Source = maps:get(north, Devices),
    #{links := Incoming} = Target = maps:get(42, Devices),
    ?assertError({duplicate_route, outgoing, 0}, hls_protocol_routing:plan(
        P#{devices := Devices#{north := Source#{links := Outgoing ++ Outgoing}}})),
    ?assertError({duplicate_route, incoming, 0}, hls_protocol_routing:plan(
        P#{devices := Devices#{42 := Target#{links := Incoming ++ Incoming}}})),
    ?assertError({unpaired_routes, [0], []}, hls_protocol_routing:plan(
        P#{devices := Devices#{42 := Target#{links := []}}})),
    ?assertError({unpaired_routes, [], [0]}, hls_protocol_routing:plan(
        P#{devices := Devices#{north := Source#{links := tl(Outgoing)}}})),
    reject([change(42, fun(L) -> L#{classes := [#{slot => 0, codec => #{other => codec}}]} end, P),
        change(42, fun(L) -> L#{source_index := 2} end, P)]),
    ok.

%% Slot uniqueness is checked before a map could collapse two credits into one.
-spec classes_test() -> ok.
classes_test() ->
    P = deployment(),
    Class = #{slot => 0, codec => #{}},
    reject([change(north, fun(L) -> L#{classes := Classes} end, P) || Classes <- [
        [], not_a_list, [Class, Class], [Class#{slot := -1}], [Class#{slot := 256}],
        [Class#{slot := 0.0}], [maps:remove(slot, Class)],
        [maps:remove(codec, Class)], [Class#{codec := not_a_map}], [not_a_class]]]),
    ok.

%% The limit is a strict positive bound on actual crossing records, not a session count.
-spec bounds_test() -> ok.
bounds_test() ->
    P = #{devices := Devices} = deployment(),
    ?assertError({invalid_crossing_count, 2, 1},
        hls_protocol_routing:plan(P#{limits := #{crossings => 1}})),
    Empty = maps:map(fun(_, Device) -> Device#{links := []} end, Devices),
    ?assertError({invalid_crossing_count, 0, 2}, hls_protocol_routing:plan(P#{devices := Empty})),
    reject([P#{limits := #{crossings => Limit}} || Limit <- [0, -1, 1.5]]),
    reject([P#{actors := Count} || Count <- [0, -1, 3.0]]),
    reject([P#{devices := #{}}, P#{devices := Devices#{42 := #{native_indices => [1]}}}]),
    ok.

%% Codec maps are intentionally incomplete: routing checks addressing, never codec semantics.
-spec deployment() -> map().
deployment() ->
    Classes = [#{slot => 0, codec => #{}}, #{slot => 255, codec => #{opaque => value}}],
    Links = [#{index => I, source_index => 0, destination_index => D, classes => Classes,
        diagnostic => {destination, D}} || {I, D} <- [{0, 1}, {65535, 2}]],
    Devices = maps:from_list([{Role, #{native_indices => [Actor],
        links => [Link#{direction => case Actor of 0 -> outgoing; _ -> incoming end}
            || Link = #{destination_index := Destination} <- Links, Actor =:= 0 orelse Actor =:= Destination]}}
        || {Role, Actor} <- [{north, 0}, {42, 1}, {{tile, south}, 2}]]),
    #{devices => Devices, actors => 3, limits => #{crossings => 2}}.

%% Change one descriptor without accidentally repairing its peer.
-spec change(term(), fun((map()) -> term()), map()) -> map().
change(Role, Fun, Plan = #{devices := Devices}) ->
    Device = #{links := [First | Rest]} = maps:get(Role, Devices),
    Plan#{devices := Devices#{Role := Device#{links := [Fun(First) | Rest]}}}.

%% These malformed plans must fail before any runtime incarnation can be constructed.
-spec reject([map()]) -> ok.
reject(Plans) ->
    lists:foreach(fun(Plan) -> ?assertException(error, _, hls_protocol_routing:plan(Plan)) end, Plans).
