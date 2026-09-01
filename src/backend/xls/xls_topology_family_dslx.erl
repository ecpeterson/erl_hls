%%%% xls_topology_family_dslx
%%%%
%%%% Lowers regular two-dimensional actor families into compact DSLX.

-module(xls_topology_family_dslx).
-moduledoc """
Generates the compact regular-family DSLX backend used by the phi/noise
experiment.

The accepted subset is deliberately narrow: one or more same-shaped
two-dimensional families, wrapped translations between those families,
single-recipient routes, and queued two-way fanout from one family endpoint to
one family endpoint plus one scalar external output. Exact actors and other
route forms remain outside this backend.

The generated source contains one reusable node proc per family and nested
`unroll_for!` spawns over channel arrays. Its routing structure therefore
follows the number of family rules rather than the number of family members.
Each node has one credit-aware ingress which polls its incoming lanes directly,
without a tree of buffered two-way muxes. Explicit startup values still
produce one match arm per configured member, and XLS elaborates one actor and
the required bounded lane and mailbox queues per coordinate.

Each compact lane relation becomes one channel array. When two ports alias one
destination, both router arms use the same array element, preserving the
actor's source-ordered egress. Queued fanout starts after the common ordered
egress accepts the event and waits for both bounded branch arrays. A scalar
external is fed by a fair polling merge whose statically indexed receive sites
are unrolled; runtime channel indexing is not supported by the pinned XLS
build.

Family-member startup remains explicit normalized data. A family which has
startup data must provide exactly one frame for every member. The generated
ingress sends that frame under the actor's first admission credit, ahead of its
first routed receive, while the actor graph and routing stay compact.
""".

-export([emit/2]).

-define(U32_MAX, 16#ffffffff).
-define(MAX_PAYLOAD_BITS, 96).

-doc "Emits deterministic regular-family DSLX from a normalized plan.".
-spec emit(hls_topology:plan(), xls_topology_dslx:profile()) -> iolist().
emit(Plan, Profile) ->
    render(lower(Plan, Profile)).

%%%
%%% Validation and annotation
%%%

lower(Plan, Profile) ->
    ok = require_empty(actors, Plan),
    ok = require_empty(routes, Plan),
    Families0 = require_families(maps:get(families, Plan, [])),
    [Width, Height] = require_common_shape(Families0),
    Families1 = annotate_families(Families0),
    FamilyIndex = index_by_id(Families1),
    Externals = annotate_externals(require_externals(
        maps:get(externals, Plan, [])
    )),
    ExternalIndex = maps:from_list([
        {maps:get(id, External), External} || External <- Externals
    ]),
    Relations = maps:get(route_relations, Plan, []),
    ok = validate_relations(Relations, FamilyIndex),
    ok = validate_route_selectors(Relations, FamilyIndex, ExternalIndex),
    LaneRelations = derive_lane_relations(Relations),
    case maps:get(lane_relations, Plan, '$missing') of
        LaneRelations -> ok;
        CachedLanes -> error({inconsistent_dslx_family_plan_lanes,
            LaneRelations, CachedLanes})
    end,
    Lanes = annotate_lanes(
        LaneRelations,
        [Width, Height],
        ExternalIndex
    ),
    Routes = annotate_routes(Relations, Lanes),
    Startup = annotate_startup(maps:get(startup, Plan), FamilyIndex),
    Families = [annotate_family_graph(
        Family,
        Routes,
        Lanes,
        Startup
    ) || Family <- Families1],
    ok = validate_lane_ports(Families),
    ok = validate_external_lanes(Externals, Lanes),
    Physical = validate_profile(Profile),
    #{
        name => maps:get(name, Physical),
        depth => maps:get(channel_depth, Physical),
        families => Families,
        width => Width,
        height => Height,
        routes => Routes,
        lanes => Lanes,
        startup => Startup,
        externals => Externals
    }.

require_empty(Field, Plan) ->
    case maps:get(Field, Plan, '$missing') of
        [] -> ok;
        Value -> error({unsupported_dslx_family_section, Field, Value})
    end.

require_families([_ | _] = Families) -> Families;
require_families([]) -> error({unsupported_family_count, 0}).

require_common_shape([First | Rest]) ->
    Shape = require_two_dimensional_shape(First),
    lists:foreach(
        fun(Family) ->
            case require_two_dimensional_shape(Family) of
                Shape -> ok;
                Other -> error({incompatible_family_shape,
                    maps:get(id, Family), Shape, Other})
            end
        end,
        Rest
    ),
    Shape.

