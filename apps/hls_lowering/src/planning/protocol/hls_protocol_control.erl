-module(hls_protocol_control).
-moduledoc "Derives source-protocol control domains, placed recipients and hardware support descriptors during transport preparation. Framed builders reuse these checked facts; the current adapter is rectangle control, and its declared sources and widths are target-specific. No fixture traffic supplies wire domains.".

%% Control-domain planning and recipient views.
-export([plan/1, addressed/2, project/2, host_ingresses/2]).

%% Framed adapter selection and boundary checks.
-export([ports/1, framed/2, check_boundary/2]).
-export_type([plan/0, target/0, hardware/0]).

-doc "One checked rectangle target with canonical receiver domains and globally indexed coordinates. Placement can leave its recipient list empty.".
-type target() :: #{
    id := hls_logical_topology:id(),
    selector := non_neg_integer(),
    schemas := [atom()],
    domains := [
        #{
            mask := non_neg_integer(),
            value := non_neg_integer(),
            tag := atom(),
            schema_sha256 := binary()
        }
    ],
    recipients := [#{index := non_neg_integer(), x := non_neg_integer(), y := non_neg_integer()}]
}.

-doc "A checked rectangle control plan; the actor mask retains whole-topology indices across native placement.".
-type plan() :: #{
    kind := rectangle,
    id := hls_logical_topology:id(),
    width := pos_integer(),
    height := pos_integer(),
    actors := pos_integer(),
    targets := [target()],
    frame_layout := hls_frame_layout:layout(),
    input_bits := pos_integer(),
    state_bits := pos_integer(),
    host_order := one_command_until_all_selected_actors_consume,
    admission := after_declared_startup_consumption,
    malformed := sticky_fault_without_delivery,
    retirement := source_consume,
    reset := cancels_command_and_fault,
    capacity := unestablished,
    network_progress := unestablished
}.

-doc "The owned rectangle adapter's wire widths, source files and implementation dependencies.".
-type hardware() :: #{
    kind := rectangle,
    frame_layout := hls_frame_layout:layout(),
    input_bits := pos_integer(),
    command_bits := pos_integer(),
    bridge_decoder := binary(),
    bridge_libraries := [binary()],
    gateway_source := binary(),
    activation_module := binary(),
    rtl := [dependency()],
    dependencies := [dependency()]
}.

%% Routing queries need only recipient indices and preserve every other control field.
-type recipient_view() :: #{
    targets := [
        #{
            recipients := [#{index := non_neg_integer(), atom() => term()}],
            atom() => term()
        }
    ],
    atom() => term()
}.

%% Paths are project-relative and resolved in the named owner's installed support tree.
-type dependency() :: #{owner := fabric | compiler, file := binary()}.

-doc "Plans zero or one rectangle ingress with one to four targets, each with nonempty explicit schemas and recipients. Every recipient of a target must have identical canonical encodings and ordered field names/types. Coordinates are inclusive within dimensions 1..65536. Rejects ambiguous recipients, incompatible encodings and unsupported shapes. Delivery uses the selected ordinary frame layout inside SpatialFrame, one registered command, and independent per-actor consumption. One postponed head can block later host commands; this establishes neither capacity nor progress.".
-spec plan(#{
    topology := #{
        actors := [
            #{
                id := hls_logical_topology:id(),
                module := module(),
                atom() => term()
            }
        ],
        ingresses := [hls_logical_topology:ingress()],
        atom() => term()
    },
    modules := #{module() => hls_local_actor:source() | hls_local_actor:artifact()},
    frame_layout := hls_frame_layout:layout(),
    atom() => term()
}) -> none | plan().
plan(#{topology := #{ingresses := []}}) ->
    none;
plan(#{
    frame_layout := Layout,
    topology := #{
        actors := Actors,
        ingresses := [#{id := Id, kind := rectangle, shape := [W, H], targets := Targets}]
    },
    modules := Modules
}) when
    W > 0, W =< 65536, H > 0, H =< 65536, length(Targets) > 0, length(Targets) =< 4
->
    Bound = [
        hls_diagnostic:with_context(
            #{ingress => Id, target => maps:get(id, T, unknown)},
            fun() -> target(T, K, Actors, Modules, W, H) end
        )
     || {K, T} <- lists:enumerate(0, Targets)
    ],
    #{input_bits := Bits} = rectangle_hardware(Layout),
    #{
        kind => rectangle,
        frame_layout => Layout,
        id => Id,
        width => W,
        height => H,
        actors => length(Actors),
        targets => Bound,
        input_bits => Bits,
        state_bits => hls_frame_layout:frame_bits(Layout) + 1 + length(Actors),
        host_order => one_command_until_all_selected_actors_consume,
        admission => after_declared_startup_consumption,
        malformed => sticky_fault_without_delivery,
        retirement => source_consume,
        reset => cancels_command_and_fault,
        capacity => unestablished,
        network_progress => unestablished
    };
