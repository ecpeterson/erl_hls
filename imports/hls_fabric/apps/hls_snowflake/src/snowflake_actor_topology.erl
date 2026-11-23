-module(snowflake_actor_topology).
-moduledoc "Communicating Snowflake vertices with independently selected barrier and execution placement.".
-export([
    topology/0, topology/2, topology/3,
    profile/3,
    geometry/2,
    vertex_config/2,
    ownership/1,
    write/3, write/4
]).
-export_type([options/0]).
-include("snowflake_actor_protocol.hrl").

-doc "Selects barrier and RAM-backed groups independently; vertex_order is a complete source permutation split into equal groups.".
-type options() :: #{
    barrier => flat | tree6,
    vertex_groups => 0 | 6 | 12,
    specialize_state => boolean(),
    admission_reductions => boolean() | exclusive_epoch,
    acknowledgment_collection => boolean(),
    gather_collection => boolean(),
    effect_delivery_width => 1..6,
    vertex_order => [non_neg_integer()]
}.

-doc "Returns the distance-three, height-three actor graph.".
-spec topology() -> hls_topology:spec().
topology() -> topology(3, 3).

-doc "Returns a fixed surface-code window; each vertex owns its state and incident edge copies.".
-spec topology(pos_integer(), pos_integer()) -> hls_topology:spec().
topology(Distance, Height) -> topology(Distance, Height, #{}).

-doc "Keeps vertex identities and neighbor routes while selecting a flat or six-member barrier tree.".
-spec topology(pos_integer(), pos_integer(), options()) -> hls_topology:spec().
topology(Distance, Height, Options) ->
    Geometry = geometry(Distance, Height),
    Count = tuple_size(maps:get(coordinates, Geometry)),
    #{barrier := Barrier} = options(Options, Count),
    Vertices = lists:seq(0, Count - 1),
    Branches = barrier_branches(Barrier, Count),
    #{
        version => 1,
        actors => maps:from_list(
            [
                {coordinator, snowflake_coordinator}
                | [{{vertex, I}, snowflake_vertex} || I <- Vertices]
            ] ++
                [{{barrier, I}, snowflake_barrier} || #{source := I} <- Branches]
        ),
        families => #{},
        route_relations => [],
        ingresses => [
            {inputs, {rectangle, [1, 1]}, [
                {sheets, [sf_input], [{actor, coordinator, {at, [0, 0]}}]}
            ]}
        ],
        externals => [
            {rounds, out, [sf_round]},
            {corrections, out, [sf_correction]},
            {unexpected, out, [sf_snapshot, sf_transfer, sf_shift]}
        ],
        routes => [
            {
                {coordinator, command},
                queued,
                [{actor, {vertex, I}} || I <- Vertices] ++
                    ?SF_ADVANCE_SELECT([{actor, {barrier, I}} || #{source := I} <- Branches], [])
            },
            {{coordinator, report}, [{external, rounds}]}
        ] ++
            lists:append([vertex_routes(I, Geometry, Barrier) || I <- Vertices]) ++
            [{{{barrier, I}, status}, [{actor, coordinator}]} || #{source := I} <- Branches],
        startup => [
            {coordinator, [
                #sf_coordinator_config{
                    count =
                        case Barrier of
                            flat -> Count;
                            tree6 -> length(Branches)
                        end,
                    height = Height
                }
            ]}
            | [
                {{vertex, I}, [geometry_config(Geometry), vertex_config(I, Geometry)]}
             || I <- Vertices
            ]
        ] ++
            [
                {{barrier, I}, [#sf_barrier_config{source = I, first = First, count = Size}]}
             || #{source := I, first := First, count := Size} <- Branches
            ]
    }.

-doc "Checks the finite protocol's source-address and syndrome-mask bounds.".
-spec geometry(pos_integer(), pos_integer()) -> snowflake_geometry:geometry().
geometry(Distance, Height) ->
    Geometry =
        #{coordinates := Coordinates, syndrome_width := Width} =
        snowflake_geometry:new(surface, Distance, Height),
    case {tuple_size(Coordinates), Width} of
        {Count, Bits} when Count =< 255, Bits =< 32 -> Geometry;
        Shape -> error({actor_protocol_capacity, Shape})
    end.

%% Global CID translation uses the same geometry authority as the reference.
-spec geometry_config(snowflake_geometry:geometry()) -> #sf_geometry{}.
geometry_config(#{
    cid_boundary_limit := Limit,
    cid_boundary_shift := Boundary,
    cid_bulk_shift := Bulk
}) ->
    #sf_geometry{boundary_limit = Limit, boundary_shift = Boundary, bulk_shift = Bulk}.

-doc "Returns one zero-based vertex's immutable local geometry and correction ownership.".
-spec vertex_config(non_neg_integer(), snowflake_geometry:geometry()) -> #sf_vertex_config{}.
vertex_config(
    Source,
    Geometry = #{
        coordinates := Coordinates,
        ids := Ids,
        neighbors := Neighbors,
        syndrome_bits := SyndromeBits,
        height := Height,
        boundaries := Boundaries,
        bottoms := Bottoms,
        node_above := Above
    }
) ->
    Index = Source + 1,
    Bit =
        case element(Index, SyndromeBits) of
            -1 -> 255;
            Value -> Value
        end,
    RetireMask = lists:foldl(
        fun
            (#{source := Owner, direction := Direction}, Acc) when
                Owner =:= Source
            ->
                Acc bor (1 bsl (Direction - 1));
            (_, Acc) ->
                Acc
        end,
        0,
        ownership(Geometry)
    ),
    Coordinate = element(Index, Coordinates),
    #sf_vertex_config{
        source = Source,
        id = element(Index, Ids),
        neighbors = lists:foldl(
            fun({Direction, _, _}, Mask) ->
                Mask bor (1 bsl (Direction - 1))
            end,
            0,
            element(Index, Neighbors)
        ),
        syndrome_bit = Bit,
        retire_mask = RetireMask,
        height = Height,
        top = element(Index, Above) =:= 0,
        bottom = element(Index, Bottoms),
        boundary = element(Index, Boundaries),
        below = element(tuple_size(Coordinate), Coordinate) > 0
    }.

-doc "Names exactly one sender and direction for every retired spatial or temporal edge bit.".
-spec ownership(snowflake_geometry:geometry()) -> [map()].
ownership(#{
    coordinates := Coordinates,
    endpoints := Endpoints,
    neighbors := Neighbors,
    retired_spatial := Spatial,
    retired_temporal := Temporal
}) ->
    Indices = maps:from_list(
        lists:zip(
            tuple_to_list(Coordinates),
            lists:seq(1, tuple_size(Coordinates))
        )
    ),
    [
        begin
            {A, _} = element(Edge, Endpoints),
            Index = maps:get(A, Indices),
            [{Direction, _, Edge}] = [N || N = {_, _, E} <- element(Index, Neighbors), E =:= Edge],
            #{
                kind => Kind,
                bit => Bit,
                edge => Edge - 1,
                source => Index - 1,
                direction => Direction
            }
        end
     || {Kind, Edges} <- [{spatial, Spatial}, {temporal, Temporal}],
        {Bit, Edge} <- lists:enumerate(0, tuple_to_list(Edges))
    ].

%% Nonexistent directions are observable errors, never artificial graph edges.
-spec vertex_routes(non_neg_integer(), snowflake_geometry:geometry(), flat | tree6) -> [tuple()].
vertex_routes(Source, #{neighbors := Neighbors, node_above := Above}, Barrier) ->
    Id = {vertex, Source},
    Adjacent = maps:from_list([
        {Direction, {actor, {vertex, Index - 1}}}
     || {Direction, Index, _} <- element(Source + 1, Neighbors)
    ]),
    Below =
        case [I - 1 || {I, A} <- lists:enumerate(tuple_to_list(Above)), A =:= Source + 1] of
            [] -> {external, unexpected};
            [Target] -> {actor, {vertex, Target}}
        end,
    Status =
        case Barrier of
            flat -> coordinator;
            tree6 -> {barrier, Source div 6}
        end,
    [
        {{Id, Port}, [maps:get(Direction, Adjacent, {external, unexpected})]}
     || {Direction, Port} <- lists:enumerate([west, east, down, up, north, south])
    ] ++
        [
            {{Id, below}, [Below]},
            {{Id, status}, [{actor, Status}]},
            {{Id, correction}, [{external, corrections}]}
        ].

-doc "Translates the original flat, dedicated topology and writes its placement manifest.".
-spec write(pos_integer(), pos_integer(), file:filename()) -> ok.
write(Distance, Height, Directory) -> write(Distance, Height, Directory, #{}).

-doc "Writes actor DSLX and RAM wiring, retaining emitted codebooks for optional debug projections.".
-spec write(pos_integer(), pos_integer(), file:filename(), options()) -> ok.
write(Distance, Height, Directory, Options) ->
    Count = tuple_size(maps:get(coordinates, geometry(Distance, Height))),
    #{barrier := Barrier, vertex_groups := GroupCount} = options(Options, Count),
    Branches = barrier_branches(Barrier, Count),
    Population =
        case Branches of
            [] -> Count;
            _ -> length(Branches)
        end,
    #{sources := SourceBound, mailbox := MailboxBound} = snowflake_coordinator:bounds(),
    case Population =< SourceBound andalso MailboxBound > 8 of
        true -> ok;
        false -> error({coordinator_bounds, Population, SourceBound, MailboxBound})
    end,
    ok = filelib:ensure_dir(filename:join(Directory, "placeholder")),
    Plan = hls_topology:normalize(topology(Distance, Height, Options)),
    Profile = #{scheduler_groups := Groups} = profile(Distance, Height, Options),
    {TopologyBackend, ActorBackend} =
        case map_size(Groups) of
            0 -> {xls_topology_dslx, xls_parse};
            _ -> {xls_fabric_topology_dslx, xls_scheduler_actor}
        end,
    Physical =
        case map_size(Groups) of
            0 ->
                maps:without(
                    [scheduler_groups, direct_collections, effect_delivery_width], Profile
                );
            _ ->
                Profile
        end,
    Resolved = TopologyBackend:artifact_requirements(Plan, Physical),
    Artifacts = maps:map(
        fun(Module, Requirement) ->
            Source = filename:join([
                code:lib_dir(hls_snowflake), "src", atom_to_list(Module) ++ ".erl"
            ]),
            [Context] = proplists:get_value(hls_source_context, Module:module_info(attributes)),
            Artifact = ActorBackend:to_artifact(Source, Requirement#{source_options => Context}),
            ok = xls_emitted:write(
                Artifact,
                filename:join(Directory, atom_to_list(Module) ++ ".x")
            ),
            Artifact
        end,
        Resolved
    ),
    ok = file:write_file(
        filename:join(Directory, "snowflake_actor_topology.x"),
        TopologyBackend:emit(Plan, Physical)
    ),
    Schedule = hls_scheduler_plan:normalize(Plan, Groups),
    case maps:get(specialize_state, Options, false) of
        false ->
            ok;
        true ->
            Projection = xls_scheduler_debug:projection(Plan, Groups, Artifacts),
            ok = file:write_file(
                filename:join(Directory, "actor-projection.json"), json:encode(Projection)
            )
    end,
    Bindings = xls_scheduler_ram_v:bindings(Schedule),
    ok = write_ram_artifacts(Directory, Bindings),
    Manifest = #{
        schema => <<"snowflake-actor-placement-v1">>,
        distance => Distance,
        height => Height,
        vertices => Count,
        barrier => Barrier,
        vertex_groups => GroupCount,
        specialize_state => maps:get(specialize_state, Options, false),
        admission_reductions => maps:get(admission_reductions, Options, false),
        acknowledgment_collection => maps:get(acknowledgment_collection, Options, false),
        gather_collection => maps:get(gather_collection, Options, false),
        core_module => <<"__snowflake_actor_topology__Top_0_next">>,
        top_module =>
            case Bindings of
                [] -> <<"__snowflake_actor_topology__Top_0_next">>;
                _ -> <<"snowflake_actor_wrapper">>
            end,
        topology_dslx => <<"snowflake_actor_topology.x">>,
        actor_dslx => [
            list_to_binary(atom_to_list(Module) ++ ".x")
         || Module <- lists:sort(maps:keys(Resolved))
        ],
        wrapper =>
            case Bindings of
                [] -> null;
                _ -> <<"snowflake_actor_wrapper.v">>
            end,
        rtl_assets =>
            case Bindings of
                [] ->
                    [];
                _ ->
                    [
                        <<"snowflake_actor_wrapper.v">>
                        | [
                            list_to_binary(filename:basename(P))
                         || P <- xls_scheduler_ram_v:assets(Bindings)
                        ]
                    ]
            end,
        ram_configurations => iolist_to_binary(ram_configurations(Bindings)),
        ram_bindings => Bindings,
        scheduler_groups => group_manifest(Schedule),
        barriers => Branches,
        coordinator_population => Population,
        coordinator_bounds => snowflake_coordinator:bounds()
    },
    file:write_file(filename:join(Directory, "placement.json"), json:encode(Manifest)).

-doc "Returns homogeneous exact-vertex groups; coordinator and optional barriers remain direct.".
-spec profile(pos_integer(), pos_integer(), options()) -> map().
profile(Distance, Height, Options) ->
    Count = tuple_size(maps:get(coordinates, geometry(Distance, Height))),
    #{vertex_groups := Groups, specialize_state := Specialize, admission_reductions := Collection} = options(
        Options, Count
    ),
    #{
        name => snowflake_actor_topology,
        channel_depth => 1,
        actor_egress_depth => burst,
        effect_delivery_width => maps:get(effect_delivery_width, Options, 1),
        direct_collections =>
            case maps:get(acknowledgment_collection, Options, false) of
                false ->
                    #{};
                true ->
                    #{
                        snowflake_barrier => exclusive_epoch,
                        snowflake_coordinator => exclusive_epoch
                    }
            end,
        scheduler_groups => maps:map(
            fun(_, G) ->
                S0 =
                    case Specialize of
                        true -> G#{specialize_state => true};
                        false -> G
                    end,
                S =
                    case maps:get(gather_collection, Options, false) of
                        true -> S0#{gather_collection => true};
                        false -> S0
                    end,
                case Collection of
                    false -> S;
                    _ -> S#{admission_reductions => Collection}
                end
            end,
            scheduler_groups(maps:get(vertex_order, Options, lists:seq(0, Count - 1)), Groups)
        )
    }.