require_two_dimensional_shape(Family = #{shape := [Width, Height]}) ->
    ok = validate_dimensions(maps:get(id, Family), Width, Height),
    [Width, Height];
require_two_dimensional_shape(#{id := Id, shape := Shape}) ->
    error({unsupported_family_shape, Id, Shape}).

validate_dimensions(_FamilyId, Width, Height)
        when is_integer(Width), Width > 0, Width =< ?U32_MAX,
             is_integer(Height), Height > 0, Height =< ?U32_MAX ->
    ok;
validate_dimensions(FamilyId, Width, Height) ->
    error({unsupported_dslx_family_dimensions,
        FamilyId, [Width, Height], ?U32_MAX}).

require_externals([_ | _] = Externals) -> Externals;
require_externals([]) -> error({unsupported_dslx_family_external_count, 0}).

annotate_families(Families) ->
    [
        begin
            Module = maps:get(module, Family),
            Interface = hls_actor_interface:from_module(Module),
            Family#{
                index => Index,
                module_name => identifier(Module, family_module),
                interface => Interface,
                egress_depth => max(
                    1,
                    hls_actor_interface:max_entry_effects(Interface)
                )
            }
        end
        || {Index, Family} <- lists:enumerate(0, Families)
    ].

validate_relations(Relations, FamilyIndex) ->
    lists:foreach(
        fun(Relation = #{source := Source = {SourceFamily, _Port}}) ->
            true = maps:is_key(SourceFamily, FamilyIndex),
            case Relation of
                #{delivery := direct, recipients := [Recipient]} ->
                    validate_relation_recipient(
                        Source, Recipient, FamilyIndex
                    );
                #{delivery := queued, recipients := Recipients}
                        when length(Recipients) =:= 2 ->
                    validate_queued_recipients(
                        Source, Recipients, FamilyIndex
                    );
                #{delivery := Delivery, recipients := Recipients} ->
                    error({unsupported_route, Source, Delivery, Recipients})
            end
        end,
        Relations
    ).

validate_relation_recipient(
        _Source,
        {family, DestinationId, {translate, [_DX, _DY], wrap}},
        FamilyIndex) ->
    true = maps:is_key(DestinationId, FamilyIndex),
    ok;
validate_relation_recipient(_Source, {external, _ExternalId}, _FamilyIndex) ->
    ok;
validate_relation_recipient(Source, Recipient, _FamilyIndex) ->
    error({unsupported_recipient, Source, Recipient}).

validate_queued_recipients(Source, Recipients, FamilyIndex) ->
    lists:foreach(
        fun(Recipient) ->
            validate_relation_recipient(Source, Recipient, FamilyIndex)
        end,
        Recipients
    ),
    case lists:sort([recipient_kind(Recipient) || Recipient <- Recipients]) of
        [external, family] -> ok;
        Kinds -> error({unsupported_queued_recipients, Source, Kinds})
    end.

recipient_kind({family, _, _}) -> family;
recipient_kind({external, _}) -> external.

derive_lane_relations(Relations) ->
    LanePorts = lists:foldl(
        fun(Relation, Acc0) ->
            {SourceFamily, Port} = maps:get(source, Relation),
            lists:foldl(
                fun(Destination, Acc) ->
                    Key = {SourceFamily, Destination},
                    maps:update_with(
                        Key,
                        fun(Ports) -> [Port | Ports] end,
                        [Port],
                        Acc
                    )
                end,
                Acc0,
                maps:get(recipients, Relation)
            )
        end,
        #{},
        Relations
    ),
    [
        #{
            source => SourceFamily,
            destination => Destination,
            source_ports => lists:sort(Ports)
        }
        || {{SourceFamily, Destination}, Ports} <-
               lists:sort(maps:to_list(LanePorts))
    ].

annotate_externals(Externals) ->
    [
        begin
            case maps:get(direction, External) of
                out -> ok;
                Direction -> error({unsupported_dslx_family_external_direction,
                    maps:get(id, External), Direction})
            end,
            External#{
                index => Index,
                output_name => [identifier(
                    maps:get(id, External),
                    external_id
                ), "_out"]
            }
        end
        || {Index, External} <- lists:enumerate(0, Externals)
    ].

annotate_lanes(Lanes, Shape, ExternalIndex) ->
    [
        annotate_lane(Index, Lane, Shape, ExternalIndex)
        || {Index, Lane} <- lists:enumerate(0, Lanes)
    ].

annotate_lane(
        Index,
        Lane = #{destination :=
            {family, DestinationId, {translate, [DX, DY], wrap}}},
        [Width, Height],
        _ExternalIndex) ->
    Stem = ["lane_", integer_to_list(Index)],
    Base = Lane#{index => Index, stem => Stem},
    Base#{
        kind => family,
        destination_family => DestinationId,
        inverse_shift => [
            inverse_shift(DX, Width),
            inverse_shift(DY, Height)
        ]
    };
