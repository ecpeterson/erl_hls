-module(xls_topology_scheduler_plan).
-moduledoc "Normalizes compact shared-scheduler hardware before rendering. Source-fragment ownership, dense RAM addresses, producer lanes, startup encoding and effect-window dependencies have one retained authority. The descriptor is inspectable planning evidence, not an executable serialized plan or a hardware proof.".
-export([prepare/1, descriptor/1, graph/1, artifact_requirements/1]).
-export_type([plan/0, descriptor/0]).

%% Renderer graphs retain checked upstream family and placement records privately.
-record(plan, {graph :: map(), descriptor :: descriptor()}).
-doc "An in-process normalized compact scheduler graph. Constructed only from the checked regular-family lowering; rendering cannot reload actor interfaces or repeat ownership decisions.".
-opaque plan() :: #plan{}.

%% Physical identities preserve the existing deterministic zero-based group order.
-type group_index() :: non_neg_integer().
%% A producer's position is its request-array lane; returned credit is a distinct producer.
-type producer() :: {scheduler, group_index()} | control | egress_credit.
%% Dense RAM addresses preserve logical family identity independently of placement.
-type address() :: #{slot := non_neg_integer(), family := atom(), coordinates := [non_neg_integer()]}.
%% Startup payloads are packed once with the actor schema before any source rendering.
-type startup() :: #{slot := non_neg_integer(), schema := atom(), payload := bitstring()}.
%% Recipients retain checked translations and ordered queued fanout.
-type recipient() :: {external, atom()} | {family, atom(), {translate, [integer()], wrap}}.
%% Captured source-fragment outputs have no ordinary route; every other port owns its checked route.
-type output() :: #{port := atom(), owner := source_fragment} |
    #{port := atom(), owner := router, delivery := direct | queued, recipients := [recipient()]}.
%% Family destination rows bind coordinates to one physical group and dense RAM slot.
-type destination() :: #{coordinates := [non_neg_integer()], group := group_index(), slot := non_neg_integer()}.
%% Families expose routing ownership without duplicating their loaded compiler interfaces.
-type family() :: #{id := atom(), module := module(), destinations := [destination()], outputs := [output()]}.
%% Each group exposes all scheduling decisions needed to inspect its generated channels.
-type scheduler() :: #{id := term(), index := group_index(), module := module(), slot_count := pos_integer(),
    addresses := [address()], producers := [producer()], producer_index := #{producer() => non_neg_integer()},
    destinations := [group_index()], external_ids := [atom()], startup := [startup()],
    has_control := boolean(), effect_window_domain := non_neg_integer(), effect_window_position := non_neg_integer()}.
%% A bounded reduction plane couples all incident scheduler owners even after ordinary route pruning.
-type plane() :: #{family := atom(), source_schedulers := [group_index()], captured_ports := [atom()],
    destinations := [destination()], fragment_capacity := 2}.
-doc "Closed description of scheduler ownership, routes, dense addresses, ordered startup payloads, control groups and backpressure domains. List order is the order consumed by source rendering.".
-type descriptor() :: #{representation := compact_shared, families := [family()], schedulers := [scheduler()],
    source_fragment_planes := [plane()], effect_window_domains := [[group_index()]],
    control := #{families := [atom()], groups := [group_index()], width := pos_integer(), height := pos_integer()}}.

-doc "Prepares one already checked shared-family lowering. Resolves source-fragment ownership before ordinary route dependencies, packs startup payloads and rejects incomplete output ownership or inconsistent dense addresses. No source is emitted and no files or tools are invoked.".
-spec prepare(map()) -> plan().
prepare(Spec0) ->
    Spec = annotate(prepare_planes(Spec0)),
    #plan{graph = Spec, descriptor = describe(Spec)}.

