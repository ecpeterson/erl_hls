-module(hls_deployment_artifact).
-moduledoc """
Versioned runtime deployment descriptors shared by target emission and deployed execution.

The artifact retains only static execution bindings. Brokers, PIDs, sessions, reset ownership and
device admission remain caller-supplied runtime facts. Its digest identifies canonical bytes; it
does not authenticate the producer or qualify the attached implementation. Every constructor and
decoder accepts trusted build input only: codec validation may load and invoke installed provider
modules. decode/1 never interns atoms; load/1 may intern retained application atoms.
""".

%% Construction and validation of trusted target output.
-export([new/2, validate/1]).
%% Canonical local-file serialization and identity.
-export([encode/1, decode/1, load/1, identity/1]).
%% Checked runtime views.
-export([kind/1, descriptor/2]).
-export_type([artifact/0, kind/0]).

-define(MAX_BYTES, 64 * 1024 * 1024).

-doc "The runtime owner selected by one emitted target composition.".
-type kind() :: partition_application | protocol_deployment | mixed_application.

-doc "A canonical static execution descriptor returned by new/2, decode/1 or load/1.".
-opaque artifact() :: #{
    format := hls_deployment,
    version := 1,
    kind := kind(),
    descriptor := map()
}.

-doc "Projects a trusted emitted target descriptor to its runtime fields and validates it. Invalid input raises `{deployment_artifact, Reason}`.".
-spec new(kind(), map()) -> artifact().
new(Kind, Candidate) ->
    try
        Artifact = #{
            format => hls_deployment,
            version => 1,
            kind => Kind,
            descriptor => project(Kind, Candidate)
        },
        ok = check(Artifact),
        Artifact
    catch
        error:{deployment_artifact, _} = Error -> error(Error);
        error:Reason -> error({deployment_artifact, {invalid_descriptor, Reason}})
    end.

-doc "Checks the exact envelope and kind-specific execution contract without acquiring a session, route or process.".
-spec validate(term()) -> ok | {error, term()}.
validate(Artifact) ->
    try check(Artifact) of
        ok -> ok
    catch
        error:Reason -> {error, Reason}
    end.

-doc "Encodes one valid artifact as canonical deterministic ETF. Invalid artifacts raise `{deployment_artifact, Reason}`.".
-spec encode(artifact()) -> binary().
encode(Artifact) ->
    case validate(Artifact) of
        ok -> term_to_binary(Artifact, [deterministic]);
        {error, Reason} -> error({deployment_artifact, Reason})
    end.

-doc "Decodes trusted canonical ETF with existing atoms up to 64 MiB and revalidates every retained runtime field. Codec validation may load and invoke installed provider modules, so safe ETF does not make untrusted input acceptable. Returns an error for compressed, trailing, noncanonical or unsupported data.".
-spec decode(binary()) -> {ok, artifact()} | {error, term()}.
decode(Bytes = <<131, 80, _/binary>>) when byte_size(Bytes) =< ?MAX_BYTES ->
    {error, noncanonical_encoding};
decode(Bytes) when is_binary(Bytes), byte_size(Bytes) =< ?MAX_BYTES ->
    decode_bytes(Bytes, [safe, used]);
decode(Bytes) when is_binary(Bytes) ->
    {error, artifact_too_large};
decode(_) ->
    {error, invalid_encoding}.

%% Both trust modes require exact canonical ETF and the complete static execution contract.
-spec decode_bytes(binary(), [term()]) -> {ok, artifact()} | {error, term()}.
decode_bytes(<<131, 80, _/binary>>, _) ->
    {error, noncanonical_encoding};
decode_bytes(Bytes, Options) ->
    try binary_to_term(Bytes, Options) of
        {Artifact, Used} when Used =:= byte_size(Bytes) ->
            case validate(Artifact) of
                ok ->
                    case term_to_binary(Artifact, [deterministic]) of
                        Bytes -> {ok, Artifact};
                        _ -> {error, noncanonical_encoding}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end;
        {_Artifact, _Used} ->
            {error, trailing_data}
    catch
        error:badarg -> {error, invalid_encoding}
    end.

-doc "Reads one trusted local build artifact through a 64 MiB bounded reader, interns its ETF atoms, then applies canonical and static validation. Codec validation may load and invoke retained providers. Never pass an uploaded, network-provided or user-selected untrusted path: identity/1 is not authentication. Filesystem errors return as `{error, {file, Reason}}`.".
-spec load(file:filename_all()) -> {ok, artifact()} | {error, term()}.
load(Path) ->
    case read_bounded(Path) of
        {ok, Bytes} -> decode_bytes(Bytes, [used]);
        Error -> Error
    end.

%% Chunked reads cap allocation even if a trusted file changes while it is being read.
-spec read_bounded(file:filename_all()) -> {ok, binary()} | {error, term()}.
read_bounded(Path) ->
    case file:open(Path, [read, binary, raw]) of
        {ok, File} ->
            try
                read_bounded(File, [], 0)
            after
                ok = file:close(File)
            end;
        {error, Reason} ->
            {error, {file, Reason}}
    end.

%% Read one bounded chunk at a time and reject before accumulating beyond the limit.
-spec read_bounded(file:io_device(), [binary()], non_neg_integer()) ->
    {ok, binary()} | {error, term()}.
read_bounded(File, Parts, Size) ->
    Remaining = ?MAX_BYTES - Size,
    case file:read(File, min(1024 * 1024, Remaining + 1)) of
        eof ->
            {ok, iolist_to_binary(lists:reverse(Parts))};
        {ok, Bytes} when byte_size(Bytes) =< Remaining ->
            read_bounded(File, [Bytes | Parts], Size + byte_size(Bytes));
        {ok, _} ->
            {error, artifact_too_large};
        {error, Reason} ->
            {error, {file, Reason}}
    end.

