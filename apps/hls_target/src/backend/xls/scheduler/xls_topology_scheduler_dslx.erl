%%%% xls_topology_scheduler_dslx
%%%%
%%%% Compact group-routed topology for homogeneous shared actor schedulers.

-module(xls_topology_scheduler_dslx).
-moduledoc "Renders the retained compact scheduler graph selected by xls_fabric_topology_dslx. xls_topology_scheduler_plan owns addresses, startup frames, source-fragment routing and dependency domains; this module emits their control, router and top-level DSLX connections.".

%% Compact scheduler topology rendering.
-export([emit/1]).

%% Shared effect-router rendering.
-export([effect_router/3]).

-doc "Renders a complete checked backend module with its channel interfaces.".
-spec emit(xls_topology_scheduler_plan:plan()) -> iolist().
emit(Plan) ->
    Spec = xls_topology_scheduler_plan:graph(Plan),
    [
        preamble(Spec),
        address_support(Spec),
        xls_topology_source_fragment_dslx:support(Spec),
        control_support(Spec),
        [
            startup_proc(Spec, Scheduler)
         || Scheduler <- maps:get(schedulers, Spec)
        ],
        [
            router_proc(Spec, Scheduler)
         || Scheduler <- maps:get(schedulers, Spec)
        ],
        grid_proc(Spec),
        top_proc(Spec)
    ].

%%%
%%% Preamble and common control
%%%