%% Only the explicitly compared placements are accepted; geometry must divide them exactly.
-spec options(options(), pos_integer()) ->
    #{
        barrier := flat | tree6,
        vertex_groups := 0 | 6 | 12,
        specialize_state := boolean(),
        admission_reductions := boolean() | exclusive_epoch,
        acknowledgment_collection := boolean(),
        gather_collection := boolean()
    }.
options(Options, Count) ->
    case
        maps:keys(Options) --
            [
                barrier,
                vertex_groups,
                specialize_state,
                admission_reductions,
                acknowledgment_collection,
                gather_collection,
                effect_delivery_width,
                vertex_order
            ]
    of
        [] -> ok;
        Unknown -> error({placement_options, Unknown})
    end,
    Barrier = maps:get(barrier, Options, flat),
    Groups = maps:get(vertex_groups, Options, 0),
    case Barrier of
        flat -> ok;
        tree6 when Count rem 6 =:= 0 -> ok;
        _ -> error({barrier_placement, Barrier, Count})
    end,
    case Groups of
        0 -> ok;
        N when (N =:= 6 orelse N =:= 12), Count rem N =:= 0 -> ok;
        _ -> error({vertex_group_placement, Groups, Count})
    end,
    Order = maps:get(vertex_order, Options, lists:seq(0, Count - 1)),
    case lists:sort(Order) =:= lists:seq(0, Count - 1) of
        true -> ok;
        false -> error({vertex_order, Order, Count})
    end,
    case maps:is_key(vertex_order, Options) andalso Groups =:= 0 of
        true -> error(vertex_order_requires_schedulers);
        false -> ok
    end,
    Gather = maps:get(gather_collection, Options, false),
    true = is_boolean(Gather),
    case Gather andalso Groups =:= 0 of
        true -> error(gather_collection_requires_schedulers);
        false -> ok
    end,
    Acks = maps:get(acknowledgment_collection, Options, false),
    true = is_boolean(Acks),
    case
        Acks andalso
            (Barrier =/= tree6 orelse Groups =:= 0 orelse
                not ?SNOWFLAKE_ACK_REDUCTION orelse not ?SNOWFLAKE_LOCAL_ADVANCE)
    of
        true -> error(acknowledgment_collection_requires_reduced_local_tree);
        false -> ok
    end,
    Specialize = maps:get(specialize_state, Options, false),
    Collection = maps:get(admission_reductions, Options, false),
    true = is_boolean(Collection) orelse Collection =:= exclusive_epoch,
    case Collection =/= false andalso Groups =:= 0 of
        true -> error(admission_reductions_require_schedulers);
        false -> ok
    end,
    true = is_boolean(Specialize),
    case Specialize andalso Groups =:= 0 of
        true -> error(state_specialization_requires_schedulers);
        false -> ok
    end,
    #{
        barrier => Barrier,
        vertex_groups => Groups,
        specialize_state => Specialize,
        admission_reductions => Collection,
        acknowledgment_collection => Acks,
        gather_collection => Gather
    }.