annotate_lane(
        Index,
        Lane = #{destination := {external, ExternalId}},
        _Shape,
        ExternalIndex) ->
    Stem = ["lane_", integer_to_list(Index)],
    Base = Lane#{index => Index, stem => Stem},
    case maps:find(ExternalId, ExternalIndex) of
        {ok, External} -> Base#{kind => external, external => External};
        error -> error({unknown_external, ExternalId})
    end;
annotate_lane(_Index, #{destination := Destination}, _Shape, _ExternalIndex) ->
    error({unsupported_destination, Destination}).

inverse_shift(0, _Size) -> zero;
inverse_shift(Offset, _Size) when Offset > 0 ->
    {minus, Offset};
inverse_shift(Offset, _Size) ->
    {plus, -Offset}.

annotate_routes(Relations, Lanes) ->
    LaneIndex = maps:from_list([
        {{maps:get(source, Lane), maps:get(destination, Lane)}, Lane}
        || Lane <- Lanes
    ]),
    [
        Relation#{lanes => [
            maps:get({SourceFamily, Recipient}, LaneIndex)
            || Recipient <- maps:get(recipients, Relation)
        ]}
        || Relation <- Relations,
           {SourceFamily, _Port} <- [maps:get(source, Relation)]
    ].

annotate_family_graph(Family, Routes, Lanes, Startup) ->
    Id = maps:get(id, Family),
    OutboundLanes = [Lane || Lane <- Lanes, maps:get(source, Lane) =:= Id],
    InboundLanes = [
        Lane
        || Lane <- Lanes,
           maps:get(kind, Lane) =:= family,
           maps:get(destination_family, Lane) =:= Id
    ],
    FamilyStartup = [
        Item || Item <- Startup, maps:get(family, Item) =:= Id
    ],
    Family#{
        routes => [
            Route
            || Route <- Routes,
               {SourceFamily, _} <- [maps:get(source, Route)],
               SourceFamily =:= Id
        ],
        outbound_lanes => OutboundLanes,
        inbound_lanes => InboundLanes,
        startup => family_startup(Family, FamilyStartup)
    }.

family_startup(_Family, []) -> none;
family_startup(Family, Items) ->
    Expected = maps:get(instance_count, Family),
    case length(Items) of
        Expected -> #{items => Items};
        Count -> error({incomplete_family_startup,
            maps:get(id, Family), Expected, Count})
    end.

validate_lane_ports(Families) ->
    lists:foreach(
        fun(Family) ->
            Ports = lists:usort(lists:append([
                maps:get(source_ports, Lane)
                || Lane <- maps:get(outbound_lanes, Family)
            ])),
            Outputs = lists:sort(maps:get(outputs, Family)),
            case lists:sort(Ports) of
                Outputs -> ok;
                Other -> error({inconsistent_family_lane_ports,
                    maps:get(id, Family), Outputs, Other})
            end
        end,
        Families
    ).

validate_external_lanes(Externals, Lanes) ->
    lists:foreach(
        fun(External) ->
            Id = maps:get(id, External),
            Matches = [
                Lane || Lane <- Lanes,
                maps:get(kind, Lane) =:= external,
                maps:get(id, maps:get(external, Lane)) =:= Id
            ],
            case Matches of
                [_] -> ok;
                _ -> error({unsupported_external_lane_count,
                    Id, length(Matches)})
            end
        end,
        Externals
    ).

validate_route_selectors(Relations, FamilyIndex, ExternalIndex) ->
    lists:foreach(
        fun(#{
            source := Source = {SourceId, Port},
            recipients := Recipients
        }) ->
            SourceInterface = maps:get(
                interface,
                maps:get(SourceId, FamilyIndex)
            ),
            Schemas = hls_actor_interface:output_schemas(
                SourceInterface,
                Port
            ),
            lists:foreach(
                fun
                    ({family, DestinationId, _} = Recipient) ->
                        DestinationInterface = maps:get(
                            interface,
                            maps:get(DestinationId, FamilyIndex)
                        ),
                        lists:foreach(
                            fun(Schema) ->
                                SourceSelector = maps:get(
                                    selector,
                                    hls_actor_interface:schema(
                                        SourceInterface, Schema
                                    )
                                ),
                                DestinationSelector = maps:get(
                                    selector,
                                    hls_actor_interface:schema(
                                        DestinationInterface, Schema
                                    )
                                ),
                                case DestinationSelector of
                                    SourceSelector -> ok;
                                    _ -> error({unsupported_route_tag_remap,
                                        Source, Recipient, Schema,
                                        SourceSelector, DestinationSelector})
                                end
                            end,
                            Schemas
                        );
                    ({external, ExternalId}) ->
                        true = maps:is_key(ExternalId, ExternalIndex)
                end,
                Recipients
            )
        end,
        Relations
    ).