-spec preamble(map()) -> [any(), ...].
preamble(Spec = #{families := Families}) ->
    Modules = lists:usort([maps:get(module_name, Family) || Family <- Families]),
    [
        "// ",
        maps:get(name, Spec),
        ".x\n",
        "// Auto-generated from compact Erlang topology and scheduler rules.\n",
        "// Manual changes will be overwritten.\n",
        "//\n",
        "// Actor state and mailbox frames use separate RAMs. Requests and\n",
        "// scheduler effect batches carry dense RAM slots; each group router\n",
        "// maps its slot to a narrow family and coordinate address, then\n",
        "// drains the effects in source order.\n\n",
        "import axis;\n",
        case maps:get(externals, Spec) of
            [] -> [];
            _ -> "import frame_transport;\n"
        end,
        "import effect_window;\n",
        case maps:get(source_fragment_planes, Spec, []) of
            [] -> [];
            [_ | _] -> "import frame_queue;\nimport arbitration;\n"
        end,
        case maps:get(ingresses, Spec) of
            [] -> [];
            [_] -> "import hls_spatial_router;\n"
        end,
        [["import ", Module, ";\n"] || Module <- Modules],
        "\n",
        "const CHANNEL_DEPTH = u32:",
        integer_to_list(maps:get(depth, Spec)),
        ";\n",
        "const WIDTH = u16:",
        integer_to_list(maps:get(width, Spec)),
        ";\n",
        "const HEIGHT = u16:",
        integer_to_list(maps:get(height, Spec)),
        ";\n\n"
    ].

%% Renders logical-coordinate to physical-slot address conversion.
-spec address_support(map()) -> iodata().
address_support(Spec = #{families := Families, schedulers := Schedulers}) ->
    [
        "enum FamilyId : u8 {\n",
        [
            [
                "  ",
                xls_names:enum_member(maps:get(id, Family)),
                " = u8:",
                integer_to_list(Index),
                ",\n"
            ]
         || {Index, Family} <- lists:enumerate(0, Families)
        ],
        "}\n\n",
        "struct ScheduledAddress {\n",
        "  family: u8,\n",
        "  x: u16,\n",
        "  y: u16,\n",
        "}\n\n",
        [
            scheduler_address_support(Spec, Scheduler)
         || Scheduler <- Schedulers
        ],
        destination_support(Families)
    ].

%% Defines the physical destinations reachable from each family.
-spec destination_support([map()]) -> iodata().
destination_support(Families) ->
    Sharded = [
        Family
     || Family <- Families,
        length(maps:get(schedulers, Family)) > 1
    ],
    case Sharded of
        [] ->
            [];
        [_ | _] ->
            [
                "struct ScheduledDestination {\n",
                "  scheduler: u8,\n",
                "  slot: u32,\n",
                "}\n\n",
                [family_destination_support(Family) || Family <- Sharded]
            ]
    end.

%% Defines one family's destination selectors and coordinate tables.
-spec family_destination_support(map()) -> iodata().
family_destination_support(#{id := Id, destination_entries := Entries}) ->
    [
        "fn ",
        atom_to_list(Id),
        "_destination(x: u16, y: u16) -> ScheduledDestination {\n",
        "  match (x, y) {\n",
        [
            [
                "    (u16:",
                integer_to_list(X),
                ", u16:",
                integer_to_list(Y),
                ") => ScheduledDestination { ",
                "scheduler: u8:",
                integer_to_list(Group),
                ", slot: u32:",
                integer_to_list(Slot),
                " },\n"
            ]
         || {[X, Y], Group, Slot} <- Entries
        ],
        "    _ => zero!<ScheduledDestination>(),\n",
        "  }\n",
        "}\n\n"
    ].

%% Maps a group's dense slots back to logical actor coordinates.
-spec scheduler_address_support(map(), map()) -> [any(), ...].
scheduler_address_support(_Spec, #{
    stem := Stem, slot_count := SlotCount, addresses := Entries
}) ->
    [
        "fn ",
        Stem,
        "_address(slot: u32) -> ScheduledAddress {\n",
        "  match slot {\n",
        [
            [
                "    u32:",
                integer_to_list(Slot),
                " => ",
                scheduled_address(Family, X, Y),
                ",\n"
            ]
         || {Slot, Family, X, Y} <- Entries
        ],
        "    _ => zero!<ScheduledAddress>(),\n",
        "  }\n",
        "}\n\n",
        "fn ",
        Stem,
        "_slot(address: ScheduledAddress) -> u32 {\n",
        "  match (address.family as FamilyId, address.x, address.y) {\n",
        [
            [
                "    (FamilyId::",
                xls_names:enum_member(Family),
                ", u16:",
                integer_to_list(X),
                ", u16:",
                integer_to_list(Y),
                ") => u32:",
                integer_to_list(Slot),
                ",\n"
            ]
         || {Slot, Family, X, Y} <- Entries
        ],
        "    _ => u32:",
        integer_to_list(SlotCount),
        ",\n",
        "  }\n",
        "}\n\n"
    ].

%% Encodes one logical coordinate's owning scheduler and RAM slot.
-spec scheduled_address(atom(), term(), term()) -> [any(), ...].
scheduled_address(Family, X, Y) ->
    [
        "ScheduledAddress { family: FamilyId::",
        xls_names:enum_member(Family),
        " as u8, x: ",
        u16_value(X),
        ", y: ",
        u16_value(Y),
        " }"
    ].

%% Formats a coordinate expression as an unsigned 16-bit value.
-spec u16_value(integer() | iodata()) -> iodata().
u16_value(Value) when is_integer(Value) ->
    ["u16:", integer_to_list(Value)];
u16_value(Value) ->
    Value.

%% Renders external control delivery to the selected actor families.
-spec control_support(map()) -> iodata().
control_support(#{ingresses := []}) ->
    [];
control_support(
    Spec = #{
        ingresses := [Ingress],
        controlled_families := Controlled,
        controlled_groups := Groups,
        width := Width,
        height := Height
    }
) ->
    render_template("scheduler_control.x.in", [
        {<<"@@FAMILY_MEMBERS@@">>, [
            control_family_member(Index, Family)
         || {Index, Family} <- lists:enumerate(0, Controlled)
        ]},
        {<<"@@CHANNEL_FIELDS@@">>, [control_member(Spec, Group) || Group <- Groups]},
        {<<"@@CONFIG_SIGNATURE@@">>,
            config_signature(
                ["spatial_in: chan<hls_spatial_router::SpatialFrame> in"] ++
                    [control_argument(Spec, Group) || Group <- Groups],
                2
            )},
        {<<"@@CHANNEL_NAMES@@">>, [[", ", control_output_name(Group)] || Group <- Groups]},
        {<<"@@DELIVERY_ARMS@@">>, [
            control_family_arm(Spec, Ingress, Family)
         || Family <- Controlled
        ]},
        {<<"@@HEIGHT@@">>, integer_to_list(Height)},
        {<<"@@WIDTH@@">>, integer_to_list(Width)},
        {<<"@@FAMILY_COUNT@@">>, integer_to_list(length(Controlled))}
    ]).

%% Finds the grouped family member addressed by a control request.
-spec control_family_member(integer(), map()) -> [string(), ...].
control_family_member(Index, #{id := Id}) ->
    ["  ", xls_names:enum_member(Id), " = u8:", integer_to_list(Index), ",\n"].

%% Tests whether a group member is included in the control address space.
-spec control_member(map(), integer()) -> [any(), ...].
control_member(Spec, Group) ->
    Module = scheduler_module(Spec, Group),
    [
        "  ",
        control_output_name(Group),
        ": chan<",
        Module,
        "::ScheduledRequest> out;\n"
    ].

%% Declares one group's external control channel.
-spec control_argument(map(), integer()) -> [any(), ...].
control_argument(Spec, Group) ->
    Module = scheduler_module(Spec, Group),
    [
        control_output_name(Group),
        ": chan<",
        Module,
        "::ScheduledRequest> out"
    ].

%% Routes a control frame across the addressed family members.
-spec control_family_arm(map(), map(), map()) -> [any(), ...].
control_family_arm(Spec, Ingress, Family = #{schedulers := [Binding]}) ->
    control_family_arm_single(Spec, Ingress, Family, Binding);
control_family_arm(
    Spec,
    Ingress,
    Family = #{
        id := Id,
        schedulers := Bindings,
        ingress := #{scale := [ScaleX, ScaleY], offset := [OffsetX, OffsetY]}
    }
) ->
    [First | _] = Bindings,
    Module = scheduler_module(Spec, maps:get(group, First)),
    [
        "        ControlFamily::",
        xls_names:enum_member(Id),
        " => {\n",
        control_address(ScaleX, ScaleY, OffsetX, OffsetY),
        "          let selected = (",
        control_target_condition(
            maps:get(targets, maps:get(ingress, Family)),
            Ingress
        ),
        ") && hls_spatial_router::contains(\n",
        "            state.packet.rectangle, address_x, address_y);\n",
        "          let destination = ",
        atom_to_list(Id),
        "_destination(state.x, state.y);\n",
        "          match destination.scheduler {\n",
        [
            begin
                Group = maps:get(group, Binding),
                [
                    "            u8:",
                    integer_to_list(Group),
                    " => send_if(join(), ",
                    control_output_name(Group),
                    ", selected, ",
                    Module,
                    "::ScheduledRequest {\n",
                    "              slot: destination.slot,\n",
                    "              frame: state.packet.frame,\n",
                    "              ..zero!<",
                    Module,
                    "::ScheduledRequest>()\n",
                    "            }),\n"
                ]
            end
         || Binding <- Bindings
        ],
        "            _ => join(),\n",
        "          }\n",
        "        },\n"
    ].

%% Routes one control frame to a concrete group member.
-spec control_family_arm_single(map(), map(), map(), map()) -> [any(), ...].
control_family_arm_single(
    Spec,
    Ingress,
    Family = #{
        id := Id,
        ingress := #{scale := [ScaleX, ScaleY], offset := [OffsetX, OffsetY]}
    },
    #{group := Group}
) ->
    Module = scheduler_module(Spec, Group),
    Scheduler = scheduler(Spec, Group),
    [
        "        ControlFamily::",
        xls_names:enum_member(Id),
        " => {\n",
        control_address(ScaleX, ScaleY, OffsetX, OffsetY),
        "          let selected = (",
        control_target_condition(
            maps:get(targets, maps:get(ingress, Family)),
            Ingress
        ),
        ") && hls_spatial_router::contains(\n",
        "            state.packet.rectangle, address_x, address_y);\n",
        "          let request = ",
        Module,
        "::ScheduledRequest {\n",
        "            slot: ",
        maps:get(stem, Scheduler),
        "_slot(",
        scheduled_address(Id, "state.x", "state.y"),
        "),\n",
        "            frame: state.packet.frame,\n",
        "            ..zero!<",
        Module,
        "::ScheduledRequest>()\n",
        "          };\n",
        "          send_if(join(), ",
        control_output_name(Group),
        ", selected, request)\n",
        "        },\n"
    ].

%% Constructs the physical address for a logical control destination.
-spec control_address(integer(), integer(), integer(), integer()) -> [string(), ...].
control_address(ScaleX, ScaleY, OffsetX, OffsetY) ->
    [
        "          let address_x = state.x * u16:",
        integer_to_list(ScaleX),
        " + u16:",
        integer_to_list(OffsetX),
        ";\n",
        "          let address_y = state.y * u16:",
        integer_to_list(ScaleY),
        " + u16:",
        integer_to_list(OffsetY),
        ";\n"
    ].

%% Checks whether a control selector addresses the current family.
-spec control_target_condition(term(), map()) -> [any()].
control_target_condition(TargetIds, Ingress) ->
    xls_topology_ingress:condition(TargetIds, Ingress, "state.packet").

%%%
%%% Startup and group routing
%%%

%% Bind prepared startup frames to the fixed ordered sender.
-spec startup_proc(map(), map()) -> iodata().
startup_proc(_Spec, #{startup_count := 0}) ->
    [];
startup_proc(_Spec, Scheduler = #{module_name := Module, startup_items := Items}) ->
    render_template("scheduler_startup.x.in", [
        {<<"@@PROC_NAME@@">>, startup_name(Scheduler)},
        {<<"@@FIELD_MODULE@@">>, Module},
        {<<"@@CONFIG_MODULE@@">>, Module},
        {<<"@@REQUEST_ARMS@@">>, [
            startup_arm(Module, Index, Item)
         || {Index, Item} <- lists:enumerate(0, Items)
        ]},
        {<<"@@EMPTY_MODULE@@">>, Module},
        {<<"@@REQUEST_COUNT@@">>, integer_to_list(length(Items))}
    ]).

%% Emits one startup frame for its assigned actor slot.
-spec startup_arm(term(), integer(), map()) -> [any(), ...].
startup_arm(Module, Index, #{
    slot := Slot,
    schema := Schema,
    packed_payload := Payload
}) ->
    [
        "      u32:",
        integer_to_list(Index),
        " => ",
        Module,
        "::ScheduledRequest {\n",
        "        slot: u32:",
        integer_to_list(Slot),
        ",\n",
        "        frame: axis::pack(\n",
        "          ",
        Module,
        "::Tag::",
        xls_names:enum_member(Schema),
        " as u8,\n",
        "          ",
        xls_nums:packed_unsigned_literal(Payload),
        "),\n",
        "        ..zero!<",
        Module,
        "::ScheduledRequest>()\n",
        "      },\n"
    ].

%% Chooses the router implementation required by a group's output graph.
-spec router_proc(map(), map()) -> [any(), ...].
router_proc(
    Spec,
    Scheduler = #{
        stem := Stem,
        families := Families,
        destinations := Destinations,
        external_ids := ExternalIds
    }
) ->
    Routing = #{
        arguments => [
            router_destination_argument(Destination)
         || Destination <- Destinations
        ] ++
            [
                router_external_argument(Spec, ExternalId)
             || ExternalId <- ExternalIds
            ],
        names => [
            router_destination_name(maps:get(index, Destination))
         || Destination <- Destinations
        ] ++
            [
                external_output_name(Spec, ExternalId)
             || ExternalId <- ExternalIds
            ],
        send => [
            "    let address = ",
            Stem,
            "_address(scheduled.slot);\n",
            router_send_binding(Spec, Scheduler, Families)
        ]
    },
    effect_router(Spec, Scheduler, Routing).

%% Both compact and materialized topologies use exactly the same retained
%% lookahead-credit protocol. Only the typed destination ports and route
%% selection differ; direct actors do not participate in this protocol.
-doc "Renders the shared ordered-publication DSLX template with concrete actor channels and routing. Compact and materialized topologies retain the same registered head, ownership actions and lookahead protocol; template reads are the only I/O.".
-spec effect_router(map(), map(), map()) -> [any(), ...].
effect_router(
    Spec,
    Scheduler = #{module_name := Module},
    #{arguments := RouteArguments, names := RouteNames, send := RouteSend}
) ->
    StateName = [router_name(Scheduler), "State"],
    Members =
        [
            ["scheduled_in: chan<", Module, "::ScheduledEffects> in"],
            ["credit_out: chan<", Module, "::ScheduledRequest> out"]
        ] ++ RouteArguments ++
            xls_topology_source_fragment_dslx:router_arguments(Spec, Scheduler) ++
            [
                "window_request_out: chan<u1> out",
                "window_grant_in: chan<u1> in",
                "window_release_out: chan<u1> out"
            ],
    Names =
        ["scheduled_in", "credit_out"] ++ RouteNames ++
            xls_topology_source_fragment_dslx:router_argument_names(Spec, Scheduler) ++
            ["window_request_out", "window_grant_in", "window_release_out"],
    Path = filename:join(
        code:priv_dir(hls_target),
        "xls/templates/scheduler_effect_router.x.in"
    ),
    {ok, Template} = file:read_file(Path),
    [
        xls_template:render(Template, [
            {<<"@@WINDOW_SCOPE@@">>, effect_window_scope(Spec)},
            {<<"@@STATE_DECLARATION@@">>, StateName},
            {<<"@@SCHEDULED_MODULE@@">>, Module},
            {<<"@@HEAD_MODULE@@">>, Module},
            {<<"@@ROUTER_NAME@@">>, router_name(Scheduler)},
            {<<"@@CHANNEL_FIELDS@@">>, [["  ", Member, ";\n"] || Member <- Members]},
            {<<"@@CONFIG_SIGNATURE@@">>, config_signature(Members, 2)},
            {<<"@@CHANNEL_NAMES@@">>, join_with(", ", Names)},
            {<<"@@STATE_INITIALIZER@@">>, StateName},
            {<<"@@STATE_INPUT@@">>, StateName},
            {<<"@@OBSERVE_BATCH_COMPLETION@@">>,
                xls_topology_source_fragment_dslx:router_state_bindings(
                    Spec, Scheduler
                )},
            {<<"@@EMPTY_INCOMING_MODULE@@">>, Module},
            {<<"@@INCOMING_MODULE@@">>, Module},
            {<<"@@OBSERVE_REDUCTION_PREFIX@@">>,
                xls_topology_source_fragment_dslx:router_batch_bindings(
                    Spec, Scheduler
                )},
            {<<"@@ROUTE_EFFECT@@">>, RouteSend},
            {<<"@@BATCH_COMPLETION@@">>, router_last_binding(Spec, Scheduler)},
            {<<"@@CREDIT_MODULE@@">>, Module},
            {<<"@@EMPTY_CREDIT_MODULE@@">>, Module},
            {<<"@@STATE_UPDATE@@">>, StateName},
            {<<"@@STATE_ZERO@@">>, StateName},
            {<<"@@STATE_INCOMING@@">>, StateName},
            {<<"@@CURSOR_ADVANCE@@">>,
                xls_topology_source_fragment_dslx:router_index_step(
                    Spec, Scheduler
                )},
            {<<"@@STATE_CONTINUED@@">>, StateName},
            {<<"@@CONTINUED_MODULE@@">>, Module}
        ])
    ].

%% Declares the routed request channel for one destination group.
-spec router_destination_argument(map()) -> [any(), ...].
router_destination_argument(#{index := Index, module_name := Module}) ->
    [
        router_destination_name(Index),
        ": chan<",
        Module,
        "::ScheduledRequest> out"
    ].

%% Declares a router's buffered external output endpoint.
-spec router_external_argument(map(), term()) -> [any(), ...].
router_external_argument(Spec, ExternalId) ->
    [external_output_name(Spec, ExternalId), ": chan<axis::Frame> out"].

%% Tests whether the current effect targets a selected output.
-spec router_send_binding(map(), map(), [map()]) -> iodata().
router_send_binding(Spec, Scheduler, Families) ->
    case
        xls_topology_source_fragment_dslx:router_arguments(
            Spec, Scheduler
        )
    of
        [] ->
            [
                "    let routed_tok = if emit {\n",
                "      match address.family as FamilyId {\n",
                [router_family_arm(Spec, Family) || Family <- Families],
                "        _ => grant_tok,\n",
                "      }\n",
                "    } else { grant_tok };\n"
            ];
        [_ | _] ->
            [
                "    let routed_tok = if reduction_batch {\n",
                xls_topology_source_fragment_dslx:router_send(
                    Spec, Scheduler
                ),
                "    } else if emit {\n",
                "      match address.family as FamilyId {\n",
                [router_family_arm(Spec, Family) || Family <- Families],
                "        _ => grant_tok,\n",
                "      }\n",
                "    } else { grant_tok };\n"
            ]
    end.

%% Recognizes the last accepted destination of an effect batch.
-spec router_last_binding(map(), map()) -> iodata().
router_last_binding(Spec, Scheduler) ->
    case
        xls_topology_source_fragment_dslx:router_arguments(
            Spec, Scheduler
        )
    of
        [] ->
            "    let last = batch_valid && effect_info.2;\n";
        [_ | _] ->
            [
                "    let last = batch_valid && if reduction_batch {\n",
                "      reduction_prefix.2\n",
                "    } else { effect_info.2 };\n"
            ]
    end.

%% Selects the output routes belonging to the issuing actor's family.
-spec router_family_arm(map(), map()) -> iodata().
router_family_arm(Spec, Family = #{id := Id}) ->
    [
        "      FamilyId::",
        xls_names:enum_member(Id),
        " => {\n",
        router_family_routes(Spec, Family),
        "      },\n"
    ].

%% Collects the output-port routes emitted by one family.
-spec router_family_routes(map(), map()) -> iodata().
router_family_routes(Spec, Family = #{module_name := Module, output_routes := Outputs}) ->
    [
        "        let x = address.x;\n",
        "        let y = address.y;\n",
        "        match effect.port {\n",
        [router_port_arm(Spec, Family, Module, Port, Route) || {Port, Route} <- Outputs],
        "        }\n"
    ].

%% Render the selected output owner without rediscovering or validating ownership.
-spec router_port_arm(map(), map(), term(), atom(), map() | source_fragment) -> iodata().
router_port_arm(_Spec, _Family, Module, Port, source_fragment) ->
    ["        ", Module, "::OutputPort::", xls_names:enum_member(Port), " => grant_tok,\n"];
router_port_arm(Spec, _Family, Module, Port, Route) ->
    router_route_arm(Spec, Module, Port, Route).

%% Renders delivery along one checked topology relation.
-spec router_route_arm(map(), term(), atom(), map()) -> [any(), ...].
router_route_arm(Spec, Module, Port, #{
    delivery := direct,
    recipients := [Recipient]
}) ->
    [
        "        ",
        Module,
        "::OutputPort::",
        xls_names:enum_member(Port),
        " => ",
        route_send(Spec, Recipient, "grant_tok"),
        ",\n"
    ];
router_route_arm(Spec, Module, Port, #{
    delivery := queued,
    recipients := [Left, Right]
}) ->
    [
        "        ",
        Module,
        "::OutputPort::",
        xls_names:enum_member(Port),
        " => {\n",
        "          let left_tok = ",
        route_send(Spec, Left, "grant_tok"),
        ";\n",
        "          let right_tok = ",
        route_send(Spec, Right, "grant_tok"),
        ";\n",
        "          join(left_tok, right_tok)\n",
        "        },\n"
    ].

%% Publishes a frame to the chosen external or actor destination.
-spec route_send(
    map(), {'external', term()} | {'family', atom(), {'translate', [integer(), ...], 'wrap'}}, [
        95 | 97 | 103 | 107 | 110 | 111 | 114 | 116, ...
    ]
) -> [any(), ...].
route_send(Spec, {external, ExternalId}, Token) ->
    [
        "send(",
        Token,
        ", ",
        external_output_name(Spec, ExternalId),
        ", effect.frame)"
    ];
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

%% Computes translated destination coordinates and the matching producer lane.
-spec route_send_bindings(
    map(), [map(), ...], atom(), [string() | 120 | 121, ...], [string() | 120 | 121, ...], [
        95 | 97 | 103 | 107 | 110 | 111 | 114 | 116, ...
    ]
) -> [any(), ...].
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
        "send(",
        Token,
        ", ",
        router_destination_name(Group),
        ", ",
        Module,
        "::ScheduledRequest {\n",
        "            slot: ",
        maps:get(stem, Scheduler),
        "_slot(",
        scheduled_address(DestinationId, DestinationX, DestinationY),
        "),\n",
        "            frame: effect.frame,\n",
        "            ..zero!<",
        Module,
        "::ScheduledRequest>()\n",
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
        "          let destination = ",
        atom_to_list(DestinationId),
        "_destination(",
        DestinationX,
        ", ",
        DestinationY,
        ");\n",
        "          match destination.scheduler {\n",
        [
            begin
                Group = maps:get(group, Binding),
                [
                    "            u8:",
                    integer_to_list(Group),
                    " => send(",
                    Token,
                    ", ",
                    router_destination_name(Group),
                    ", ",
                    Module,
                    "::ScheduledRequest {\n",
                    "              slot: destination.slot,\n",
                    "              frame: effect.frame,\n",
                    "              ..zero!<",
                    Module,
                    "::ScheduledRequest>()\n",
                    "            }),\n"
                ]
            end
         || Binding <- Bindings
        ],
        "            _ => ",
        Token,
        ",\n",
        "          }\n",
        "        }"
    ].

%% Applies a signed wrapped translation to a bounded coordinate expression.
-spec translated_index([120 | 121, ...], integer(), integer()) -> [string() | 120 | 121, ...].
translated_index(Axis, Offset, Size) ->
    Shift = positive_modulo(Offset, Size),
    case Shift of
        0 ->
            Axis;
        _ ->
            Boundary = Size - Shift,
            [
                "(if ",
                Axis,
                " >= u16:",
                integer_to_list(Boundary),
                " { ",
                Axis,
                " - u16:",
                integer_to_list(Boundary),
                " } else { ",
                Axis,
                " + u16:",
                integer_to_list(Shift),
                " })"
            ]
    end.

%% Normalizes a wrapped translation to a nonnegative offset.
-spec positive_modulo(integer(), integer()) -> integer().
positive_modulo(Value, Modulus) ->
    ((Value rem Modulus) + Modulus) rem Modulus.

%%%
%%% Network composition
%%%

-spec grid_proc(map()) -> [[any()], ...].
grid_proc(
    Spec = #{
        schedulers := Schedulers,
        effect_window_domains := EffectWindowDomains,
        ingresses := Ingresses,
        externals := Externals
    }
) ->
    Arguments =
        ram_arguments(Spec) ++ xls_scheduler_observation:arguments(Spec) ++
            ingress_arguments(Ingresses) ++
            external_arguments(Externals),
    [
        "proc ",
        grid_name(Spec),
        " {\n",
        config_signature(Arguments, 2),
        xls_effect_window_dslx:channels(EffectWindowDomains),
        [external_channel(External) || External <- Externals],
        [scheduler_channels(Spec, Scheduler) || Scheduler <- Schedulers],
        xls_topology_source_fragment_dslx:plane_channels(Spec),
        xls_effect_window_dslx:spawn(EffectWindowDomains),
        xls_topology_source_fragment_dslx:aggregate_mux_spawns(Spec),
        [scheduler_spawn(Spec, Scheduler) || Scheduler <- Schedulers],
        xls_topology_source_fragment_dslx:plane_spawns(Spec),
        [router_spawn(Spec, Scheduler) || Scheduler <- Schedulers],
        control_spawn(Spec),
        [external_spawn(External) || External <- Externals],
        "    ()\n",
        "  }\n\n",
        "  init { () }\n",
        "  next(state: ()) { state }\n",
        "}\n\n"
    ].