%% Contiguous six-vertex branches preserve source identities at the leaves.
-spec barrier_branches(flat | tree6, pos_integer()) -> [map()].
barrier_branches(flat, _) ->
    [];
barrier_branches(tree6, Count) ->
    [#{source => I, first => 6 * I, count => 6} || I <- lists:seq(0, Count div 6 - 1)].

%% Split an explicit identity permutation independently of barrier membership.
-spec scheduler_groups([non_neg_integer()], 0 | 6 | 12) -> hls_scheduler_plan:spec().
scheduler_groups(_, 0) ->
    #{};
scheduler_groups(Order, Groups) ->
    PerGroup = length(Order) div Groups,
    maps:from_list([
        {{vertex_group, Group}, #{
            state_storage => block_ram,
            mailbox_storage => block_ram,
            members => [
                {actor, {vertex, Source}}
             || Source <- lists:sublist(Order, Group * PerGroup + 1, PerGroup)
            ]
        }}
     || Group <- lists:seq(0, Groups - 1)
    ]).

%% Record actual normalized slot identities rather than asking probes to infer instance order.
-spec group_manifest(hls_scheduler_plan:plan()) -> [map()].
group_manifest(#{groups := Groups}) ->
    [
        #{
            index => Index,
            module => Module,
            mailbox_capacity => Capacity,
            slot_count => Slots,
            members => [
                #{source => Source, slot => Base}
             || #{id := {vertex, Source}, base_slot := Base} <- Members
            ]
        }
     || {Index, #{
            module := Module,
            mailbox_capacity := Capacity,
            slot_count := Slots,
            members := Members
        }} <- lists:enumerate(0, Groups)
    ].