annotate_startup(Startup, FamilyIndex) when is_list(Startup) ->
    [annotate_startup_item(Item, FamilyIndex) || Item <- Startup];
annotate_startup(Startup, _FamilyIndex) ->
    error({invalid_startup, Startup}).

annotate_startup_item(
        #{target := Target, delivery := cast, messages := [Message]},
        FamilyIndex) ->
    [FamilyId | Coordinates] = tuple_to_list(Target),
    #{interface := Interface, module := Module} =
        maps:get(FamilyId, FamilyIndex),
    case hls_actor_interface:initial_effects(Interface) of
        [] -> ok;
        Effects -> error({startup_target_has_initial_effects,
            Target, Module, Effects})
    end,
    Packed = pack_startup_message(Target, Module, Message),
    Packed#{
        target => Target,
        family => FamilyId,
        coordinates => Coordinates
    };
annotate_startup_item(Item, _FamilyIndex) ->
    error({unsupported_family_startup, Item}).

pack_startup_message(Target, Module, Message)
        when is_tuple(Message), tuple_size(Message) > 0,
             is_atom(element(1, Message)) ->
    TagName = element(1, Message),
    {Tag, Payload} = case {Module:pack_tag(TagName), Module:pack(Message)} of
        {PackedTag, PackedPayload}
                when is_integer(PackedTag), PackedTag >= 0,
                     PackedTag =< 255, is_binary(PackedPayload) ->
            {PackedTag, PackedPayload};
        Invalid -> error({invalid_packed_startup, Target, Invalid})
    end,
    Width = bit_size(Payload),
    case Width > 0 andalso Width rem 32 =:= 0 andalso
            Width =< ?MAX_PAYLOAD_BITS of
        true -> #{
            tag => Tag,
            payload => xls_nums:packed_unsigned_literal(Payload)
        };
        false -> error({unsupported_startup_payload, Target, Width})
    end;
pack_startup_message(Target, _Module, Message) ->
    error({invalid_startup_message, Target, Message}).

validate_profile(Profile) when is_map(Profile) ->
    Required = lists:sort([channel_depth, name]),
    Keys = lists:sort(maps:keys(Profile)),
    case {Required -- Keys, Keys -- Required} of
        {[], []} -> ok;
        {Missing, Unknown} ->
            error({invalid_dslx_profile_keys, Missing, Unknown})
    end,
    Name = identifier(maps:get(name, Profile), topology_name),
    case maps:get(channel_depth, Profile) of
        Depth when is_integer(Depth), Depth > 0, Depth =< ?U32_MAX -> ok;
        Depth -> error({invalid_dslx_channel_depth, Depth})
    end,
    Profile#{name := Name};
validate_profile(Profile) ->
    error({invalid_dslx_profile, Profile}).

identifier(Name, Context) when is_atom(Name) ->
    identifier(atom_to_list(Name), Context);
identifier(Name, Context) when is_list(Name) ->
    case re:run(Name, "^[a-z][a-z0-9_]*$", [{capture, none}]) of
        match ->
            case lists:member(Name, reserved_identifiers()) of
                true -> error({reserved_dslx_identifier, Context, Name});
                false -> Name
            end;
        nomatch -> error({invalid_dslx_identifier, Context, Name})
    end;
identifier(Name, Context) ->
    error({invalid_dslx_identifier, Context, Name}).

reserved_identifiers() ->
    [
        "as", "const", "else", "enum", "fn", "for", "if", "import",
        "in", "let", "match", "proc", "pub", "spawn", "struct",
        "type", "while"
    ].

%%%
%%% Rendering
%%%

render(Spec) ->
    [
        preamble(Spec),
        startup_support(maps:get(families, Spec)),
        family_routers(Spec),
        frame_grid_mux(maps:get(externals, Spec)),
        family_ingresses(Spec),
        family_nodes(Spec),
        family_grid(Spec),
        top_proc(Spec)
    ].

