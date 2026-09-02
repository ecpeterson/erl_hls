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
frame_relay(#{externals := [_ | _]}) ->
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

    """.

annotate(Spec = #{families := Families, schedulers := Schedulers}) ->
    FamilyIndex = maps:from_list([
        {maps:get(id, Family), Family} || Family <- Families
    ]),
    SchedulerIndex = maps:from_list([
        {maps:get(index, Scheduler), Scheduler} || Scheduler <- Schedulers
    ]),
    FamilyScheduler = maps:from_list([
        {maps:get(id, Family), maps:get(group, maps:get(scheduler, Family))}
        || Family <- Families
    ]),
    Annotated = [
        annotate_scheduler(
            Scheduler,
            Families,
            FamilyIndex,
            SchedulerIndex,
            FamilyScheduler
        )
        || Scheduler <- Schedulers
    ],
    Spec#{
        family_index => FamilyIndex,
        scheduler_index => maps:from_list([
            {maps:get(index, Scheduler), Scheduler}
            || Scheduler <- Annotated
        ]),
        family_scheduler => FamilyScheduler,
        schedulers => Annotated
    }.

annotate_scheduler(
    Scheduler = #{index := Index, members := Members},
    Families,
    FamilyIndex,
    SchedulerIndex,
    FamilyScheduler
) ->
    MemberIds = [maps:get(id, Member) || Member <- Members],
    MemberFamilies = [maps:get(Id, FamilyIndex) || Id <- MemberIds],
    SourceGroups = lists:usort([
        maps:get(maps:get(id, SourceFamily), FamilyScheduler)
        || SourceFamily <- Families,
           route_targets_group(
               maps:get(routes, SourceFamily),
               MemberIds
           )
    ]),
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
    Destinations = lists:usort([
        maps:get(DestinationId, FamilyScheduler)
        || Family <- MemberFamilies,
           Route <- maps:get(routes, Family),
           {family, DestinationId, _} <- maps:get(recipients, Route)
    ]),
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
    [
        Item#{slot => family_slot(Family, Scheduler, X, Y)}
        || Item = #{coordinates := [X, Y]} <- Items
    ].

family_slot(
    #{id := Id},
    #{members := Members},
    X,
    Y
) ->
    {family, Id, #{base_slot := Base, shape := [_Width, Height]}} =
        lists:keyfind(Id, 2, [
            {family, maps:get(id, Member), Member}
            || Member <- Members
        ]),
    Base + X * Height + Y.

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
        "// Actor state and mailbox frames use separate RAMs. Group routers\n",
        "// carry scheduled {slot, frame} requests without coordinate-level\n",
        "// request, admission, or egress channel arrays.\n\n",
        "import axis;\n",
        case maps:get(ingresses, Spec) of
            [] -> [];
            [_] -> "import hls_spatial_router;\n"
        end,
        [["import ", Module, ";\n"] || Module <- Modules],
        "\n",
        "const CHANNEL_DEPTH = u32:",
        integer_to_list(maps:get(depth, Spec)), ";\n",
        "const WIDTH = u32:", integer_to_list(maps:get(width, Spec)), ";\n",
        "const HEIGHT = u32:", integer_to_list(maps:get(height, Spec)),
        ";\n\n"
    ].

control_support(#{ingresses := []}) -> [];
control_support(Spec = #{ingresses := [Ingress]}) ->
    Controlled = [
        Family
        || Family <- maps:get(families, Spec),
           maps:get(ingress, Family) =/= none
    ],
    [
        "struct ControlState {\n",
        "  active: u1,\n",
        "  packet: hls_spatial_router::SpatialFrame,\n",
        "  family: u32,\n",
        "  x: u32,\n",
        "  y: u32,\n",
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
        "      let _done = match state.family {\n",
        [control_family_arm(Spec, Ingress, Index, Family)
            || {Index, Family} <- lists:enumerate(0, Controlled)],
        "        _ => join(),\n",
        "      };\n",
        control_advance(length(Controlled)),
        "    }\n",
        "  }\n",
        "}\n\n"
    ].

controlled_groups(Families) ->
    lists:usort([
        maps:get(group, maps:get(scheduler, Family))
        || Family <- Families
    ]).

control_member(Spec, Group) ->
    Module = scheduler_module(Spec, Group),
    ["  ", control_output_name(Group), ": chan<", Module,
        "::ScheduledRequest> out;\n"].

control_argument(Spec, Group) ->
    Module = scheduler_module(Spec, Group),
    [control_output_name(Group), ": chan<", Module,
        "::ScheduledRequest> out"].

control_family_arm(Spec, Ingress, Index, Family = #{
    scheduler := #{group := Group, base_slot := Base},
    ingress := #{scale := [ScaleX, ScaleY], offset := [OffsetX, OffsetY]}
}) ->
    Module = scheduler_module(Spec, Group),
    [
        "        u32:", integer_to_list(Index), " => {\n",
        "          let address_x = (state.x * u32:",
        integer_to_list(ScaleX), " + u32:", integer_to_list(OffsetX),
        ") as u16;\n",
        "          let address_y = (state.y * u32:",
        integer_to_list(ScaleY), " + u32:", integer_to_list(OffsetY),
        ") as u16;\n",
        "          let selected = (", control_target_condition(
            maps:get(targets, maps:get(ingress, Family)),
            Ingress
        ), ") && hls_spatial_router::contains(\n",
        "            state.packet.rectangle, address_x, address_y);\n",
        "          let request = ", Module, "::ScheduledRequest {\n",
        "            slot: u32:", integer_to_list(Base),
        " + state.x * HEIGHT + state.y,\n",
        "            frame: state.packet.frame,\n",
        "            ..zero!<", Module, "::ScheduledRequest>()\n",
        "          };\n",
        "          send_if(join(), ", control_output_name(Group),
        ", selected, request)\n",
        "        },\n"
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

control_advance(FamilyCount) ->
    [
        "      let last_y = state.y + u32:1 == HEIGHT;\n",
        "      let last_x = state.x + u32:1 == WIDTH;\n",
        "      let last_family = state.family + u32:1 == u32:",
        integer_to_list(FamilyCount), ";\n",
        "      let family_done = last_y && last_x;\n",
        "      let all_done = family_done && last_family;\n",
        "      ControlState {\n",
        "        active: !all_done,\n",
        "        family: if family_done { state.family + u32:1 }\n",
        "          else { state.family },\n",
        "        x: if last_y {\n",
        "          if last_x { u32:0 } else { state.x + u32:1 }\n",
        "        } else { state.x },\n",
        "        y: if last_y { u32:0 } else { state.y + u32:1 },\n",
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
    tag := Tag,
    payload := Payload
}) ->
    [
        "      u32:", integer_to_list(Index), " => ",
        Module, "::ScheduledRequest {\n",
        "        slot: u32:", integer_to_list(Slot), ",\n",
        "        frame: axis::pack(u8:", integer_to_list(Tag), ", ",
        Payload, "),\n",
        "        ..zero!<", Module, "::ScheduledRequest>()\n",
        "      },\n"
    ].

router_proc(Spec, Scheduler = #{
    module_name := Module,
    families := Families,
    destinations := Destinations,
    external_ids := ExternalIds
}) ->
    Members =
        [
            ["scheduled_in: chan<", Module, "::ScheduledEgress> in"],
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
        "proc ", router_name(Scheduler), " {\n",
        [["  ", Member, ";\n"] || Member <- Members],
        "\n",
        config_signature(Members, 2),
        "    (", join_with(", ", Names), ")\n  }\n\n",
        "  init { () }\n\n",
        "  next(state: ()) {\n",
        "    let (tok, scheduled) = recv(join(), scheduled_in);\n",
        "    let routed_tok = ",
        router_family_choice(Spec, Families, 0),
        ";\n",
        "    let _done = send(\n",
        "      routed_tok, credit_out, ", Module,
        "::ScheduledRequest {\n",
        "        credit: u1:1,\n",
        "        ..zero!<", Module, "::ScheduledRequest>()\n",
        "      });\n",
        "    state\n",
        "  }\n",
        "}\n\n"
    ].

router_destination_argument(#{index := Index, module_name := Module}) ->
    [router_destination_name(Index), ": chan<", Module,
        "::ScheduledRequest> out"].

router_external_argument(Spec, ExternalId) ->
    [external_output_name(Spec, ExternalId), ": chan<axis::Frame> out"].

router_family_choice(_Spec, [], _Limit) -> "tok";
router_family_choice(
    Spec,
    [Family | Rest],
    Limit
) ->
    Count = maps:get(instance_count, Family),
    Upper = Limit + Count,
    [
        "if scheduled.slot < u32:", integer_to_list(Upper), " {\n",
        router_family_routes(Spec, Family, Limit),
        "    } else {\n",
        "      ", router_family_choice(Spec, Rest, Upper), "\n",
        "    }"
    ].

router_family_routes(Spec, Family, Base) ->
    Module = maps:get(module_name, Family),
    RouteIndex = maps:from_list([
        {Port, Route}
        || Route <- maps:get(routes, Family),
           {_Family, Port} <- [maps:get(source, Route)]
    ]),
    [
        "      let local = scheduled.slot - u32:",
        integer_to_list(Base), ";\n",
        "      let x = local / HEIGHT;\n",
        "      let y = local % HEIGHT;\n",
        "      match scheduled.egress.port {\n",
        [
            router_route_arm(
                Spec,
                Module,
                Port,
                maps:get(Port, RouteIndex)
            )
            || Port <- maps:get(outputs, Family)
        ],
        "      }\n"
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
        ", scheduled.egress.frame)"];
route_send(
    Spec,
    {family, DestinationId, {translate, [DX, DY], wrap}},
    Token
) ->
    Family = maps:get(DestinationId, maps:get(family_index, Spec)),
    #{group := Group, base_slot := Base} = maps:get(scheduler, Family),
    Module = scheduler_module(Spec, Group),
    DestinationX = translated_index("x", DX, "WIDTH"),
    DestinationY = translated_index("y", DY, "HEIGHT"),
    [
        "send(", Token, ", ", router_destination_name(Group), ", ",
        Module, "::ScheduledRequest {\n",
        "            slot: u32:", integer_to_list(Base), " + ",
        DestinationX, " * HEIGHT + ", DestinationY, ",\n",
        "            frame: scheduled.egress.frame,\n",
        "            ..zero!<", Module, "::ScheduledRequest>()\n",
        "          })"
    ].

translated_index(Axis, 0, _Size) -> Axis;
translated_index(Axis, Offset, Size) when Offset > 0 ->
    ["(", Axis, " + u32:", integer_to_list(Offset), ") % ", Size];
translated_index(Axis, Offset, Size) ->
    ["(", Axis, " + ", Size, " - u32:",
        integer_to_list(-Offset), ") % ", Size].

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
    [
        "    let (", Stem, "_p, ", Stem, "_c) =\n",
        "      chan<axis::Frame, CHANNEL_DEPTH>(\"", Stem, "\");\n"
    ].

external_spawn(External) ->
    Stem = external_buffer_name(External),
    [
        "    spawn FrameRelay(", Stem, "_c, ",
        maps:get(output_name, External), ");\n"
    ].

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
        "      chan<", Module, "::ScheduledEgress, CHANNEL_DEPTH>(\"",
        Stem, "_egress\");\n",
        case maps:get(startup_count, Scheduler) of
            0 -> [];
            _ -> ["    spawn ", startup_name(Scheduler), "(",
                Stem, "_startup_p);\n"]
        end
    ].

scheduler_spawn(_Spec, #{
    stem := Stem,
    module_name := Module,
    slot_count := SlotCount,
    producers := Producers,
    startup_count := StartupCount
}) ->
    [
        "    spawn ", Module, "::SharedService<\n",
        "      u32:", integer_to_list(SlotCount), ", u32:",
        integer_to_list(length(Producers)), ", u32:",
        integer_to_list(StartupCount), ">(\n",
        "      ", Stem, "_requests_c, ", Stem, "_startup_c,\n",
        "      ", Stem, "_egress_p,\n",
        "      ", Stem, "_ram_req_out, ", Stem, "_ram_resp_in,\n",
        "      ", Stem, "_ram_wr_comp_in,\n",
        "      ", Stem, "_mailbox_req_out, ", Stem,
        "_mailbox_resp_in,\n",
        "      ", Stem, "_mailbox_wr_comp_in);\n"
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
        [[",\n      ", external_buffer_producer(Spec, ExternalId)]
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
            [Stem, "_ram_req_out: chan<", Module,
                "::MachineRamReq> out"],
            [Stem, "_ram_resp_in: chan<", Module,
                "::MachineRamResp> in"],
            [Stem, "_ram_wr_comp_in: chan<()> in"],
            [Stem, "_mailbox_req_out: chan<", Module,
                "::MailboxRamReq> out"],
            [Stem, "_mailbox_resp_in: chan<", Module,
                "::MailboxRamResp> in"],
            [Stem, "_mailbox_wr_comp_in: chan<()> in"]
        ]
        || #{stem := Stem, module_name := Module} <- Schedulers
    ]).

ram_names(#{schedulers := Schedulers}) ->
    lists:append([
        [
            [Stem, "_ram_req_out"],
            [Stem, "_ram_resp_in"],
            [Stem, "_ram_wr_comp_in"],
            [Stem, "_mailbox_req_out"],
            [Stem, "_mailbox_resp_in"],
            [Stem, "_mailbox_wr_comp_in"]
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

external_buffer_producer(#{externals := Externals}, Id) ->
    {external, Id, External} = lists:keyfind(Id, 2, [
        {external, maps:get(id, Candidate), Candidate}
        || Candidate <- Externals
    ]),
    [external_buffer_name(External), "_p"].

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

separator(Index, Count) when Index + 1 < Count -> ",";
separator(_Index, _Count) -> "".

join_with(_Separator, []) -> [];
join_with(Separator, [First | Rest]) ->
    [First | [[Separator, Item] || Item <- Rest]].