%% Match the existing generic XLS 1R1W adapter channel names exactly.
-spec ram_configurations([map()]) -> iodata().
ram_configurations(Bindings) ->
    lists:join(",", [
        [
            "scheduler_",
            integer_to_list(Index),
            "_",
            Kind,
            ":1R1W:",
            "_scheduler_",
            integer_to_list(Index),
            "_",
            Channel,
            "_read_req_out:",
            "_scheduler_",
            integer_to_list(Index),
            "_",
            Channel,
            "_read_resp_in:",
            "_scheduler_",
            integer_to_list(Index),
            "_",
            Channel,
            "_write_req_out:",
            "_scheduler_",
            integer_to_list(Index),
            "_",
            Channel,
            "_write_resp_in"
        ]
     || B = #{index := Index} <- Bindings,
        {Kind, Channel} <-
            [{"state", "ram"}, {"mailbox", "mailbox"}] ++
                case maps:is_key(gather_members, B) of
                    true -> [{"gather", "gather"}];
                    false -> []
                end
    ]).

%% Generic RAM instances are the only additional RTL; decoder behavior stays in the actors.
-spec write_ram_artifacts(file:filename(), [map()]) -> ok.
write_ram_artifacts(_, []) ->
    ok;
write_ram_artifacts(Directory, Bindings) ->
    ok = file:write_file(
        filename:join(Directory, "snowflake_actor_wrapper.v"), ram_wrapper(Bindings)
    ),
    lists:foreach(
        fun(Source) ->
            {ok, _} = file:copy(Source, filename:join(Directory, filename:basename(Source)))
        end,
        xls_scheduler_ram_v:assets(Bindings)
    ),
    ok.

