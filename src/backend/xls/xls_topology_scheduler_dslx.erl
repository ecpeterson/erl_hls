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

annotate(Spec = #{families := Families, schedulers := Schedulers}) ->
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
    Annotated = [
        annotate_scheduler(
            Scheduler,
            Families,
            FamilyIndex,
            SchedulerIndex,
            FamilySchedulers
        )
        || Scheduler <- Schedulers
    ],
    Externals = [annotate_external(External, Annotated)
        || External <- maps:get(externals, Spec)],
    Spec#{
        family_index => FamilyIndex,
        scheduler_index => maps:from_list([
            {maps:get(index, Scheduler), Scheduler}
            || Scheduler <- Annotated
        ]),
        family_schedulers => FamilySchedulers,
        schedulers => Annotated,
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
        index => Index
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
            || ExternalId <- ExternalIds],
    Names = ["scheduled_in", "credit_out"] ++
        [router_destination_name(maps:get(index, Destination))
            || Destination <- Destinations] ++
        [external_output_name(Spec, ExternalId)
            || ExternalId <- ExternalIds],
    [
        "// Holds one committed actor-entry batch while routing at most one\n",
        "// valid effect per activation. Credit returns only after the final\n",
        "// source-order position has been drained.\n",
        "struct ", StateName, " {\n",
        "  active: u1,\n",
        "  scheduled: ", Module, "::ScheduledEffects,\n",
        "  index: u8,\n",
        "}\n\n",
        "proc ", router_name(Scheduler), " {\n",
        [["  ", Member, ";\n"] || Member <- Members],
        "\n",
        config_signature(Members, 2),
        "    (", join_with(", ", Names), ")\n  }\n\n",
        "  init { zero!<", StateName, ">() }\n\n",
        "  next(state: ", StateName, ") {\n",
        "    let (tok, incoming) = recv_if(\n",
        "      join(), scheduled_in, !state.active,\n",
        "      zero!<", Module, "::ScheduledEffects>());\n",
        "    let scheduled = if state.active {\n",
        "      state.scheduled\n",
        "    } else { incoming };\n",
        "    let index = if state.active { state.index } else { u8:0 };\n",
        "    let effect = scheduled.effects.values[index as u32];\n",
        "    let emit = index < scheduled.effects.count &&\n",
        "      scheduled.effects.valid[index as u32];\n",
        "    let address = ", Stem, "_address(scheduled.slot);\n",
        "    let routed_tok = if emit {\n",
        "      match address.family as FamilyId {\n",
        [router_family_arm(Spec, Family) || Family <- Families],
        "        _ => tok,\n",
        "      }\n",
        "    } else { tok };\n",
        "    let last = index + u8:1 >= scheduled.effects.count;\n",
        "    let _done = send_if(\n",
        "      routed_tok, credit_out, last, ", Module,
        "::ScheduledRequest {\n",
        "        credit: u1:1,\n",
        "        ..zero!<", Module, "::ScheduledRequest>()\n",
        "      });\n",
        "    if last {\n",
        "      zero!<", StateName, ">()\n",
        "    } else {\n",
        "      ", StateName, " {\n",
        "        active: u1:1,\n",
        "        scheduled,\n",
        "        index: index + u8:1,\n",
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
        route_send(Spec, Recipient, "tok"),
        ",\n"
    ];
router_route_arm(Spec, Module, Port, #{
    delivery := queued,
    recipients := [Left, Right]
}) ->
    [
        "        ", Module, "::OutputPort::", uppercase(Port), " => {\n",
        "          let left_tok = ", route_send(Spec, Left, "tok"), ";\n",
        "          let right_tok = ", route_send(Spec, Right, "tok"), ";\n",
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
                ["            u8:", integer_to_list(Group), " => send(",
                    Token, ", ", router_destination_name(Group), ", ",
                    Module, "::ScheduledRequest {\n",
                    "              slot: destination.slot,\n",
                    "              frame: effect.frame,\n",
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
    ingresses := Ingresses,
    externals := Externals
}) ->
    Arguments = ram_arguments(Spec) ++ ingress_arguments(Ingresses) ++
        external_arguments(Externals),
    [
        "proc ", grid_name(Spec), " {\n",
        config_signature(Arguments, 2),
        [external_channel(External) || External <- Externals],
        [scheduler_channels(Scheduler) || Scheduler <- Schedulers],
        [scheduler_spawn(Spec, Scheduler) || Scheduler <- Schedulers],
        [router_spawn(Spec, Scheduler) || Scheduler <- Schedulers],
        control_spawn(Spec),
        [external_spawn(External) || External <- Externals],
        "    ()\n",
        "  }\n\n",
        "  init { () }\n",
        "  next(state: ()) { state }\n",
        "}\n\n"
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
    producers := Producers
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
        case maps:get(startup_count, Scheduler) of
            0 -> [];
            _ -> ["    spawn ", startup_name(Scheduler), "(",
                Stem, "_startup_p);\n"]
        end
    ].

scheduler_spawn(_Spec, #{
    stem := Stem,
    index := Index,
    module_name := Module,
    slot_count := SlotCount,
    producers := Producers,
    startup_count := StartupCount
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
        "_mailbox_write_resp_in);\n"
    ].

router_spawn(Spec, Scheduler = #{
    stem := Stem,
    index := Source,
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
        ]
        || #{stem := Stem, module_name := Module} <- Schedulers
    ]).

ram_names(#{schedulers := Schedulers}) ->
    lists:append([
        [
            [Stem, "_ram_read_req_out"],
            [Stem, "_ram_read_resp_in"],
            [Stem, "_ram_write_req_out"],
            [Stem, "_ram_write_resp_in"],
            [Stem, "_mailbox_read_req_out"],
            [Stem, "_mailbox_read_resp_in"],
            [Stem, "_mailbox_write_req_out"],
            [Stem, "_mailbox_write_resp_in"]
        ]
        || #{stem := Stem} <- Schedulers
    ]).

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