-doc "Returns a lowercase SHA-256 identity of the artifact's canonical bytes.".
-spec identity(artifact()) -> binary().
identity(Artifact) ->
    binary:encode_hex(crypto:hash(sha256, encode(Artifact)), lowercase).

-doc "Returns the validated artifact kind.".
-spec kind(artifact()) -> kind().
kind(Artifact = #{kind := Kind}) ->
    ok = valid(Artifact),
    Kind.

-doc "Returns the validated descriptor for the required kind; a different kind raises `{deployment_kind, Expected, Actual}`.".
-spec descriptor(kind(), artifact()) -> map().
descriptor(Expected, Artifact = #{kind := Actual, descriptor := Descriptor}) ->
    ok = valid(Artifact),
    case Actual of
        Expected -> Descriptor;
        _ -> error({deployment_kind, Expected, Actual})
    end.

%% Normalize only the three public stream descriptors; build reports remain outside the artifact.
-spec project(kind(), map()) -> map().
project(partition_application, #{partition := Partition, devices := Devices}) ->
    #{
        partition => project_partition(Partition),
        devices => maps:map(fun(_, Binding) -> project_binding(Binding, identity) end, Devices)
    };
project(
    protocol_deployment,
    Candidate = #{
        devices := Devices, actors := Actors, limits := Limits
    }
) ->
    Application =
        case maps:find(application, Candidate) of
            {ok, Value} -> project_application(Value);
            error -> none
        end,
    #{
        devices => maps:map(fun(_, Device) -> project_protocol_device(Device) end, Devices),
        actors => Actors,
        limits => maps:with([commands, events, crossings], Limits),
        application => Application
    };
project(mixed_application, #{
    actors := Actors,
    targets := Targets,
    mixed := Mixed,
    application := Application,
    binding := Binding,
    bridge := #{externals := Externals}
}) ->
    #{
        actors => maps:map(fun(_, Actor) -> project_host_actor(Actor) end, Actors),
        targets => Targets,
        mixed => project_mixed(Mixed, length(Externals)),
        application => project_application(Application),
        binding => maps:with([host, control], Binding)
    };
project(Kind, _) ->
    error({unsupported_kind, Kind}).

%% Retain only geometry and codecs interpreted by partition/runtime command selection.
-spec project_partition(map()) -> map().
project_partition(Partition = #{ingresses := Ingresses}) ->
    #{
        frame_layout => maps:get(frame_layout, Partition, hls_frame_layout:default()),
        ingresses => [project_ingress(Ingress) || Ingress <- Ingresses]
    }.

%% Ingress order remains the source-declared selection order.
-spec project_ingress(map()) -> map().
project_ingress(#{id := Id, shape := Shape, targets := Targets, bindings := Bindings}) ->
    #{
        id => Id,
        shape => Shape,
        targets => [maps:with([id, selector, schemas], Target) || Target <- Targets],
        bindings => [maps:with([index, device, point, targets, schemas], B) || B <- Bindings]
    }.

%% Device bindings omit target adapters while retaining attachment identity when required.
-spec project_binding(map(), identity | no_identity) -> map().
project_binding(Binding, identity) ->
    (project_binding(Binding, no_identity))#{identity => maps:get(identity, Binding)};
project_binding(Binding, no_identity) ->
    Base = #{
        host => maps:get(host, Binding),
        control => maps:get(control, Binding),
        ingress => maps:get(ingress, Binding),
        events => maps:get(events, Binding),
        frame_layout => maps:get(frame_layout, Binding, hls_frame_layout:default()),
        activation => maps:get(activation, Binding, automatic)
    },
    Base#{
        events := maps:map(
            fun(_, Event) -> maps:with([id, port, schemas], Event) end,
            maps:get(events, Base)
        )
    }.

%% Application bindings use the same compact runtime partition view on every stream kind.
-spec project_application(map()) -> map().
project_application(#{partition := Partition, devices := Devices}) ->
    #{
        partition => project_partition(Partition),
        devices => maps:map(fun(_, Binding) -> project_binding(Binding, no_identity) end, Devices)
    }.

%% Protocol relays need role endpoints, attachment identity, ownership and compact crossing codecs.
-spec project_protocol_device(map()) -> map().
project_protocol_device(#{
    host := Host,
    service := Service,
    identity := Identity,
    native_indices := Native,
    externals := Externals,
    links := Links
}) ->
    #{
        host => Host,
        service => Service,
        identity => Identity,
        native_indices => Native,
        external_count => length(Externals),
        links => [project_protocol_link(Link) || Link <- Links]
    }.

%% Relay routing ignores physical capture annotations on a crossing.
-spec project_protocol_link(map()) -> map().
project_protocol_link(#{
    index := Index,
    direction := Direction,
    source_index := Source,
    destination_index := Destination,
    classes := Classes
}) ->
    #{
        index => Index,
        direction => Direction,
        source_index => Source,
        destination_index => Destination,
        classes => [maps:with([slot, codec], Class) || Class <- Classes]
    }.

%% Mixed host actors retain only admission, connection, startup and record-codec facts.
-spec project_host_actor(map()) -> map().
project_host_actor(#{
    module := Module,
    capacity := Capacity,
    outputs := Outputs,
    startup := Startup,
    schemas := Schemas,
    output_schemas := OutputSchemas
}) ->
    #{
        module => Module,
        capacity => Capacity,
        outputs => Outputs,
        startup => Startup,
        schemas => Schemas,
        output_schemas => OutputSchemas
    }.