%% Declares the arbitration input buffer for one external sink.
-spec external_channel(map()) -> iodata().
external_channel(External) ->
    Stem = external_buffer_name(External),
    case maps:get(source_schedulers, External) of
        [_] ->
            [
                "    let (",
                Stem,
                "_p, ",
                Stem,
                "_c) =\n",
                "      chan<axis::Frame, CHANNEL_DEPTH>(\"",
                Stem,
                "\");\n"
            ];
        Sources ->
            [
                "    let (",
                Stem,
                "_p, ",
                Stem,
                "_c) =\n",
                "      chan<axis::Frame, CHANNEL_DEPTH>[u32:",
                integer_to_list(length(Sources)),
                "](\"",
                Stem,
                "\");\n"
            ]
    end.

%% Connects source buffers to the external sink's frame arbiter.
-spec external_spawn(map()) -> [any(), ...].
external_spawn(External) ->
    Stem = external_buffer_name(External),
    case maps:get(source_schedulers, External) of
        [_] ->
            [
                "    spawn frame_transport::FrameRelay(",
                Stem,
                "_c, ",
                maps:get(output_name, External),
                ");\n"
            ];
        Sources ->
            [
                "    spawn frame_transport::FrameArrayMux<u32:",
                integer_to_list(length(Sources)),
                ">(",
                Stem,
                "_c, ",
                maps:get(output_name, External),
                ");\n"
            ]
    end.

