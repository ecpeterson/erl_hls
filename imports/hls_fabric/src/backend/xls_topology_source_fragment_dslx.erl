%%%% xls_topology_source_fragment_dslx
%%%%
%%%% Renders the source-fragment reduction plane selected by
%%%% hls_reduction_plan.  Structural and semantic topology validation belongs
%%%% to that planner; this module consumes its closed placement facts.

-module(xls_topology_source_fragment_dslx).
-moduledoc false.

-export([
    aggregate_mux_spawns/1,
    captured_port/2,
    plane_channels/1,
    plane_spawns/1,
    prepare/1,
    router_arguments/2,
    router_argument_names/2,
    router_batch_bindings/2,
    router_index_step/2,
    router_send/2,
    router_spawn_arguments/2,
    router_state_bindings/2,
    scheduler_channels/2,
    scheduler_service_argument/2,
    support/1
]).

%%%
%%% Closed backend annotation
%%%

-doc "Checks and annotates source-fragment planes before topology rendering.".
-spec prepare(map()) -> map().
prepare(Spec = #{families := Families, schedulers := Schedulers}) ->
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
        families := [prepare_family(Family, PlaneIndex)
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

-doc "Tests whether an actor output belongs to a source-fragment prefix.".
-spec captured_port(map(), atom()) -> boolean().
captured_port(Family, Port) ->
    lists:member(Port, maps:get(source_fragment_ports, Family, [])).

%%%
%%% Router integration
%%%

-doc "Declares the reduction-plane endpoints used by a group's router.".
-spec router_arguments(map(), map()) -> [iodata()].
router_arguments(Spec, Scheduler) ->
    [
        [batch_output_name(Plane), ": chan<",
            batch_name(Plane), "> out"]
        || Plane <- scheduler_planes(Spec, Scheduler)
    ].

-doc "Lists reduction endpoints in the same order as their declarations.".
-spec router_argument_names(map(), map()) -> [iodata()].
router_argument_names(Spec, Scheduler) ->
    [batch_output_name(Plane) || Plane <- scheduler_planes(Spec, Scheduler)].

-doc "Retains per-plane publication cursors in router state.".
-spec router_state_bindings(map(), map()) -> iodata().
router_state_bindings(Spec, Scheduler = #{module_name := Module}) ->
    case scheduler_planes(Spec, Scheduler) of
        [] ->
            "    let state_last = state.control.active && state_effect_info.2;\n";
        [_ | _] ->
            [
                "    let state_reduction_prefix = ", Module,
                "::scheduled_reduction_prefix(state.scheduled);\n",
                "    let state_reduction_batch = state.control.active &&\n",
                "      state.index == u8:0 && state_reduction_prefix.0;\n",
                "    let state_last = state.control.active &&\n",
                "      if state_reduction_batch { state_reduction_prefix.2\n",
                "      } else { state_effect_info.2 };\n"
            ]
    end.

-doc "Extracts captured contributions from the selected ordered effect batch.".
-spec router_batch_bindings(map(), map()) -> iodata().
router_batch_bindings(Spec, Scheduler = #{module_name := Module}) ->
    case scheduler_planes(Spec, Scheduler) of
        [] -> [];
        [_ | _] ->
            [
                "    let reduction_prefix = ", Module,
                "::scheduled_reduction_prefix(scheduled);\n",
                "    let reduction_batch = batch_valid && index == u8:0 &&\n",
                "      reduction_prefix.0;\n"
            ]
    end.

-doc "Publishes the selected contribution prefix to its reduction plane.".
-spec router_send(map(), map()) -> iodata().
router_send(Spec, Scheduler) ->
    Planes = scheduler_planes(Spec, Scheduler),
    [
        "      match address.family as FamilyId {\n",
        [router_family_send(Plane) || Plane <- Planes],
        "        _ => grant_tok,\n",
        "      }\n"
    ].

%% Selects the source-fragment route for the issuing actor family.
-spec router_family_send(map()) -> iodata().
router_family_send(Plane = #{
    id := Id,
    module_name := Module,
    population := Population,
    fragments := Fragments
}) ->
    Population = length(Fragments),
    [
        "        FamilyId::", xls_names:enum_member(Id), " => {\n",
        [
            [
                "          let effect_", integer_to_list(Ordinal), " = ",
                Module, "::scheduled_effect(scheduled, u8:",
                integer_to_list(Ordinal), ").0;\n"
            ]
            || #{ordinal := Ordinal} <- Fragments
        ],
        "          let batch = ", batch_name(Plane), " {\n",
        "            source: (address.x as u32) * u32:",
        integer_to_list(lists:nth(2, maps:get(shape, Plane))),
        " + address.y as u32,\n",
        "            frames: [",
        join_with(", ", [
            ["effect_", integer_to_list(Ordinal), ".frame"]
            || #{ordinal := Ordinal} <- Fragments
        ]),
        "],\n",
        "          };\n",
        "          send(grant_tok, ", batch_output_name(Plane),
        ", batch)\n",
        "        },\n"
    ].

-doc "Advances the effect cursor only after captured delivery is accepted.".
-spec router_index_step(map(), map()) -> iodata().
router_index_step(Spec, Scheduler) ->
    case scheduler_planes(Spec, Scheduler) of
        [] -> "u8:1";
        [First | Rest] ->
            Population = maps:get(population, First),
            true = lists:all(fun(Plane) ->
                maps:get(population, Plane) =:= Population
            end, Rest),
            ["if reduction_batch { u8:", integer_to_list(Population),
                " } else { u8:1 }"]
    end.

-doc "Connects a group's router to the planes it can publish into.".
-spec router_spawn_arguments(map(), map()) -> [iodata()].
router_spawn_arguments(Spec, Scheduler = #{index := Source}) ->
    [
        begin
            Position = position(Source,
                maps:get(source_schedulers, Plane), 0),
            [maps:get(stem, Plane), "_batch_p[u32:",
                integer_to_list(Position), "]"]
        end
        || Plane <- scheduler_planes(Spec, Scheduler)
    ].

%%%
%%% Source-fragment plane
%%%

-doc "Renders source-fragment declarations, planes and aggregate-output arbitration.".
-spec support(map()) -> iodata().
support(Spec) ->
    [
        [aggregate_mux_proc(Spec, Scheduler)
            || Scheduler <- maps:get(schedulers, Spec),
               length(scheduler_planes(Spec, Scheduler)) > 1],
        [[fragment_declarations(Plane), fragment_plane_proc(Plane)]
            || Plane <- maps:get(source_fragment_planes, Spec, [])]
    ].

%% Defines the payload and address types of a reduction fragment.
-spec fragment_declarations(map()) -> iodata().
fragment_declarations(Plane = #{fragments := Fragments}) ->
    Population = maps:get(population, Plane),
    [
        "struct ", batch_name(Plane), " {\n",
        "  source: u32,\n",
        "  frames: axis::Frame[u32:", integer_to_list(Population), "],\n",
        "}\n\n",
        [fragment_comment(Fragment) || Fragment <- Fragments]
    ].

%% Records the validated contribution geometry beside generated wiring.
-spec fragment_comment(map()) -> [string(),...].
fragment_comment(#{ordinal := Ordinal, port := Port,
        inverse_offset := [DX, DY], inverse_ordinal := Inverse}) ->
    [
        "// Fragment ", integer_to_list(Ordinal), " (",
        atom_to_list(Port), ") uses inverse fragment ",
        integer_to_list(Inverse), " at offset [",
        integer_to_list(DX), ", ", integer_to_list(DY), "].\n"
    ].

%% Concrete dimensions and reciprocal rows are prepared before any DSLX is rendered.
-type plane_layout() :: #{source_count := pos_integer(), actor_count := pos_integer(),
    population := pos_integer(), inverse_rows := [[map()]],
    members := [iodata()], names := [iodata()]}.

%% Combines reciprocal contributions using the fixed plane transition template.
-spec fragment_plane_proc(map()) -> binary().
fragment_plane_proc(Plane) ->
    render_plane(Plane, plane_layout(Plane)).

%% Separates topology geometry and channel order from the plane's state machine.
-spec plane_layout(map()) -> plane_layout().
plane_layout(Plane = #{module_name := Module, source_schedulers := Sources,
        destinations := Destinations, population := Population}) ->
    SourceCount = length(Sources),
    OutputNames = [["aggregate_out_", integer_to_list(Index)]
        || Index <- lists:seq(0, SourceCount - 1)],
    Members = [["batch_in: chan<", batch_name(Plane), ">[u32:",
        integer_to_list(SourceCount), "] in"] | [
        [Name, ": chan<", Module, "::ReductionAggregateRequest> out"]
        || Name <- OutputNames]],
    #{source_count => SourceCount, actor_count => length(Destinations),
        population => Population, inverse_rows => inverse_rows(Plane),
        members => Members, names => ["batch_in" | OutputNames]}.

%% Bind only dimensions, names and constant topology wiring; sequencing stays in DSLX.
-spec render_plane(map(), plane_layout()) -> binary().
render_plane(Plane = #{module_name := Module, destinations := Destinations,
        fragments := Fragments}, #{source_count := SourceCount,
        actor_count := ActorCount, population := Population,
        inverse_rows := InverseRows, members := Members, names := Names}) ->
    State = state_name(Plane),
    Batch = batch_name(Plane),
    Sources = integer_to_list(SourceCount),
    Actors = integer_to_list(ActorCount),
    PopulationText = integer_to_list(Population),
    Rows = lists:enumerate(0, InverseRows),
    render_template("source_fragment_plane.x.in", [
        {<<"@@STATE_DECLARATION@@">>, State},
        {<<"@@INPUT_INDEX@@">>, xls_nums:index_type(SourceCount)},
        {<<"@@OUTPUT_INDEX@@">>, xls_nums:index_type(ActorCount)},
        {<<"@@OPEN_TOKEN_COUNT@@">>, Actors},
        {<<"@@BANK_FIELDS@@">>, [["  bank_", integer_to_list(Ordinal),
            ": frame_queue::Queue[u32:", Actors, "],\n"]
            || #{ordinal := Ordinal} <- Fragments]},
        {<<"@@BATCH_FIELD@@">>, Batch},
        {<<"@@PLANE_NAME@@">>, plane_name(Plane)},
        {<<"@@MEMBERS@@">>, [["  ", Member, ";\n"] || Member <- Members]},
        {<<"@@CONFIG_SIGNATURE@@">>, config_signature(Members, 2)},
        {<<"@@CONFIG_NAMES@@">>, join_with(", ", Names)},
        {<<"@@INITIAL_STATE@@">>, State},
        {<<"@@PRIOR_STATE@@">>, State},
        {<<"@@READY_ROWS@@">>, [ready_row(Row, Index, ActorCount) || {Index, Row} <- Rows]},
        {<<"@@POP_SOURCE_ROWS@@">>, [inverse_arm(Row, Index) || {Index, Row} <- Rows]},
        {<<"@@POP_SOURCE_COUNT@@">>, PopulationText},
        {<<"@@FRAME_ROWS@@">>, [frames_arm(Row, Index) || {Index, Row} <- Rows]},
        {<<"@@FRAME_COUNT@@">>, PopulationText},
        {<<"@@AGGREGATE_MODULE@@">>, Module},
        {<<"@@AGGREGATE_COUNT@@">>, PopulationText},
        {<<"@@OUTPUT_ROUTES@@">>, [output_arm(Plane, D) || D <- Destinations]},
        {<<"@@BATCH_ACCUMULATOR@@">>, Batch},
        {<<"@@INPUT_COUNT@@">>, Sources},
        {<<"@@EMPTY_INPUT_BATCH@@">>, Batch},
        {<<"@@INITIAL_INPUT_BATCH@@">>, Batch},
        {<<"@@WORK_SOURCE_BOUND@@">>, Actors},
        {<<"@@INCOMING_SOURCE_BOUND@@">>, Actors},
        {<<"@@CAPACITY_BINDINGS@@">>, [capacity_binding(F) || F <- Fragments]},
        {<<"@@CAPACITY_GUARDS@@">>, [[" && capacity_", integer_to_list(Ordinal)]
            || #{ordinal := Ordinal} <- Fragments]},
        {<<"@@BANK_UPDATES@@">>, [bank_binding(F) || F <- Fragments]},
        {<<"@@NEXT_STATE@@">>, State},
        {<<"@@INPUT_CURSOR_COUNT@@">>, Sources},
        {<<"@@OUTPUT_CURSOR_COUNT@@">>, Actors},
        {<<"@@BANK_VALUES@@">>, [["      bank_", integer_to_list(Ordinal), ",\n"]
            || #{ordinal := Ordinal} <- Fragments]}
    ]).

%% Builds the destination-indexed inverse of source delivery geometry.
-spec inverse_rows(map()) -> [[map()]].
inverse_rows(#{shape := [Width, Height], fragments := Fragments}) ->
    [
        [
            begin
                [DX, DY] = maps:get(inverse_offset, Fragment),
                SourceX = positive_modulo(X + DX, Width),
                SourceY = positive_modulo(Y + DY, Height),
                #{ordinal => maps:get(ordinal, Fragment),
                    source => SourceX * Height + SourceY}
            end
            || Fragment <- Fragments
        ]
        || X <- lists:seq(0, Width - 1),
           Y <- lists:seq(0, Height - 1)
    ].

%% Tests whether every source needed by a destination has a contribution ready.
-spec ready_row([map()],integer(),pos_integer()) -> iodata().
ready_row(Row, Index, Count) ->
    [
        "      state.open_tokens[u32:", integer_to_list(Index), "] && ",
        join_with(" && ", [
            ["state.bank_", integer_to_list(maps:get(ordinal, Item)),
                "[u32:", integer_to_list(maps:get(source, Item)),
                "].current_valid"]
            || Item <- Row
        ]),
        separator(Index, Count), "\n"
    ].

%% Selects the source slots belonging to one destination.
-spec inverse_arm([map()],integer()) -> iodata().
inverse_arm(Row, Index) ->
    [
        "      u32:", integer_to_list(Index), " => [",
        join_with(", ", [["u32:", integer_to_list(maps:get(source, Item))]
            || Item <- Row]),
        "],\n"
    ].

%% Collects the destination's selected source contributions for combination.
-spec frames_arm([map()],integer()) -> iodata().
frames_arm(Row, Index) ->
    [
        "      u32:", integer_to_list(Index), " => [",
        join_with(", ", [
            ["state.bank_", integer_to_list(maps:get(ordinal, Item)),
                "[u32:", integer_to_list(maps:get(source, Item)),
                "].current"]
            || Item <- Row
        ]),
        "],\n"
    ].

%% Selects the aggregate output lane owning a destination slot.
-spec output_arm(map(),map()) -> iodata().
output_arm(Plane, Destination = #{index := Index, group := Group}) ->
    Module = maps:get(module_name, Plane),
    Output = position(Group, maps:get(source_schedulers, Plane), 0),
    [
        "        u32:", integer_to_list(Index), " => send(\n",
        "          join(), aggregate_out_", integer_to_list(Output),
        ", ", Module, "::ReductionAggregateRequest {\n",
        "            slot: u32:",
        integer_to_list(maps:get(slot, Destination)), ",\n",
        "            aggregate,\n",
        "          }),\n"
    ].

%% Computes room for incoming fragments after accepted aggregate retirement.
-spec capacity_binding(map()) -> [string(),...].
capacity_binding(#{ordinal := Ordinal}) ->
    Index = integer_to_list(Ordinal),
    [
        "    let queue_", Index, " = state.bank_", Index,
        "[push_source];\n",
        "    let after_pop_", Index, " = frame_queue::after_pop(\n",
        "      queue_", Index, ", output_ready &&\n",
        "        pop_sources[u32:", Index, "] == push_source);\n",
        "    let capacity_", Index,
        " = !after_pop_", Index, ".lookahead_valid;\n"
    ].

%% Updates one bounded source-fragment bank after accepted reads and writes.
-spec bank_binding(map()) -> [string(),...].
bank_binding(#{ordinal := Ordinal}) ->
    Index = integer_to_list(Ordinal),
    [
        "    let bank_", Index, " = frame_queue::update_bank(\n",
        "      state.bank_", Index, ", output_ready,\n",
        "      pop_sources[u32:", Index,
        "], can_insert, push_source,\n",
        "      work.frames[u32:", Index, "]);\n"
    ].

%%%
%%% Aggregate arbitration and graph wiring
%%%

%% A scheduler with several planes retains one aggregate per incoming lane.
-spec aggregate_mux_proc(map(), map()) -> binary().
aggregate_mux_proc(Spec, Scheduler = #{module_name := Module}) ->
    Count = length(scheduler_planes(Spec, Scheduler)),
    CountText = integer_to_list(Count),
    State = mux_state_name(Scheduler),
    Request = [Module, "::ReductionAggregateRequest"],
    render_template("source_fragment_mux.x.in", [
        {<<"@@STATE_DECLARATION@@">>, State},
        {<<"@@CURSOR_TYPE@@">>, xls_nums:index_type(Count)},
        {<<"@@VALID_COUNT@@">>, CountText},
        {<<"@@STATE_REQUEST@@">>, Request},
        {<<"@@STATE_VALUE_COUNT@@">>, CountText},
        {<<"@@MUX_NAME@@">>, mux_name(Scheduler)},
        {<<"@@INPUT_REQUEST@@">>, Request},
        {<<"@@INPUT_COUNT@@">>, CountText},
        {<<"@@OUTPUT_REQUEST@@">>, Request},
        {<<"@@CONFIG_INPUT_REQUEST@@">>, Request},
        {<<"@@CONFIG_INPUT_COUNT@@">>, CountText},
        {<<"@@CONFIG_OUTPUT_REQUEST@@">>, Request},
        {<<"@@INITIAL_STATE@@">>, State},
        {<<"@@PRIOR_STATE@@">>, State},
        {<<"@@ACCUMULATOR_VALID_COUNT@@">>, CountText},
        {<<"@@ACCUMULATOR_REQUEST@@">>, Request},
        {<<"@@ACCUMULATOR_VALUE_COUNT@@">>, CountText},
        {<<"@@CAPTURE_COUNT@@">>, CountText},
        {<<"@@EMPTY_REQUEST@@">>, Request},
        {<<"@@NEXT_STATE@@">>, State},
        {<<"@@CURSOR_COUNT@@">>, CountText}
    ]).

-doc "Emit bounded aggregate handoffs for a scheduler and its selected reduction planes.".
-spec scheduler_channels(map(), map()) -> iodata().
scheduler_channels(Spec, Scheduler = #{stem := Stem, module_name := Module}) ->
    case scheduler_planes(Spec, Scheduler) of
        [] -> [];
        Planes ->
            %% Empty bypass preserves immediate delivery; the stored slot makes
            %% upstream readiness independent of the scheduler's current issue.
            %% Buffer acceptance transfers ownership, not actor-state commit.
            [
                "    let (", Stem, "_aggregate_p, ", Stem,
                "_aggregate_c) =\n",
                "      chan<", Module,
                "::ReductionAggregateRequest, u32:1>(\"", Stem,
                "_aggregate\");\n",
                case Planes of
                    [_, _ | _] -> [
                        "    let (", Stem, "_aggregate_sources_p, ", Stem,
                        "_aggregate_sources_c) =\n",
                        "      chan<", Module,
                        "::ReductionAggregateRequest, u32:0>[u32:",
                        integer_to_list(length(Planes)), "](\"", Stem,
                        "_aggregate_sources\");\n"
                    ];
                    [_] -> []
                end
            ]
    end.

-doc "Declares publication and aggregate channels for a reduction plane.".
-spec plane_channels(map()) -> iodata().
plane_channels(Spec) ->
    [
        [
            "    let (", Stem, "_batch_p, ", Stem, "_batch_c) =\n",
            "      chan<", batch_name(Plane),
            ", CHANNEL_DEPTH>[u32:", integer_to_list(length(Sources)),
            "](\"", Stem, "_batch\");\n"
        ]
        || Plane = #{stem := Stem, source_schedulers := Sources} <-
               maps:get(source_fragment_planes, Spec, [])
    ].

-doc "Arbitrates aggregate producers sharing one destination service.".
-spec aggregate_mux_spawns(map()) -> iodata().
aggregate_mux_spawns(Spec) ->
    [
        [
            "    spawn ", mux_name(Scheduler), "(\n",
            "      ", Stem, "_aggregate_sources_c, ", Stem,
            "_aggregate_p);\n"
        ]
        || Scheduler = #{stem := Stem} <- maps:get(schedulers, Spec),
           length(scheduler_planes(Spec, Scheduler)) > 1
    ].

-doc "Connects each reduction plane to its source and destination endpoints.".
-spec plane_spawns(map()) -> iodata().
plane_spawns(Spec) ->
    [
        [
            "    spawn ", plane_name(Plane), "(\n",
            "      ", Stem, "_batch_c",
            [[",\n      ", aggregate_producer(Spec, Plane, Group)]
                || Group <- Sources],
            ");\n"
        ]
        || Plane = #{stem := Stem, source_schedulers := Sources} <-
               maps:get(source_fragment_planes, Spec, [])
    ].

-doc "Declares a group's aggregate-delivery input when required.".
-spec scheduler_service_argument(map(), map()) -> iodata().
scheduler_service_argument(Spec, Scheduler = #{stem := Stem}) ->
    case scheduler_planes(Spec, Scheduler) of
        [] -> [];
        [_ | _] -> [",\n      ", Stem, "_aggregate_c"]
    end.

%% Finds the aggregate lane from a selected plane to a group.
-spec aggregate_producer(map(),map(),term()) -> iodata().
aggregate_producer(Spec, Plane, Group) ->
    Scheduler = scheduler(Spec, Group),
    Stem = maps:get(stem, Scheduler),
    case scheduler_planes(Spec, Scheduler) of
        [Plane] -> [Stem, "_aggregate_p"];
        Planes ->
            Position = plane_position(maps:get(id, Plane), Planes, 0),
            [Stem, "_aggregate_sources_p[u32:",
                integer_to_list(Position), "]"]
    end.

%% Lists the reduction planes delivering into a physical group.
-spec scheduler_planes(term(),term()) -> [map()].
scheduler_planes(#{source_fragment_planes := Planes}, #{index := Group}) ->
    [Plane || Plane <- Planes,
        lists:member(Group, maps:get(source_schedulers, Plane))];
scheduler_planes(_Spec, _Scheduler) ->
    [].

%% Combines grouped actor identities, RAM layout and observation settings.
-spec scheduler(map(), term()) -> map().
scheduler(#{scheduler_index := Schedulers}, Group) ->
    maps:get(Group, Schedulers).

%% Finds a group's position among a plane's aggregate destinations.
-spec plane_position(atom(),[map(),...],non_neg_integer()) -> non_neg_integer().
plane_position(Id, [#{id := Id} | _], Position) -> Position;
plane_position(Id, [_ | Rest], Position) ->
    plane_position(Id, Rest, Position + 1).

%% Returns the zero-based position of a required entry in an ordered list.
-spec position(term(),nonempty_maybe_improper_list(),non_neg_integer()) -> non_neg_integer().
position(Value, [Value | _], Index) -> Index;
position(Value, [_ | Rest], Index) -> position(Value, Rest, Index + 1).

%% Normalizes a wrapped translation to a nonnegative offset.
-spec positive_modulo(integer(),integer()) -> integer().
positive_modulo(Value, Modulus) ->
    ((Value rem Modulus) + Modulus) rem Modulus.

%%%
%%% Names and rendering utilities
%%%

-spec batch_name(map()) -> iodata().
batch_name(#{id := Id}) ->
    [string:titlecase(atom_to_list(Id)), "ReductionBatch"].

%% Names the retained source-fragment state associated with a plane.
-spec state_name(map()) -> iodata().
state_name(#{id := Id}) ->
    [string:titlecase(atom_to_list(Id)), "ReductionPlaneState"].

%% Names one generated source-fragment proc.
-spec plane_name(map()) -> iodata().
plane_name(#{id := Id}) ->
    [string:titlecase(atom_to_list(Id)), "ReductionPlane"].

%% Names the captured-effect publication endpoint for a group.
-spec batch_output_name(map()) -> [string(),...].
batch_output_name(#{id := Id}) ->
    [atom_to_list(Id), "_reduction_out"].



%% Names the aggregate arbiter feeding a physical group.
-spec mux_name(map()) -> [string(),...].
mux_name(#{index := Index}) ->
    ["SchedulerAggregateArrayMux", integer_to_list(Index)].

%% Names the retained arbitration state for aggregate delivery.
-spec mux_state_name(map()) -> [string(),...].
mux_state_name(#{index := Index}) ->
    ["SchedulerAggregateArrayMuxState", integer_to_list(Index)].

%% Templates expose each substitution once and reject missing or unresolved bindings.
-spec render_template(string(), [{binary(), iodata()}]) -> binary().
render_template(Name, Bindings) ->
    Path = filename:join([code:priv_dir(hls_fabric), "xls", "templates", Name]),
    {ok, Template} = file:read_file(Path),
    xls_template:render(Template, Bindings).

%% Declares configuration parameters in channel-binding order.
-spec config_signature([iodata()], non_neg_integer()) -> iodata().
config_signature(Arguments, Indent) ->
    Padding = lists:duplicate(Indent + 2, $ ),
    [
        lists:duplicate(Indent, $ ), "config(\n",
        [
            [Padding, Argument, separator(Index, length(Arguments)), "\n"]
            || {Index, Argument} <- lists:enumerate(0, Arguments)
        ],
        lists:duplicate(Indent, $ ), ") {\n"
    ].

%% Adds a separator only when preceding generated elements are present.
-spec separator(integer(),non_neg_integer()) -> [44].
separator(Index, Count) when Index + 1 =:= Count -> [];
separator(_Index, _Count) -> ",".

%% Interleaves a delimiter without adding a leading or trailing separator.
-spec join_with(iodata(), [iodata()]) -> iodata().
join_with(_Separator, []) -> [];
join_with(Separator, [First | Rest]) ->
    [First | [[Separator, Item] || Item <- Rest]].