%% Mixed attachment keeps its native identity, external bound and crossing record codecs.
-spec project_mixed(map(), non_neg_integer()) -> map().
project_mixed(#{host_actors := Host, links := Links, identity := Identity}, ExternalCount) ->
    #{
        host_actors => Host,
        links => [project_mixed_link(Link) || Link <- Links],
        identity => Identity,
        external_count => ExternalCount
    }.

%% Mixed queues ignore physical capture annotations but need both provider descriptors.
-spec project_mixed_link(map()) -> map().
project_mixed_link(#{
    index := Index,
    source_index := Source,
    destination_index := Destination,
    direction := Direction,
    classes := Classes
}) ->
    #{
        index => Index,
        source_index => Source,
        destination_index => Destination,
        direction => Direction,
        classes => [
            maps:with(
                [slot, codec, port, tag, message_bits, source_record, destination_record], Class
            )
         || Class <- Classes
        ]
    }.

%% Reject process-local capabilities even where caller-defined identifiers remain otherwise opaque.
-spec check(term()) -> ok.
check(Artifact) ->
    check_static_term(Artifact),
    check_envelope(Artifact).

%% Exact envelopes prevent a build report or arbitrary ETF map from masquerading as a deployment.
-spec check_envelope(term()) -> ok.
check_envelope(
    #{
        format := hls_deployment, version := 1, kind := Kind, descriptor := Descriptor
    } = Artifact
) when map_size(Artifact) =:= 4 ->
    check_descriptor(Kind, Descriptor);
check_envelope(_) ->
    error(invalid_shape).

%% ETF can encode process capabilities; deployment files may contain only static values.
-spec check_static_term(term()) -> ok.
check_static_term(Term) when is_pid(Term) -> error({ephemeral_term, pid});
check_static_term(Term) when is_port(Term) -> error({ephemeral_term, port});
check_static_term(Term) when is_reference(Term) -> error({ephemeral_term, reference});
check_static_term(Term) when is_function(Term) -> error({ephemeral_term, function});
check_static_term(Term) when is_map(Term) ->
    maps:foreach(
        fun(Key, Value) ->
            check_static_term(Key),
            check_static_term(Value)
        end,
        Term
    );
check_static_term(Term) when is_tuple(Term) ->
    lists:foreach(fun check_static_term/1, tuple_to_list(Term));
check_static_term([Head | Tail]) ->
    check_static_term(Head),
    check_static_term(Tail);
check_static_term(_) ->
    ok.

%% Each kind has one exact top-level descriptor and delegates retained codec checks to runtime owners.
-spec check_descriptor(term(), term()) -> ok.
check_descriptor(partition_application, Descriptor) ->
    check_application(Descriptor, identity);
check_descriptor(
    protocol_deployment,
    Descriptor = #{
        devices := Devices,
        actors := Actors,
        limits := Limits,
        application := Application
    }
) when map_size(Descriptor) =:= 4, is_map(Devices), map_size(Devices) > 0 ->
    check_limits(Limits),
    true = is_integer(Actors) andalso Actors > 0,
    maps:foreach(fun check_protocol_device/2, Devices),
    check_unique([
        {Service, Host}
     || #{host := Host, service := Service} <- maps:values(Devices)
    ]),
    _ = hls_protocol_routing:plan(Descriptor),
    check_protocol_application(Application, Devices),
    ok;
check_descriptor(
    mixed_application,
    Descriptor = #{
        actors := Actors,
        targets := Targets,
        mixed := Mixed,
        application := Application,
        binding := Binding
    }
) when map_size(Descriptor) =:= 5, is_map(Actors), map_size(Actors) > 0, is_map(Targets) ->
    check_targets(Targets),
    maps:foreach(fun(Index, Actor) -> check_host_actor(Index, Actor, Targets) end, Actors),
    ExternalCount = check_mixed(Mixed, Actors, Targets),
    check_application(Application, no_identity),
    check_mixed_application(Application, ExternalCount, Targets, Actors),
    check_endpoints(Binding),
    ok = hls_protocol_mixed_codec:check(Descriptor),
    ok;
check_descriptor(Kind, _) when
    Kind =:= partition_application;
    Kind =:= protocol_deployment;
    Kind =:= mixed_application
->
    error(invalid_descriptor_shape);
check_descriptor(Kind, _) ->
    error({unsupported_kind, Kind}).

%% Raw protocol streams omit typed application codecs; application streams require the checked view.
-spec check_protocol_application(none | map(), map()) -> ok.
check_protocol_application(none, _Devices) ->
    ok;