%% Declares a group's RAM, executor and producer channels.
-spec scheduler_channels(map(), map()) -> [any(), ...].
scheduler_channels(
    Spec,
    Scheduler = #{
        stem := Stem,
        module_name := Module,
        producers := Producers
    }
) ->
    ProducerCount = integer_to_list(length(Producers)),
    [
        "    let (",
        Stem,
        "_requests_p, ",
        Stem,
        "_requests_c) =\n",
        "      chan<",
        Module,
        "::ScheduledRequest, CHANNEL_DEPTH>",
        "[u32:",
        ProducerCount,
        "](\"",
        Stem,
        "_requests\");\n",
        "    let (",
        Stem,
        "_startup_p, ",
        Stem,
        "_startup_c) =\n",
        "      chan<",
        Module,
        "::ScheduledRequest, CHANNEL_DEPTH>(\"",
        Stem,
        "_startup\");\n",
        "    let (",
        Stem,
        "_egress_p, ",
        Stem,
        "_egress_c) =\n",
        "      chan<",
        Module,
        "::ScheduledEffects, u32:",
        integer_to_list(xls_scheduler_codegen:publication_depth()),
        ">(\"",
        Stem,
        "_egress\");\n",
        xls_topology_source_fragment_dslx:scheduler_channels(
            Spec, Scheduler
        ),
        case maps:get(startup_count, Scheduler) of
            0 ->
                [];
            _ ->
                [
                    "    spawn ",
                    startup_name(Scheduler),
                    "(",
                    Stem,
                    "_startup_p);\n"
                ]
        end
    ].

