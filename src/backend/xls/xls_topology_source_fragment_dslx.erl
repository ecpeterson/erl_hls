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

-spec captured_port(map(), atom()) -> boolean().
captured_port(Family, Port) ->
    lists:member(Port, maps:get(source_fragment_ports, Family, [])).

%%%
%%% Router integration
%%%

-spec router_arguments(map(), map()) -> [iodata()].
router_arguments(Spec, Scheduler) ->
    [
        [batch_output_name(Plane), ": chan<",
            batch_name(Plane), "> out"]
        || Plane <- scheduler_planes(Spec, Scheduler)
    ].

-spec router_argument_names(map(), map()) -> [iodata()].
router_argument_names(Spec, Scheduler) ->
    [batch_output_name(Plane) || Plane <- scheduler_planes(Spec, Scheduler)].

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

-spec router_send(map(), map()) -> iodata().
router_send(Spec, Scheduler) ->
    Planes = scheduler_planes(Spec, Scheduler),
    [
        "      match address.family as FamilyId {\n",
        [router_family_send(Plane) || Plane <- Planes],
        "        _ => grant_tok,\n",
        "      }\n"
    ].

router_family_send(Plane = #{
    id := Id,
    module_name := Module,
    population := Population,
    fragments := Fragments
}) ->
    Population = length(Fragments),
    [
        "        FamilyId::", uppercase(Id), " => {\n",
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

-spec support(map()) -> iodata().
support(Spec) ->
    [
        [aggregate_mux_proc(Spec, Scheduler)
            || Scheduler <- maps:get(schedulers, Spec),
               length(scheduler_planes(Spec, Scheduler)) > 1],
        [[fragment_declarations(Plane), fragment_plane_proc(Plane)]
            || Plane <- maps:get(source_fragment_planes, Spec, [])]
    ].

fragment_declarations(Plane = #{fragments := Fragments}) ->
    Population = maps:get(population, Plane),
    [
        "struct ", batch_name(Plane), " {\n",
        "  source: u32,\n",
        "  frames: axis::Frame[u32:", integer_to_list(Population), "],\n",
        "}\n\n",
        [fragment_comment(Fragment) || Fragment <- Fragments]
    ].

fragment_comment(#{ordinal := Ordinal, port := Port,
        inverse_offset := [DX, DY], inverse_ordinal := Inverse}) ->
    [
        "// Fragment ", integer_to_list(Ordinal), " (",
        atom_to_list(Port), ") uses inverse fragment ",
        integer_to_list(Inverse), " at offset [",
        integer_to_list(DX), ", ", integer_to_list(DY), "].\n"
    ].

fragment_plane_proc(Plane = #{
    module_name := Module,
    source_schedulers := Sources,
    destinations := Destinations,
    fragments := Fragments
}) ->
    SourceCount = length(Sources),
    ActorCount = length(Destinations),
    Population = maps:get(population, Plane),
    State = state_name(Plane),
    Queue = "frame_queue::Queue",
    Batch = batch_name(Plane),
    InverseRows = inverse_rows(Plane),
    Members = [
        ["batch_in: chan<", Batch, ">[u32:",
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
        "  open_tokens: u1[u32:", integer_to_list(ActorCount), "],\n",
        [["  bank_", integer_to_list(maps:get(ordinal, Fragment)), ": ",
            Queue, "[u32:", integer_to_list(ActorCount), "],\n"]
            || Fragment <- Fragments],
        "  pending_valid: u1,\n",
        "  pending_batch: ", Batch, ",\n",
        "}\n\n",
        "proc ", plane_name(Plane), " {\n",
        [["  ", Member, ";\n"] || Member <- Members],
        "\n",
        config_signature(Members, 2),
        "    (", join_with(", ", Names), ")\n",
        "  }\n\n",
        "  init { zero!<", State, ">() }\n\n",
        "  next(state: ", State, ") {\n",
        "    let ready_slots = [\n",
        [ready_row(Row, Index, ActorCount)
            || {Index, Row} <- lists:enumerate(0, InverseRows)],
        "    ];\n",
        "    let (output_ready, output_slot) =\n",
        "      unroll_for! (offset, selected):\n",
        "          (u32, (u1, u32)) in u32:0..u32:",
        integer_to_list(ActorCount), " {\n",
        "        let unwrapped = state.output_cursor + offset;\n",
        "        let candidate = if unwrapped < u32:",
        integer_to_list(ActorCount), " { unwrapped } else {\n",
        "          unwrapped - u32:", integer_to_list(ActorCount), " };\n",
        "        let take = !selected.0 && ready_slots[candidate];\n",
        "        (selected.0 || take,\n",
        "          if take { candidate } else { selected.1 })\n",
        "      }((u1:0, u32:0));\n",
        "    let pop_sources = match output_slot {\n",
        [inverse_arm(Row, Index)
            || {Index, Row} <- lists:enumerate(0, InverseRows)],
        "      _ => zero!<u32[u32:", integer_to_list(Population), "]>(),\n",
        "    };\n",
        "    let frames = match output_slot {\n",
        [frames_arm(Row, Index)
            || {Index, Row} <- lists:enumerate(0, InverseRows)],
        "      _ => zero!<axis::Frame[u32:",
        integer_to_list(Population), "]>(),\n",
        "    };\n",
        "    let aggregate = ", Module,
        "::reduction_aggregate_batch<u32:", integer_to_list(Population),
        ">(frames);\n",
        "    let output_tok = if output_ready {\n",
        "      match output_slot {\n",
        [output_arm(Plane, Destination) || Destination <- Destinations],
        "        _ => join(),\n",
        "      }\n",
        "    } else { join() };\n",
        "    // Input and output handshakes are independent. The scalar\n",
        "    // pending batch makes all fragment-bank insertion atomic.\n",
        "    let (input_tok, received, incoming) =\n",
        "      unroll_for! (candidate, acc):\n",
        "          (u32, (token, u1, ", Batch,
        ")) in u32:0..u32:", integer_to_list(SourceCount), " {\n",
        "        let (next_tok, next_batch, valid) =\n",
        "          recv_if_non_blocking(\n",
        "            acc.0, batch_in[candidate],\n",
        "            !state.pending_valid &&\n",
        "              state.input_cursor == candidate,\n",
        "            zero!<", Batch, ">());\n",
        "        (next_tok, acc.1 || valid,\n",
        "          if valid { next_batch } else { acc.2 })\n",
        "      }((join(), u1:0, zero!<", Batch, ">()));\n",
        "    let work_valid = state.pending_valid || received;\n",
        "    let work = if state.pending_valid {\n",
        "      state.pending_batch\n",
        "    } else { incoming };\n",
        "    let source_valid = work.source < u32:",
        integer_to_list(ActorCount), ";\n",
        "    let push_source = if source_valid { work.source\n",
        "      } else { u32:0 };\n",
        "    // An actor cannot reopen before its current aggregate retires,\n",
        "    // so one token bit is sufficient. Clear before set keeps the\n",
        "    // conservative same-cycle update well-defined.\n",
        "    let open_tokens_after_output = if output_ready {\n",
        "      update(state.open_tokens, output_slot, u1:0)\n",
        "    } else { state.open_tokens };\n",
        "    let incoming_source_valid = received &&\n",
        "      incoming.source < u32:", integer_to_list(ActorCount), ";\n",
        "    let open_tokens = if incoming_source_valid {\n",
        "      update(open_tokens_after_output, incoming.source, u1:1)\n",
        "    } else { open_tokens_after_output };\n",
        [capacity_binding(Fragment) || Fragment <- Fragments],
        "    let can_insert = work_valid && source_valid",
        [[" && capacity_", integer_to_list(maps:get(ordinal, Fragment))]
            || Fragment <- Fragments],
        ";\n",
        [bank_binding(Fragment) || Fragment <- Fragments],
        "    let _done = join(output_tok, input_tok);\n",
        "    ", State, " {\n",
        "      input_cursor: if state.pending_valid {\n",
        "        state.input_cursor\n",
        "      } else if state.input_cursor + u32:1 == u32:",
        integer_to_list(SourceCount), " { u32:0 } else {\n",
        "        state.input_cursor + u32:1 },\n",
        "      output_cursor: if !output_ready { state.output_cursor\n",
        "      } else if output_slot + u32:1 == u32:",
        integer_to_list(ActorCount), " { u32:0 } else {\n",
        "        output_slot + u32:1 },\n",
        "      open_tokens,\n",
        [["      bank_", integer_to_list(maps:get(ordinal, Fragment)),
            ",\n"] || Fragment <- Fragments],
        "      pending_valid: work_valid && !can_insert,\n",
        "      pending_batch: if work_valid && !can_insert { work\n",
        "        } else { state.pending_batch },\n",
        "    }\n",
        "  }\n",
        "}\n\n"
    ].

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

inverse_arm(Row, Index) ->
    [
        "      u32:", integer_to_list(Index), " => [",
        join_with(", ", [["u32:", integer_to_list(maps:get(source, Item))]
            || Item <- Row]),
        "],\n"
    ].

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

aggregate_mux_proc(Spec, Scheduler = #{module_name := Module}) ->
    Planes = scheduler_planes(Spec, Scheduler),
    Count = length(Planes),
    CountText = integer_to_list(Count),
    State = mux_state_name(Scheduler),
    Name = mux_name(Scheduler),
    [
        "struct ", State, " {\n",
        "  cursor: u32,\n",
        "  valid: u1[u32:", CountText, "],\n",
        "  values: ", Module,
        "::ReductionAggregateRequest[u32:", CountText, "],\n",
        "}\n\n",
        "proc ", Name, " {\n",
        "  aggregate_in: chan<", Module,
        "::ReductionAggregateRequest>[u32:", CountText, "] in;\n",
        "  aggregate_out: chan<", Module,
        "::ReductionAggregateRequest> out;\n\n",
        "  config(\n",
        "      aggregate_in: chan<", Module,
        "::ReductionAggregateRequest>[u32:", CountText, "] in,\n",
        "      aggregate_out: chan<", Module,
        "::ReductionAggregateRequest> out\n",
        "  ) { (aggregate_in, aggregate_out) }\n\n",
        "  init { zero!<", State, ">() }\n\n",
        "  next(state: ", State, ") {\n",
        "    let (recv_tok, available, values) =\n",
        "      unroll_for! (candidate, acc):\n",
        "          (u32, (token, u1[u32:", CountText, "], ", Module,
        "::ReductionAggregateRequest[u32:", CountText,
        "])) in u32:0..u32:", CountText, " {\n",
        "        let (next_tok, incoming, received) =\n",
        "          recv_if_non_blocking(\n",
        "            acc.0, aggregate_in[candidate],\n",
        "            !acc.1[candidate], zero!<", Module,
        "::ReductionAggregateRequest>());\n",
        "        (\n",
        "          next_tok,\n",
        "          update(acc.1, candidate, acc.1[candidate] || received),\n",
        "          update(acc.2, candidate,\n",
        "            if received { incoming } else { acc.2[candidate] })\n",
        "        )\n",
        "      }((join(), state.valid, state.values));\n",
        "    let (selected, selected_index) =\n",
        "      unroll_for! (offset, choice):\n",
        "          (u32, (u1, u32)) in u32:0..u32:", CountText, " {\n",
        "        let unwrapped = state.cursor + offset;\n",
        "        let candidate = if unwrapped < u32:", CountText,
        " { unwrapped\n",
        "          } else { unwrapped - u32:", CountText, " };\n",
        "        let take = !choice.0 && available[candidate];\n",
        "        (choice.0 || take,\n",
        "          if take { candidate } else { choice.1 })\n",
        "      }((u1:0, u32:0));\n",
        "    let _done = send_if(\n",
        "      recv_tok, aggregate_out, selected, values[selected_index]);\n",
        "    let valid = if selected {\n",
        "      update(available, selected_index, u1:0)\n",
        "    } else { available };\n",
        "    ", State, " {\n",
        "      cursor: if !selected { state.cursor\n",
        "        } else if selected_index + u32:1 == u32:", CountText,
        " { u32:0\n",
        "        } else { selected_index + u32:1 },\n",
        "      valid,\n",
        "      values,\n",
        "    }\n",
        "  }\n",
        "}\n\n"
    ].

-spec scheduler_channels(map(), map()) -> iodata().
scheduler_channels(Spec, Scheduler = #{stem := Stem, module_name := Module}) ->
    case scheduler_planes(Spec, Scheduler) of
        [] -> [];
        Planes ->
            [
                "    let (", Stem, "_aggregate_p, ", Stem,
                "_aggregate_c) =\n",
                "      chan<", Module,
                "::ReductionAggregateRequest, u32:0>(\"", Stem,
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

-spec scheduler_service_argument(map(), map()) -> iodata().
scheduler_service_argument(Spec, Scheduler = #{stem := Stem}) ->
    case scheduler_planes(Spec, Scheduler) of
        [] -> [];
        [_ | _] -> [",\n      ", Stem, "_aggregate_c"]
    end.

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

scheduler_planes(#{source_fragment_planes := Planes}, #{index := Group}) ->
    [Plane || Plane <- Planes,
        lists:member(Group, maps:get(source_schedulers, Plane))];
scheduler_planes(_Spec, _Scheduler) ->
    [].

scheduler(#{scheduler_index := Schedulers}, Group) ->
    maps:get(Group, Schedulers).

plane_position(Id, [#{id := Id} | _], Position) -> Position;
plane_position(Id, [_ | Rest], Position) ->
    plane_position(Id, Rest, Position + 1).

position(Value, [Value | _], Index) -> Index;
position(Value, [_ | Rest], Index) -> position(Value, Rest, Index + 1).

positive_modulo(Value, Modulus) ->
    ((Value rem Modulus) + Modulus) rem Modulus.

%%%
%%% Names and rendering utilities
%%%

batch_name(#{id := Id}) ->
    [string:titlecase(atom_to_list(Id)), "ReductionBatch"].

state_name(#{id := Id}) ->
    [string:titlecase(atom_to_list(Id)), "ReductionPlaneState"].

plane_name(#{id := Id}) ->
    [string:titlecase(atom_to_list(Id)), "ReductionPlane"].

batch_output_name(#{id := Id}) ->
    [atom_to_list(Id), "_reduction_out"].



mux_name(#{index := Index}) ->
    ["SchedulerAggregateArrayMux", integer_to_list(Index)].

mux_state_name(#{index := Index}) ->
    ["SchedulerAggregateArrayMuxState", integer_to_list(Index)].

uppercase(Atom) -> string:uppercase(atom_to_list(Atom)).

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

separator(Index, Count) when Index + 1 =:= Count -> [];
separator(_Index, _Count) -> ",".

join_with(_Separator, []) -> [];
join_with(Separator, [First | Rest]) ->
    [First | [[Separator, Item] || Item <- Rest]].