%% Preserve the public external interface while connecting the generated scheduler RAM ports.
-spec ram_wrapper([map()]) -> iodata().
ram_wrapper(Bindings) ->
    [
        "// Generic storage wiring; all decoder transitions are ordinary compiled actors.\n",
        "module snowflake_actor_wrapper(input wire clk, reset,\n",
        "  input wire [193:0] _inputs_in, input wire _inputs_in_vld, output wire _inputs_in_rdy,\n",
        "  output wire [127:0] _rounds_out, _corrections_out, _unexpected_out,\n",
        "  output wire _rounds_out_vld, _corrections_out_vld, _unexpected_out_vld,\n",
        "  input wire _rounds_out_rdy, _corrections_out_rdy, _unexpected_out_rdy);\n",
        xls_scheduler_ram_v:wires(Bindings),
        "  __snowflake_actor_topology__Top_0_next core(.clk(clk), .reset(reset),\n",
        "    ._inputs_in(_inputs_in), ._inputs_in_vld(_inputs_in_vld), ._inputs_in_rdy(_inputs_in_rdy),\n",
        "    ._rounds_out(_rounds_out), ._rounds_out_vld(_rounds_out_vld), ._rounds_out_rdy(_rounds_out_rdy),\n",
        "    ._corrections_out(_corrections_out), ._corrections_out_vld(_corrections_out_vld), ._corrections_out_rdy(_corrections_out_rdy),\n",
        "    ._unexpected_out(_unexpected_out), ._unexpected_out_vld(_unexpected_out_vld), ._unexpected_out_rdy(_unexpected_out_rdy)",
        xls_scheduler_ram_v:application_ports(Bindings),
        ");\n",
        xls_scheduler_ram_v:instances(Bindings, "clk"),
        "endmodule\n"
    ].