%% Connects a shared service, executor and RAM interfaces.
-spec scheduler_spawn(map(), map()) -> [any(), ...].
scheduler_spawn(
    Spec,
    Scheduler = #{
        stem := Stem,
        index := Index,
        module_name := Module,
        slot_count := SlotCount,
        producers := Producers,
        startup_count := StartupCount
    }
) ->
    [
        "    spawn ",
        Module,
        "::SharedService<\n",
        "      u32:",
        integer_to_list(SlotCount),
        ", u32:",
        integer_to_list(length(Producers)),
        ", u32:",
        integer_to_list(StartupCount),
        ", u32:",
        integer_to_list(Index),
        ">(\n",
        "      ",
        Stem,
        "_requests_c, ",
        Stem,
        "_startup_c,\n",
        "      ",
        Stem,
        "_egress_p,\n",
        "      ",
        lists:join(
            ",\n      ",
            ram_argument_pairs(
                xls_scheduler_ram_dslx:names([Stem, "_"])
            )
        ),
        xls_topology_source_fragment_dslx:scheduler_service_argument(
            Spec, Scheduler
        ),
        xls_scheduler_observation:spawn_argument(Spec, Stem),
        ");\n"
    ].

%% Keep each request and response together in the generated spawn call.
-spec ram_argument_pairs([[binary() | maybe_improper_list(any(), binary() | []) | byte(), ...]]) ->
    [[[any(), ...], ...]].