preamble(Spec) ->
    Families = maps:get(families, Spec),
    Modules = lists:usort([
        maps:get(module_name, Family) || Family <- Families
    ]),
    [
        "// ", maps:get(name, Spec), ".x\n",
        "// Auto-generated by xls_topology_dslx from compact Erlang family ",
        "rules.\n",
        "// Manual changes will be overwritten.\n",
        "//\n",
        preamble_node_comment(Families),
        "// Scalar external streams use fair polling over statically indexed ",
        "family lanes.\n\n",
        "import axis;\n",
        [["import ", Module, ";\n"] || Module <- Modules],
        "\n",
        "const CHANNEL_DEPTH = u32:", integer_to_list(maps:get(depth, Spec)),
        ";\n",
        "const WIDTH = u32:", integer_to_list(maps:get(width, Spec)), ";\n",
        "const HEIGHT = u32:", integer_to_list(maps:get(height, Spec)),
        ";\n\n"
    ].

preamble_node_comment([_]) ->
    "// One reusable node and nested unroll_for! spawns retain regular "
    "source structure.\n";
preamble_node_comment([_, _ | _]) ->
    "// Reusable family nodes and nested unroll_for! spawns retain regular "
    "source structure.\n".

startup_support(Families) ->
    [startup_function(Family) || Family <- Families].

