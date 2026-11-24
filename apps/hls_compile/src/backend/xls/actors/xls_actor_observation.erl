-module(xls_actor_observation).
-moduledoc "Adds optional committed-state sampling to dedicated actor and topology rendering. xls_statem_codegen consumes the proc fragments; topology and debug builders share the channel bindings and layout. Observation reports state and mailbox metadata without owning actor execution or a query transport.".
%% Check observation policy and describe the sampled state.
-export([enabled/1, layout/1, collection/1, validate_channels/1]).
%% Bind topology channels and stable instance names.
-export([bindings/2, bindings/3, wires/1, ports/1, scalar_name/1, family_name/1, spawn_argument/2]).
%% Decorate core materialization with generated topology observation ports.
-export([instance_origins/2]).
%% Fragments consumed by the dedicated actor renderer.
-export([imports/1, declarations/1, proc_field/1, config_parameter/1, config_value/1, sample/1]).

enabled(Options) ->
    case maps:get(direct_actor_debug, Options, false) of
        Flag when is_boolean(Flag) -> Flag;
        Other -> error({direct_actor_debug, Other})
    end.

imports(Options) -> optional(Options, [direct_mailbox_observation]).

%% The observation contains no payload or accumulator bits. Its reduction
%% metadata and mailbox counts follow the common state fields. The query shell
%% places each projection into its protocol field and retains one coherent sample.
-doc "Describes committed actor, mailbox and reduction fields within the fixed query reply budget.".
-spec layout(none | map()) -> map().
layout(none) ->
    #{
        width => 49,
        mailbox => #{offset => 25, width => 24},
        fields => #{
            phase => #{offset => 0, width => 8},
            enter_pending => #{offset => 8, width => 1},
            failure => #{offset => 9, width => 16}
        }
    };
layout(#{kind := collections, sites := Sites}) ->
    SiteBits = integer_width(length(Sites) - 1),
    RemainingBits = integer_width(
        lists:max([maps:get(size, maps:get(population, S)) || S <- Sites])
    ),
    MemberBits = lists:max([
        0 | [maps:get(size, P) || #{population := P = #{mode := members}} <- Sites]
    ]),
    Base = [{status, 2}, {site, SiteBits}, {key, 32}, {remaining, RemainingBits}, {failure, 16}],
    Used = lists:sum([W || {_, W} <- Base]),
    Masks =
        if
            Used + 2 * MemberBits =< 72 -> [{expected, MemberBits}, {seen, MemberBits}];
            Used + MemberBits =< 72 -> [{expected, MemberBits}];
            true -> []
        end,
    {Width, Fields} = lists:foldl(
        fun({Name, Bits}, {Offset, Acc}) ->
            {Offset + Bits, Acc#{
                Name => #{offset => 25 + Offset, width => Bits, observation_offset => 56 + Offset}
            }}
        end,
        {0, #{}},
        Base ++ Masks
    ),
    (layout(none))#{
        width := 49 + Width,
        mailbox := #{offset => 25 + Width, width => 24},
        reduction => #{width => Width, fields => Fields}
    };
layout(Reduction) ->
    Packed = xls_statem_reduction_ir:packed_layout(Reduction),
    {Width, Fields} = lists:foldl(
        fun(Name, {Offset, Acc}) ->
            Bits = maps:get(width, maps:get(Name, Packed)),
            {Offset + Bits, Acc#{
                Name => #{
                    offset => 25 + Offset,
                    width => Bits,
                    observation_offset => 56 + Offset
                }
            }}
        end,
        {0, #{}},
        xls_statem_reduction_ir:observation_fields(Reduction)
    ),
    (layout(none))#{
        width := 49 + Width,
        mailbox := #{offset => 25 + Width, width => 24},
        reduction => #{width => Width, fields => Fields}
    }.

-doc "Builds the one-active-collection observation vocabulary; gather sites follow scalar sites without widening query packets.".
-spec collection(map()) -> none | map().
collection(Spec) ->
    Reduction = maps:get(reductions, Spec, none),
    case maps:get(gathers, Spec, none) of
        none ->
            Reduction;
        #{sites := Gathers} ->
            Scalars =
                case Reduction of
                    none -> [];
                    #{sites := Sites} -> Sites
                end,
            #{
                kind => collections,
                sites => Scalars ++
                    [S#{id := length(Scalars) + maps:get(id, S), kind => gather} || S <- Gathers]
            }
    end.

%% Numeric selectors and remaining counts use the smallest nonzero representation.
-spec integer_width(non_neg_integer()) -> pos_integer().
integer_width(Value) when Value < 2 -> 1;
integer_width(Value) -> 1 + integer_width(Value bsr 1).

