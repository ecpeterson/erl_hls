%%%% xls_topology_scheduler_dslx
%%%%
%%%% Compact group-routed topology for homogeneous shared actor schedulers.

-module(xls_topology_scheduler_dslx).
-moduledoc false.

-export([emit/1]).

-spec emit(map()) -> iolist().
emit(Spec0) ->
    Spec = annotate(Spec0),
    [
        preamble(Spec),
        address_support(Spec),
        reduction_support(Spec),
        frame_relay(Spec),
        control_support(Spec),
        [startup_proc(Spec, Scheduler)
            || Scheduler <- maps:get(schedulers, Spec)],
        [router_proc(Spec, Scheduler)
            || Scheduler <- maps:get(schedulers, Spec)],
        grid_proc(Spec),
        top_proc(Spec)
    ].

frame_relay(#{externals := []}) -> [];
frame_relay(#{externals := Externals}) ->
    [
        """
        proc FrameRelay {
          frame_in: chan<axis::Frame> in;
          frame_out: chan<axis::Frame> out;

          config(
              frame_in: chan<axis::Frame> in,
              frame_out: chan<axis::Frame> out
          ) {
            (frame_in, frame_out)
          }

          init { () }

          next(state: ()) {
            let (tok, frame) = recv(join(), frame_in);
            let _done = send(tok, frame_out, frame);
            state
          }
        }

        """,
        case lists:any(
            fun(#{source_schedulers := Sources}) -> length(Sources) > 1 end,
            Externals
        ) of
            false -> [];
            true -> frame_array_mux()
        end
    ].

frame_array_mux() ->
    """
    proc FrameArrayMux<INPUT_COUNT: u32> {
      frame_in: chan<axis::Frame>[INPUT_COUNT] in;
      frame_out: chan<axis::Frame> out;

      config(
          frame_in: chan<axis::Frame>[INPUT_COUNT] in,
          frame_out: chan<axis::Frame> out
      ) {
        (frame_in, frame_out)
      }

      init { u32:0 }

      next(cursor: u32) {
        let (tok, received, frame) =
          unroll_for! (candidate, acc):
              (u32, (token, u1, axis::Frame)) in u32:0..INPUT_COUNT {
            let selected = cursor == candidate;
            let (next_tok, next_frame, valid) = recv_if_non_blocking(
              acc.0, frame_in[candidate], selected, zero!<axis::Frame>());
            (
              next_tok,
              acc.1 | valid,
              if valid { next_frame } else { acc.2 }
            )
          }((join(), u1:0, zero!<axis::Frame>()));
        let _done = send_if(tok, frame_out, received, frame);
        if cursor + u32:1 == INPUT_COUNT {
          u32:0
        } else {
          cursor + u32:1
        }
      }
    }

    """.

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
    Domains = xls_topology_effect_windows:partition(
        Annotated0,
        WindowPartition
    ),
    Membership = maps:from_list([
        {SchedulerIndex0, {DomainIndex, Position}}
        || {DomainIndex, Members} <- lists:enumerate(0, Domains),
           {Position, SchedulerIndex0} <- lists:enumerate(0, Members)
    ]),
    Annotated = [
        begin
            {Domain, Position} = maps:get(
                maps:get(index, Scheduler), Membership
            ),
            Scheduler#{
                effect_window_domain => Domain,
                effect_window_position => Position
            }
        end
        || Scheduler <- Annotated0
    ],
    Externals = [annotate_external(External, Annotated)
        || External <- maps:get(externals, Spec)],
    ReductionPlanes = annotate_reduction_planes(
        Families,
        maps:get(width, Spec),
        maps:get(height, Spec)
    ),
    Spec#{
        family_index => FamilyIndex,
        scheduler_index => maps:from_list([
            {maps:get(index, Scheduler), Scheduler}
            || Scheduler <- Annotated
        ]),
        family_schedulers => FamilySchedulers,
        schedulers => Annotated,
        effect_window_domains => Domains,
        reduction_planes => ReductionPlanes,
        externals => Externals
    }.

annotate_external(External = #{id := Id}, Schedulers) ->
    Sources = [
        maps:get(index, Scheduler)
        || Scheduler <- Schedulers,
           lists:member(Id, maps:get(external_ids, Scheduler))
    ],
    [_ | _] = Sources,
    External#{source_schedulers => Sources}.

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
    Scheduler#{
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
        has_reductions => lists:any(
            fun family_has_reductions/1,
            MemberFamilies
        ),
        joined_reduction_families => [
            Family || Family <- MemberFamilies,
            is_joined_reduction(Family)
        ],
        index => Index
    }.

is_joined_reduction(#{reduction_transport := #{mode := joined}}) -> true;
is_joined_reduction(_Family) -> false.

family_has_reductions(#{interface := Interface}) ->
    maps:get(reductions, Interface, none) =/= none.

annotate_reduction_planes(Families, Width, Height) ->
    [annotate_reduction_plane(Family, Width, Height)
        || Family <- Families,
           is_joined_reduction(Family)].

annotate_reduction_plane(
    Family = #{id := Id, schedulers := Bindings},
    Width,
    Height
) ->
    SourceSchedulers = [maps:get(group, Binding) || Binding <- Bindings],
    CoordinateRows = lists:append([
        [
            begin
                [X, Y] = maps:get(coordinates, Instance),
                Slot = maps:get(base_slot, Binding) +
                    maps:get(local_index, Instance),
                #{x => X, y => Y, group => maps:get(group, Binding),
                    slot => Slot}
            end
            || Instance <- maps:get(instances, Binding)
        ]
        || Binding <- Bindings
    ]),
    Width = 1 + lists:max([maps:get(x, Row) || Row <- CoordinateRows]),
    Height = 1 + lists:max([maps:get(y, Row) || Row <- CoordinateRows]),
    Dense = lists:keysort(1, [
        {maps:get(x, Row) * Height + maps:get(y, Row), Row}
        || Row <- CoordinateRows
    ]),
    lists:seq(0, Width * Height - 1) =:=
        [Index || {Index, _Row} <- Dense] orelse
        error({joined_reduction_sparse_family, Id}),
    Family#{
        stem => [atom_to_list(Id), "_reduction"],
        width => Width,
        height => Height,
        source_schedulers => SourceSchedulers,
        destinations => [Row#{index => Index} || {Index, Row} <- Dense],
        module_name => maps:get(module_name, Family)
    }.

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
    [Item#{slot => maps:get([X, Y], Coordinates)}
        || Item = #{coordinates := [X, Y]} <- Items,
           maps:is_key([X, Y], Coordinates)].

scheduler_family_member(#{id := Id}, #{members := Members}) ->
    hd([Member || Member = #{kind := family, id := MemberId} <- Members,
        MemberId =:= Id]).

%%%
%%% Preamble and common control
%%%

preamble(Spec = #{families := Families}) ->
    Modules = lists:usort([
        maps:get(module_name, Family) || Family <- Families
    ]),
    [
        "// ", maps:get(name, Spec), ".x\n",
        "// Auto-generated from compact Erlang topology and scheduler rules.\n",
        "// Manual changes will be overwritten.\n",
        "//\n",
        "// Actor state and mailbox frames use separate RAMs. Requests and\n",
        "// scheduler effect batches carry dense RAM slots; each group router\n",
        "// maps its slot to a narrow family and coordinate address, then\n",
        "// drains the effects in source order.\n\n",
        "import axis;\n",
        "import effect_window;\n",
        case maps:get(ingresses, Spec) of
            [] -> [];
            [_] -> "import hls_spatial_router;\n"
        end,
        [["import ", Module, ";\n"] || Module <- Modules],
        "\n",
        "const CHANNEL_DEPTH = u32:",
        integer_to_list(maps:get(depth, Spec)), ";\n",
        "const WIDTH = u16:", integer_to_list(maps:get(width, Spec)), ";\n",
        "const HEIGHT = u16:", integer_to_list(maps:get(height, Spec)),
        ";\n\n"
    ].

address_support(Spec = #{families := Families, schedulers := Schedulers}) ->
    [
        "enum FamilyId : u8 {\n",
        [
            ["  ", uppercase(maps:get(id, Family)), " = u8:",
                integer_to_list(Index), ",\n"]
            || {Index, Family} <- lists:enumerate(0, Families)
        ],
        "}\n\n",
        "struct ScheduledAddress {\n",
        "  family: u8,\n",
        "  x: u16,\n",
        "  y: u16,\n",
        "}\n\n",
        [scheduler_address_support(Spec, Scheduler)
            || Scheduler <- Schedulers],
        destination_support(Families)
    ].

destination_support(Families) ->
    Sharded = [Family || Family <- Families,
        length(maps:get(schedulers, Family)) > 1],
    case Sharded of
        [] -> [];
        [_ | _] -> [
            "struct ScheduledDestination {\n",
            "  scheduler: u8,\n",
            "  slot: u32,\n",
            "}\n\n",
            [family_destination_support(Family) || Family <- Sharded]
        ]
    end.

family_destination_support(#{id := Id, schedulers := Bindings}) ->
    Entries = lists:append([
        [
            {maps:get(coordinates, Instance), maps:get(group, Binding),
                maps:get(base_slot, Binding) +
                    maps:get(local_index, Instance)}
            || Instance <- maps:get(instances, Binding)
        ]
        || Binding <- Bindings
    ]),
    [
        "fn ", atom_to_list(Id),
        "_destination(x: u16, y: u16) -> ScheduledDestination {\n",
        "  match (x, y) {\n",
        [
            ["    (u16:", integer_to_list(X), ", u16:",
                integer_to_list(Y), ") => ScheduledDestination { ",
                "scheduler: u8:", integer_to_list(Group), ", slot: u32:",
                integer_to_list(Slot), " },\n"]
            || {[X, Y], Group, Slot} <- Entries
        ],
        "    _ => zero!<ScheduledDestination>(),\n",
        "  }\n",
        "}\n\n"
    ].

scheduler_address_support(_Spec, Scheduler = #{
    stem := Stem,
    slot_count := SlotCount
}) ->
    Entries = scheduler_address_entries(Scheduler),
    true = length(Entries) =:= SlotCount,
    [
        "fn ", Stem, "_address(slot: u32) -> ScheduledAddress {\n",
        "  match slot {\n",
        [
            ["    u32:", integer_to_list(Slot), " => ",
                scheduled_address(Family, X, Y), ",\n"]
            || {Slot, Family, X, Y} <- Entries
        ],
        "    _ => zero!<ScheduledAddress>(),\n",
        "  }\n",
        "}\n\n",
        "fn ", Stem, "_slot(address: ScheduledAddress) -> u32 {\n",
        "  match (address.family as FamilyId, address.x, address.y) {\n",
        [
            [
                "    (FamilyId::", uppercase(Family), ", u16:",
                integer_to_list(X), ", u16:", integer_to_list(Y),
                ") => u32:", integer_to_list(Slot), ",\n"
            ]
            || {Slot, Family, X, Y} <- Entries
        ],
        "    _ => u32:", integer_to_list(SlotCount), ",\n",
        "  }\n",
        "}\n\n"
    ].

scheduler_address_entries(#{members := Members}) ->
    lists:keysort(1, lists:append([
        family_address_entries(Member) || Member <- Members
    ])).

family_address_entries(#{
    id := Family,
    base_slot := Base,
    instances := Instances
}) ->
    [
        {Base + Local, Family, X, Y}
        || #{coordinates := [X, Y], local_index := Local} <- Instances
    ].

%% A joined reduction plane buffers one fixed source batch per scheduler and
%% folds it into a small register bank with statically selected writes. Each
%% destination keeps its current window plus one causally permitted lookahead
%% window: a neighbor cannot enter k+2 before this actor has itself entered
%% k+1. Ingress and completed-aggregate retirement are independent work in one
%% activation; retirement is applied first when both touch the same receptacle.
%% One completed aggregate stream per destination shard bypasses ordinary
%% mailbox storage and credits; the request's slot selects the actor-local
%% receptacle.
reduction_support(#{reduction_planes := Planes, schedulers := Schedulers}) ->
    [
        [aggregate_idle_proc(Scheduler)
            || Scheduler <- Schedulers,
               maps:get(has_reductions, Scheduler),
               maps:get(joined_reduction_families, Scheduler) =:= []],
        [[reduction_batch(Plane), reduction_plane_proc(Plane)]
            || Plane <- Planes]
    ].

aggregate_idle_proc(Scheduler = #{module_name := Module}) ->
    Name = aggregate_idle_name(Scheduler),
    [
        "// Own an unused optional aggregate producer without manufacturing\n",
        "// a zero-valued request on an ordinary reduction transport.\n",
        "proc ", Name, " {\n",
        "  aggregate_out: chan<", Module,
        "::ReductionAggregateRequest> out;\n\n",
        "  config(aggregate_out: chan<", Module,
        "::ReductionAggregateRequest> out) {\n",
        "    (aggregate_out,)\n",
        "  }\n\n",
        "  init { () }\n\n",
        "  next(state: ()) {\n",
        "    let _done = send_if(\n",
        "      join(), aggregate_out, false,\n",
        "      zero!<", Module, "::ReductionAggregateRequest>());\n",
        "    state\n",
        "  }\n",
        "}\n\n"
    ].

reduction_batch(Plane = #{module_name := Module}) ->
    Population = reduction_population(Plane),
    FoldLanes = reduction_fold_lanes(Plane),
    [
        "struct ", reduction_batch_name(Plane), " {\n",
        "  destinations: u32[u32:", integer_to_list(Population), "],\n",
        "  frames: axis::Frame[u32:", integer_to_list(Population), "],\n",
        "}\n\n",
        case FoldLanes < Population of
            true -> [
                "struct ", reduction_work_name(Plane), " {\n",
                "  valid: u1,\n",
                "  destination: u32,\n",
                "  frame: axis::Frame,\n",
                "}\n\n"
            ];
            false -> []
        end,
        "// The batch is a physical transport optimization for one fixed,\n",
        "// statically validated prefix of independent ", Module,
        " effects.\n\n",
        "fn ", reduction_destinations_name(Plane), "(source: u32)\n",
        "    -> u32[u32:", integer_to_list(Population), "] {\n",
        "  match source {\n",
        [reduction_destinations_arm(Plane, Destination)
            || Destination <- maps:get(destinations, Plane)],
        "    _ => zero!<u32[u32:", integer_to_list(Population), "]>(),\n",
        "  }\n",
        "}\n\n"
    ].

reduction_plane_proc(Plane = #{
    module_name := Module,
    source_schedulers := Sources,
    destinations := Destinations
}) ->
    SourceCount = length(Sources),
    DestinationCount = length(Destinations),
    Population = reduction_population(Plane),
    FoldLanes = reduction_fold_lanes(Plane),
    Buffered = FoldLanes < Population,
    State = reduction_state_name(Plane),
    Members = [
        ["batch_in: chan<", reduction_batch_name(Plane), ">[u32:",
            integer_to_list(SourceCount), "] in"]
        | [["aggregate_out_", integer_to_list(Index), ": chan<", Module,
            "::ReductionAggregateRequest> out"]
            || Index <- lists:seq(0, SourceCount - 1)]
    ],
    Names = ["batch_in" | [["aggregate_out_", integer_to_list(Index)]
        || Index <- lists:seq(0, SourceCount - 1)]],
    [
        "struct ", State, " {\n",
        "  input_cursor: u32,\n",
        "  output_cursor: u32,\n",
        "  aggregate_pairs: ", Module, "::ReductionAggregatePair[u32:",
        integer_to_list(DestinationCount), "],\n",
        case Buffered of
            true -> [
                "  pending_valid: u1,\n",
                "  pending_cursor: u32,\n",
                "  pending_batch: ", reduction_batch_name(Plane), ",\n"
            ];
            false -> []
        end,
        "}\n\n",
        "proc ", reduction_plane_name(Plane), " {\n",
        [["  ", Member, ";\n"] || Member <- Members],
        "\n",
        config_signature(Members, 2),
        "    (", join_with(", ", Names), ")\n",
        "  }\n\n",
        "  init { zero!<", State, ">() }\n\n",
        "  next(state: ", State, ") {\n",
        "    // Materialize only one ready bit per destination; the payloads\n",
        "    // remain in their register-resident aggregate pairs. Selecting\n",
        "    // any ready row avoids spending activations scanning incomplete\n",
        "    // destinations.\n",
        "    let ready_slots = unroll_for! (candidate, ready):\n",
        "        (u32, u1[u32:", integer_to_list(DestinationCount),
        "]) in u32:0..u32:", integer_to_list(DestinationCount), " {\n",
        "      update(ready, candidate, ", Module,
        "::reduction_aggregate_ready(\n",
        "        state.aggregate_pairs[candidate].current))\n",
        "    }(zero!<u1[u32:", integer_to_list(DestinationCount), "]>());\n",
        "    let (output_ready, output_slot) =\n",
        "      unroll_for! (offset, selected):\n",
        "          (u32, (u1, u32)) in u32:0..u32:",
        integer_to_list(DestinationCount), " {\n",
        "        let unwrapped = state.output_cursor + offset;\n",
        "        let candidate = if unwrapped < u32:",
        integer_to_list(DestinationCount), " { unwrapped } else {\n",
        "          unwrapped - u32:", integer_to_list(DestinationCount),
        " };\n",
        "        let take = !selected.0 && ready_slots[candidate];\n",
        "        (selected.0 || take,\n",
        "          if take { candidate } else { selected.1 })\n",
        "      }((u1:0, u32:0));\n",
        "    let output_tok = if output_ready {\n",
        "      match output_slot {\n",
        [reduction_output_send_arm(Plane, Destination)
            || Destination <- Destinations],
        "        _ => join(),\n",
        "      }\n",
        "    } else {\n",
        "      join()\n",
        "    };\n",
        "    // Input polling proceeds independently of aggregate retirement.\n",
        "    // Independent tokens allow the generated pipeline to overlap the\n",
        "    // two handshakes while the single state update below remains the\n",
        "    // only owner of the aggregate-pair bank.\n",
        reduction_pending_capacity(Plane),
        "    let (input_tok, received, batch) =\n",
        "      unroll_for! (candidate, acc):\n",
        "          (u32, (token, u1, ", reduction_batch_name(Plane),
        ")) in u32:0..u32:", integer_to_list(SourceCount), " {\n",
        "        let (next_tok, next_batch, valid) =\n",
        "          recv_if_non_blocking(\n",
        "            acc.0, batch_in[candidate],\n",
        reduction_input_condition(Plane),
        "            zero!<", reduction_batch_name(Plane), ">());\n",
        "        (next_tok, acc.1 || valid,\n",
        "          if valid { next_batch } else { acc.2 })\n",
        "      }((join(), u1:0, zero!<", reduction_batch_name(Plane),
        ">()));\n",
        "    // Retire first. A same-cycle next-window contribution is then\n",
        "    // classified against the promoted lookahead aggregate.\n",
        "    let retired_pairs = if output_ready {\n",
        "      update(\n",
        "        state.aggregate_pairs, output_slot,\n",
        "        ", Module, "::ReductionAggregatePair {\n",
        "          current: state.aggregate_pairs[output_slot].lookahead,\n",
        "          lookahead: zero!<", Module,
        "::ReductionAggregate>(),\n",
        "        })\n",
        "    } else { state.aggregate_pairs };\n",
        reduction_plane_updates(Plane, "retired_pairs"),
        "    let _done = join(output_tok, input_tok);\n",
        "    ", State, " {\n",
        reduction_input_cursor(Plane, SourceCount),
        "      output_cursor: if !output_ready { state.output_cursor\n",
        "      } else if output_slot + u32:1 == u32:",
        integer_to_list(DestinationCount), " { u32:0 } else {\n",
        "        output_slot + u32:1 },\n",
        "      aggregate_pairs,\n",
        reduction_pending_state(Plane),
        "    }\n",
        "  }\n",
        "}\n\n"
    ].

reduction_output_send_arm(Plane, Destination = #{index := Index}) ->
    Module = maps:get(module_name, Plane),
    Sources = maps:get(source_schedulers, Plane),
    Group = maps:get(group, Destination),
    Output = source_position(Group, Sources, 0),
    [
        "        u32:", integer_to_list(Index), " => {\n",
        "          send(\n",
        "            join(), aggregate_out_", integer_to_list(Output),
        ", ", Module, "::ReductionAggregateRequest {\n",
        "              slot: u32:",
        integer_to_list(maps:get(slot, Destination)), ",\n",
        "              reduction_aggregate: state.aggregate_pairs[u32:",
        integer_to_list(Index), "].current,\n",
        "            })\n",
        "        },\n"
    ].

reduction_destinations_arm(Plane, #{index := Source, x := X, y := Y}) ->
    Routes = maps:get(routes, maps:get(reduction_transport, Plane)),
    Destinations = [
        begin
            #{recipient := Recipient} = Route,
            {family, _DestinationId,
                {translate, [DX, DY], wrap}} = Recipient,
            fixed_reduction_destination(Plane, X, Y, DX, DY)
        end
        || Route <- Routes
    ],
    [
        "    u32:", integer_to_list(Source), " => [",
        join_with(", ", [["u32:", integer_to_list(Destination)]
            || Destination <- Destinations]),
        "],\n"
    ].

reduction_pending_capacity(Plane) ->
    Population = reduction_population(Plane),
    FoldLanes = reduction_fold_lanes(Plane),
    case FoldLanes < Population of
        false -> [];
        true -> [
            "    let pending_remaining = if state.pending_valid {\n",
            "      u32:", integer_to_list(Population),
            " - state.pending_cursor\n",
            "    } else { u32:0 };\n",
            "    let can_receive = !state.pending_valid ||\n",
            "      pending_remaining < u32:",
            integer_to_list(FoldLanes), ";\n"
        ]
    end.

reduction_input_condition(Plane) ->
    case reduction_fold_lanes(Plane) < reduction_population(Plane) of
        false -> "            state.input_cursor == candidate,\n";
        true -> [
            "            can_receive &&\n",
            "              state.input_cursor == candidate,\n"
        ]
    end.

reduction_plane_updates(Plane, Base) ->
    Population = reduction_population(Plane),
    FoldLanes = reduction_fold_lanes(Plane),
    case FoldLanes < Population of
        false -> [
            "    let aggregate_pairs = if received {\n",
            reduction_batch_updates(Plane, Base),
            "    } else { retired_pairs };\n"
        ];
        true -> [
            [reduction_work(Plane, Index)
                || Index <- lists:seq(0, FoldLanes - 1)],
            reduction_work_updates(Plane, Base),
            "    let aggregate_pairs = aggregate_pairs_",
            integer_to_list(FoldLanes - 1), ";\n"
        ]
    end.

reduction_work(Plane, Index) ->
    Work = reduction_work_name(Plane),
    IndexText = integer_to_list(Index),
    [
        "    let work_", IndexText,
        "_from_pending = state.pending_valid &&\n",
        "      u32:", IndexText, " < pending_remaining;\n",
        "    let work_", IndexText,
        "_from_received = received &&\n",
        "      u32:", IndexText, " >= pending_remaining;\n",
        "    let work_", IndexText, "_pending_index =\n",
        "      if work_", IndexText, "_from_pending {\n",
        "        state.pending_cursor + u32:", IndexText,
        "\n      } else { u32:0 };\n",
        "    let work_", IndexText, "_received_index =\n",
        "      if work_", IndexText, "_from_received {\n",
        "        u32:", IndexText,
        " - pending_remaining\n",
        "      } else { u32:0 };\n",
        "    let work_", IndexText, " = ", Work, " {\n",
        "      valid: work_", IndexText, "_from_pending ||\n",
        "        work_", IndexText, "_from_received,\n",
        "      destination: if work_", IndexText,
        "_from_pending {\n",
        "        state.pending_batch.destinations[",
        "work_", IndexText, "_pending_index]\n",
        "      } else if work_", IndexText, "_from_received {\n",
        "        batch.destinations[work_", IndexText,
        "_received_index]\n",
        "      } else { u32:0 },\n",
        "      frame: if work_", IndexText, "_from_pending {\n",
        "        state.pending_batch.frames[work_", IndexText,
        "_pending_index]\n",
        "      } else if work_", IndexText, "_from_received {\n",
        "        batch.frames[work_", IndexText,
        "_received_index]\n",
        "      } else { zero!<axis::Frame>() },\n",
        "    };\n"
    ].

reduction_work_updates(Plane = #{module_name := Module}, Base) ->
    FoldLanes = reduction_fold_lanes(Plane),
    [
        begin
            Previous = case Index of
                0 -> Base;
                _ -> ["aggregate_pairs_", integer_to_list(Index - 1)]
            end,
            IndexText = integer_to_list(Index),
            [
                "    let aggregate_pairs_", IndexText,
                " = if work_", IndexText, ".valid {\n",
                "      update(\n",
                "        ", Previous, ", work_", IndexText,
                ".destination,\n",
                "        ", Module,
                "::reduction_aggregate_pair_push(\n",
                "          ", Previous, "[work_", IndexText,
                ".destination],\n",
                "          work_", IndexText, ".frame))\n",
                "    } else { ", Previous, " };\n"
            ]
        end
        || Index <- lists:seq(0, FoldLanes - 1)
    ].

reduction_input_cursor(Plane, SourceCount) ->
    Advance = [
        "if state.input_cursor + u32:1 == u32:",
        integer_to_list(SourceCount), " { u32:0 } else {\n",
        "        state.input_cursor + u32:1 }"
    ],
    case reduction_fold_lanes(Plane) < reduction_population(Plane) of
        false -> ["      input_cursor: ", Advance, ",\n"];
        true -> [
            "      input_cursor: if !can_receive { state.input_cursor\n",
            "      } else { ", Advance, " },\n"
        ]
    end.

reduction_pending_state(Plane) ->
    FoldLanes = reduction_fold_lanes(Plane),
    case FoldLanes < reduction_population(Plane) of
        false -> [];
        true -> [
            "      pending_valid: if received { u1:1 } else {\n",
            "        state.pending_valid && pending_remaining > u32:",
            integer_to_list(FoldLanes), "\n",
            "      },\n",
            "      pending_cursor: if received {\n",
            "        u32:", integer_to_list(FoldLanes),
            " - pending_remaining\n",
            "      } else if state.pending_valid &&\n",
            "          pending_remaining > u32:",
            integer_to_list(FoldLanes), " {\n",
            "        state.pending_cursor + u32:",
            integer_to_list(FoldLanes), "\n",
            "      } else { u32:0 },\n",
            "      pending_batch: if received { batch } else {\n",
            "        state.pending_batch\n",
            "      },\n"
        ]
    end.

reduction_batch_updates(Plane = #{module_name := Module}, Base) ->
    Population = reduction_population(Plane),
    [
        [
            begin
                Previous = case Index of
                    0 -> Base;
                    _ -> ["aggregate_pairs_", integer_to_list(Index - 1)]
                end,
                [
                    "        let aggregate_pairs_", integer_to_list(Index),
                    " = update(\n",
                    "          ", Previous,
                    ", batch.destinations[u32:", integer_to_list(Index),
                    "],\n",
                    "          ", Module,
                    "::reduction_aggregate_pair_push(\n",
                    "            ", Previous,
                    "[batch.destinations[u32:", integer_to_list(Index),
                    "]],\n",
                    "            batch.frames[u32:",
                    integer_to_list(Index), "]));\n"
                ]
            end
            || Index <- lists:seq(0, Population - 1)
        ],
        "        aggregate_pairs_", integer_to_list(Population - 1), "\n"
    ].

reduction_population(#{reduction_transport := #{population := Population}}) ->
    Population.

reduction_fold_lanes(#{reduction_transport := #{fold_lanes := FoldLanes}}) ->
    FoldLanes.

scheduled_address(Family, X, Y) ->
    [
        "ScheduledAddress { family: FamilyId::",
        uppercase(Family), " as u8, x: ", u16_value(X),
        ", y: ", u16_value(Y), " }"
    ].

u16_value(Value) when is_integer(Value) ->
    ["u16:", integer_to_list(Value)];
u16_value(Value) -> Value.

control_support(#{ingresses := []}) -> [];
control_support(Spec = #{ingresses := [Ingress]}) ->
    Controlled = [
        Family
        || Family <- maps:get(families, Spec),
           maps:get(ingress, Family) =/= none
    ],
    [
        "enum ControlFamily : u8 {\n",
        [control_family_member(Index, Family)
            || {Index, Family} <- lists:enumerate(0, Controlled)],
        "}\n\n",
        "struct ControlState {\n",
        "  active: u1,\n",
        "  packet: hls_spatial_router::SpatialFrame,\n",
        "  family: u8,\n",
        "  x: u16,\n",
        "  y: u16,\n",
        "}\n\n",
        "proc ControlDispatcher {\n",
        "  spatial_in: chan<hls_spatial_router::SpatialFrame> in;\n",
        [control_member(Spec, Group) || Group <-
            controlled_groups(Controlled)],
        "\n",
        config_signature(
            ["spatial_in: chan<hls_spatial_router::SpatialFrame> in"] ++
                [control_argument(Spec, Group)
                    || Group <- controlled_groups(Controlled)],
            2
        ),
        "    (spatial_in",
        [[", ", control_output_name(Group)]
            || Group <- controlled_groups(Controlled)],
        ")\n  }\n\n",
        "  init { zero!<ControlState>() }\n\n",
        "  next(state: ControlState) {\n",
        "    if !state.active {\n",
        "      let (_tok, packet) = recv(join(), spatial_in);\n",
        "      ControlState { active: u1:1, packet,\n",
        "        ..zero!<ControlState>() }\n",
        "    } else {\n",
        "      let _done = match state.family as ControlFamily {\n",
        [control_family_arm(Spec, Ingress, Family)
            || Family <- Controlled],
        "        _ => join(),\n",
        "      };\n",
        control_advance(Spec, length(Controlled)),
        "    }\n",
        "  }\n",
        "}\n\n"
    ].

control_family_member(Index, #{id := Id}) ->
    ["  ", uppercase(Id), " = u8:", integer_to_list(Index), ",\n"].

controlled_groups(Families) ->
    lists:usort(lists:append([
        [maps:get(group, Binding)
            || Binding <- maps:get(schedulers, Family)]
        || Family <- Families
    ])).

control_member(Spec, Group) ->
    Module = scheduler_module(Spec, Group),
    ["  ", control_output_name(Group), ": chan<", Module,
        "::ScheduledRequest> out;\n"].

control_argument(Spec, Group) ->
    Module = scheduler_module(Spec, Group),
    [control_output_name(Group), ": chan<", Module,
        "::ScheduledRequest> out"].

control_family_arm(Spec, Ingress, Family = #{schedulers := [Binding]}) ->
    control_family_arm_single(Spec, Ingress, Family, Binding);
control_family_arm(Spec, Ingress, Family = #{
    id := Id,
    schedulers := Bindings,
    ingress := #{scale := [ScaleX, ScaleY], offset := [OffsetX, OffsetY]}
}) ->
    [First | _] = Bindings,
    Module = scheduler_module(Spec, maps:get(group, First)),
    [
        "        ControlFamily::", uppercase(Id), " => {\n",
        control_address(ScaleX, ScaleY, OffsetX, OffsetY),
        "          let selected = (", control_target_condition(
            maps:get(targets, maps:get(ingress, Family)),
            Ingress
        ), ") && hls_spatial_router::contains(\n",
        "            state.packet.rectangle, address_x, address_y);\n",
        "          let destination = ", atom_to_list(Id),
        "_destination(state.x, state.y);\n",
        "          match destination.scheduler {\n",
        [
            begin
                Group = maps:get(group, Binding),
                ["            u8:", integer_to_list(Group),
                    " => send_if(join(), ", control_output_name(Group),
                    ", selected, ", Module, "::ScheduledRequest {\n",
                    "              slot: destination.slot,\n",
                    "              frame: state.packet.frame,\n",
                    "              ..zero!<", Module,
                    "::ScheduledRequest>()\n",
                    "            }),\n"]
            end
            || Binding <- Bindings
        ],
        "            _ => join(),\n",
        "          }\n",
        "        },\n"
    ].

control_family_arm_single(Spec, Ingress, Family = #{
    id := Id,
    ingress := #{scale := [ScaleX, ScaleY], offset := [OffsetX, OffsetY]}
}, #{group := Group}) ->
    Module = scheduler_module(Spec, Group),
    Scheduler = scheduler(Spec, Group),
    [
        "        ControlFamily::", uppercase(Id), " => {\n",
        control_address(ScaleX, ScaleY, OffsetX, OffsetY),
        "          let selected = (", control_target_condition(
            maps:get(targets, maps:get(ingress, Family)),
            Ingress
        ), ") && hls_spatial_router::contains(\n",
        "            state.packet.rectangle, address_x, address_y);\n",
        "          let request = ", Module, "::ScheduledRequest {\n",
        "            slot: ", maps:get(stem, Scheduler), "_slot(",
        scheduled_address(Id, "state.x", "state.y"), "),\n",
        "            frame: state.packet.frame,\n",
        "            ..zero!<", Module, "::ScheduledRequest>()\n",
        "          };\n",
        "          send_if(join(), ", control_output_name(Group),
        ", selected, request)\n",
        "        },\n"
    ].

control_address(ScaleX, ScaleY, OffsetX, OffsetY) ->
    [
        "          let address_x = state.x * u16:",
        integer_to_list(ScaleX), " + u16:", integer_to_list(OffsetX),
        ";\n",
        "          let address_y = state.y * u16:",
        integer_to_list(ScaleY), " + u16:", integer_to_list(OffsetY),
        ";\n"
    ].

control_target_condition(TargetIds, #{targets := Targets}) ->
    join_with(" || ", [
        [
            "(state.packet.target == u2:",
            integer_to_list(maps:get(selector, Target)),
            " && (",
            join_with(" || ", [
                ["state.packet.frame.header.op == u8:",
                    integer_to_list(Selector)]
                || {_Schema, Selector, _Fields} <-
                       maps:get(encodings, Target)
            ]),
            "))"
        ]
        || Target = #{id := Id} <- Targets,
           lists:member(Id, TargetIds)
    ]).

control_advance(#{width := Width, height := Height}, FamilyCount) ->
    [
        "      let last_y = state.y + u16:1 == u16:",
        integer_to_list(Height), ";\n",
        "      let last_x = state.x + u16:1 == u16:",
        integer_to_list(Width), ";\n",
        "      let last_family = state.family + u8:1 == u8:",
        integer_to_list(FamilyCount), ";\n",
        "      let family_done = last_y && last_x;\n",
        "      let all_done = family_done && last_family;\n",
        "      ControlState {\n",
        "        active: !all_done,\n",
        "        family: if family_done { state.family + u8:1 }\n",
        "          else { state.family },\n",
        "        x: if last_y {\n",
        "          if last_x { u16:0 } else { state.x + u16:1 }\n",
        "        } else { state.x },\n",
        "        y: if last_y { u16:0 } else { state.y + u16:1 },\n",
        "        ..state\n",
        "      }\n"
    ].

%%%
%%% Startup and group routing
%%%

startup_proc(_Spec, #{startup_count := 0}) -> [];
startup_proc(_Spec, Scheduler = #{
    module_name := Module,
    startup_items := Items
}) ->
    [
        "proc ", startup_name(Scheduler), " {\n",
        "  request_out: chan<", Module, "::ScheduledRequest> out;\n\n",
        "  config(request_out: chan<", Module,
        "::ScheduledRequest> out) { (request_out,) }\n\n",
        "  init { u32:0 }\n\n",
        "  next(index: u32) {\n",
        "    let request = match index {\n",
        [startup_arm(Module, Index, Item)
            || {Index, Item} <- lists:enumerate(0, Items)],
        "      _ => zero!<", Module, "::ScheduledRequest>(),\n",
        "    };\n",
        "    let active = index < u32:", integer_to_list(length(Items)),
        ";\n",
        "    let _done = send_if(join(), request_out, active, request);\n",
        "    if active { index + u32:1 } else { index }\n",
        "  }\n",
        "}\n\n"
    ].

startup_arm(Module, Index, #{
    slot := Slot,
    schema := Schema,
    fields := Fields
}) ->
    Struct = record_struct_name(Schema),
    Function = record_function_name(Schema),
    [
        "      u32:", integer_to_list(Index), " => ",
        Module, "::ScheduledRequest {\n",
        "        slot: u32:", integer_to_list(Slot), ",\n",
        "        frame: axis::pack(\n",
        "          ", Module, "::Tag::", uppercase(Schema), " as u8,\n",
        "          ", Module, "::bits_from_", Function, "(\n",
        "            ", Module, "::", Struct, " {\n",
        [startup_field(Field) || Field <- Fields],
        "            })),\n",
        "        ..zero!<", Module, "::ScheduledRequest>()\n",
        "      },\n"
    ].

startup_field(#{name := Name, type := Type, value := Value})
        when is_integer(Value) ->
    ["              ", atom_to_list(Name), ": ",
        hls_type:print_type(Type), ":", integer_to_list(Value), ",\n"];
startup_field(#{name := Name, type := Type, value := Value}) ->
    error({unsupported_startup_literal, Name, Type, Value}).

router_proc(Spec, Scheduler = #{
    stem := Stem,
    module_name := Module,
    families := Families,
    joined_reduction_families := ReductionFamilies,
    destinations := Destinations,
    external_ids := ExternalIds
}) ->
    StateName = [router_name(Scheduler), "State"],
    Members =
        [
            ["scheduled_in: chan<", Module, "::ScheduledEffects> in"],
            ["credit_out: chan<", Module, "::ScheduledRequest> out"]
        ] ++
        [router_destination_argument(Destination)
            || Destination <- Destinations] ++
        [router_external_argument(Spec, ExternalId)
            || ExternalId <- ExternalIds] ++
        [router_reduction_argument(Spec, Family)
            || Family <- ReductionFamilies] ++
        [
            "window_request_out: chan<u1> out",
            "window_grant_in: chan<u1> in",
            "window_release_out: chan<u1> out"
        ],
    Names = ["scheduled_in", "credit_out"] ++
        [router_destination_name(maps:get(index, Destination))
            || Destination <- Destinations] ++
        [external_output_name(Spec, ExternalId)
            || ExternalId <- ExternalIds] ++
        [router_reduction_output_name(Family)
            || Family <- ReductionFamilies] ++
        ["window_request_out", "window_grant_in", "window_release_out"],
    [
        "// Routes one committed actor-entry batch in source order. A ",
        effect_window_scope(Spec), "\n",
        "// reservation may admit one lookahead batch while the active batch\n",
        "// drains; only the active batch can emit downstream effects.\n",
        "struct ", StateName, " {\n",
        "  active: u1,\n",
        "  scheduled: ", Module, "::ScheduledEffects,\n",
        "  index: u8,\n",
        "  window_requested: u1,\n",
        "  window_granted: u1,\n",
        "  credit_debt: u1,\n",
        "  lookahead: u1,\n",
        "}\n\n",
        "proc ", router_name(Scheduler), " {\n",
        [["  ", Member, ";\n"] || Member <- Members],
        "\n",
        config_signature(Members, 2),
        "    (", join_with(", ", Names), ")\n  }\n\n",
        "  init { zero!<", StateName, ">() }\n\n",
        "  next(state: ", StateName, ") {\n",
        "    let state_effect_info = ", Module,
        "::scheduled_effect(state.scheduled, state.index);\n",
        router_state_reduction_prefix(Module, ReductionFamilies),
        "    let state_last = state.active && if state_reduction_batch {\n",
        "      state_reduction_prefix.2\n",
        "    } else { state_effect_info.2 };\n",
        "    let can_receive = !state.active ||\n",
        "      (state_last && state.credit_debt && !state.lookahead);\n",
        "    let (receive_tok, incoming, incoming_valid) =\n",
        "      recv_if_non_blocking(\n",
        "        join(), scheduled_in, can_receive,\n",
        "        zero!<", Module, "::ScheduledEffects>());\n",
        "    let (grant_tok, _grant, grant_valid) =\n",
        "      recv_if_non_blocking(\n",
        "        receive_tok, window_grant_in,\n",
        "        state.window_requested && !state.window_granted, u1:0);\n",
        "    let batch_valid = state.active || incoming_valid;\n",
        "    let scheduled = if state.active {\n",
        "      state.scheduled\n",
        "    } else { incoming };\n",
        "    let index = if state.active { state.index } else { u8:0 };\n",
        "    let effect_info = ", Module,
        "::scheduled_effect(scheduled, index);\n",
        router_reduction_prefix(Module, ReductionFamilies),
        "    let effect = effect_info.0;\n",
        "    let emit = batch_valid && effect_info.1;\n",
        "    let address = ", Stem, "_address(scheduled.slot);\n",
        "    let routed_tok = if reduction_batch {\n",
        router_reduction_send(Spec, ReductionFamilies),
        "    } else if emit {\n",
        "      match address.family as FamilyId {\n",
        [router_family_arm(Spec, Family) || Family <- Families],
        "        _ => grant_tok,\n",
        "      }\n",
        "    } else { grant_tok };\n",
        "    let last = batch_valid && if reduction_batch {\n",
        "      reduction_prefix.2\n",
        "    } else { effect_info.2 };\n",
        "    let batch_continues = batch_valid && !last;\n",
        "    // Never apply a stale grant to a batch admitted in this same\n",
        "    // activation: the virtual credit could otherwise bypass back to\n",
        "    // SharedService before that batch has made egress_busy visible.\n",
        "    let grant_usable = grant_valid && state.active &&\n",
        "      !state.lookahead && batch_continues;\n",
        "    let fake_credit = grant_usable;\n",
        "    let swallow_physical = last && state.credit_debt &&\n",
        "      !state.lookahead;\n",
        "    let forward_physical = last && !swallow_physical;\n",
        "    let forward_credit = fake_credit || forward_physical;\n",
        "    let credit_tok = send_if(\n",
        "      routed_tok, credit_out, forward_credit, ", Module,
        "::ScheduledRequest {\n",
        "        credit: u1:1,\n",
        "        ..zero!<", Module, "::ScheduledRequest>()\n",
        "      });\n",
        "    let carry_lookahead = last && swallow_physical &&\n",
        "      incoming_valid;\n",
        "    let release = (last && state.lookahead) ||\n",
        "      (last && state.credit_debt && !incoming_valid) ||\n",
        "      (grant_valid && !grant_usable);\n",
        "    let release_tok = send_if(\n",
        "      credit_tok, window_release_out, release, u1:1);\n",
        "    let pending_request = state.window_requested && !grant_valid;\n",
        "    let window_granted =\n",
        "      (state.window_granted || grant_usable) && !release;\n",
        "    let credit_debt =\n",
        "      (state.credit_debt || fake_credit) && !swallow_physical;\n",
        "    let next_active = carry_lookahead || batch_continues;\n",
        "    let next_lookahead = if carry_lookahead { u1:1 } else {\n",
        "      if batch_continues { state.lookahead } else { u1:0 }\n",
        "    };\n",
        "    let request = next_active && !next_lookahead &&\n",
        "      !window_granted && !credit_debt && !pending_request;\n",
        "    let _request_tok = send_if(\n",
        "      release_tok, window_request_out, request, u1:1);\n",
        "    if carry_lookahead {\n",
        "      ", StateName, " {\n",
        "        active: u1:1,\n",
        "        scheduled: incoming,\n",
        "        index: u8:0,\n",
        "        window_requested: u1:0,\n",
        "        window_granted,\n",
        "        credit_debt,\n",
        "        lookahead: u1:1,\n",
        "      }\n",
        "    } else if batch_continues {\n",
        "      ", StateName, " {\n",
        "        active: u1:1,\n",
        "        scheduled,\n",
        "        index: index + if reduction_batch {\n",
        "          reduction_prefix.1\n",
        "        } else { u8:1 },\n",
        "        window_requested: pending_request || request,\n",
        "        window_granted,\n",
        "        credit_debt,\n",
        "        lookahead: state.lookahead,\n",
        "      }\n",
        "    } else {\n",
        "      ", StateName, " {\n",
        "        window_requested: pending_request || request,\n",
        "        ..zero!<", StateName, ">()\n",
        "      }\n",
        "    }\n",
        "  }\n",
        "}\n\n"
    ].

router_destination_argument(#{index := Index, module_name := Module}) ->
    [router_destination_name(Index), ": chan<", Module,
        "::ScheduledRequest> out"].

router_external_argument(Spec, ExternalId) ->
    [external_output_name(Spec, ExternalId), ": chan<axis::Frame> out"].

router_reduction_argument(Spec, Family) ->
    Plane = reduction_plane(Spec, maps:get(id, Family)),
    [router_reduction_output_name(Family), ": chan<",
        reduction_batch_name(Plane), "> out"].

router_state_reduction_prefix(_Module, []) ->
    [
        "    let state_reduction_prefix = (u1:0, u8:0, u1:0);\n",
        "    let state_reduction_batch = u1:0;\n"
    ];
router_state_reduction_prefix(Module, [_ | _]) ->
    [
        "    let state_reduction_prefix = ", Module,
        "::scheduled_reduction_prefix(state.scheduled);\n",
        "    let state_reduction_batch = state.active &&\n",
        "      state.index == u8:0 && state_reduction_prefix.0;\n"
    ].

router_reduction_prefix(_Module, []) ->
    [
        "    let reduction_prefix = (u1:0, u8:0, u1:0);\n",
        "    let reduction_batch = u1:0;\n"
    ];
router_reduction_prefix(Module, [_ | _]) ->
    [
        "    let reduction_prefix = ", Module,
        "::scheduled_reduction_prefix(scheduled);\n",
        "    let reduction_batch = batch_valid && index == u8:0 &&\n",
        "      reduction_prefix.0;\n"
    ].

router_reduction_send(_Spec, []) ->
    "      grant_tok\n";
router_reduction_send(Spec, Families) ->
    [
        "      match address.family as FamilyId {\n",
        [router_reduction_family_arm(Spec, Family) || Family <- Families],
        "        _ => grant_tok,\n",
        "      }\n"
    ].

router_reduction_family_arm(Spec, Family = #{
    id := Id,
    module_name := Module,
    reduction_transport := #{routes := Routes, population := Population}
}) ->
    true = length(Routes) =:= Population,
    Plane = reduction_plane(Spec, Id),
    [
        "        FamilyId::", uppercase(Id), " => {\n",
        [[
            "          let effect_", integer_to_list(Index), " = ",
            Module, "::scheduled_effect(scheduled, u8:",
            integer_to_list(Index), ").0;\n"
        ] || Index <- lists:seq(0, Population - 1)],
        "          let batch = ", reduction_batch_name(Plane), " {\n",
        "            destinations: ", reduction_destinations_name(Plane),
        "((address.x as u32) * (HEIGHT as u32) +\n",
        "              address.y as u32),\n",
        "            frames: [", join_with(", ", [
            ["effect_", integer_to_list(Index), ".frame"]
            || Index <- lists:seq(0, Population - 1)
        ]), "],\n",
        "          };\n",
        "          send(grant_tok, ", router_reduction_output_name(Family),
        ", batch)\n",
        "        },\n"
    ].

fixed_reduction_destination(Spec, X, Y, DX, DY) ->
    Width = maps:get(width, Spec),
    Height = maps:get(height, Spec),
    positive_modulo(X + DX, Width) * Height +
        positive_modulo(Y + DY, Height).

router_family_arm(Spec, Family = #{id := Id}) ->
    [
        "      FamilyId::", uppercase(Id), " => {\n",
        router_family_routes(Spec, Family),
        "      },\n"
    ].

router_family_routes(Spec, Family) ->
    Module = maps:get(module_name, Family),
    RouteIndex = maps:from_list([
        {Port, Route}
        || Route <- maps:get(routes, Family),
           {_Family, Port} <- [maps:get(source, Route)]
    ]),
    [
        "        let x = address.x;\n",
        "        let y = address.y;\n",
        "        match effect.port {\n",
        [
            router_route_arm(
                Spec,
                Module,
                Port,
                maps:get(Port, RouteIndex)
            )
            || Port <- maps:get(outputs, Family)
        ],
        "        }\n"
    ].

router_route_arm(Spec, Module, Port, #{
    delivery := direct,
    recipients := [Recipient]
}) ->
    [
        "        ", Module, "::OutputPort::", uppercase(Port), " => ",
        route_send(Spec, Recipient, "grant_tok"),
        ",\n"
    ];
router_route_arm(Spec, Module, Port, #{
    delivery := queued,
    recipients := [Left, Right]
}) ->
    [
        "        ", Module, "::OutputPort::", uppercase(Port), " => {\n",
        "          let left_tok = ", route_send(Spec, Left, "grant_tok"),
        ";\n",
        "          let right_tok = ", route_send(Spec, Right, "grant_tok"),
        ";\n",
        "          join(left_tok, right_tok)\n",
        "        },\n"
    ].

route_send(Spec, {external, ExternalId}, Token) ->
    ["send(", Token, ", ", external_output_name(Spec, ExternalId),
        ", effect.frame)"];
route_send(
    Spec,
    {family, DestinationId, {translate, [DX, DY], wrap}},
    Token
) ->
    Family = maps:get(DestinationId, maps:get(family_index, Spec)),
    DestinationX = translated_index("x", DX, maps:get(width, Spec)),
    DestinationY = translated_index("y", DY, maps:get(height, Spec)),
    route_send_bindings(
        Spec,
        maps:get(schedulers, Family),
        DestinationId,
        DestinationX,
        DestinationY,
        Token
    ).

route_send_bindings(
    Spec,
    [#{group := Group}],
    DestinationId,
    DestinationX,
    DestinationY,
    Token
) ->
    Scheduler = scheduler(Spec, Group),
    Module = scheduler_module(Spec, Group),
    [
        "send(", Token, ", ", router_destination_name(Group), ", ",
        Module, "::ScheduledRequest {\n",
        "            slot: ", maps:get(stem, Scheduler), "_slot(",
        scheduled_address(DestinationId, DestinationX, DestinationY), "),\n",
        "            frame: effect.frame,\n",
        route_reduction_marker(Scheduler, Module),
        "            ..zero!<", Module, "::ScheduledRequest>()\n",
        "          })"
    ];
route_send_bindings(
    Spec,
    [First | _] = Bindings,
    DestinationId,
    DestinationX,
    DestinationY,
    Token
) ->
    Module = scheduler_module(Spec, maps:get(group, First)),
    [
        "{\n",
        "          let destination = ", atom_to_list(DestinationId),
        "_destination(", DestinationX, ", ", DestinationY, ");\n",
        "          match destination.scheduler {\n",
        [
            begin
                Group = maps:get(group, Binding),
                Scheduler = scheduler(Spec, Group),
                ["            u8:", integer_to_list(Group), " => send(",
                    Token, ", ", router_destination_name(Group), ", ",
                    Module, "::ScheduledRequest {\n",
                    "              slot: destination.slot,\n",
                    "              frame: effect.frame,\n",
                    route_reduction_marker(Scheduler, Module, 14),
                    "              ..zero!<", Module,
                    "::ScheduledRequest>()\n",
                    "            }),\n"]
            end
            || Binding <- Bindings
        ],
        "            _ => ", Token, ",\n",
        "          }\n",
        "        }"
    ].

route_reduction_marker(Scheduler, Module) ->
    route_reduction_marker(Scheduler, Module, 12).

route_reduction_marker(#{reduction_storage_width := Width}, Module, Indent)
        when Width > 0 ->
    [lists:duplicate(Indent, $\s),
        "direct_reduction: ", Module,
        "::direct_reduction_candidate(effect.frame),\n"];
route_reduction_marker(_Scheduler, _Module, _Indent) ->
    [].

translated_index(Axis, Offset, Size) ->
    Shift = positive_modulo(Offset, Size),
    case Shift of
        0 -> Axis;
        _ ->
            Boundary = Size - Shift,
            [
                "(if ", Axis, " >= u16:", integer_to_list(Boundary),
                " { ", Axis, " - u16:", integer_to_list(Boundary),
                " } else { ", Axis, " + u16:",
                integer_to_list(Shift), " })"
            ]
    end.

positive_modulo(Value, Modulus) ->
    ((Value rem Modulus) + Modulus) rem Modulus.

%%%
%%% Network composition
%%%

grid_proc(Spec = #{
    schedulers := Schedulers,
    effect_window_domains := EffectWindowDomains,
    reduction_planes := ReductionPlanes,
    ingresses := Ingresses,
    externals := Externals
}) ->
    Arguments = ram_arguments(Spec) ++ ingress_arguments(Ingresses) ++
        external_arguments(Externals),
    [
        "proc ", grid_name(Spec), " {\n",
        config_signature(Arguments, 2),
        effect_window_channels(EffectWindowDomains),
        [external_channel(External) || External <- Externals],
        [scheduler_channels(Scheduler) || Scheduler <- Schedulers],
        [reduction_plane_channels(Plane) || Plane <- ReductionPlanes],
        effect_window_spawn(EffectWindowDomains),
        [scheduler_spawn(Spec, Scheduler) || Scheduler <- Schedulers],
        [reduction_plane_spawn(Spec, Plane) || Plane <- ReductionPlanes],
        [router_spawn(Spec, Scheduler) || Scheduler <- Schedulers],
        control_spawn(Spec),
        [external_spawn(External) || External <- Externals],
        "    ()\n",
        "  }\n\n",
        "  init { () }\n",
        "  next(state: ()) { state }\n",
        "}\n\n"
    ].

effect_window_channels(Domains) ->
    [effect_window_domain_channels(Index, Members, Domains)
        || {Index, Members} <- lists:enumerate(0, Domains)].

effect_window_domain_channels(Index, Members, Domains) ->
    Count = integer_to_list(length(Members)),
    Stem = effect_window_domain_stem(Index, Domains),
    [
        effect_window_domain_comment(Index, Members, Domains),
        "    let (", Stem, "_request_p, ", Stem, "_request_c) =\n",
        "      chan<u1, CHANNEL_DEPTH>[u32:", Count,
        "](\"", Stem, "_request\");\n",
        "    let (", Stem, "_grant_p, ", Stem, "_grant_c) =\n",
        "      chan<u1, CHANNEL_DEPTH>[u32:", Count,
        "](\"", Stem, "_grant\");\n",
        "    let (", Stem, "_release_p, ", Stem, "_release_c) =\n",
        "      chan<u1, CHANNEL_DEPTH>[u32:", Count,
        "](\"", Stem, "_release\");\n"
    ].

effect_window_spawn(Domains) ->
    [effect_window_domain_spawn(Index, Members, Domains)
        || {Index, Members} <- lists:enumerate(0, Domains)].

effect_window_domain_spawn(Index, Members, Domains) ->
    Stem = effect_window_domain_stem(Index, Domains),
    [
        "    spawn effect_window::Arbiter<u32:",
        integer_to_list(length(Members)), ">(\n",
        "      ", Stem, "_request_c, ", Stem, "_grant_p,\n",
        "      ", Stem, "_release_c);\n"
    ].

external_channel(External) ->
    Stem = external_buffer_name(External),
    case maps:get(source_schedulers, External) of
        [_] ->
            [
                "    let (", Stem, "_p, ", Stem, "_c) =\n",
                "      chan<axis::Frame, CHANNEL_DEPTH>(\"", Stem,
                "\");\n"
            ];
        Sources ->
            [
                "    let (", Stem, "_p, ", Stem, "_c) =\n",
                "      chan<axis::Frame, CHANNEL_DEPTH>[u32:",
                integer_to_list(length(Sources)), "](\"", Stem, "\");\n"
            ]
    end.

external_spawn(External) ->
    Stem = external_buffer_name(External),
    case maps:get(source_schedulers, External) of
        [_] ->
            [
                "    spawn FrameRelay(", Stem, "_c, ",
                maps:get(output_name, External), ");\n"
            ];
        Sources ->
            [
                "    spawn FrameArrayMux<u32:",
                integer_to_list(length(Sources)), ">(", Stem, "_c, ",
                maps:get(output_name, External), ");\n"
            ]
    end.

scheduler_channels(Scheduler = #{
    stem := Stem,
    module_name := Module,
    producers := Producers,
    has_reductions := HasReductions,
    joined_reduction_families := ReductionFamilies
}) ->
    ProducerCount = integer_to_list(length(Producers)),
    [
        "    let (", Stem, "_requests_p, ", Stem, "_requests_c) =\n",
        "      chan<", Module, "::ScheduledRequest, CHANNEL_DEPTH>",
        "[u32:", ProducerCount, "](\"", Stem, "_requests\");\n",
        "    let (", Stem, "_startup_p, ", Stem, "_startup_c) =\n",
        "      chan<", Module, "::ScheduledRequest, CHANNEL_DEPTH>(\"",
        Stem, "_startup\");\n",
        "    let (", Stem, "_egress_p, ", Stem, "_egress_c) =\n",
        "      chan<", Module, "::ScheduledEffects, CHANNEL_DEPTH>(\"",
        Stem, "_egress\");\n",
        case HasReductions of
            false -> [];
            true -> [
                "    let (", Stem, "_aggregate_p, ", Stem,
                "_aggregate_c) =\n",
                "      chan<", Module,
                "::ReductionAggregateRequest, u32:0>(\"", Stem,
                "_aggregate\");\n",
                case ReductionFamilies of
                    [] -> ["    spawn ", aggregate_idle_name(Scheduler),
                        "(", Stem, "_aggregate_p);\n"];
                    [_ | _] -> []
                end
            ]
        end,
        case maps:get(startup_count, Scheduler) of
            0 -> [];
            _ -> ["    spawn ", startup_name(Scheduler), "(",
                Stem, "_startup_p);\n"]
        end
    ].

reduction_plane_channels(#{
    stem := Stem,
    source_schedulers := Sources
} = Plane) ->
    [
        "    let (", Stem, "_batch_p, ", Stem, "_batch_c) =\n",
        "      chan<", reduction_batch_name(Plane),
        ", CHANNEL_DEPTH>[u32:", integer_to_list(length(Sources)),
        "](\"", Stem, "_batch\");\n"
    ].

reduction_plane_spawn(Spec, Plane = #{
    stem := Stem,
    source_schedulers := Sources
}) ->
    [
        "    spawn ", reduction_plane_name(Plane), "(\n",
        "      ", Stem, "_batch_c",
        [[",\n      ", maps:get(stem, scheduler(Spec, Group)),
            "_aggregate_p"] || Group <- Sources],
        ");\n"
    ].

scheduler_spawn(_Spec, #{
    stem := Stem,
    index := Index,
    module_name := Module,
    slot_count := SlotCount,
    producers := Producers,
    startup_count := StartupCount,
    has_reductions := HasReductions
}) ->
    [
        "    spawn ", Module, "::SharedService<\n",
        "      u32:", integer_to_list(SlotCount), ", u32:",
        integer_to_list(length(Producers)), ", u32:",
        integer_to_list(StartupCount), ", u32:",
        integer_to_list(Index), ">(\n",
        "      ", Stem, "_requests_c, ", Stem, "_startup_c,\n",
        "      ", Stem, "_egress_p,\n",
        "      ", Stem, "_ram_read_req_out, ", Stem,
        "_ram_read_resp_in,\n",
        "      ", Stem, "_ram_write_req_out, ", Stem,
        "_ram_write_resp_in,\n",
        "      ", Stem, "_mailbox_read_req_out, ", Stem,
        "_mailbox_read_resp_in,\n",
        "      ", Stem, "_mailbox_write_req_out, ", Stem,
        "_mailbox_write_resp_in",
        case HasReductions of
            false -> [];
            true -> [",\n      ", Stem, "_aggregate_c"]
        end,
        ");\n"
    ].

router_spawn(Spec, Scheduler = #{
    stem := Stem,
    index := Source,
    effect_window_domain := WindowDomain,
    effect_window_position := WindowPosition,
    joined_reduction_families := ReductionFamilies,
    destinations := Destinations,
    external_ids := ExternalIds
}) ->
    CreditIndex = producer_index(Spec, Source, egress_credit),
    [
        "    spawn ", router_name(Scheduler), "(\n",
        "      ", Stem, "_egress_c, ", Stem,
        "_requests_p[u32:", integer_to_list(CreditIndex), "]",
        [
            begin
                DestinationIndex = maps:get(index, Destination),
                ProducerIndex = producer_index(
                    Spec, DestinationIndex, {scheduler, Source}
                ),
                DestinationStem = maps:get(stem, Destination),
                [",\n      ", DestinationStem, "_requests_p[u32:",
                    integer_to_list(ProducerIndex), "]"]
            end
            || Destination <- Destinations
        ],
        [[",\n      ", external_buffer_producer(Spec, ExternalId, Source)]
            || ExternalId <- ExternalIds],
        [
            begin
                Plane = reduction_plane(Spec, maps:get(id, Family)),
                Position = source_position(
                    Source,
                    maps:get(source_schedulers, Plane),
                    0
                ),
                [",\n      ", maps:get(stem, Plane),
                    "_batch_p[u32:", integer_to_list(Position), "]"]
            end
            || Family <- ReductionFamilies
        ],
        ",\n      ", effect_window_domain_stem(
            WindowDomain, maps:get(effect_window_domains, Spec)),
        "_request_p[u32:", integer_to_list(WindowPosition), "],\n",
        "      ", effect_window_domain_stem(
            WindowDomain, maps:get(effect_window_domains, Spec)),
        "_grant_c[u32:", integer_to_list(WindowPosition), "],\n",
        "      ", effect_window_domain_stem(
            WindowDomain, maps:get(effect_window_domains, Spec)),
        "_release_p[u32:", integer_to_list(WindowPosition), "]",
        ");\n"
    ].

control_spawn(#{ingresses := []}) -> [];
control_spawn(Spec = #{ingresses := [#{input_name := InputName}]}) ->
    Groups = controlled_groups([
        Family
        || Family <- maps:get(families, Spec),
           maps:get(ingress, Family) =/= none
    ]),
    [
        "    spawn ControlDispatcher(", InputName,
        [
            begin
                Scheduler = scheduler(Spec, Group),
                Index = producer_index(Spec, Group, control),
                [", ", maps:get(stem, Scheduler),
                    "_requests_p[u32:", integer_to_list(Index), "]"]
            end
            || Group <- Groups
        ],
        ");\n"
    ].

producer_index(Spec, Group, Producer) ->
    maps:get(
        Producer,
        maps:get(producer_index, scheduler(Spec, Group))
    ).

%%%
%%% Top-level boundary
%%%

top_proc(Spec = #{ingresses := Ingresses, externals := Externals}) ->
    Arguments = ram_arguments(Spec) ++ ingress_arguments(Ingresses) ++
        external_arguments(Externals),
    Names = ram_names(Spec) ++ ingress_names(Ingresses) ++
        external_names(Externals),
    [
        "pub proc Top {\n",
        [["  ", Argument, ";\n"] || Argument <- Arguments],
        "\n",
        config_signature(Arguments, 2),
        "    spawn ", grid_name(Spec), "(\n",
        [
            ["      ", Name, separator(Index, length(Names)), "\n"]
            || {Index, Name} <- lists:enumerate(0, Names)
        ],
        "    );\n",
        "    ", channel_tuple(Names), "\n",
        "  }\n\n",
        "  init { () }\n",
        "  next(state: ()) { state }\n",
        "}\n"
    ].

ram_arguments(#{schedulers := Schedulers}) ->
    lists:append([
        scheduler_ram_arguments(Scheduler)
        || Scheduler <- Schedulers
    ]).

scheduler_ram_arguments(#{
    stem := Stem,
    module_name := Module
}) ->
    [
        [Stem, "_ram_read_req_out: chan<", Module,
            "::MachineRamReadReq> out"],
        [Stem, "_ram_read_resp_in: chan<", Module,
            "::MachineRamReadResp> in"],
        [Stem, "_ram_write_req_out: chan<", Module,
            "::MachineRamWriteReq> out"],
        [Stem, "_ram_write_resp_in: chan<", Module,
            "::MachineRamWriteResp> in"],
        [Stem, "_mailbox_read_req_out: chan<", Module,
            "::MailboxRamReadReq> out"],
        [Stem, "_mailbox_read_resp_in: chan<", Module,
            "::MailboxRamReadResp> in"],
        [Stem, "_mailbox_write_req_out: chan<", Module,
            "::MailboxRamWriteReq> out"],
        [Stem, "_mailbox_write_resp_in: chan<", Module,
            "::MailboxRamWriteResp> in"]
    ].

ram_names(#{schedulers := Schedulers}) ->
    lists:append([
        scheduler_ram_names(Scheduler)
        || Scheduler <- Schedulers
    ]).

scheduler_ram_names(#{stem := Stem}) ->
    [
        [Stem, "_ram_read_req_out"],
        [Stem, "_ram_read_resp_in"],
        [Stem, "_ram_write_req_out"],
        [Stem, "_ram_write_resp_in"],
        [Stem, "_mailbox_read_req_out"],
        [Stem, "_mailbox_read_resp_in"],
        [Stem, "_mailbox_write_req_out"],
        [Stem, "_mailbox_write_resp_in"]
    ].

ingress_arguments(Ingresses) ->
    [[maps:get(input_name, Ingress),
        ": chan<hls_spatial_router::SpatialFrame> in"]
        || Ingress <- Ingresses].

ingress_names(Ingresses) ->
    [maps:get(input_name, Ingress) || Ingress <- Ingresses].

external_arguments(Externals) ->
    [[maps:get(output_name, External), ": chan<axis::Frame> out"]
        || External <- Externals].

external_names(Externals) ->
    [maps:get(output_name, External) || External <- Externals].

%%%
%%% Lookups and names
%%%

scheduler(Spec, Group) ->
    maps:get(Group, maps:get(scheduler_index, Spec)).

scheduler_module(Spec, Group) ->
    maps:get(module_name, scheduler(Spec, Group)).

reduction_plane(#{reduction_planes := Planes}, Id) ->
    hd([Plane || Plane = #{id := PlaneId} <- Planes, PlaneId =:= Id]).

external_output_name(#{externals := Externals}, Id) ->
    {external, Id, External} = lists:keyfind(Id, 2, [
        {external, maps:get(id, External), External}
        || External <- Externals
    ]),
    maps:get(output_name, External).

external_buffer_producer(#{externals := Externals}, Id, Source) ->
    {external, Id, External} = lists:keyfind(Id, 2, [
        {external, maps:get(id, Candidate), Candidate}
        || Candidate <- Externals
    ]),
    Stem = external_buffer_name(External),
    case maps:get(source_schedulers, External) of
        [_] -> [Stem, "_p"];
        Sources ->
            Position = source_position(Source, Sources, 0),
            [Stem, "_p[u32:", integer_to_list(Position), "]"]
    end.

source_position(Source, [Source | _], Position) -> Position;
source_position(Source, [_ | Rest], Position) ->
    source_position(Source, Rest, Position + 1).

external_buffer_name(#{index := Index}) ->
    ["external_", integer_to_list(Index), "_buffer"].

router_name(#{index := Index}) ->
    ["SchedulerRouter", integer_to_list(Index)].

router_destination_name(Index) ->
    ["to_scheduler_", integer_to_list(Index)].

control_output_name(Group) ->
    ["scheduler_", integer_to_list(Group), "_control_out"].

startup_name(#{index := Index}) ->
    ["SchedulerStartup", integer_to_list(Index)].

reduction_batch_name(#{id := Id}) ->
    [string:titlecase(atom_to_list(Id)), "ReductionBatch"].

reduction_work_name(#{id := Id}) ->
    [string:titlecase(atom_to_list(Id)), "ReductionWork"].

reduction_destinations_name(#{id := Id}) ->
    [atom_to_list(Id), "_reduction_destinations"].

reduction_state_name(#{id := Id}) ->
    [string:titlecase(atom_to_list(Id)), "ReductionPlaneState"].

reduction_plane_name(#{id := Id}) ->
    [string:titlecase(atom_to_list(Id)), "ReductionPlane"].

router_reduction_output_name(#{id := Id}) ->
    [atom_to_list(Id), "_reduction_out"].

aggregate_idle_name(#{index := Index}) ->
    ["SchedulerAggregateIdle", integer_to_list(Index)].

effect_window_domain_stem(0, [_OnlyDomain]) ->
    "effect_window";
effect_window_domain_stem(Index, [_ | _]) ->
    ["effect_window_domain_", integer_to_list(Index)].

effect_window_domain_comment(_Index, _Members, [_OnlyDomain]) -> [];
effect_window_domain_comment(Index, Members, [_ | _]) ->
    [
        "    // Effect-window domain ", integer_to_list(Index),
        ": schedulers ", join_with(", ", [integer_to_list(Member)
            || Member <- Members]), ".\n"
    ].

effect_window_scope(#{effect_window_domains := [_OnlyDomain]}) ->
    "global";
effect_window_scope(#{effect_window_domains := [_ | _]}) ->
    "domain-".

grid_name(_Spec) -> "SchedulerGrid".

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

channel_tuple([]) -> "()";
channel_tuple([Name]) -> ["(", Name, ",)"];
channel_tuple(Names) -> ["(", join_with(", ", Names), ")"].

uppercase(Atom) -> string:uppercase(atom_to_list(Atom)).

record_struct_name(Atom) ->
    string:titlecase(lists:delete($_, atom_to_list(Atom))).

record_function_name(Atom) ->
    string:lowercase(lists:delete($_, atom_to_list(Atom))).

separator(Index, Count) when Index + 1 < Count -> ",";
separator(_Index, _Count) -> "".

join_with(_Separator, []) -> [];
join_with(Separator, [First | Rest]) ->
    [First | [[Separator, Item] || Item <- Rest]].