-doc "Returns retained planning facts without reloading interfaces, rechecking topology or rendering source.".
-spec descriptor(plan()) -> descriptor().
descriptor(#plan{descriptor = Descriptor}) -> Descriptor.

-doc "Returns the internal checked renderer graph. This view contains upstream compiler records and is only for the scheduler DSLX renderer; applications inspect descriptor/1 instead.".
-spec graph(plan()) -> map().
graph(#plan{graph = Graph}) -> Graph.

-doc "Returns the actor specializations already selected by the checked placement and reduction plan.".
-spec artifact_requirements(plan()) -> #{module() => map()}.
artifact_requirements(#plan{graph = #{artifact_requirements := Requirements}}) -> Requirements.

%% Source-fragment capture owns outputs before ordinary routing dependencies are derived.
-spec prepare_planes(map()) -> map().
prepare_planes(Spec = #{families := Families, schedulers := Schedulers}) ->
    ReductionPlan = maps:get(reduction_plan, Spec, #{placements => []}),
    Placements = maps:get(placements, ReductionPlan, []),
    FamilyIndex = maps:from_list([
        {maps:get(id, Family), Family} || Family <- Families
    ]),
    SchedulerIndex = maps:from_list([
        {maps:get(id, Scheduler), Scheduler} || Scheduler <- Schedulers
    ]),
    Planes = [annotate_plane(Placement, FamilyIndex, SchedulerIndex)
        || Placement <- Placements],
    PlaneIndex = maps:from_list([
        {maps:get(id, Plane), Plane} || Plane <- Planes
    ]),
    Spec#{
        families := [prepare_routes(prepare_family(Family, PlaneIndex))
            || Family <- Families],
        source_fragment_planes => Planes
    }.

%% Assigns destination groups and channel identities to one reduction plane.
-spec annotate_plane(map(),map(),map()) -> map().
annotate_plane(Placement = #{
    kind := source_fragments,
    family := FamilyId,
    module := Module,
    shape := Shape,
    scheduler_groups := GroupIds,
    population := Population,
    fragments := Fragments,
    fragment_capacity := 2
}, FamilyIndex, SchedulerIndex) ->
    Family = maps:get(FamilyId, FamilyIndex),
    SourceSchedulers = [
        maps:get(index, maps:get(GroupId, SchedulerIndex))
        || GroupId <- GroupIds
    ],
    OrderedFragments = lists:keysort(1, [
        {maps:get(ordinal, Fragment), Fragment} || Fragment <- Fragments
    ]),
    Placement#{
        id => FamilyId,
        module_name => maps:get(module_name, Family),
        module => Module,
        shape => Shape,
        population => Population,
        fragments => [Fragment || {_Ordinal, Fragment} <- OrderedFragments],
        source_schedulers => SourceSchedulers,
        destinations => destination_rows(Family),
        stem => [atom_to_list(FamilyId), "_reduction"]
    }.

%% Builds each actor's reciprocal contribution-source row.
-spec destination_rows(map()) -> [map()].
destination_rows(#{schedulers := Bindings}) ->
    Rows = lists:append([
        [
            #{
                index => maps:get(linear_index, Instance),
                x => X,
                y => Y,
                group => maps:get(group, Binding),
                slot => maps:get(base_slot, Binding) +
                    maps:get(local_index, Instance)
            }
            || Instance = #{coordinates := [X, Y]} <-
                   maps:get(instances, Binding)
        ]
        || Binding <- Bindings
    ]),
    [Row || {_Index, Row} <- lists:keysort(1, [
        {maps:get(index, Row), Row} || Row <- Rows
    ])].

%% Attaches the selected plane and captured ports to a logical family.
-spec prepare_family(map(),map()) -> map().
prepare_family(Family = #{id := Id, routes := Routes}, PlaneIndex) ->
    case maps:find(Id, PlaneIndex) of
        error -> Family;
        {ok, Plane} ->
            CapturedPorts = [maps:get(port, Fragment)
                || Fragment <- maps:get(fragments, Plane)],
            Family#{
                routes := [Route || Route <- Routes,
                    begin
                        {_Source, Port} = maps:get(source, Route),
                        not lists:member(Port, CapturedPorts)
                    end],
                source_fragment => Plane,
                source_fragment_ports => CapturedPorts
            }
    end.

%% Attaches domain identity and local arbitration position to each execution group.
-spec annotate(map()) -> map().
annotate(Spec = #{
    families := Families,
    schedulers := Schedulers,
    effect_window_partition := WindowPartition
}) ->
    FamilyIndex = maps:from_list([
        {maps:get(id, Family), Family} || Family <- Families
    ]),
    SchedulerIndex = maps:from_list([
        {maps:get(index, Scheduler), Scheduler} || Scheduler <- Schedulers
    ]),
    FamilySchedulers = maps:from_list([
        {maps:get(id, Family), [maps:get(group, Binding)
            || Binding <- maps:get(schedulers, Family)]}
        || Family <- Families
    ]),
    Annotated0 = [
        annotate_scheduler(
            Scheduler,
            Families,
            FamilyIndex,
            SchedulerIndex,
            FamilySchedulers
        )
        || Scheduler <- Schedulers
    ],
    %% Source-fragment routing is pruned from the ordinary route graph before
    %% this annotation pass.  Its bounded plane can nevertheless propagate
    %% backpressure between every scheduler incident to that plane, so those
    %% schedulers must remain in one effect-window ownership domain.
    PlaneIncidences = [maps:get(source_schedulers, Plane)
        || Plane <- maps:get(source_fragment_planes, Spec, [])],
    Dependencies = [[Index, Destination] ||
        #{index := Index, destinations := Destinations} <- Annotated0,
        #{index := Destination} <- Destinations] ++ PlaneIncidences,
    Domains = xls_topology_effect_windows:partition(
        [Index || #{index := Index} <- Annotated0], WindowPartition, Dependencies),
    Annotated = xls_topology_effect_windows:annotate(Annotated0, Domains),
    Externals = [annotate_external(External, Annotated)
        || External <- maps:get(externals, Spec)],
    Controlled = [Family || Family <- Families, maps:get(ingress, Family) =/= none],
    Spec#{
        controlled_families => Controlled,
        controlled_groups => controlled_groups(Controlled),
        family_index => FamilyIndex,
        scheduler_index => maps:from_list([
            {maps:get(index, Scheduler), Scheduler}
            || Scheduler <- Annotated
        ]),
        family_schedulers => FamilySchedulers,
        schedulers => Annotated,
        effect_window_domains => Domains,
        externals => Externals
    }.

%% Lists the shared sources that can emit to an external output.
-spec annotate_external(map(),[map()]) -> map().
annotate_external(External = #{id := Id}, Schedulers) ->
    Sources = [
        maps:get(index, Scheduler)
        || Scheduler <- Schedulers,
           lists:member(Id, maps:get(external_ids, Scheduler))
    ],
    [_ | _] = Sources,
    External#{source_schedulers => Sources}.

%% Assigns actor addresses, producer lanes and routed destinations to one group.
-spec annotate_scheduler(map(),[map()],map(),map(),map()) -> map().
annotate_scheduler(
    Scheduler = #{index := Index, members := Members},
    Families,
    FamilyIndex,
    SchedulerIndex,
    FamilySchedulers
) ->
    MemberIds = [maps:get(id, Member) || Member <- Members],
    MemberFamilies = [maps:get(Id, FamilyIndex) || Id <- MemberIds],
    SourceGroups = lists:usort(lists:append([
        maps:get(maps:get(id, SourceFamily), FamilySchedulers)
        || SourceFamily <- Families,
           route_targets_group(
               maps:get(routes, SourceFamily),
               MemberIds
           )
    ])),
    HasControl = lists:any(
        fun(#{ingress := Ingress}) -> Ingress =/= none end,
        MemberFamilies
    ),
    Producers0 = [{scheduler, Source} || Source <- SourceGroups],
    MessageProducers = case HasControl of
        true -> Producers0 ++ [control];
        false -> Producers0
    end,
    Producers = MessageProducers ++ [egress_credit],
    ProducerIndex = maps:from_list([
        {Producer, ProducerNumber}
        || {ProducerNumber, Producer} <- lists:enumerate(0, Producers)
    ]),
    Destinations = lists:usort(lists:append([
        maps:get(DestinationId, FamilySchedulers)
        || Family <- MemberFamilies,
           Route <- maps:get(routes, Family),
           {family, DestinationId, _} <- maps:get(recipients, Route)
    ])),
    Externals = lists:usort([
        ExternalId
        || Family <- MemberFamilies,
           Route <- maps:get(routes, Family),
           {external, ExternalId} <- maps:get(recipients, Route)
    ]),
    Startup = lists:append([
        scheduler_startup_items(Family, Scheduler)
        || Family <- MemberFamilies
    ]),
    Addresses = scheduler_address_entries(Scheduler),
    true = length(Addresses) =:= maps:get(slot_count, Scheduler),
    Scheduler#{
        addresses => Addresses,
        families => MemberFamilies,
        producers => Producers,
        producer_index => ProducerIndex,
        destinations => [
            maps:get(Destination, SchedulerIndex)
            || Destination <- Destinations
        ],
        external_ids => Externals,
        startup_items => Startup,
        startup_count => length(Startup),
        has_control => HasControl,
        index => Index
    }.

%% Tests whether a logical route reaches a member of the group.
-spec route_targets_group([any()],[any()]) -> boolean().
route_targets_group(Routes, MemberIds) ->
    lists:any(
        fun(#{recipients := Recipients}) ->
            lists:any(
                fun
                    ({family, Id, _}) -> lists:member(Id, MemberIds);
                    ({external, _}) -> false
                end,
                Recipients
            )
        end,
        Routes
    ).

%% Collects startup frames in the group's dense-slot order.
-spec scheduler_startup_items(map(),map()) -> [map()].
scheduler_startup_items(#{startup := none}, _Scheduler) -> [];
scheduler_startup_items(
    Family = #{startup := #{items := Items}},
    Scheduler
) ->
    Member = scheduler_family_member(Family, Scheduler),
    Coordinates = maps:from_list([
        {maps:get(coordinates, Instance),
            maps:get(base_slot, Member) + maps:get(local_index, Instance)}
        || Instance <- maps:get(instances, Member)
    ]),
    [pack_startup(Item#{slot => maps:get([X, Y], Coordinates)})
        || Item = #{coordinates := [X, Y]} <- Items,
           maps:is_key([X, Y], Coordinates)].

%% Resolves a family instance to its owning group member.
-spec scheduler_family_member(map(),map()) -> map().
scheduler_family_member(#{id := Id}, #{members := Members}) ->
    hd([Member || Member = #{kind := family, id := MemberId} <- Members,
        MemberId =:= Id]).

%% Enumerates the logical coordinates assigned to a physical group.
-spec scheduler_address_entries(map()) -> [tuple()].
scheduler_address_entries(#{members := Members}) ->
    lists:keysort(1, lists:append([
        family_address_entries(Member) || Member <- Members
    ])).

%% Enumerates physical group and slot addresses for a family.
-spec family_address_entries(map()) -> [{number(),term(),term(),term()}].
family_address_entries(#{
    id := Family,
    base_slot := Base,
    instances := Instances
}) ->
    [
        {Base + Local, Family, X, Y}
        || #{coordinates := [X, Y], local_index := Local} <- Instances
    ].

%% Collects groups reachable by external control traffic.
-spec controlled_groups([map()]) -> [any()].
controlled_groups(Families) ->
    lists:usort(lists:append([
        [maps:get(group, Binding)
            || Binding <- maps:get(schedulers, Family)]
        || Family <- Families
    ])).

%% Pack startup values using their checked actor field types, before rendering any DSLX.
-spec pack_startup(map()) -> map().
pack_startup(Item = #{fields := Fields}) ->
    Payload = hls_codec:align(hls_codec:join([hls_type:pack(Value, Type)
        || #{type := Type, value := Value} <- Fields]), 32),
    Item#{packed_payload => Payload}.

%% Resolve every declared output exactly once after source-fragment routes have been removed.
-spec prepare_routes(map()) -> map().
prepare_routes(Family = #{routes := Routes, outputs := Outputs, schedulers := Bindings}) ->
    RouteIndex = maps:from_list([{Port, Route} || Route = #{source := {_, Port}} <- Routes]),
    Owned = [{Port, output_route(Port, RouteIndex, Family)} || Port <- Outputs],
    Destinations = [{maps:get(coordinates, Instance), maps:get(group, Binding),
        maps:get(base_slot, Binding) + maps:get(local_index, Instance)}
        || Binding <- Bindings, Instance <- maps:get(instances, Binding)],
    Family#{output_routes => Owned, destination_entries => Destinations}.

%% An absent ordinary route must have an explicit captured source-fragment owner.
-spec output_route(atom(), map(), map()) -> map() | source_fragment.
output_route(Port, Routes, Family) ->
    case maps:find(Port, Routes) of
        {ok, Route} -> Route;
        error ->
            true = lists:member(Port, maps:get(source_fragment_ports, Family, [])),
            source_fragment
    end.

%% Inspection selects physical ownership facts, excluding compiler interfaces and rendering names.
-spec describe(map()) -> descriptor().
describe(#{families := Families, schedulers := Schedulers,
        source_fragment_planes := Planes, effect_window_domains := Domains,
        controlled_families := Controlled, controlled_groups := Groups, width := Width, height := Height}) ->
    #{representation => compact_shared,
        families => [describe_family(Family) || Family <- Families],
        schedulers => [describe_scheduler(Scheduler) || Scheduler <- Schedulers],
        source_fragment_planes => [describe_plane(Plane) || Plane <- Planes],
        effect_window_domains => Domains,
        control => #{families => [Id || #{id := Id} <- Controlled], groups => Groups, width => Width, height => Height}}.

%% Preserve declaration order for ports and binding order for physical destinations.
-spec describe_family(map()) -> family().
describe_family(#{id := Id, module := Module, destination_entries := Entries, output_routes := Outputs}) ->
    #{id => Id, module => Module,
        destinations => [#{coordinates => Coordinates, group => Group, slot => Slot}
            || {Coordinates, Group, Slot} <- Entries],
        outputs => [describe_output(Port, Route) || {Port, Route} <- Outputs]}.

%% Captured and normally routed outputs have disjoint, explicit owners.
-spec describe_output(atom(), map() | source_fragment) -> output().
describe_output(Port, source_fragment) -> #{port => Port, owner => source_fragment};
describe_output(Port, #{delivery := Delivery, recipients := Recipients}) ->
    #{port => Port, owner => router, delivery => Delivery, recipients => Recipients}.

%% Expose producer arbitration and retained startup order alongside inverse address tables.
-spec describe_scheduler(map()) -> scheduler().
describe_scheduler(Scheduler = #{addresses := Addresses, destinations := Destinations, startup_items := Startup}) ->
    (maps:with([id, index, module, slot_count, producers, producer_index, external_ids,
        has_control, effect_window_domain, effect_window_position], Scheduler))#{
        addresses => [#{slot => Slot, family => Family, coordinates => [X, Y]}
            || {Slot, Family, X, Y} <- Addresses],
        destinations => [Index || #{index := Index} <- Destinations],
        startup => [#{slot => Slot, schema => Schema, payload => Payload}
            || #{slot := Slot, schema := Schema, packed_payload := Payload} <- Startup]}.

%% Keep hyperedge ownership visible after captured routes disappear from ordinary fanout.
-spec describe_plane(map()) -> plane().
describe_plane(#{id := Id, source_schedulers := Sources, fragments := Fragments, destinations := Destinations}) ->
    #{family => Id, source_schedulers => Sources, captured_ports => [Port || #{port := Port} <- Fragments],
        destinations => [#{coordinates => [X, Y], group => Group, slot => Slot}
            || #{x := X, y := Y, group := Group, slot := Slot} <- Destinations],
        fragment_capacity => 2}.