ram_argument_pairs([]) ->
    [];
ram_argument_pairs([Request, Response | Rest]) ->
    [[Request, ", ", Response] | ram_argument_pairs(Rest)].

%% Connects a unit's ordered output to its topology router.
-spec router_spawn(map(), map()) -> iodata().
router_spawn(
    Spec,
    Scheduler = #{
        stem := Stem,
        index := Source,
        destinations := Destinations,
        external_ids := ExternalIds
    }
) ->
    CreditIndex = producer_index(Spec, Source, egress_credit),
    [
        "    spawn ",
        router_name(Scheduler),
        "(\n",
        "      ",
        Stem,
        "_egress_c, ",
        Stem,
        "_requests_p[u32:",
        integer_to_list(CreditIndex),
        "]",
        [
            begin
                DestinationIndex = maps:get(index, Destination),
                ProducerIndex = producer_index(
                    Spec, DestinationIndex, {scheduler, Source}
                ),
                DestinationStem = maps:get(stem, Destination),
                [
                    ",\n      ",
                    DestinationStem,
                    "_requests_p[u32:",
                    integer_to_list(ProducerIndex),
                    "]"
                ]
            end
         || Destination <- Destinations
        ],
        [
            [",\n      ", external_buffer_producer(Spec, ExternalId, Source)]
         || ExternalId <- ExternalIds
        ],
        [
            [",\n      ", Argument]
         || Argument <-
                xls_topology_source_fragment_dslx:router_spawn_arguments(
                    Spec, Scheduler
                )
        ],
        ",\n      ",
        lists:join(
            ",\n      ",
            xls_effect_window_dslx:arguments(
                maps:get(effect_window_domains, Spec), Scheduler
            )
        ),
        ");\n"
    ].