plan(#{topology := #{ingresses := Ingresses}}) ->
    hls_diagnostic:raise(
        control,
        unsupported_protocol_ingress,
        <<"Use at most one rectangle ingress, with dimensions 1..65536 and one to four targets.">>,
        #{ingresses => Ingresses}
    ).

-doc "Reports whether the checked plan addresses an actor index. Addressed receivers need exactly one host slot, shared by all targets because at most one host command is outstanding.".
-spec addressed(none | recipient_view(), non_neg_integer()) -> boolean().
addressed(none, _) ->
    false;
addressed(#{targets := Targets}, Index) ->
    lists:any(
        fun(#{recipients := Rs}) -> lists:any(fun(#{index := I}) -> I =:= Index end, Rs) end,
        Targets
    ).

-doc "Restricts a checked control plan to native actor indices without renumbering its full-topology mask. A target may have no recipients on this role; none remains none. Use the whole plan, not this projection, for host binding.".
-spec project(Control, [non_neg_integer()]) -> Control when Control :: none | recipient_view().
project(none, _) ->
    none;
project(Control = #{targets := Targets}, Native) ->
    Control#{
        targets := [
            T#{recipients := [R || R = #{index := I} <- Rs, lists:member(I, Native)]}
         || T = #{recipients := Rs} <- Targets
        ]
    }.

-doc "Derives the shared partition host codec's rectangle binding from the checked whole control plan and indexed, placed actors. Preserves each target's schemas and coordinates, including different points for one actor across targets, without lowering the source topology again. Call after validating loaded codecs against the same source build; this adapter does not revalidate them. Empty control yields no ingresses.".
-spec host_ingresses(none | plan(), [#{index := non_neg_integer(), atom() => term()}]) -> [map()].
host_ingresses(none, _) ->
    [];
host_ingresses(
    #{
        kind := rectangle,
        frame_layout := Layout,
        id := Id,
        width := W,
        height := H,
        targets := Targets
    },
    Actors
) ->
    ByIndex = maps:from_list([{I, A} || A = #{index := I} <- Actors]),
    Bindings = [
        (maps:get(I, ByIndex))#{point => [X, Y], targets => [Target]}
     || #{id := Target, recipients := Recipients} <- Targets,
        #{index := I, x := X, y := Y} <- Recipients
    ],
    [
        #{
            id => Id,
            frame_layout => Layout,
            shape => [W, H],
            targets => [maps:with([id, selector, schemas], T) || T <- Targets],
            bindings => Bindings
        }
    ].

%% Different targets may reuse recipients; a target may not deliver duplicate copies.
-spec target(
    #{
        id := hls_logical_topology:id(),
        schemas := [atom()],
        recipients := [#{actor := hls_logical_topology:id(), at := [non_neg_integer()]}],
        atom() => term()
    },
    non_neg_integer(),
    [#{id := hls_logical_topology:id(), module := module(), atom() => term()}],
    #{module() => hls_local_actor:source() | hls_local_actor:artifact()},
    pos_integer(),
    pos_integer()
) -> target().
target(#{id := Id, schemas := Schemas, recipients := Recipients}, Selector, Actors, Modules, W, H) ->
    case Recipients of
        [] ->
            hls_diagnostic:raise(
                control,
                empty_ingress_target,
                <<"An ingress target must address at least one actor.">>,
                #{target => Id}
            );
        _ ->
            ok
    end,
    Points = [
        begin
            case X >= 0 andalso X < W andalso Y >= 0 andalso Y < H of
                true ->
                    ok;
                false ->
                    hls_diagnostic:raise(
                        control,
                        ingress_coordinate,
                        <<"Ingress coordinates must lie within the declared rectangle.">>,
                        #{target => Id, actor => Actor, coordinate => [X, Y], shape => [W, H]}
                    )
            end,
            [{I, #{module := M}}] = [
                {J, A}
             || {J, A = #{id := Identity}} <- lists:enumerate(0, Actors), Identity =:= Actor
            ],
            Domains = hls_diagnostic:with_context(
                #{actor => Actor, module => M},
                fun() -> hls_protocol_schema:domains(maps:get(M, Modules), Schemas) end
            ),
            #{index => I, x => X, y => Y, schemas => lists:sort(Domains)}
        end
     || #{actor := Actor, at := [X, Y]} <- Recipients
    ],
    case
        length(Points) =:= length(Recipients) andalso
            length(Points) =:= length(lists:usort([I || #{index := I} <- Points]))
    of
        true ->
            ok;
        false ->
            hls_diagnostic:raise(
                control,
                ambiguous_ingress_recipients,
                <<"Each ingress target must name every recipient once with an explicit coordinate.">>,
                #{target => Id, recipients => Recipients}
            )
    end,
    case lists:usort([Fs || #{schemas := Fs} <- Points]) of
        [Domains] ->
            #{
                id => Id,
                selector => Selector,
                schemas => Schemas,
                domains => Domains,
                recipients => [maps:remove(schemas, P) || P <- Points]
            };
        _ ->
            hls_diagnostic:raise(
                control,
                incompatible_ingress_schemas,
                <<"Recipients of an ingress target must share the same canonical schema encodings.">>,
                #{target => Id, schemas => Schemas, recipients => Recipients}
            )
    end;
target(Target, _, _, _, _, _) ->
    hls_diagnostic:raise(
        control,
        invalid_ingress_target,
        <<"An ingress target needs an ID, explicit schemas and recipients with coordinates.">>,
        #{value => Target}
    ).

-doc "Returns the sampled native control input/output ports for a checked plan, in packed interface order. No control contributes no ports. The input width belongs to the adapter, independently of crossing and external frame widths.".
-spec ports(none | #{kind := rectangle, input_bits := pos_integer(), atom() => term()}) ->
    {[{string(), pos_integer()}], [{string(), pos_integer()}]}.
ports(none) ->
    {[], []};
ports(#{kind := rectangle, input_bits := Bits}) ->
    {[{"ingress_valid", 1}, {"ingress_data", Bits}], [{"ingress_ready", 1}, {"ingress_fault", 1}]}.

-doc "Checks framed control capability and returns its concrete hardware support. Requires a rectangle plan and explicit_start; omitted control/activation select those existing defaults. Rejects mismatched selections and absent control. The returned DSLX source, module names, widths and project-relative support paths bind the gateway, bridge decoder and activation wiring together; the external rectangle envelope retains its 96-bit payload capacity and rejects wider native layouts.".
-spec framed(
    none | #{kind := rectangle, input_bits := pos_integer(), atom() => term()},
    #{control => atom(), activation => atom(), atom() => term()}
) -> hardware().
framed(Control = #{kind := rectangle, input_bits := Bits}, Options) ->
    Layout = maps:get(frame_layout, Control, hls_frame_layout:default()),
    case hls_frame_layout:payload_bits(Layout) =< 96 of
        true ->
            ok;
        false ->
            hls_diagnostic:raise(
                control,
                framed_payload_capacity,
                <<"The framed rectangle envelope supports at most 96 payload bits.">>,
                #{payload_bits => hls_frame_layout:payload_bits(Layout), maximum => 96}
            )
    end,
    Hardware = #{input_bits := Bits} = rectangle_hardware(Layout),
    case {maps:get(control, Options, rectangle), maps:get(activation, Options, explicit_start)} of
        {rectangle, explicit_start} ->
            Hardware;
        {Kind, Mode} ->
            hls_diagnostic:raise(
                control,
                unsupported_framed_control,
                <<"Framed control requires the rectangle adapter and explicit_start activation.">>,
                #{control => Kind, activation => Mode}
            )
    end;
framed(Control, _) ->
    hls_diagnostic:raise(
        control,
        unsupported_framed_control,
        <<"Framed builds require a source-declared rectangle ingress.">>,
        #{control => Control}
    ).

-doc "Checks that a planned or emitted explicit-start boundary provides the adapter's exact native control handshake. Call before rendering the boundary or its framed parent; mismatches fail rather than producing incompatible pin wiring.".
-spec check_boundary(hardware(), #{
    activation := explicit_start,
    inputs := [#{name := binary(), width := pos_integer()}],
    outputs := [#{name := binary(), width := pos_integer()}],
    atom() => term()
}) -> ok.
check_boundary(#{input_bits := Bits}, #{
    activation := explicit_start, inputs := Inputs, outputs := Outputs
}) ->
    ExpectedInputs = [
        #{name => <<"ingress_valid">>, width => 1},
        #{name => <<"ingress_data">>, width => Bits},
        #{name => <<"start_valid">>, width => 1}
    ],
    ExpectedOutputs = [
        #{name => <<"ingress_ready">>, width => 1},
        #{name => <<"ingress_fault">>, width => 1},
        #{name => <<"start_ready">>, width => 1}
    ],
    case
        lists:all(fun(P) -> lists:member(P, Inputs) end, ExpectedInputs) andalso
            lists:all(fun(P) -> lists:member(P, Outputs) end, ExpectedOutputs)
    of
        true -> ok;
        false -> error(control_boundary_mismatch)
    end.

%% The ordered rectangle gateway adds one start discriminator to SpatialFrame.
%% External drivers resolve these owned support files, never choose the adapter.
-spec rectangle_hardware(hls_frame_layout:layout()) -> hardware().
rectangle_hardware(Layout) ->
    Bits = hls_frame_layout:frame_bits(Layout) + 66,
    #{
        kind => rectangle,
        frame_layout => Layout,
        input_bits => Bits,
        command_bits => Bits + 1,
        bridge_decoder => <<"protocol_rectangle">>,
        bridge_libraries => [<<"protocol_rectangle.x">>],
        gateway_source => <<"xls/templates/protocol_application.x">>,
        activation_module => <<"hls_partition_activation">>,
        rtl => [#{owner => fabric, file => <<"priv/rtl/hls_partition_activation.sv">>}],
        dependencies => [
            #{owner => fabric, file => F}
         || F <- [
                <<"priv/xls/hls_partition_io.x">>,
                <<"priv/xls/lib/protocol_framing.x">>,
                <<"priv/xls/lib/protocol_rectangle.x">>,
                <<"priv/xls/lib/protocol_envelope.x">>
            ]
        ] ++
            [
                #{owner => compiler, file => F}
             || F <- [<<"priv/xls/lib/axis.x">>, <<"priv/xls/fabric/hls_spatial_router.x">>]
            ]
    }.