%% Names come from the same normalized actor/family ordering as topology
%% emission. XLS lowers a channel array [height][width] to __x_y port suffixes.
-doc "Lists observation ports for actors not assigned to another execution backend.".
-spec bindings(map(), term()) -> [map()].
bindings(Plan, Excluded) ->
    Direct = direct(Plan, Excluded),
    case Direct of
        [] ->
            [];
        _ ->
            Interfaces = hls_actor_interface:from_modules(
                maps:keys(hls_logical_topology:interfaces(Plan))
            ),
            ok = hls_topology:validate_interfaces(Plan, Interfaces),
            observation_bindings(Direct, Interfaces)
    end.

-doc "Lists direct observation ports using the checked interfaces retained by the topology planner; excludes scheduler-owned identities without reloading their modules.".
-spec bindings(hls_topology:plan(), map(), #{module() => hls_actor_interface:summary()}) -> [map()].
bindings(Plan, Excluded, Interfaces) ->
    ok = hls_topology:validate_interfaces(Plan, Interfaces),
    observation_bindings(direct(Plan, Excluded), Interfaces).

-doc "Maps core instances to their established scalar or family-array DSLX observation ports without re-enumerating the logical graph.".
-spec instance_origins(
    hls_logical_topology:compact_plan(), [hls_logical_topology:instance()]
) -> #{hls_logical_identity:id() => map()}.
instance_origins(#{actors := Actors, families := Families}, Instances) ->
    ExactIndices = maps:from_list([
        {Id, Index}
     || {Index, #{id := Id}} <- lists:enumerate(0, Actors)
    ]),
    FamilyIndices = maps:from_list([
        {Id, Index}
     || {Index, #{id := Id}} <- lists:enumerate(0, Families)
    ]),
    maps:from_list([
        {maps:get(id, Actor), instance_origin(Identity, ExactIndices, FamilyIndices)}
     || #{identity := Identity, actor := Actor} <- Instances
    ]).

%% Exact and family observation identities select scalar or coordinate-bearing ports.
-spec instance_origin(hls_actor_identity:id(), map(), map()) -> map().
instance_origin(Identity = {actor, Id}, ExactIndices, _FamilyIndices) ->
    #{logical => Identity, debug => scalar_name(maps:get(Id, ExactIndices))};
instance_origin(Identity = {family, Id, [X, Y]}, _ExactIndices, FamilyIndices) ->
    #{
        logical => Identity,
        debug => [
            family_name(maps:get(Id, FamilyIndices)),
            "[u32:",
            integer_to_list(X),
            "][u32:",
            integer_to_list(Y),
            "]"
        ]
    }.

%% Logical ordering determines stable observation indices and generated port names.
-spec direct(hls_topology:plan(), map()) -> [{term(), module(), iodata()}].
direct(Plan = #{actors := Actors, families := Families}, Excluded) ->
    ExactIndices = maps:from_list([
        {Id, Index}
     || {Index, #{id := Id}} <- lists:enumerate(0, Actors)
    ]),
    FamilyIndices = maps:from_list([
        {Id, Index}
     || {Index, #{id := Id}} <- lists:enumerate(0, Families)
    ]),
    Logical = [
        {Identity, maps:get(module, Actor), observation_port(Identity, ExactIndices, FamilyIndices)}
     || #{identity := Identity, actor := Actor} <- hls_logical_topology:instances(Plan)
    ],
    [Entry || Entry = {Id, _, _} <- Logical, not maps:is_key(Id, Excluded)].

%% Preserve generated scalar and family-array names while core owns instance enumeration.
-spec observation_port(hls_actor_identity:id(), map(), map()) -> iodata().
observation_port({actor, Id}, ExactIndices, _FamilyIndices) ->
    ["_", scalar_name(maps:get(Id, ExactIndices))];
observation_port({family, Id, [X, Y]}, _ExactIndices, FamilyIndices) ->
    [
        "_",
        family_name(maps:get(Id, FamilyIndices)),
        "__",
        integer_to_list(X),
        "_",
        integer_to_list(Y)
    ].

%% Only public observation metadata is derived; no callback payload is exposed.
-spec observation_bindings(
    [{term(), module(), iodata()}],
    #{module() => hls_actor_interface:summary()}
) -> [map()].
observation_bindings(Direct, Interfaces) ->
    [
        begin
            Interface = maps:get(Module, Interfaces),
            #{width := Width} = layout(collection(Interface)),
            #{
                id => Id,
                module => Module,
                index => I,
                port => iolist_to_binary(Port),
                width => Width
            }
        end
     || {I, {Id, Module, Port}} <- lists:enumerate(0, Direct)
    ].

wires(Bindings) ->
    [
        [
            "    wire [",
            integer_to_list(Width - 1),
            ":0] ",
            wire_name(I),
            ";\n",
            "    wire ",
            wire_name(I),
            "_vld;\n"
        ]
     || #{index := I, width := Width} <- Bindings
    ].

ports(Bindings) ->
    [
        [
            ",\n        .",
            Port,
            "(",
            wire_name(I),
            "),\n",
            "        .",
            Port,
            "_vld(",
            wire_name(I),
            "_vld),\n",
            "        .",
            Port,
            "_rdy(1'b1)"
        ]
     || #{index := I, port := Port} <- Bindings
    ].

wire_name(Index) -> ["direct_actor_", integer_to_list(Index), "_debug"].
scalar_name(Index) -> ["actor_", integer_to_list(Index), "_debug_out"].
family_name(Index) -> ["family_", integer_to_list(Index), "_debug_out"].

%% Application boundary names and generated observation names share Top's
%% namespace. Reject collisions before XLS could shadow or reject a channel.
validate_channels(Names) ->
    lists:foldl(
        fun(Name, Seen) ->
            Key = iolist_to_binary(Name),
            case is_map_key(Key, Seen) of
                true -> error({topology_channel_collision, Key});
                false -> Seen#{Key => true}
            end
        end,
        #{},
        Names
    ),
    ok.

-doc "Emits the optional committed-state observation without accumulator payloads.".
-spec declarations(map()) -> iodata().
declarations(Spec) ->
    Collection = collection(Spec),
    #{width := Width} = Layout = layout(Collection),
    Prefix =
        case Layout of
            #{reduction := #{fields := Fields}} ->
                Ordered = lists:sort([
                    {maps:get(offset, Field), Name, maps:get(width, Field)}
                 || {Name, Field} <- maps:to_list(Fields)
                ]),
                [
                    ["    ", progress_value(Name, Bits, Spec), " ++\n"]
                 || {_, Name, Bits} <- lists:reverse(Ordered)
                ];
            _ ->
                []
        end,
    optional(Spec, [
        "pub type ActorObservation = bits[",
        integer_to_list(Width),
        "];\n\n",
        "fn actor_observation(machine: Machine) -> ActorObservation {\n",
        "    direct_mailbox_observation::snapshot(machine.slots, machine.occupied, machine.admission_pending) ++\n",
        Prefix,
        "    machine.failure ++ machine.enter_pending ++ (machine.phase as u8)\n",
        "}\n\n"
    ]).

%% The logical active collection determines metadata; neither branch reads its element payload.
-spec progress_value(atom(), pos_integer(), map()) -> iodata().
progress_value(Name, Width, Spec) ->
    Reduction = maps:get(reductions, Spec, none),
    Gather = maps:get(gathers, Spec, none),
    Type = ["bits[", integer_to_list(Width), "]"],
    Scalar =
        case {Reduction, Name} of
            {none, _} ->
                ["zero!<", Type, ">()"];
            {_, expected} ->
                case xls_statem_reduction_ir:has_runtime_members(Reduction) of
                    false -> ["zero!<", Type, ">()"];
                    true -> ["(machine.reduction.expected as ", Type, ")"]
                end;
            _ ->
                ["(machine.reduction.", atom_to_list(Name), " as ", Type, ")"]
        end,
    case Gather of
        none ->
            Scalar;
        _ ->
            Count =
                case Reduction of
                    none -> 0;
                    #{sites := Sites} -> length(Sites)
                end,
            Value = ["(machine.gather.progress.", atom_to_list(Name), " as ", Type, ")"],
            Indexed =
                case {Name, Count} of
                    {site, N} when N > 0 -> ["(", Value, " + ", Type, ":", integer_to_list(N), ")"];
                    _ -> Value
                end,
            case Reduction of
                none ->
                    Indexed;
                _ ->
                    [
                        "(if machine.gather.progress.status != GatherStatus::IDLE { ",
                        Indexed,
                        " } else { ",
                        Scalar,
                        " })"
                    ]
            end
    end.

proc_field(Options) ->
    optional(
        Options,
        "  actor_debug_out: chan<ActorObservation> out;\n"
    ).
config_parameter(Options) ->
    optional(
        Options,
        ",\n         actor_debug_out: chan<ActorObservation> out"
    ).
config_value(Options) -> optional(Options, ", actor_debug_out").
spawn_argument(Options, Channel) -> optional(Options, [", ", Channel]).

sample(Options) -> optional(Options, """

        // Publish the committed state entering this step, before any current
        // receive or egress can stall. The shell always accepts and retains this
        // diagnostic output independently of host query backpressure.
        let _observation = send(join(), actor_debug_out, actor_observation(machine));

    """).

optional(Options, Value) ->
    case enabled(Options) of
        true -> Value;
        false -> []
    end.