check_protocol_application(Application, Devices) ->
    check_application(Application, no_identity),
    true =
        lists:sort(maps:keys(Devices)) =:=
            lists:sort(maps:keys(maps:get(devices, Application))),
    maps:foreach(
        fun(Role, #{host := Host, external_count := ExternalCount}) ->
            #{host := Host, events := Events} =
                maps:get(Role, maps:get(devices, Application)),
            check_external_ports(Events, ExternalCount)
        end,
        Devices
    ).

%% A mixed native partition has one fixed board binding matching its physical external indices.
-spec check_mixed_application(map(), non_neg_integer(), map(), map()) -> ok.
check_mixed_application(
    #{devices := #{board := #{events := Events}} = Devices}, ExternalCount, Targets, Actors
) when
    map_size(Devices) =:= 1
->
    check_external_ports(Events, ExternalCount),
    EventIds = [Id || #{id := Id} <- maps:values(Events)],
    ExternalIds = [Id || {_, {external, Id}} <- maps:to_list(Targets)],
    true = lists:all(
        fun(Id) -> length([ok || EventId <- EventIds, EventId =:= Id]) =:= 1 end, ExternalIds
    ),
    maps:foreach(
        fun(_, #{outputs := Outputs, output_schemas := OutputSchemas, schemas := Schemas}) ->
            maps:foreach(
                fun(Port, Target) ->
                    case maps:get(Target, Targets) of
                        {actor, _} ->
                            ok;
                        {external, Id} ->
                            [#{schemas := EventSchemas}] = [
                                Event
                             || Event = #{id := EventId} <- maps:values(Events), EventId =:= Id
                            ],
                            lists:foreach(
                                fun(Tag) ->
                                    ActorSchema = #{selector := Selector} = maps:get(Tag, Schemas),
                                    ActorSchema = maps:get(Selector, EventSchemas)
                                end,
                                maps:get(Port, OutputSchemas)
                            )
                    end
                end,
                Outputs
            )
        end,
        Actors
    ),
    ok;
check_mixed_application(_, _, _, _) ->
    error(invalid_mixed_application).

%% Every physical external index has exactly one canonical application event port.
-spec check_external_ports(map(), non_neg_integer()) -> ok.
check_external_ports(Events, ExternalCount) ->
    Expected = ["external_" ++ integer_to_list(Index) || Index <- lists:seq(0, ExternalCount - 1)],
    Ports = [Port || #{port := Port} <- maps:values(Events)],
    true = lists:sort(Ports) =:= lists:sort(Expected),
    ok.

%% A partition application is exactly one compact partition and its device bindings.
-spec check_application(term(), identity | no_identity) -> ok.
check_application(Descriptor = #{partition := Partition, devices := Devices}, IdentityMode) when
    map_size(Descriptor) =:= 2, is_map(Devices), map_size(Devices) > 0
->
    {Layout, IngressDevices} = check_partition(Partition, maps:keys(Devices)),
    case IdentityMode of
        identity -> ok;
        no_identity -> true = hls_frame_layout:payload_words(Layout) =< 3
    end,
    maps:foreach(
        fun(Device, Binding) ->
            check_binding(Device, Binding, IdentityMode, Layout, IngressDevices)
        end,
        Devices
    ),
    OwnedRoutes = lists:append([
        [{{Endpoint, Host}, Device} || Endpoint <- [Control | maps:keys(Events)]]
     || {Device, #{host := Host, control := Control, events := Events}} <- maps:to_list(Devices)
    ]),
    check_route_owners(OwnedRoutes),
    ok = hls_partition_wire:check(Descriptor),
    ok;
check_application(_, _) ->
    error(invalid_application_shape).

%% The compact partition contains only the frame capacity and ordered ingress catalog.
-spec check_partition(term(), [term()]) -> {hls_frame_layout:layout(), #{term() => [term()]}}.
check_partition(#{frame_layout := Layout, ingresses := Ingresses} = Partition, Devices) when
    map_size(Partition) =:= 2, is_list(Ingresses), Ingresses =/= []
->
    CheckedLayout = check_layout(Layout),
    Checked = [check_ingress(Ingress, Devices, CheckedLayout) || Ingress <- Ingresses],
    Ids = [Id || {Id, _} <- Checked],
    true = length(Ids) =:= length(lists:usort(Ids)),
    {CheckedLayout, maps:from_list(Checked)};
check_partition(_, _) ->
    error(invalid_partition_shape).

%% Every retained ingress has canonical selectors and device-owned recipients.
-spec check_ingress(term(), [term()], hls_frame_layout:layout()) -> {term(), [term()]}.
check_ingress(
    #{id := Id, shape := Shape = [Width, Height], targets := Targets, bindings := Bindings} =
        Ingress,
    Devices,
    Layout
) when
    map_size(Ingress) =:= 4,
    is_integer(Width),
    Width > 0,
    Width =< (1 bsl 16),
    is_integer(Height),
    Height > 0,
    Height =< (1 bsl 16),
    is_list(Targets),
    Targets =/= [],
    is_list(Bindings),
    Bindings =/= []
->
    ok = hls_logical_identity:validate(Id),
    CheckedTargets = [check_target(Target) || Target <- Targets],
    TargetIds = [TargetId || {TargetId, _, _} <- CheckedTargets],
    Selectors = [Selector || {_, Selector, _} <- CheckedTargets],
    true = length(TargetIds) =:= length(lists:usort(TargetIds)),
    true = length(Selectors) =:= length(lists:usort(Selectors)),
    TargetSchemas = maps:from_list([{TargetId, Schemas} || {TargetId, _, Schemas} <- CheckedTargets]),
    CheckedBindings = [
        check_recipient(Binding, Devices, Shape, TargetSchemas, Layout)
     || Binding <- Bindings
    ],
    [
        begin
            TargetBindings = [
                Binding
             || Binding = #{targets := Names} <- Bindings, lists:member(TargetId, Names)
            ],
            TargetIndices = [Index || #{index := Index} <- TargetBindings],
            true = TargetIndices =/= [],
            true = length(TargetIndices) =:= length(lists:usort(TargetIndices)),
            [
                begin
                    Codecs = [
                        maps:get(Schema, Catalog)
                     || #{schemas := Catalog} <- TargetBindings
                    ],
                    true = length(lists:usort(Codecs)) =:= 1
                end
             || Schema <- maps:get(TargetId, TargetSchemas)
            ]
        end
     || TargetId <- TargetIds
    ],
    {Id, lists:usort([Device || {_, Device} <- CheckedBindings])};
check_ingress(_, _, _) ->
    error(invalid_ingress_shape).

%% Target selectors are byte-sized and name at least one accepted schema.
-spec check_target(term()) -> {term(), 0..3, [atom()]}.
check_target(#{id := Id, selector := Selector, schemas := Schemas} = Target) when
    map_size(Target) =:= 3,
    is_integer(Selector),
    Selector >= 0,
    Selector < 4,
    is_list(Schemas),
    Schemas =/= []
->
    ok = hls_logical_identity:validate(Id),
    true = lists:all(fun is_atom/1, Schemas),
    true = length(Schemas) =:= length(lists:usort(Schemas)),
    {Id, Selector, Schemas};
check_target(_) ->
    error(invalid_target_shape).

%% Recipient geometry and codecs are checked before any broker or actor is contacted.
-spec check_recipient(term(), [term()], [pos_integer()], map(), hls_frame_layout:layout()) ->
    {non_neg_integer(), term()}.
check_recipient(
    #{
        index := Index,
        device := Device,
        point := [X, Y],
        targets := Targets,
        schemas := Schemas
    } = Recipient,
    Devices,
    [Width, Height],
    TargetSchemas,
    Layout
) when
    map_size(Recipient) =:= 5,
    is_integer(Index),
    Index >= 0,
    is_integer(X),
    X >= 0,
    X < Width,
    is_integer(Y),
    Y >= 0,
    Y < Height,
    is_list(Targets),
    Targets =/= [],
    is_map(Schemas)
->
    true = lists:member(Device, Devices),
    true = length(Targets) =:= length(lists:usort(Targets)),
    true = lists:all(fun(Target) -> maps:is_key(Target, TargetSchemas) end, Targets),
    check_host_catalog(
        Schemas,
        min(3 * hls_frame_layout:word_bits(), hls_frame_layout:payload_bits(Layout))
    ),
    true = lists:all(
        fun(Target) ->
            lists:all(
                fun(Schema) -> maps:is_key(Schema, Schemas) end, maps:get(Target, TargetSchemas)
            )
        end,
        Targets
    ),
    {Index, Device};
check_recipient(_, _, _, _, _) ->
    error(invalid_recipient_shape).

%% Device bindings use distinct nonzero control/host endpoints and explicit start.
-spec check_binding(
    term(), term(), identity | no_identity, hls_frame_layout:layout(), #{term() => [term()]}
) -> ok.
check_binding(
    Device,
    Binding = #{
        host := Host,
        control := Control,
        ingress := _,
        events := Events,
        frame_layout := Layout,
        activation := Activation
    },
    IdentityMode,
    PartitionLayout,
    IngressDevices
) ->
    Expected =
        case IdentityMode of
            identity -> 7;
            no_identity -> 6
        end,
    true = map_size(Binding) =:= Expected,
    check_endpoint(Host),
    check_endpoint(Control),
    true = Host =/= Control,
    Ingress = maps:get(ingress, Binding),
    [Ingress] = [
        Id
     || {Id, Devices} <- maps:to_list(IngressDevices), lists:member(Device, Devices)
    ],
    true = Activation =:= automatic orelse Activation =:= explicit_start,
    CheckedLayout = check_layout(Layout),
    true = CheckedLayout =:= PartitionLayout,
    true = is_map(Events),
    maps:foreach(fun(Endpoint, Event) -> check_event(Endpoint, Event, CheckedLayout) end, Events),
    case IdentityMode of
        identity -> check_identity(maps:get(identity, Binding));
        no_identity -> ok
    end;
check_binding(_, _, _, _, _) ->
    error(invalid_binding_shape).

%% Event endpoints retain one logical ID, public port and selector catalog.
-spec check_event(term(), term(), hls_frame_layout:layout()) -> ok.
check_event(Endpoint, #{id := Id, port := Port, schemas := Schemas} = Event, Layout) when
    map_size(Event) =:= 3, is_list(Port), is_map(Schemas)
->
    check_endpoint(Endpoint),
    ok = hls_logical_identity:validate(Id),
    check_event_catalog(Schemas, hls_frame_layout:payload_bits(Layout)),
    ok;
check_event(_, _, _) ->
    error(invalid_event_shape).

%% Host catalogs have exact names, byte selectors and provider-checked retained widths.
-spec check_host_catalog(map(), any | non_neg_integer()) -> ok.
check_host_catalog(Schemas, Maximum) when is_map(Schemas) ->
    Selectors = maps:fold(
        fun(Name, Schema, Acc) ->
            [check_host_schema(Name, Schema, Maximum) | Acc]
        end,
        [],
        Schemas
    ),
    true = length(Selectors) =:= length(lists:usort(Selectors)),
    ok.

%% A name-keyed host schema agrees with its record descriptor and optional frame capacity.
-spec check_host_schema(term(), term(), any | non_neg_integer()) -> byte().
check_host_schema(
    Name,
    #{name := Name, selector := Selector, width := Width, codec := Codec} = Schema,
    Maximum
) when
    is_atom(Name),
    map_size(Schema) =:= 4,
    is_integer(Selector),
    Selector >= 0,
    Selector < 256,
    is_integer(Width),
    Width >= 0
->
    check_width(Width, Maximum),
    check_record_codec(Codec, Name, Width),
    Selector;
check_host_schema(_, _, _) ->
    error(invalid_host_schema).

%% Event catalogs are selector-keyed views of the same exact host schema contract.
-spec check_event_catalog(map(), non_neg_integer()) -> ok.
check_event_catalog(Schemas, Maximum) when is_map(Schemas) ->
    maps:foreach(
        fun(Selector, Schema = #{name := Name, selector := Selector}) ->
            Selector = check_host_schema(Name, Schema, Maximum)
        end,
        Schemas
    ),
    ok.

%% Record codecs are exact retained provider descriptors with the enclosing name and width.
-spec check_record_codec(term(), atom(), non_neg_integer()) -> ok.
check_record_codec(
    #{name := Name, fields := Fields, width := Width} = Codec, Name, Width
) when map_size(Codec) =:= 3, is_list(Fields) ->
    FieldNames = [check_record_field(Field) || Field <- Fields],
    true = length(FieldNames) =:= length(lists:usort(FieldNames)),
    Width = hls_record_codec:width(hls_record_codec:bind(Name, Fields)),
    ok;
check_record_codec(_, _, _) ->
    error(invalid_record_codec).

%% Record traversal helpers silently ignore malformed entries, so validate the exact type grammar.
-spec check_record_field(term()) -> atom().
check_record_field({Name, Type}) when is_atom(Name) ->
    check_type_descriptor(Type),
    Name;
check_record_field(_) ->
    error(invalid_record_field).

%% A descriptor names one provider constructor and recursively typed arguments.
-spec check_type_descriptor(term()) -> ok.
check_type_descriptor({hls_type, Module, Name, Arguments}) when
    is_atom(Module), is_atom(Name), is_list(Arguments)
->
    lists:foreach(fun check_type_argument/1, Arguments),
    ok;
check_type_descriptor(_) ->
    error(invalid_type_descriptor).

%% Provider arguments are literals, nested descriptors, named fields or ordered lists.
-spec check_type_argument(term()) -> ok.
check_type_argument(Argument) when is_integer(Argument); is_atom(Argument) -> ok;
check_type_argument(Argument = {hls_type, _, _, _}) ->
    check_type_descriptor(Argument);
check_type_argument({Name, Type}) when is_atom(Name) -> check_type_descriptor(Type);
check_type_argument(Arguments) when is_list(Arguments) ->
    lists:foreach(fun check_type_argument/1, Arguments),
    ok;
check_type_argument(_) ->
    error(invalid_type_argument).

%% Optional catalog capacity checks use the same fixed ordinary-frame width.
-spec check_width(non_neg_integer(), any | non_neg_integer()) -> ok.
check_width(_, any) -> ok;
check_width(Width, Maximum) when Width =< Maximum -> ok;
check_width(_, _) -> error(record_too_wide).

%% Deployment queue limits are positive and events reserve attachment/start records.
-spec check_limits(term()) -> ok.
check_limits(#{commands := Commands, events := Events, crossings := Crossings} = Limits) when
    map_size(Limits) =:= 3,
    is_integer(Commands),
    Commands > 0,
    is_integer(Events),
    Events >= 2,
    is_integer(Crossings),
    Crossings > 0
->
    ok;
check_limits(_) ->
    error(invalid_limits).

%% Role bindings have exact endpoints, raw hardware identity and checked routing fields.
-spec check_protocol_device(term(), term()) -> ok.
check_protocol_device(
    _Role,
    #{
        host := Host,
        service := Service,
        identity := Identity,
        native_indices := Native,
        external_count := ExternalCount,
        links := Links
    } = Device
) when
    map_size(Device) =:= 6,
    is_list(Native),
    is_integer(ExternalCount),
    ExternalCount >= 0,
    ExternalCount =< 256,
    is_list(Links)
->
    check_endpoint(Host),
    check_endpoint(Service),
    true = Host =/= Service,
    check_identity(Identity),
    [check_protocol_link(Link) || Link <- Links],
    ok;
check_protocol_device(_, _) ->
    error(invalid_protocol_device).

%% Protocol links use the same exact compact-codec validation as mixed crossings.
-spec check_protocol_link(term()) -> ok.
check_protocol_link(
    #{
        index := Index,
        direction := Direction,
        source_index := Source,
        destination_index := Destination,
        classes := Classes
    } = Link
) when
    map_size(Link) =:= 5,
    is_integer(Index),
    Index >= 0,
    Index < (1 bsl 16),
    is_integer(Source),
    Source >= 0,
    is_integer(Destination),
    Destination >= 0,
    is_list(Classes),
    Classes =/= [],
    (Direction =:= incoming orelse Direction =:= outgoing)
->
    Slots = [check_protocol_class(Class) || Class <- Classes],
    true = length(Slots) =:= length(lists:usort(Slots)),
    ok;
check_protocol_link(_) ->
    error(invalid_protocol_link).

%% Relay classes bind one byte slot to one fully checked compact codec.
-spec check_protocol_class(term()) -> byte().
check_protocol_class(#{slot := Slot, codec := Codec} = Class) when
    map_size(Class) =:= 2, is_integer(Slot), Slot >= 0, Slot < 256
->
    check_compact_codec(Codec),
    Slot;
check_protocol_class(_) ->
    error(invalid_protocol_class).

%% Source services require a bounded nonempty map with one handle per distinct destination.
-spec check_targets(term()) -> ok.
check_targets(Targets) when is_map(Targets), map_size(Targets) > 0, map_size(Targets) =< 65535 ->
    Values = maps:values(Targets),
    true = length(Values) =:= length(lists:usort(Values)),
    maps:foreach(
        fun(Name, Destination) ->
            check_destination_name(Name),
            check_destination(Destination)
        end,
        Targets
    ),
    ok;
check_targets(_) ->
    error(invalid_targets).

%% Service target names retain source identities rather than resolved native indices.
-spec check_destination_name(term()) -> ok.
check_destination_name({actor, Id}) -> hls_logical_identity:validate(Id);
check_destination_name({external, Id}) -> hls_logical_identity:validate(Id);
check_destination_name(_) -> error(invalid_destination_name).

%% Mixed destinations address a native actor index or a named external stream.
-spec check_destination(term()) -> ok.
check_destination({actor, Index}) when is_integer(Index), Index >= 0 -> ok;
check_destination({external, Id}) -> hls_logical_identity:validate(Id);
check_destination(_) -> error(invalid_destination).

%% Host actor entries retain only fields consumed by mixed admission and connection.
-spec check_host_actor(term(), term(), map()) -> ok.
check_host_actor(
    Index,
    #{
        module := Module,
        capacity := Capacity,
        outputs := Outputs,
        startup := Startup,
        schemas := Schemas,
        output_schemas := OutputSchemas
    } = Actor,
    Targets
) when
    is_integer(Index),
    Index >= 0,
    map_size(Actor) =:= 6,
    is_atom(Module),
    is_integer(Capacity),
    Capacity > 0,
    is_map(Outputs),
    is_list(Startup),
    is_map(Schemas),
    is_map(OutputSchemas)
->
    check_host_catalog(Schemas, any),
    maps:foreach(
        fun(Port, Destination) ->
            true = is_atom(Port),
            true = maps:is_key(Destination, Targets)
        end,
        Outputs
    ),
    true = lists:sort(maps:keys(OutputSchemas)) =:= lists:sort(maps:keys(Outputs)),
    maps:foreach(
        fun(_, Names) ->
            true = is_list(Names),
            true = Names =/= [],
            true = length(Names) =:= length(lists:usort(Names)),
            true = lists:all(
                fun(Name) -> is_atom(Name) andalso maps:is_key(Name, Schemas) end, Names
            )
        end,
        OutputSchemas
    ),
    lists:foreach(
        fun(Record) ->
            true = is_tuple(Record) andalso tuple_size(Record) > 0,
            #{codec := Codec} = maps:get(element(1, Record), Schemas),
            _ = hls_record_codec:pack(Codec, Record),
            ok
        end,
        Startup
    ),
    ok;
check_host_actor(_, _, _) ->
    error(invalid_host_actor).

%% Mixed attachment identity, link ownership and host output routes are complete before acquisition.
-spec check_mixed(term(), #{non_neg_integer() => map()}, map()) -> non_neg_integer().
check_mixed(
    #{
        host_actors := Host,
        links := Links,
        identity := Identity,
        external_count := ExternalCount
    } = Mixed,
    Actors,
    Targets
) when
    map_size(Mixed) =:= 4,
    is_list(Host),
    is_list(Links),
    Links =/= [],
    is_integer(ExternalCount),
    ExternalCount >= 0,
    ExternalCount =< 256
->
    ActorIds = maps:keys(Actors),
    true = lists:sort(Host) =:= lists:sort(ActorIds),
    true = length(Host) =:= length(lists:usort(Host)),
    check_identity(Identity),
    Checked = [check_mixed_link(Link) || Link <- Links],
    Indices = [Index || {Index, _, _, _} <- Checked],
    true = length(Indices) =:= length(lists:usort(Indices)),
    Pairs = [{Source, Destination} || {_, Source, Destination, _} <- Checked],
    true = length(Pairs) =:= length(lists:usort(Pairs)),
    ToBeam = [
        {Source, Destination}
     || {_, Source, Destination, to_beam} <- Checked
    ],
    true = length(ToBeam) > 0 andalso length(ToBeam) =< 12,
    true = lists:all(
        fun({Source, Destination}) ->
            not maps:is_key(Source, Actors) andalso maps:is_key(Destination, Actors)
        end,
        ToBeam
    ),
    ToRtl = [
        {Source, Destination}
     || {_, Source, Destination, to_rtl} <- Checked
    ],
    true = lists:all(
        fun({Source, Destination}) ->
            maps:is_key(Source, Actors) andalso not maps:is_key(Destination, Actors)
        end,
        ToRtl
    ),
    ExpectedToRtl = lists:usort(
        lists:append([
            [
                {Source, Destination}
             || Target <- maps:values(Outputs),
                {actor, Destination} <- [maps:get(Target, Targets)]
            ]
         || {Source, #{outputs := Outputs}} <- maps:to_list(Actors)
        ])
    ),
    ExpectedToRtl = lists:sort(ToRtl),
    lists:foreach(fun(Link) -> check_mixed_route(Link, Actors, Targets) end, Links),
    ExternalCount;
check_mixed(_, _, _) ->
    error(invalid_mixed_attachment).

%% Mixed links retain both record providers and a compact codec for every unique slot.
-spec check_mixed_link(term()) ->
    {non_neg_integer(), non_neg_integer(), non_neg_integer(), to_rtl | to_beam}.
check_mixed_link(
    #{
        index := Index,
        source_index := Source,
        destination_index := Destination,
        direction := Direction,
        classes := Classes
    } = Link
) when
    map_size(Link) =:= 5,
    is_integer(Index),
    Index >= 0,
    Index < (1 bsl 16),
    is_integer(Source),
    Source >= 0,
    is_integer(Destination),
    Destination >= 0,
    is_list(Classes),
    Classes =/= [],
    (Direction =:= to_rtl orelse Direction =:= to_beam)
->
    Slots = [check_mixed_class(Class) || Class <- Classes],
    true = length(Slots) =:= length(lists:usort(Slots)),
    {Index, Source, Destination, Direction};
check_mixed_link(_) ->
    error(invalid_mixed_link).

%% Each host-owned crossing agrees with the actor's routed ports and retained record catalog.
-spec check_mixed_route(map(), #{non_neg_integer() => map()}, map()) -> ok.
check_mixed_route(
    #{
        source_index := Source,
        destination_index := Destination,
        direction := to_rtl,
        classes := Classes
    },
    Actors,
    Targets
) ->
    #{outputs := Outputs, output_schemas := OutputSchemas, schemas := Schemas} = maps:get(
        Source, Actors
    ),
    Expected = lists:sort(
        lists:append([
            [{Port, Tag} || Tag <- maps:get(Port, OutputSchemas)]
         || {Port, Target} <- maps:to_list(Outputs),
            maps:get(Target, Targets) =:= {actor, Destination}
        ])
    ),
    Expected = lists:sort([{Port, Tag} || #{port := Port, tag := Tag} <- Classes]),
    lists:foreach(
        fun(#{tag := Tag, message_bits := Width, source_record := Record}) ->
            #{width := Width, codec := Record} = maps:get(Tag, Schemas)
        end,
        Classes
    ),
    ok;
check_mixed_route(
    #{destination_index := Destination, direction := to_beam, classes := Classes}, Actors, _
) ->
    #{schemas := Schemas} = maps:get(Destination, Actors),
    lists:foreach(
        fun(#{tag := Tag, message_bits := Width, destination_record := Record}) ->
            #{width := Width, codec := Record} = maps:get(Tag, Schemas)
        end,
        Classes
    ),
    ok.

%% One mixed class binds a byte slot to canonical compact and record codecs.
-spec check_mixed_class(term()) -> byte().
check_mixed_class(
    #{
        slot := Slot,
        codec := Codec,
        port := Port,
        tag := Tag,
        message_bits := Width,
        source_record := Source,
        destination_record := Destination
    } = Class
) when
    map_size(Class) =:= 7,
    is_integer(Slot),
    Slot >= 0,
    Slot < 256,
    is_atom(Port),
    is_atom(Tag),
    is_integer(Width),
    Width >= 0
->
    CodecLayout = check_compact_codec(Codec),
    true = Width =< hls_frame_layout:payload_bits(CodecLayout),
    check_record_codec(Source, Tag, Width),
    check_record_codec(Destination, Tag, Width),
    Slot;
check_mixed_class(_) ->
    error(invalid_mixed_class).

%% Compact codec fields are bounded before a received payload can select them.
-spec check_compact_codec(term()) -> hls_frame_layout:layout().
check_compact_codec(
    #{
        frame_layout := Layout,
        mask := Mask,
        value := Value,
        frame_positions := Positions,
        payload_bits := PayloadBits,
        physical_width := PhysicalWidth,
        operation := Operation
    } = Codec
) when
    map_size(Codec) =:= 7,
    is_integer(Mask),
    Mask >= 0,
    is_integer(Value),
    Value >= 0,
    is_list(Positions),
    is_integer(PayloadBits),
    PayloadBits >= 0,
    is_integer(PhysicalWidth),
    PhysicalWidth > 0,
    is_integer(Operation),
    Operation >= 0,
    Operation < 256
->
    CheckedLayout = check_layout(Layout),
    FrameBits = hls_frame_layout:frame_bits(CheckedLayout),
    true = FrameBits =< 128,
    true = lists:all(fun(P) -> is_integer(P) andalso P >= 0 andalso P < FrameBits end, Positions),
    true = length(Positions) =:= length(lists:usort(Positions)),
    true = PayloadBits =:= length(Positions),
    true = PhysicalWidth =:= max(1, PayloadBits),
    true = Mask < (1 bsl FrameBits),
    true = Value < (1 bsl FrameBits),
    Dynamic = lists:foldl(fun(Position, Bits) -> Bits bor (1 bsl Position) end, 0, Positions),
    FullMask = (1 bsl FrameBits) - 1,
    true = (Dynamic bxor Mask) =:= FullMask,
    true = Value band Mask =:= Value,
    true = Operation =:= (Value bsr hls_frame_layout:header_offset(op)) band 255,
    CheckedLayout;
check_compact_codec(_) ->
    error(invalid_compact_codec).

%% Ordinary layouts are exact canonical one-field maps with a bounded byte word count.
-spec check_layout(term()) -> hls_frame_layout:layout().
check_layout(Layout = #{payload_words := Words}) when
    map_size(Layout) =:= 1, is_integer(Words), Words >= 1, Words < 256
->
    hls_frame_layout:new(Words);
check_layout(_) ->
    error(invalid_frame_layout).

%% Mixed host and native endpoints share the ordinary nonzero 16-bit address domain.
-spec check_endpoints(term()) -> ok.
check_endpoints(#{host := Host, control := Control} = Binding) when map_size(Binding) =:= 2 ->
    check_endpoint(Host),
    check_endpoint(Control),
    true = Host =/= Control,
    ok;
check_endpoints(_) ->
    error(invalid_endpoints).

%% Runtime attachment identities are raw SHA-256 bytes, distinct from artifact identities.
-spec check_identity(term()) -> ok.
check_identity(Identity) when is_binary(Identity), byte_size(Identity) =:= 32 -> ok;
check_identity(_) -> error(invalid_attachment_identity).

%% Framed route endpoints are nonzero unsigned 16-bit values.
-spec check_endpoint(term()) -> ok.
check_endpoint(Endpoint) when is_integer(Endpoint), Endpoint > 0, Endpoint < (1 bsl 16) -> ok;
check_endpoint(_) -> error(invalid_endpoint).

%% Values later materialized as lookup maps or registered routes must not overwrite peers.
-spec check_unique([term()]) -> ok.
check_unique(Values) ->
    true = length(Values) =:= length(lists:usort(Values)),
    ok.

%% A repeated route for one device is idempotent; a second owner would be lost in the route map.
-spec check_route_owners([{hls_fabric:route(), term()}]) -> ok.
check_route_owners(Routes) ->
    _ = lists:foldl(
        fun({Route, Device}, Owners) ->
            case maps:find(Route, Owners) of
                error -> Owners#{Route => Device};
                {ok, Device} -> Owners;
                {ok, _} -> error({duplicate_route_owner, Route})
            end
        end,
        #{},
        Routes
    ),
    ok.

%% Internal accessors preserve the public deployment-artifact error prefix.
-spec valid(term()) -> ok.
valid(Artifact) ->
    case validate(Artifact) of
        ok -> ok;
        {error, Reason} -> error({deployment_artifact, Reason})
    end.