%% Connects the topology's external control fanout.
-spec control_spawn(map()) -> [any()].
control_spawn(#{ingresses := []}) ->
    [];
control_spawn(Spec = #{ingresses := [#{input_name := InputName}], controlled_groups := Groups}) ->
    [
        "    spawn ControlDispatcher(",
        InputName,
        [
            begin
                Scheduler = scheduler(Spec, Group),
                Index = producer_index(Spec, Group, control),
                [
                    ", ",
                    maps:get(stem, Scheduler),
                    "_requests_p[u32:",
                    integer_to_list(Index),
                    "]"
                ]
            end
         || Group <- Groups
        ],
        ");\n"
    ].

%% Resolves a producer identity to its assigned input-lane index.
-spec producer_index(map(), term(), term()) -> non_neg_integer().
producer_index(Spec, Group, Producer) ->
    maps:get(
        Producer,
        maps:get(producer_index, scheduler(Spec, Group))
    ).

%%%
%%% Top-level boundary
%%%

-spec top_proc(map()) -> [[any()], ...].
top_proc(Spec = #{ingresses := Ingresses, externals := Externals}) ->
    Arguments =
        ram_arguments(Spec) ++ xls_scheduler_observation:arguments(Spec) ++
            ingress_arguments(Ingresses) ++
            external_arguments(Externals),
    Names =
        ram_names(Spec) ++ xls_scheduler_observation:names(Spec) ++ ingress_names(Ingresses) ++
            external_names(Externals),
    [
        "pub proc Top {\n",
        [["  ", Argument, ";\n"] || Argument <- Arguments],
        "\n",
        config_signature(Arguments, 2),
        "    spawn ",
        grid_name(Spec),
        "(\n",
        [
            ["      ", Name, separator(Index, length(Names)), "\n"]
         || {Index, Name} <- lists:enumerate(0, Names)
        ],
        "    );\n",
        "    ",
        channel_tuple(Names),
        "\n",
        "  }\n\n",
        "  init { () }\n",
        "  next(state: ()) { state }\n",
        "}\n"
    ].

%% Declares paired request and response channels for each RAM.
-spec ram_arguments(map()) -> [any()].
ram_arguments(#{schedulers := Schedulers}) ->
    lists:append([
        xls_scheduler_ram_dslx:parameters([Stem, "_"], [Module, "::"])
     || #{stem := Stem, module_name := Module} <- Schedulers
    ]).

%% Lists RAM endpoints in declaration order.
-spec ram_names(map()) -> [any()].
ram_names(#{schedulers := Schedulers}) ->
    lists:append([
        xls_scheduler_ram_dslx:names([Stem, "_"])
     || #{stem := Stem} <- Schedulers
    ]).

%% Declares external control inputs required by the topology.
-spec ingress_arguments([map()]) -> [[any(), ...]].
ingress_arguments(Ingresses) ->
    [
        [
            maps:get(input_name, Ingress),
            ": chan<hls_spatial_router::SpatialFrame> in"
        ]
     || Ingress <- Ingresses
    ].

%% Lists external control endpoints in declaration order.
-spec ingress_names([map()]) -> [any()].
ingress_names(Ingresses) ->
    [maps:get(input_name, Ingress) || Ingress <- Ingresses].

%% Declares the topology's externally routed outputs.
-spec external_arguments([map()]) -> [[any(), ...]].
external_arguments(Externals) ->
    [
        [maps:get(output_name, External), ": chan<axis::Frame> out"]
     || External <- Externals
    ].

%% Lists external output endpoints in declaration order.
-spec external_names([map()]) -> [any()].
external_names(Externals) ->
    [maps:get(output_name, External) || External <- Externals].

%%%
%%% Lookups and names
%%%

-spec scheduler(map(), term()) -> map().
scheduler(Spec, Group) ->
    maps:get(Group, maps:get(scheduler_index, Spec)).

%% Resolves a physical group to its generated actor implementation.
-spec scheduler_module(map(), term()) -> module().
scheduler_module(Spec, Group) ->
    maps:get(module_name, scheduler(Spec, Group)).

%% Names one source's lane to an external sink.
-spec external_output_name(map(), term()) -> iodata().
external_output_name(#{externals := Externals}, Id) ->
    {external, Id, External} = lists:keyfind(Id, 2, [
        {external, maps:get(id, External), External}
     || External <- Externals
    ]),
    maps:get(output_name, External).

%% Resolves the buffered producer endpoint for an external sink.
-spec external_buffer_producer(map(), term(), integer()) -> iodata().
external_buffer_producer(#{externals := Externals}, Id, Source) ->
    {external, Id, External} = lists:keyfind(Id, 2, [
        {external, maps:get(id, Candidate), Candidate}
     || Candidate <- Externals
    ]),
    Stem = external_buffer_name(External),
    case maps:get(source_schedulers, External) of
        [_] ->
            [Stem, "_p"];
        Sources ->
            Position = source_position(Source, Sources, 0),
            [Stem, "_p[u32:", integer_to_list(Position), "]"]
    end.

%% Finds a scheduler's local position among an output's producers.
-spec source_position(integer(), nonempty_maybe_improper_list(), non_neg_integer()) ->
    non_neg_integer().
source_position(Source, [Source | _], Position) -> Position;
source_position(Source, [_ | Rest], Position) -> source_position(Source, Rest, Position + 1).

%% Names the queue joining one router to external arbitration.
-spec external_buffer_name(map()) -> [string(), ...].
external_buffer_name(#{index := Index}) ->
    ["external_", integer_to_list(Index), "_buffer"].

%% Names the effect router belonging to a physical group.
-spec router_name(map()) -> [string(), ...].
router_name(#{index := Index}) ->
    ["SchedulerRouter", integer_to_list(Index)].

%% Names the router lane reaching a destination group.
-spec router_destination_name(integer()) -> [string(), ...].
router_destination_name(Index) ->
    ["to_scheduler_", integer_to_list(Index)].

%% Names a physical group's external control input.
-spec control_output_name(integer()) -> [string(), ...].
control_output_name(Group) ->
    ["scheduler_", integer_to_list(Group), "_control_out"].

%% Names a group's finite startup producer.
-spec startup_name(map()) -> [string(), ...].
startup_name(#{index := Index}) ->
    ["SchedulerStartup", integer_to_list(Index)].

%% Returns the ownership domain attached to the group.
-spec effect_window_scope(map()) -> [45 | 97 | 98 | 100 | 103 | 105 | 108 | 109 | 110 | 111, ...].
effect_window_scope(#{effect_window_domains := [_OnlyDomain]}) ->
    "global";
effect_window_scope(#{effect_window_domains := [_ | _]}) ->
    "domain-".

%% Names the generated channel array for a logical actor family.
-spec grid_name(map()) -> [71 | 83 | 99 | 100 | 101 | 104 | 105 | 108 | 114 | 117, ...].
grid_name(_Spec) -> "SchedulerGrid".

%% Declares configuration parameters in channel-binding order.
-spec config_signature([any()], 2) -> [[any()], ...].
config_signature(Arguments, Indent) ->
    Padding = lists:duplicate(Indent + 2, $\s),
    [
        lists:duplicate(Indent, $\s),
        "config(\n",
        [
            [Padding, Argument, separator(Index, length(Arguments)), "\n"]
         || {Index, Argument} <- lists:enumerate(0, Arguments)
        ],
        lists:duplicate(Indent, $\s),
        ") {\n"
    ].

%% Builds the endpoint tuple used by proc configuration.
-spec channel_tuple([any()]) -> [any(), ...].
channel_tuple([]) -> "()";
channel_tuple([Name]) -> ["(", Name, ",)"];
channel_tuple(Names) -> ["(", join_with(", ", Names), ")"].

%% Adds a separator only when preceding generated elements are present.
-spec separator(integer(), non_neg_integer()) -> [44].
separator(Index, Count) when Index + 1 < Count -> ",";
separator(_Index, _Count) -> "".

%% Join rendered channel names without flattening their fragments.
-spec join_with(iodata(), [iodata(), ...]) -> iolist().
join_with(Separator, Items) -> lists:join(Separator, Items).

%% Load packaged fixed algorithms through the same application resource boundary as the effect router.
-spec render_template(file:filename(), [{binary(), iodata()}]) -> binary().
render_template(Name, Bindings) ->
    Path = filename:join([code:priv_dir(hls_target), "xls", "templates", Name]),
    {ok, Template} = file:read_file(Path),
    xls_template:render(Template, Bindings).