startup_function(#{startup := none}) -> [];
startup_function(Family = #{startup := #{items := Items}}) ->
    [
        "fn ", startup_function_name(Family),
        "(x: u32, y: u32) -> axis::Frame {\n",
        "  match (x, y) {\n",
        [startup_arm(Item) || Item <- Items],
        "    _ => zero!<axis::Frame>(),\n",
        "  }\n}\n\n"
    ].

startup_arm(#{coordinates := [X, Y], tag := Tag, payload := Payload}) ->
    ["    (u32:", integer_to_list(X), ", u32:", integer_to_list(Y),
        ") => axis::pack(u8:", integer_to_list(Tag), ", ", Payload,
        "),\n"].

family_routers(Spec) ->
    [family_router(Spec, Family) || Family <- maps:get(families, Spec)].

family_router(Spec, Family) ->
    Module = maps:get(module_name, Family),
    Lanes = maps:get(outbound_lanes, Family),
    Outputs = maps:get(outputs, Family),
    RouteIndex = maps:from_list([
        {Port, Route}
        || Route <- maps:get(routes, Family),
           {_FamilyId, Port} <- [maps:get(source, Route)]
    ]),
    [
        "proc ", router_name(Spec, Family), " {\n",
        "  egress_in: chan<", Module, "::Egress> in;\n",
        [["  ", lane_output(Lane), ": chan<axis::Frame> out;\n"]
            || Lane <- Lanes],
        "\n",
        config_signature(
            [["egress_in: chan<", Module, "::Egress> in"] |
                [[lane_output(Lane), ": chan<axis::Frame> out"]
                    || Lane <- Lanes]],
            2
        ),
        "    (egress_in",
        [[", ", lane_output(Lane)] || Lane <- Lanes],
        ")\n  }\n\n",
        "  init { () }\n\n",
        "  next(state: ()) {\n",
        "    let (tok, egress) = recv(join(), egress_in);\n",
        "    let _route_tok = match egress.port {\n",
        [
            router_arm(Module, Port, maps:get(Port, RouteIndex))
            || Port <- Outputs
        ],
        "    };\n",
        "    state\n  }\n}\n\n"
    ].

router_arm(Module, Port, #{delivery := direct, lanes := [Lane]}) ->
    ["      ", Module, "::OutputPort::", uppercase(Port),
        " => send(tok, ", lane_output(Lane), ", egress.frame),\n"];
router_arm(Module, Port, #{delivery := queued, lanes := [Left, Right]}) ->
    ["      ", Module, "::OutputPort::", uppercase(Port), " => {\n",
        "        let branch_0_tok = send(tok, ", lane_output(Left),
        ", egress.frame);\n",
        "        let branch_1_tok = send(tok, ", lane_output(Right),
        ", egress.frame);\n",
        "        join(branch_0_tok, branch_1_tok)\n",
        "      },\n"].

frame_grid_mux([]) -> [];
frame_grid_mux(_Externals) ->
    %% DSLX writes array dimensions from inner to outer. Consequently
    %% `[GRID_HEIGHT][GRID_WIDTH]` has `GRID_WIDTH` outer elements and
    %% supports the coordinate order `frame_in[x][y]` used below.
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
              acc.0,
              frame_in[candidate],
              selected,
              zero!<axis::Frame>());
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

    proc FrameGridMux<GRID_WIDTH: u32, GRID_HEIGHT: u32> {
      config(
          frame_in: chan<axis::Frame>[GRID_HEIGHT][GRID_WIDTH] in,
          frame_out: chan<axis::Frame> out
      ) {
        let (column_p, column_c) =
          chan<axis::Frame, CHANNEL_DEPTH>[GRID_WIDTH]("grid_column");
        unroll_for! (x, _): (u32, ()) in u32:0..GRID_WIDTH {
          spawn FrameArrayMux<GRID_HEIGHT>(frame_in[x], column_p[x]);
        }(());
        spawn FrameArrayMux<GRID_WIDTH>(column_c, frame_out);
        ()
      }

      init { () }
      next(state: ()) { state }
    }

    """.

family_ingresses(Spec) ->
    [family_ingress(Spec, Family) || Family <- maps:get(families, Spec)].

family_ingress(_Spec, #{inbound_lanes := []}) ->
    error(no_inbound_lanes);
family_ingress(Spec, Family = #{inbound_lanes := InboundLanes}) ->
    InputCount = length(InboundLanes),
    InputNames = [incoming_name(Index)
        || Index <- lists:seq(0, InputCount - 1)],
    CursorType = xls_nums:unsigned_type(cursor_width(InputCount)),
    InputMembers = [
        [Name, ": chan<axis::Frame> in"] || Name <- InputNames
    ],
    Members = InputMembers ++ [
        "frame_out: chan<axis::Frame> out",
        "admission_in: chan<u1> in"
    ],
    MemberNames = InputNames ++ ["frame_out", "admission_in"],
    [
        "// Retains one mailbox credit while polling one input per ",
        "activation.\n",
        "proc ", ingress_name(Spec, Family), node_parametrics(Family), " {\n",
        [["  ", Member, ";\n"] || Member <- Members],
        "\n",
        config_signature(Members, 2),
        "    (", join_with(", ", MemberNames), ")\n  }\n\n",
        ingress_init(Family, CursorType),
        ingress_next(Family, CursorType, InputCount),
        "}\n\n"
    ].

ingress_init(#{startup := none}, CursorType) ->
    ["  init { (", cursor_literal(CursorType, 0), ", u1:0) }\n\n"];
ingress_init(#{startup := #{}}, CursorType) ->
    ["  init { (", cursor_literal(CursorType, 0),
        ", u1:0, u1:0) }\n\n"].

ingress_next(#{startup := none}, CursorType, InputCount) ->
    [
        "  next(state: (", CursorType, ", u1)) {\n",
        "    if !state.1 {\n",
        ingress_credit_state(false),
        "    } else {\n",
        ingress_poll(CursorType, InputCount, false),
        "    }\n",
        "  }\n"
    ];
ingress_next(Family = #{startup := #{}}, CursorType, InputCount) ->
    [
        "  next(state: (", CursorType, ", u1, u1)) {\n",
        "    if !state.1 {\n",
        ingress_credit_state(true),
        "    } else if !state.2 {\n",
        "      let _tok = send(\n",
        "        join(), frame_out, ", startup_function_name(Family),
        "(X, Y));\n",
        "      (state.0, u1:0, u1:1)\n",
        "    } else {\n",
        ingress_poll(CursorType, InputCount, true),
        "    }\n",
        "  }\n"
    ].

ingress_credit_state(HasStartup) ->
    [
        "      let (_tok, _credit) = recv(join(), admission_in);\n",
        "      (state.0, u1:1", ingress_started_state(HasStartup), ")\n"
    ].

ingress_started_state(false) -> [];
ingress_started_state(true) -> ", state.2".

ingress_poll(CursorType, InputCount, HasStartup) ->
    Indexes = lists:seq(0, InputCount - 1),
    [
        [ingress_receive(Index, CursorType) || Index <- Indexes],
        "      let received = ",
        join_with(" || ", [valid_name(Index) || Index <- Indexes]), ";\n",
        "      let frame = ", select_received_frame(Indexes), ";\n",
        "      let _done = send_if(", token_name(InputCount - 1),
        ", frame_out, received, frame);\n",
        "      let next_cursor = if state.0 == ",
        cursor_literal(CursorType, InputCount - 1), " {\n",
        "        ", cursor_literal(CursorType, 0), "\n",
        "      } else {\n",
        "        state.0 + ", cursor_literal(CursorType, 1), "\n",
        "      };\n",
        "      (next_cursor, !received", ingress_started_state(HasStartup),
        ")\n"
    ].

ingress_receive(Index, CursorType) ->
    PreviousToken = case Index of
        0 -> "join()";
        _ -> token_name(Index - 1)
    end,
    [
        "      let (", token_name(Index), ", ", frame_name(Index), ", ",
        valid_name(Index), ") = recv_if_non_blocking(\n",
        "        ", PreviousToken, ", ", incoming_name(Index),
        ", state.0 == ", cursor_literal(CursorType, Index),
        ", zero!<axis::Frame>());\n"
    ].

select_received_frame([Index]) -> frame_name(Index);
select_received_frame([Index | Rest]) ->
    ["if ", valid_name(Index), " { ", frame_name(Index),
        " } else { ", select_received_frame(Rest), " }"].

cursor_width(InputCount) ->
    cursor_width(InputCount - 1, 0).

cursor_width(0, 0) -> 1;
cursor_width(0, Width) -> Width;
cursor_width(Value, Width) -> cursor_width(Value bsr 1, Width + 1).

cursor_literal(CursorType, Value) ->
    [CursorType, ":", integer_to_list(Value)].

token_name(Index) -> ["tok_", integer_to_list(Index)].
frame_name(Index) -> ["frame_", integer_to_list(Index)].
valid_name(Index) -> ["valid_", integer_to_list(Index)].

family_nodes(Spec) ->
    [family_node(Spec, Family) || Family <- maps:get(families, Spec)].

family_node(Spec, Family) ->
    Module = maps:get(module_name, Family),
    InboundLanes = maps:get(inbound_lanes, Family),
    OutboundLanes = maps:get(outbound_lanes, Family),
    Inputs = [[incoming_name(Index), ": chan<axis::Frame> in"]
        || {Index, _Lane} <- lists:enumerate(0, InboundLanes)],
    Outputs = [[lane_output(Lane), ": chan<axis::Frame> out"]
        || Lane <- OutboundLanes],
    [
        "proc ", node_name(Spec, Family), node_parametrics(Family), " {\n",
        config_signature(Inputs ++ Outputs, 2),
        "    let (actor_req_p, actor_req_c) =\n",
        "      chan<axis::Frame, CHANNEL_DEPTH>(\"actor_req\");\n",
        "    let (actor_admit_p, actor_admit_c) =\n",
        "      chan<u1, CHANNEL_DEPTH>(\"actor_admit\");\n",
        "    let (actor_egress_p, actor_egress_c) =\n",
        "      chan<", Module, "::Egress, u32:",
        integer_to_list(maps:get(egress_depth, Family)),
        ">(\"actor_egress\");\n",
        "    spawn ", Module, "::Service(\n",
        "      actor_req_c, actor_egress_p, actor_admit_p);\n",
        "    spawn ", router_name(Spec, Family), "(actor_egress_c",
        [[", ", lane_output(Lane)] || Lane <- OutboundLanes],
        ");\n",
        "    spawn ", ingress_name(Spec, Family),
        ingress_specialization(Family), "(",
        join_with(", ", [
            incoming_name(Index)
            || {Index, _Lane} <- lists:enumerate(0, InboundLanes)
        ] ++ ["actor_req_p", "actor_admit_c"]),
        ");\n",
        "    ()\n  }\n\n",
        "  init { () }\n",
        "  next(state: ()) { state }\n",
        "}\n\n"
    ].

family_grid(Spec) ->
    Lanes = maps:get(lanes, Spec),
    Externals = maps:get(externals, Spec),
    [
        "proc ", grid_name(Spec),
        "<TORUS_WIDTH: u32, TORUS_HEIGHT: u32> {\n",
        config_signature(
            [[maps:get(output_name, External),
                ": chan<axis::Frame> out"] || External <- Externals],
            2
        ),
        [lane_array(Lane) || Lane <- Lanes],
        [family_spawn(Spec, Family)
            || Family <- maps:get(families, Spec)],
        [external_merge_spawn(External, Lanes) || External <- Externals],
        "    ()\n  }\n\n",
        "  init { () }\n",
        "  next(state: ()) { state }\n",
        "}\n\n"
    ].

lane_array(Lane) ->
    %% As above, the rightmost dimension is the outer x dimension in DSLX.
    Stem = maps:get(stem, Lane),
    [
        "    let (", Stem, "_p, ", Stem, "_c) =\n",
        "      chan<axis::Frame, CHANNEL_DEPTH>",
        "[TORUS_HEIGHT][TORUS_WIDTH](\"", Stem, "\");\n"
    ].

family_spawn(Spec, Family) ->
    [
        family_comment(Spec, Family),
        "    unroll_for! (x, _): (u32, ()) in u32:0..TORUS_WIDTH {\n",
        "      unroll_for! (y, _): (u32, ()) in u32:0..TORUS_HEIGHT {\n",
        "        spawn ", node_name(Spec, Family),
        node_specialization(Family), "(\n",
        node_spawn_arguments(Family),
        "        );\n",
        "      }(())\n",
        "    }(());\n"
    ].

family_comment(#{families := [_]}, _Family) -> [];
family_comment(_Spec, Family) ->
    ["    // Family ", io_lib:format("~tp", [maps:get(id, Family)]), ".\n"].

node_spawn_arguments(Family) ->
    InboundLanes = maps:get(inbound_lanes, Family),
    OutboundLanes = maps:get(outbound_lanes, Family),
    Arguments =
        [family_lane_consumer(Lane) || Lane <- InboundLanes] ++
        [[maps:get(stem, Lane), "_p[x][y]"] || Lane <- OutboundLanes],
    [
        ["          ", Argument, separator(Index, length(Arguments)), "\n"]
        || {Index, Argument} <- lists:enumerate(0, Arguments)
    ].

family_lane_consumer(Lane) ->
    [DX, DY] = maps:get(inverse_shift, Lane),
    [maps:get(stem, Lane), "_c[", shifted_index("x", DX, "TORUS_WIDTH"),
        "][", shifted_index("y", DY, "TORUS_HEIGHT"), "]"].

shifted_index(Axis, zero, _Size) -> Axis;
shifted_index(Axis, {plus, Offset}, Size) ->
    ["(", Axis, " + u32:", integer_to_list(Offset), ") % ", Size];
shifted_index(Axis, {minus, Offset}, Size) ->
    ["(", Axis, " + ", Size, " - u32:", integer_to_list(Offset),
        ") % ", Size].

external_merge_spawn(External, Lanes) ->
    [Lane] = [
        Candidate || Candidate <- Lanes,
        maps:get(kind, Candidate) =:= external,
        maps:get(id, maps:get(external, Candidate)) =:= maps:get(id, External)
    ],
    [
        "    spawn FrameGridMux<TORUS_WIDTH, TORUS_HEIGHT>(",
        maps:get(stem, Lane), "_c, ", maps:get(output_name, External),
        ");\n"
    ].

top_proc(Spec) ->
    Externals = maps:get(externals, Spec),
    [
        "pub proc Top {\n",
        [["  ", maps:get(output_name, External),
            ": chan<axis::Frame> out;\n"] || External <- Externals],
        "\n",
        config_signature(
            [[maps:get(output_name, External),
                ": chan<axis::Frame> out"] || External <- Externals],
            2
        ),
        "    spawn ", grid_name(Spec), "<WIDTH, HEIGHT>(",
        join_with(", ", [maps:get(output_name, External)
            || External <- Externals]),
        ");\n",
        "    ", external_tuple(Externals), "\n",
        "  }\n\n",
        "  init { () }\n",
        "  next(state: ()) { state }\n",
        "}\n"
    ].

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

incoming_name(Index) -> ["incoming_", integer_to_list(Index)].
lane_output(Lane) -> [maps:get(stem, Lane), "_out"].

router_name(Spec, Family) ->
    ["FamilyRouter", family_suffix(Spec, Family)].

node_name(Spec, Family) ->
    ["FamilyNode", family_suffix(Spec, Family)].

ingress_name(Spec, Family) ->
    ["FamilyIngress", family_suffix(Spec, Family)].

startup_function_name(Family) ->
    ["family_", integer_to_list(maps:get(index, Family)), "_startup"].

node_parametrics(#{startup := none}) -> [];
node_parametrics(#{startup := #{}}) -> "<X: u32, Y: u32>".

node_specialization(#{startup := none}) -> [];
node_specialization(#{startup := #{}}) -> "<x, y>".

ingress_specialization(#{startup := none}) -> [];
ingress_specialization(#{startup := #{}}) -> "<X, Y>".

family_suffix(#{families := [_]}, _Family) -> [];
family_suffix(#{families := [_, _ | _]}, #{index := Index}) ->
    integer_to_list(Index).

grid_name(#{families := [_]}) -> "FamilyTorus";
grid_name(#{families := [_, _ | _]}) -> "FamilyGrid".

separator(Index, Arity) when Index + 1 < Arity -> ",";
separator(_Index, _Arity) -> "".

external_tuple([]) -> "()";
external_tuple([External]) -> ["(", maps:get(output_name, External), ",)"];
external_tuple(Externals) ->
    ["(", join_with(", ", [maps:get(output_name, External)
        || External <- Externals]), ")"].

uppercase(Atom) -> string:uppercase(atom_to_list(Atom)).

join_with(_Separator, []) -> [];
join_with(Separator, [First | Rest]) ->
    [First | [[Separator, Item] || Item <- Rest]].

index_by_id(Items) ->
    maps:from_list([{maps:get(id, Item), Item} || Item <- Items]).
